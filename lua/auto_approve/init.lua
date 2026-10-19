local config = require("auto_approve.config")
local context = require("auto_approve.context")
local review = require("auto_approve.review")
local util = require("auto_approve.util")
local M = {}

function M.setup()
  require("auto_approve.inspect").setup()
  local captured, active, results = context.new(), 0, {}
  local function remember(sid, req, status, reason, assessment, limit)
    local records = results[sid] or {}
    records[#records + 1] = { tool = req.tool, status = status, reason = util.clean(reason, 1000),
      risk = assessment and assessment.risk_level, authorization = assessment and assessment.user_authorization }
    while #records > (limit or 50) do table.remove(records, 1) end
    results[sid] = records
    local message = tostring(req.tool) .. ": " .. status .. " — " .. util.clean(reason, 400)
    maki.log.info("auto-approve: " .. message)
    if status ~= "approved" then maki.notify(message, "info", { title = "Auto-approve" }) end
  end

  maki.api.set_slot("agent.user_message", function(prev, message, ctx)
    -- Record the original human text, not additions introduced by downstream layers.
    local source, original = message.source, message.text
    -- The native identity continuation returns (message, ctx), not (value, err).
    local result, extra = prev(message, ctx)
    local dropped = result == nil and type(extra) == "string"
    local emptied = type(result) == "table" and type(result.text) == "string"
      and not result.text:match("%S") and (message.images or 0) == 0
    if not dropped and not emptied then
      captured.capture(ctx.session_id, original, source, message.images)
    end
    return result, extra
  end)
  maki.api.create_autocmd({ "SessionReset", "SessionEnd" }, {
    callback = function(ev)
      local sid = ev.data.session_id
      captured.clear(sid)
      results[sid] = nil
    end,
  })

  -- Only this slot grants approval: native allow/deny/YOLO decisions have already
  -- resolved, and explicit human-only escalations never enter the slot.
  maki.api.set_slot("permission.prompt", function(prev, req, ctx)
    local sid = ctx:session_id()
    if not sid then return prev(req, ctx) end
    local cfg, error_text
    local accepted = false
    local assessment
    local ok, thrown = pcall(function()
      local cwd = util.cwd(sid)
      cfg, error_text = config.load(cwd)
      if not cfg or not cfg.enabled then return end
      if active >= cfg.reviewer.max_concurrent then error_text = "Reviewer concurrency limit reached."; return end
      local prompt, build_err, revision = captured.build(sid, ctx:task_id(), util.copy(req), cfg)
      if not prompt then error_text = build_err; return end
      active = active + 1
      local released = false
      local function release_active()
        if not released then active = active - 1; released = true end
      end
      maki.async.on_cancel(release_active)
      local ran, value, run_err = pcall(review.run, ctx, cfg, prompt, cwd, req.tool_id)
      release_active()
      if not ran then error_text = "Review failed: " .. tostring(value); return end
      assessment, error_text = value, run_err
      if not assessment or assessment.outcome ~= "allow" then return end
      local fresh, refresh_err = config.load(cwd)
      if not fresh or util.encode(fresh) ~= util.encode(cfg) then
        error_text = refresh_err or "Configuration changed during review."
        return
      end
      -- All filesystem/trust reads above may yield. No yield may occur between
      -- this final authorization/cancellation check and publishing the allow.
      if ctx:cancelled() then error_text = "Call was cancelled during review."; return end
      if captured.revision(sid) ~= revision then error_text = "User instructions changed during review."; return end
      accepted = true
    end)
    if not ok then error_text = "Review failed: " .. tostring(thrown) end
    if cfg and not cfg.enabled then return prev(req, ctx) end
    local reason = error_text or (assessment and assessment.rationale) or "Review unavailable."
    remember(sid, req, accepted and "approved" or "human review", reason, assessment,
      cfg and cfg.logging.history_size)
    if accepted then return { decision = "allow" } end
    return prev(req, ctx)
  end)

  maki.api.register_command({
    name = "/auto-approve", description = "Show recent automatic approval decisions for this session",
    handler = function()
      local sid = maki.session.current()
      local records = results[sid] or {}
      local buf = maki.ui.buf({ scratch = true })
      buf:line("Auto-approve: recent decisions (oldest first)")
      if #records == 0 then buf:line("No reviews recorded in this session since the plugin loaded.") end
      for _, record in ipairs(records) do
        buf:line(record.tool .. ": " .. record.status .. (record.risk and (" [" .. record.risk .. ", authorization=" .. record.authorization .. "]") or ""))
        buf:line("  " .. record.reason)
      end
      buf:line("Close: q or Esc")
      local win = maki.ui.open_win(buf, { title = "Auto-approve", width = "85%", height = "70%" })
      while true do
        local ev = win:recv()
        if not ev or ev.key == "q" or ev.key == "<Esc>" then break end
      end
      win:close()
    end,
  })
  require("auto_approve.trust_commands").setup()
  return { context = captured, results = results }
end

return M
