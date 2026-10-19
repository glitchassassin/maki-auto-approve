local toml = require("auto_approve.toml")
local policy = require("auto_approve.policy")
local util = require("auto_approve.util")
local trust = require("auto_approve.trust")
local M = {}

M.defaults = {
  enabled = true,
  project_overrides = true,
  reviewer = { model = "", thinking = "", timeout_ms = 45000, max_inspections = 8, max_concurrent = 2 },
  context = { max_messages = 40, max_bytes = 48000, max_user_bytes = 16000 },
  inspection = { enabled = true, max_file_bytes = 65536, max_directory_entries = 100 },
  policy = { rubric = policy.rubric },
  logging = { history_size = 50 },
}

local ranges = {
  ["reviewer.timeout_ms"] = { 100, 55000 }, ["reviewer.max_inspections"] = { 1, 32 },
  ["reviewer.max_concurrent"] = { 1, 8 }, ["context.max_messages"] = { 1, 200 },
  ["context.max_bytes"] = { 2048, 200000 }, ["context.max_user_bytes"] = { 512, 64000 },
  ["inspection.max_file_bytes"] = { 256, 262144 },
  ["inspection.max_directory_entries"] = { 1, 1000 }, ["logging.history_size"] = { 1, 200 },
}
local efforts = { [""] = true, off = true, adaptive = true, minimal = true, low = true,
  medium = true, high = true, xhigh = true, max = true }

local function validate(part, defaults, prefix)
  for key, value in pairs(part) do
    local path = prefix == "" and key or (prefix .. "." .. key)
    local expected = defaults[key]
    if expected == nil then return nil, "unknown setting: " .. path end
    if type(value) ~= type(expected) then return nil, "wrong type for " .. path end
    if type(value) == "table" then
      local ok, err = validate(value, expected, path)
      if not ok then return nil, err end
    elseif ranges[path] then
      local range = ranges[path]
      if value % 1 ~= 0 or value < range[1] or value > range[2] then
        return nil, path .. " must be an integer from " .. range[1] .. " to " .. range[2]
      end
    elseif path == "reviewer.thinking" and not efforts[value] then
      return nil, "unsupported reviewer.thinking"
    elseif path == "reviewer.model" and value ~= "" and not value:match("^[^%s/]+/[^%s]+$") then
      return nil, "reviewer.model must be a provider/model spec or empty"
    elseif path == "policy.rubric" and (not value:match("%S") or #value > 64000) then
      return nil, "policy.rubric must contain 1–64000 bytes of policy text"
    end
  end
  return true
end

local function read(path)
  local meta, err = maki.fs.metadata(path)
  if err then return nil, err end
  if not meta then return {} end
  if not meta.is_file or meta.size > 131072 then return nil, "config must be a regular file <= 128 KiB" end
  local text, read_err = maki.fs.read(path)
  if not text then return nil, read_err end
  if #text > 131072 then return nil, "config exceeds 128 KiB" end
  local parsed, parse_err = toml.parse(text)
  if not parsed then return nil, parse_err end
  local ok, validation_err = validate(parsed, M.defaults, "")
  if not ok then return nil, validation_err end
  return parsed, nil, text
end

-- Read/validate configuration without applying any project policy. This is also
-- the snapshot displayed for explicit human consent by /auto-approve-trust.
function M.project(cwd)
  local global_dir = maki.env.config_dir()
  if not global_dir then return nil, "Maki config directory is unavailable" end
  local global_path = maki.fs.joinpath(global_dir, "auto-approve.toml")
  local global, err = read(global_path)
  if not global then return nil, global_path .. ": " .. tostring(err) end
  local config = util.merge(M.defaults, global)
  local root = maki.fs.root(cwd, ".git") or cwd
  local project_path = maki.fs.joinpath(root, ".maki", "auto-approve.toml")
  local project, text = {}, nil
  if config.project_overrides and project_path ~= global_path then
    local project_err
    project, project_err, text = read(project_path)
    if not project then return nil, project_path .. ": " .. tostring(project_err) end
    if project.project_overrides ~= nil then return nil, "project_overrides is a global-only setting" end
  end
  return { base = config, project = project, text = text, root = root,
    global_dir = global_dir, global_path = global_path, project_path = project_path }
end

function M.load(cwd)
  local snapshot, err = M.project(cwd)
  if not snapshot then return nil, err end
  local config, project = snapshot.base, snapshot.project
  if next(project) ~= nil then
    -- Requiring manual approvals is safe at every trust level. Every other
    -- project override needs explicit consent, including another model/provider.
    if project.enabled ~= false then
      local trusted, trust_err = trust.check(snapshot.global_dir, snapshot.root, snapshot.text)
      if not trusted then return nil, trust_err or
        "Project policy is untrusted or changed. Review it with /auto-approve-trust." end
    end
    config = util.merge(config, project)
  end
  local root, global_path, project_path = snapshot.root, snapshot.global_path, snapshot.project_path
  config.root, config.global_path, config.project_path = root, global_path, project_path
  return config
end

M.validate = function(part) return validate(part, M.defaults, "") end
return M
