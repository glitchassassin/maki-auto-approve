-- Local consent records are outside repositories and bind exact project bytes.
local util = require("auto_approve.util")
local M = {}
local MAX_BYTES = 4194304

function M.path(directory) return maki.fs.joinpath(directory, "auto-approve-trust.json") end

local function load(directory)
  local path = M.path(directory)
  local meta, err = maki.fs.metadata(path)
  if err then return nil, err end
  if not meta then return { version = 1, projects = {} } end
  if not meta.is_file or meta.size > MAX_BYTES then return nil, "Invalid project trust file size/type." end
  local text, read_err = maki.fs.read(path)
  if not text then return nil, read_err end
  if #text > MAX_BYTES then return nil, "Project trust file is too large." end
  local data, decode_err = util.decode(text)
  if type(data) ~= "table" or data.version ~= 1 or type(data.projects) ~= "table" then
    return nil, decode_err or "Invalid project trust file."
  end
  for root, record in pairs(data.projects) do
    if type(root) ~= "string" or type(record) ~= "table" or type(record.text) ~= "string"
        or #record.text > 131072 then return nil, "Invalid project trust record." end
  end
  return data
end

function M.check(directory, root, text)
  local data, err = load(directory)
  if not data then return nil, "Could not read project policy trust: " .. tostring(err) end
  return data.projects[root] ~= nil and data.projects[root].text == text
end

function M.save(directory, root, text)
  local data, err = load(directory)
  if not data then return nil, err end
  if text == nil then data.projects[root] = nil else data.projects[root] = { text = text } end
  local encoded = util.encode(data)
  if #encoded > MAX_BYTES then return nil, "Project trust store exceeds 4 MiB; revoke unused entries." end
  return maki.fs.atomic_write(M.path(directory), encoded)
end

return M
