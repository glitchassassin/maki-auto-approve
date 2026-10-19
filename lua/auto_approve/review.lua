local util = require("auto_approve.util")
local policy = require("auto_approve.policy")
local inspect = require("auto_approve.inspect")
local M = {}
local risks = { low = true, medium = true, high = true, critical = true }
local auth = { unknown = true, low = true, medium = true, high = true }

function M.parse(text)
  local value, err = util.decode(text)
  if type(value) ~= "table" then return nil, err or "Reviewer did not return a JSON object." end
  local keys = { risk_level = true, user_authorization = true, outcome = true, rationale = true }
  for key in pairs(value) do if not keys[key] then return nil, "Unexpected reviewer response field." end end
  if not risks[value.risk_level] or not auth[value.user_authorization]
      or (value.outcome ~= "allow" and value.outcome ~= "deny")
      or type(value.rationale) ~= "string" or not value.rationale:match("%S") or #value.rationale > 2000 then
    return nil, "Reviewer response does not satisfy the decision schema."
  end
  if value.outcome == "allow" then
    if value.risk_level == "critical" then return nil, "Critical risk requires human approval." end
    if value.user_authorization ~= "medium" and value.user_authorization ~= "high" then
      return nil, "User authorization is unclear; human approval is required."
    end
  end
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
  if type(result.text) ~= "string" or #result.text > 8000 then return nil, "Invalid reviewer response size." end
  local assessment, parse_err = M.parse(result.text)
  if not assessment then return nil, parse_err end
  if assessment.outcome == "allow" then
    local unchanged, changed_err = inspections.unchanged()
    if not unchanged then return nil, changed_err end
  end
  return assessment
end

return M
