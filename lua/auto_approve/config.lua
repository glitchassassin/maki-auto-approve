local policy = require("auto_approve.policy")
local M = {}

-- Maki merges scalar package options from global and trusted project init.lua.
M.spec = {
  reviewer_model = { default = "", desc = "Reviewer provider/model; empty inherits the calling model." },
  reviewer_thinking = { default = "", desc = "Reviewer thinking level; empty inherits the calling setting." },
  reviewer_timeout_ms = { default = 45000, min = 100, desc = "Total queue and review timeout in milliseconds (100–55000)." },
  reviewer_max_inspections = { default = 8, min = 1, desc = "Read-only inspection calls per review (1–32)." },
  reviewer_max_concurrent = { default = 2, min = 1, desc = "Concurrent reviews; excess calls wait in order (1–8)." },
  context_max_messages = { default = 40, min = 1, desc = "Recent conversation messages included in a review (1–200)." },
  context_max_bytes = { default = 48000, min = 2048, desc = "Action and conversation context byte budget (2048–200000)." },
  context_max_user_bytes = { default = 16000, min = 512, desc = "Recorded user instruction byte budget (512–64000)." },
  inspection_enabled = { default = true, desc = "Offer the reviewer bounded read-only inspection tools." },
  inspection_max_file_bytes = { default = 65536, min = 256, desc = "Bytes per inspected regular UTF-8 file (256–262144)." },
  inspection_max_directory_entries = { default = 100, min = 1, desc = "Entries per one-level directory listing (1–1000)." },
  logging_history_size = { default = 50, min = 1, desc = "Review outcomes retained in memory per session (1–200)." },
  policy_rubric = { default = policy.rubric, desc = "Replacement Guardian security policy (1–64000 bytes)." },
}

local maxima = {
  reviewer_timeout_ms = 55000, reviewer_max_inspections = 32, reviewer_max_concurrent = 8,
  context_max_messages = 200, context_max_bytes = 200000, context_max_user_bytes = 64000,
  inspection_max_file_bytes = 262144, inspection_max_directory_entries = 1000, logging_history_size = 200,
}
local efforts = { [""] = true, off = true, adaptive = true, minimal = true, low = true,
  medium = true, high = true, xhigh = true, max = true }

function M.resolve(options)
  local config = { reviewer = {}, context = {}, inspection = {}, logging = {}, policy = {} }
  for name in pairs(options) do
    if not M.spec[name] then return nil, "unknown option: " .. tostring(name) end
  end
  for name, spec in pairs(M.spec) do
    local value = options[name]
    if value == nil then value = spec.default end
    if type(value) ~= type(spec.default) then return nil, "wrong type for " .. name end
    if maxima[name] and (value % 1 ~= 0 or value < spec.min or value > maxima[name]) then
      return nil, name .. " must be an integer from " .. spec.min .. " to " .. maxima[name]
    end
    if name == "reviewer_thinking" and not efforts[value] then return nil, "unsupported reviewer_thinking" end
    if name == "reviewer_model" and value ~= "" and not value:match("^[^%s/]+/[^%s]+$") then
      return nil, "reviewer_model must be a provider/model spec or empty"
    end
    if name == "policy_rubric" and (not value:match("%S") or #value > 64000) then
      return nil, "policy_rubric must contain 1–64000 bytes of policy text"
    end
    local section, key = name:match("^([^_]+)_(.+)$")
    config[section][key] = value
  end
  return config
end

function M.register()
  local options = maki.api.register_options(M.spec)
  local config, err = M.resolve(options)
  if not config then error("maki-auto-approve: " .. tostring(err)) end
  return config
end

return M
