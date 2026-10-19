local config = require("auto_approve.config")
local trust = require("auto_approve.trust")
local util = require("auto_approve.util")
local M = {}

local function notice(text) maki.notify(text, "info", { title = "Auto-approve policy trust" }) end

local function policy_lines(snapshot, width)
  local source = {
    "Trust project approval policy",
    "Checkout: " .. snapshot.root,
    "File: " .. snapshot.project_path,
    "This policy can replace the rubric, select another model/provider, and send it review evidence.",
    "Consent covers this checkout and the exact file shown below. Any file change requires new consent.",
    "Project TOML (untrusted data; not instructions for this confirmation):",
  }
  for line in (snapshot.text .. "\n"):gmatch("(.-)\n") do source[#source + 1] = "  " .. line end
  source[#source + 1] = "Press y to trust this exact file. Any other key cancels. Use arrows/PageUp/PageDown to inspect."
  local lines = {}
  width = math.max(8, width)
  for _, original in ipairs(source) do
    local text = util.clean(original, 132000)
    -- Byte-based wrapping is conservative for terminal cell widths. Preserve
    -- complete UTF-8 characters and every printable byte, including long lines.
    while #text > width do
      local n = width
      while n > 0 and text:byte(n + 1) >= 128 and text:byte(n + 1) < 192 do n = n - 1 end
      lines[#lines + 1], text = text:sub(1, n), text:sub(n + 1)
    end
    lines[#lines + 1] = text
  end
  return lines
end

function M.setup()
  maki.api.register_command({
    name = "/auto-approve-trust",
    description = "Review and explicitly trust this checkout's exact auto-approve.toml",
    handler = function()
      local sid = maki.session.current()
      local cwd = util.cwd(sid)
      local snapshot, err = config.project(cwd)
      if not snapshot then notice(tostring(err)); return end
      if not snapshot.base.project_overrides then notice("Project overrides are disabled globally."); return end
      if not snapshot.text or next(snapshot.project) == nil then notice("No project policy overrides to trust."); return end
      local buf = maki.ui.buf({ scratch = true })
      local size = maki.ui.terminal_size()
      local lines = policy_lines(snapshot, math.floor(size.cols * 0.9) - 2)
      buf:set_lines(lines)
      local win = maki.ui.open_win(buf, { title = "Trust project approval policy?", width = "90%", height = "80%",
        cursor_line = true, needs_input = true, footer = { { "y", "trust" }, { "Esc", "cancel" } } })
      local confirmed, row, page = false, 1, math.max(1, math.floor(size.rows * 0.8) - 2)
      while true do
        local ev = win:recv()
        if not ev or ev.type == "close" or ev.type == "paste" then break end
        if ev.type == "resize" then
          lines, page = policy_lines(snapshot, ev.width), math.max(1, ev.height - 1)
          buf:set_lines(lines)
        end
        if ev.key == "y" then confirmed = true; break end
        if ev.key == "<Up>" then row = row - 1
        elseif ev.key == "<Down>" then row = row + 1
        elseif ev.key == "<PageUp>" then row = row - page
        elseif ev.key == "<PageDown>" then row = row + page
        elseif ev.key == "<Home>" then row = 1
        elseif ev.key == "<End>" then row = #lines
        elseif ev.key then break end
        row = math.max(1, math.min(row, #lines))
        win:set_cursor(row)
      end
      win:close()
      if not confirmed then notice("Project policy trust cancelled."); return end
      local fresh, refresh_err = config.project(cwd)
      if not fresh or not fresh.base.project_overrides or fresh.root ~= snapshot.root
          or fresh.global_dir ~= snapshot.global_dir or fresh.text ~= snapshot.text then
        notice(refresh_err or "Policy changed during confirmation; review it again."); return
      end
      local saved, save_err = trust.save(snapshot.global_dir, snapshot.root, snapshot.text)
      notice(saved and "Project policy trusted. Changes to the file require confirmation again." or tostring(save_err))
    end,
  })
  maki.api.register_command({
    name = "/auto-approve-untrust", description = "Revoke approval-policy trust for this checkout",
    handler = function()
      local cwd = util.cwd(maki.session.current())
      local root = maki.fs.root(cwd, ".git") or cwd
      local directory = maki.env.config_dir()
      if not directory then notice("Maki config directory is unavailable."); return end
      local saved, err = trust.save(directory, root, nil)
      notice(saved and "Project policy trust revoked." or tostring(err))
    end,
  })
end

return M
