local util = require("auto_approve.util")
local M = {}

function M.new()
  local sessions = {}
  local api = {}
  function api.capture(sid, text, source, images)
    if not sid or not ({ tui = true, headless = true, acp = true })[source] then return end
    if type(text) ~= "string" then return end
    if not text:match("%S") and (images or 0) == 0 then return end
    local state = sessions[sid] or { revision = 0, messages = {}, bytes = 0, omitted = false }
    state.revision = state.revision + 1
    local saved = util.clip(text, 64000)
    if saved ~= text then state.omitted = true end
    state.messages[#state.messages + 1] = { source = source, text = saved, images_omitted = (images or 0) > 0 }
    state.bytes = state.bytes + #saved
    while #state.messages > 128 or state.bytes > 256000 do
      state.bytes = state.bytes - #state.messages[1].text
      table.remove(state.messages, 1)
      state.omitted = true
    end
    sessions[sid] = state
  end
  function api.revision(sid) return sessions[sid] and sessions[sid].revision or 0 end
  function api.clear(sid) sessions[sid] = nil end

  function api.build(sid, task, request, config)
    local state = sessions[sid]
    if not state or #state.messages == 0 then
      return nil, "No captured human instructions; send a user message after loading the plugin."
    end
    local history, err = maki.session.messages({ session = sid, last = config.context.max_messages })
    if not history then return nil, "Conversation evidence unavailable: " .. tostring(err) end
    local trusted, user_bytes, omitted = {}, 0, state.omitted
    for i = #state.messages, 1, -1 do
      local entry = state.messages[i]
      local encoded = util.encode(entry)
      if user_bytes + #encoded <= config.context.max_user_bytes then
        table.insert(trusted, 1, entry)
        user_bytes = user_bytes + #encoded
      else omitted = true; break end
    end
    if #trusted == 0 then return nil, "Human instructions exceed the configured evidence budget." end
    local payload = {
      captured_user_instructions = trusted,
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
    for i = #history, 1, -1 do
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
    return encoded, nil, state.revision
  end
  return api
end

return M
