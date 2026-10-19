local util = require("auto_approve.util")
local policy = require("auto_approve.policy")
local inspect = require("auto_approve.inspect")
local M = {}
local risks = { low = true, medium = true, high = true, critical = true }
local auth = { unknown = true, low = true, medium = true, high = true }

local function repeated_field(text)
  -- Maki decodes through a JSON value, which loses duplicate keys. Codex's
  -- serde struct rejects duplicates of known fields, while ignoring extra fields.
  local known = { risk_level = true, user_authorization = true, outcome = true, rationale = true }
  local seen, depth, previous, i = {}, 0, nil, 1
  while i <= #text do
    local char = text:sub(i, i)
    if char == '"' then
      local finish = i + 1
      while finish <= #text do
        local current = text:sub(finish, finish)
        if current == "\\" then finish = finish + 2
        elseif current == '"' then break
        else finish = finish + 1 end
      end
      if depth == 1 and (previous == "{" or previous == ",") then
        local key = util.decode(text:sub(i, finish))
        if known[key] then
          if seen[key] then return true end
          seen[key] = true
        end
      end
      previous, i = '"', finish
    elseif char == "{" or char == "[" then depth, previous = depth + 1, char
    elseif char == "}" or char == "]" then depth, previous = depth - 1, char
    elseif char:match("%S") then previous = char end
    i = i + 1
  end
  return false
end

local function parse_payload(text)
  local value = util.decode(text)
  if type(value) ~= "table" or (value.outcome ~= "allow" and value.outcome ~= "deny") then return nil end
  if repeated_field(text) then return nil end
  if (value.risk_level ~= nil and not risks[value.risk_level])
      or (value.user_authorization ~= nil and not auth[value.user_authorization])
      or (value.rationale ~= nil and type(value.rationale) ~= "string") then return nil end
  local allowed = value.outcome == "allow"
  return {
    outcome = value.outcome,
    risk_level = value.risk_level or (allowed and "low" or "high"),
    user_authorization = value.user_authorization or "unknown",
    rationale = value.rationale and value.rationale:match("%S") and value.rationale
      or (allowed and "Auto-review returned a low-risk allow decision."
        or "Auto-review returned a deny decision without a rationale."),
  }
end

function M.parse(text)
  if type(text) ~= "string" then return nil, "Reviewer did not return assessment text." end
  local value = parse_payload(text)
  if value then return value end
  -- Match Codex's recovery of a JSON object surrounded by prose or markdown.
  local first = text:find("{", 1, true)
  local last = text:reverse():find("}", 1, true)
  last = last and (#text - last + 1)
  if first and last and first < last then value = parse_payload(text:sub(first, last)) end
  if not value then return nil, "Reviewer response does not satisfy the Codex assessment schema." end
  return value
end

function M.run(ctx, config, prompt, cwd, task)
  local tools, inspections, release = inspect.bind(config, cwd, ctx:session_id(), task)
  -- Only these registered read-only tools are delegated; no shell/MCP tools.
  -- Omit an empty tools table: Maki expects an array, whereas Lua {} is an object.
  local opts = { system = policy.system(config.policy.rubric), tools = tools,
    mcp = false, name = "Auto-approve review" }
  if config.reviewer.model ~= "" then opts.model_spec = config.reviewer.model end
  if config.reviewer.thinking ~= "" then opts.thinking = config.reviewer.thinking end
  local opened, session, open_err = pcall(maki.agent.session, ctx, opts)
  if not opened then release(); return nil, "Could not start reviewer: " .. tostring(session) end
  if not session then release(); return nil, "Could not start reviewer: " .. tostring(open_err) end
  local timed_out, cancelled = false, false
  local timer = maki.async.spawn(function()
    maki.async.sleep(config.reviewer.timeout_ms)
    timed_out = true
    session:close()
  end)
  maki.async.on_cancel(function()
    cancelled = true
    timer:cancel()
    release()
  end)
  local ok, result, err = pcall(function() return session:prompt(prompt) end)
  timer:cancel()
  local closed, close_err = pcall(function() session:close() end)
  release()
  if cancelled or ctx:cancelled() then return nil, "Review cancelled." end
  if timed_out then return nil, "Review timed out; human approval is required." end
  if not closed then return nil, "Reviewer cleanup failed: " .. tostring(close_err) end
  if not ok then return nil, "Reviewer failed: " .. tostring(result) end
  if err or not result then return nil, "Reviewer failed: " .. tostring(err) end
  if type(result.text) ~= "string" then return nil, "Reviewer did not return assessment text." end
  local assessment, parse_err = M.parse(result.text)
  if not assessment then return nil, parse_err end
  if assessment.outcome == "allow" then
    local unchanged, changed_err = inspections.unchanged()
    if not unchanged then return nil, changed_err end
  end
  return assessment
end

return M
