local M = {}

function M.copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = M.copy(v) end
  return out
end

function M.merge(base, override)
  local out = M.copy(base)
  for k, v in pairs(override) do
    if type(v) == "table" and type(out[k]) == "table" then
      out[k] = M.merge(out[k], v)
    else
      out[k] = M.copy(v)
    end
  end
  return out
end

function M.clip(text, bytes)
  if #text <= bytes then return text end
  local marker = "\n[omitted: byte budget]"
  local n = math.max(0, bytes - #marker)
  -- Do not cut through a UTF-8 sequence.
  while n > 0 and string.byte(text, n + 1) and string.byte(text, n + 1) >= 128
      and string.byte(text, n + 1) < 192 do n = n - 1 end
  return text:sub(1, n) .. marker
end

function M.clean(text, bytes)
  return M.clip(tostring(text):gsub("[%z\1-\31\127]", " "), bytes or 500)
end

function M.encode(value)
  local text, err = maki.json.encode(value)
  if not text then error(err or "JSON encoding failed") end
  return text
end

function M.decode(text)
  local ok, value, err = pcall(maki.json.decode, text)
  if not ok then return nil, tostring(value) end
  return value, err
end

function M.cwd(session)
  if session then
    local snapshot = maki.session.read({ session = session })
    if snapshot and snapshot.cwd then return snapshot.cwd end
  end
  return maki.uv.cwd()
end

return M
