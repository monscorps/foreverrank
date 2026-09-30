-- ForeverProbe :: Util (ported from LevelPace's tested helpers)
local ADDON, NS = ...
local util = {}
NS.util = util

function util.ConvertGlobalString(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt
  p = string.gsub(p, "([%^%(%)%.%[%]%*%+%-%?])", "%%%1")
  p = string.gsub(p, "%%(%d)%$s", "\1")
  p = string.gsub(p, "%%(%d)%$d", "\2")
  p = string.gsub(p, "%%s", "\1")
  p = string.gsub(p, "%%d", "\2")
  p = string.gsub(p, "%$", "%%$")
  p = string.gsub(p, "\1", "(.-)")
  -- numbers may carry thousands separators ("1,234" or "1.234")
  p = string.gsub(p, "\2", "(%%d[%%d,%%.]*)")
  return "^" .. p .. "$"
end

-- "1,234" -> 1234; nil stays nil
function util.Num(v)
  if v == nil then return nil end
  return tonumber((tostring(v):gsub("[^%d]", "")))
end

-- pcall that hands back every return value (a three-value version dropped guild levels and professions)
local function pass(ok, ...)
  if ok then return ... end
end
function util.Safe(fn, ...)
  if not fn then return nil end
  return pass(pcall(fn, ...))
end

-- a value Blizzard's restricted-combat rules hide from addons
function util.Secret(x)
  return issecretvalue ~= nil and issecretvalue(x) and true or false
end

-- the character this is about: name-realm, the way the pace history has always keyed it
function util.CharKey()
  local realm = GetRealmName and GetRealmName() or "?"
  return (UnitName("player") or "?") .. "-" .. realm
end

function util.FormatTime(sec)
  if type(sec) ~= "number" or sec ~= sec or sec < 0 or sec == math.huge then return "--" end
  sec = math.floor(sec)
  if sec < 60 then return sec .. "s" end
  if sec < 3600 then return string.format("%dm", math.floor(sec / 60)) end
  return string.format("%dh %dm", math.floor(sec / 3600), math.floor((sec % 3600) / 60))
end

function util.Short(n)
  if type(n) ~= "number" then return "--" end
  if n >= 100000 then return string.format("%.0fk", n / 1000) end
  if n >= 10000 then return string.format("%.1fk", n / 1000) end
  return tostring(math.floor(n + 0.5))
end

function util.Median(list)
  if type(list) ~= "table" then return nil end
  local n = #list
  if n == 0 then return nil end
  local copy = {}
  for i = 1, n do copy[i] = list[i] end
  table.sort(copy)
  if n % 2 == 1 then return copy[(n + 1) / 2] end
  return (copy[n / 2] + copy[n / 2 + 1]) / 2
end

function util.Percentile(list, p)
  local n = #list
  if n == 0 then return nil end
  local copy = {}
  for i = 1, n do copy[i] = list[i] end
  table.sort(copy)
  local idx = math.floor(p * (n - 1)) + 1
  if idx < 1 then idx = 1 end
  if idx > n then idx = n end
  return copy[idx]
end

function util.PushBounded(list, value, maxN)
  list[#list + 1] = value
  while #list > maxN do table.remove(list, 1) end
end

-- run it; if it fails, note where and why (once per message, with a count) and carry on.
-- /probe debug lists them, so "it didn't work" comes with the reason.
function util.Try(where, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and NS.db then
    local okDb, d = pcall(NS.db)
    if okDb and d and d.meta then
      local list = d.meta.errors or {}
      d.meta.errors = list
      local msg = tostring(err)
      for _, e in ipairs(list) do
        if e.msg == msg then e.n = (e.n or 1) + 1; return false end
      end
      list[#list + 1] = { where = where, msg = msg, n = 1, v = NS.version }
      while #list > 20 do table.remove(list, 1) end
    end
  end
  return ok
end

