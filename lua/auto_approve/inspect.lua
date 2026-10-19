local util = require("auto_approve.util")
local M = {}
local pending, sequence = {}, 0
local names = { "inspect_path", "read_file", "list_directory" }

function M.setup()
  for _, name in ipairs(names) do
    local tool = name
    maki.api.register_tool({
      name = "auto_approve_" .. tool,
      description = "Read-only evidence for a pending automatic approval review: " .. tool,
      audiences = { "general_sub" }, permission = "fs_read",
      schema = { type = "object", properties = { path = { type = "string" }, review_id = { type = "string" } },
        required = { "path", "review_id" }, additionalProperties = false },
      handler = function(args, ctx)
        local bound = pending[args.review_id]
        if not bound or ctx:session_id() ~= bound.session
            or (bound.task and ctx:task_id() ~= bound.task) or ctx:cancelled() then
          return { llm_output = "No active review owns this inspection.", is_error = true }
        end
        local ok, result, err = pcall(bound.tools[tool].handler, args)
        if not ok or not result then
          bound.state.failed = true
          return { llm_output = tostring(err or result or "Inspection failed."), is_error = true }
        end
        return { llm_output = result }
      end,
    })
  end
end

function M.new(config, cwd)
  local state = { count = 0, failed = false, observations = {} }
  local function failure(reason)
    state.failed = true
    return nil, reason
  end
  local function path_for(args)
    state.count = state.count + 1
    if state.count > config.reviewer.max_inspections then return failure("Inspection limit reached.") end
    if type(args) ~= "table" or type(args.path) ~= "string" or args.path == "" or args.path:find("%z") then
      return failure("A nonempty path is required.")
    end
    local path = args.path
    if path:sub(1, 1) ~= "/" and path:sub(1, 2) ~= "~/" and not path:match("^%a:[/\\]") then
      path = maki.fs.joinpath(cwd, path)
    end
    return maki.fs.abspath(path)
  end
  local function metadata(path)
    local meta, err = maki.fs.metadata(path)
    if err then return failure(err) end
    return { path = path, exists = meta ~= nil, metadata = meta }
  end
  local schema = { type = "object", properties = { path = { type = "string" } },
    required = { "path" }, additionalProperties = false }
  local tools = {}
  tools.inspect_path = {
    description = "Read only: inspect existence, type, size and modification time of a relevant path. No shell or writes.",
    input_schema = schema,
    handler = function(args)
      local path, err = path_for(args)
      if not path then return nil, err end
      local result, meta_err = metadata(path)
      if not result then return nil, meta_err end
      state.observations[#state.observations + 1] = { path = path, metadata = util.encode(result) }
      return util.encode(result)
    end,
  }
  tools.read_file = {
    description = "Read only: read one relevant UTF-8 regular file within the configured size limit. Never executes content.",
    input_schema = schema,
    handler = function(args)
      local path, err = path_for(args)
      if not path then return nil, err end
      local result, meta_err = metadata(path)
      if not result then return nil, meta_err end
      if not result.metadata or not result.metadata.is_file then return failure("Not a regular file.") end
      if result.metadata.size > config.inspection.max_file_bytes then return failure("File exceeds inspection byte limit.") end
      local text, read_err = maki.fs.read(path)
      if not text then return failure(read_err or "File could not be read.") end
      if #text > config.inspection.max_file_bytes then return failure("File grew beyond inspection byte limit.") end
      state.observations[#state.observations + 1] = { path = path, content = text }
      return util.encode({ path = path, untrusted_file_contents = text })
    end,
  }
  tools.list_directory = {
    description = "Read only: list one relevant directory, one level deep, with bounded output. Never runs commands.",
    input_schema = schema,
    handler = function(args)
      local path, err = path_for(args)
      if not path then return nil, err end
      local result, meta_err = metadata(path)
      if not result then return nil, meta_err end
      if not result.metadata or not result.metadata.is_dir then return failure("Not a directory.") end
      local entries, list_err = maki.fs.dir(path, { depth = 1 })
      if not entries then return failure(list_err or "Directory could not be read.") end
      table.sort(entries, function(a, b) return a[1] < b[1] end)
      local output = {}
      for i = 1, math.min(#entries, config.inspection.max_directory_entries) do
        output[#output + 1] = { name = util.clip(entries[i][1], 512), type = entries[i][2] }
      end
      state.observations[#state.observations + 1] = { path = path, metadata = util.encode(result) }
      return util.encode({ path = path, entries = output, entries_omitted = #entries - #output })
    end,
  }

  function state.unchanged()
    if state.failed then return nil, "An inspection failed; human review is required." end
    for _, item in ipairs(state.observations) do
      if item.content then
        local meta = maki.fs.metadata(item.path)
        if not meta or not meta.is_file or meta.size > config.inspection.max_file_bytes then
          return nil, "An inspected file changed during review."
        end
        local text = maki.fs.read(item.path)
        if text ~= item.content then return nil, "An inspected file changed during review." end
      else
        local result = metadata(item.path)
        if not result or util.encode(result) ~= item.metadata then
          return nil, "An inspected path changed during review."
        end
      end
    end
    return true
  end
  return config.inspection.enabled and tools or {}, state
end

function M.bind(config, cwd, session, task)
  local tools, state = M.new(config, cwd)
  sequence = sequence + 1
  local id = session .. ":" .. sequence
  pending[id] = { tools = tools, state = state, session = session, task = task ~= "" and task or nil }
  local definitions = {}
  for _, name in ipairs(names) do
    if tools[name] then
      local schema = util.copy(tools[name].input_schema)
      schema.properties.review_id = { type = "string", enum = { id } }
      schema.required[#schema.required + 1] = "review_id"
      definitions[#definitions + 1] = { name = "auto_approve_" .. name,
        description = tools[name].description, input_schema = schema }
    end
  end
  return #definitions > 0 and definitions or nil, state, function() pending[id] = nil end
end

return M
