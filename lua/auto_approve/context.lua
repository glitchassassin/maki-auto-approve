local util = require("auto_approve.util")
local M = {}

local function user_instructions(history)
  local instructions = {}
  for i, message in ipairs(history) do
    if message.role == "user" and message.kind == "turn" and not message.hidden then
      local text, images, eligible = {}, false, true
      for _, block in ipairs(message.content or {}) do
        if block.type == "text" then text[#text + 1] = block.text or ""
        elseif block.type == "image" then images = true
        else eligible = false end
      end
      local joined = table.concat(text, "\n")
      if eligible and (joined:match("%S") or images) then
        instructions[#instructions + 1] = { history_index = i, text = joined, images_omitted = images }
      end
    end
  end
  return instructions
end

function M.new()
  local sessions, sequence = {}, 0
  local api = {}
  function api.observe(sid, text, source, images)
    if not sid or not ({ tui = true, headless = true, acp = true })[source] then return end
    if type(text) ~= "string" then return end
    if not text:match("%S") and (images or 0) == 0 then return end
    sequence = sequence + 1
    sessions[sid] = sequence
  end
  function api.revision(sid)
    if not sessions[sid] then sequence = sequence + 1; sessions[sid] = sequence end
    return sessions[sid]
  end
  function api.clear(sid) sessions[sid] = nil end

  function api.build(sid, task, request, config)
    local revision = api.revision(sid)
    local history, err = maki.session.messages({ session = sid })
    if not history then return nil, "Conversation evidence unavailable: " .. tostring(err) end
    local instructions = user_instructions(history)
    local trusted, user_bytes, omitted = {}, 0, false
    for i = #instructions, 1, -1 do
      local entry = instructions[i]
      local encoded = util.encode(entry)
      if user_bytes + #encoded <= config.context.max_user_bytes then
        table.insert(trusted, 1, entry)
        user_bytes = user_bytes + #encoded
      else omitted = true; break end
    end
    if #instructions > 0 and #trusted == 0 then return nil, "User instructions exceed the configured evidence budget." end
    local payload = {
      user_instructions = trusted,
      user_instruction_source = "Maki recorded visible user turns; original input source is unavailable.",
      user_instructions_omitted = omitted,
      untrusted_conversation_evidence = {},
      conversation_is_partial = true,
      planned_action = request,
      session_id = sid,
      task_id = task,
      project_root = config.root,
    }
    local size = #util.encode(payload)
    if size > config.context.max_bytes then return nil, "Complete action exceeds the review context budget." end
    for i = #history, math.max(1, #history - config.context.max_messages + 1), -1 do
      local message = history[i]
      local content = {}
      for _, block in ipairs(message.content or {}) do
        if block.type == "text" then
          content[#content + 1] = { type = "text", text = util.clip(block.text or "", 6000) }
        elseif block.type == "tool_use" then
          content[#content + 1] = { type = "tool_use", name = block.name, id = block.id,
            evidence = util.clip(util.encode(block.input), 6000) }
        elseif block.type == "tool_result" then
          local text = type(block.content) == "string" and block.content or util.encode(block.content)
          content[#content + 1] = { type = "tool_result", tool_use_id = block.tool_use_id,
            evidence = util.clip(text, 6000), is_error = block.is_error }
        elseif block.type == "image" then
          content[#content + 1] = { type = "image", evidence = "Image contents omitted." }
        end
      end
      if #content > 0 then
        local entry = { role = message.role, kind = message.kind, hidden = message.hidden, content = content }
        local entry_bytes = #util.encode(entry) + 1
        if size + entry_bytes > config.context.max_bytes then break end
        table.insert(payload.untrusted_conversation_evidence, 1, entry)
        size = size + entry_bytes
      end
    end
    local encoded = util.encode(payload)
    if #encoded > config.context.max_bytes then return nil, "Review context exceeds its byte budget." end
    return encoded, nil, { revision = revision, instructions = instructions }
  end

  function api.unchanged(sid, proof)
    local history, err = maki.session.messages({ session = sid })
    if not history then return nil, "Could not revalidate user instructions: " .. tostring(err) end
    local current = user_instructions(history)
    if #current == #proof.instructions then
      local same = true
      for i, entry in ipairs(current) do
        local previous = proof.instructions[i]
        if entry.history_index ~= previous.history_index or entry.text ~= previous.text
            or entry.images_omitted ~= previous.images_omitted then same = false; break end
      end
      if same then return true end
    end
    return nil, "Recorded user instructions changed during review."
  end
  return api
end

return M
