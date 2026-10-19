-- A strict TOML subset for this plugin's configuration: tables, dotted/bare
-- keys, booleans, decimal integers, and basic/literal strings (also multiline).
-- Unsupported TOML types are errors, never silently ignored.
local M = {}

function M.parse(input)
  if type(input) ~= "string" then return nil, "expected TOML text" end
  local src = input:gsub("\r\n", "\n")
  local pos, len, root, current, declared = 1, #src, {}, nil, {}
  current = root
  local function fail(msg)
    local _, lines = src:sub(1, pos):gsub("\n", "")
    error("line " .. (lines + 1) .. ": " .. msg, 0)
  end
  local function peek(n) return src:sub(pos, pos + (n or 1) - 1) end
  local function spaces()
    while peek() == " " or peek() == "\t" do pos = pos + 1 end
  end
  local function eol()
    spaces()
    if peek() == "#" then
      pos = src:find("\n", pos, true) or (len + 1)
    end
    if pos <= len and peek() ~= "\n" then fail("unexpected trailing content") end
    if peek() == "\n" then pos = pos + 1 end
  end
  local escapes = { b = "\b", t = "\t", n = "\n", f = "\f", r = "\r", ['"'] = '"', ['\\'] = '\\' }
  local function quoted()
    local quote = peek()
    local multiline = peek(3) == string.rep(quote, 3)
    local delimiter = multiline and string.rep(quote, 3) or quote
    pos = pos + #delimiter
    if multiline and peek() == "\n" then pos = pos + 1 end
    local parts = {}
    while pos <= len do
      if peek(#delimiter) == delimiter then
        pos = pos + #delimiter
        return table.concat(parts)
      end
      local ch = peek()
      if ch == "\n" and not multiline then fail("newline in single-line string") end
      if ch:byte() < 32 and ch ~= "\t" and ch ~= "\n" then fail("control character in string") end
      if quote == '"' and ch == "\\" then
        pos = pos + 1
        ch = peek()
        if multiline and (ch == "\n" or ch == " " or ch == "\t") then
          spaces()
          if peek() ~= "\n" then fail("expected newline after multiline continuation") end
          repeat pos = pos + 1 until peek() ~= "\n" and peek() ~= " " and peek() ~= "\t"
        elseif ch == "u" or ch == "U" then
          local n = ch == "u" and 4 or 8
          local hex = src:sub(pos + 1, pos + n)
          if #hex ~= n or not hex:match("^%x+$") then fail("invalid Unicode escape") end
          local cp = tonumber(hex, 16)
          if cp > 1114111 or (cp >= 55296 and cp <= 57343) then fail("invalid Unicode code point") end
          parts[#parts + 1] = utf8.char(cp)
          pos = pos + n + 1
        elseif escapes[ch] then
          parts[#parts + 1] = escapes[ch]
          pos = pos + 1
        else fail("invalid escape") end
      else
        parts[#parts + 1] = ch
        pos = pos + 1
      end
    end
    fail("unterminated string")
  end
  local function keypath(text)
    local keys = {}
    for raw in (text .. "."):gmatch("(.-)%.") do
      local segment = raw:match("^%s*(.-)%s*$")
      if not segment:match("^[A-Za-z0-9_-]+$") then fail("expected bare key") end
      keys[#keys + 1] = segment
    end
    return keys
  end
  local function assign(base, keys, value)
    for i = 1, #keys - 1 do
      local key = keys[i]
      if base[key] == nil then base[key] = {} end
      if type(base[key]) ~= "table" then fail("key conflicts with value") end
      base = base[key]
    end
    local key = keys[#keys]
    if base[key] ~= nil then fail("duplicate key: " .. key) end
    base[key] = value
  end
  local function value()
    if peek() == '"' or peek() == "'" then return quoted() end
    local start = pos
    while pos <= len and not peek():match("[%s#]") do pos = pos + 1 end
    local token = src:sub(start, pos - 1)
    if token == "true" then return true end
    if token == "false" then return false end
    if token:match("^[+-]?%d[%d_]*$") and not token:match("__") and token:sub(-1) ~= "_" then
      local digits = token:gsub("_", ""):gsub("^[+-]", "")
      if #digits > 1 and digits:sub(1, 1) == "0" then fail("leading zero in integer") end
      local number = tonumber((token:gsub("_", "")))
      if number and math.abs(number) <= 9007199254740991 then return number end
    end
    fail("unsupported or invalid value (expected string, integer, or boolean)")
  end
  local ok, result = pcall(function()
    while pos <= len do
      spaces()
      if peek() == "\n" or peek() == "#" then eol()
      elseif pos > len then break
      elseif peek() == "[" then
        local close = src:find("]", pos + 1, true)
        if not close then fail("unterminated table") end
        local keys = keypath(src:sub(pos + 1, close - 1))
        local name = table.concat(keys, ".")
        if declared[name] then fail("duplicate table: " .. name) end
        declared[name] = true
        current = root
        for _, key in ipairs(keys) do
          if current[key] == nil then current[key] = {} end
          if type(current[key]) ~= "table" then fail("table conflicts with value") end
          current = current[key]
        end
        pos = close + 1
        eol()
      else
        local equal = src:find("=", pos, true)
        local newline = src:find("\n", pos, true)
        if not equal or (newline and equal > newline) then fail("expected key = value") end
        local keys = keypath(src:sub(pos, equal - 1))
        pos = equal + 1
        spaces()
        assign(current, keys, value())
        eol()
      end
    end
    return root
  end)
  if not ok then return nil, tostring(result) end
  return result
end

return M
