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
  p = string.gsub(p, "\2", "(%%d+)")
  return "^" .. p .. "$"
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
