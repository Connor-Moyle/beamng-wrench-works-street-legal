-- Street Legal: where the sun is, for the sky when the game's own sky driver (core_celestial) is not there. Pure (tested by tools/luatest.js).
-- NOAA's low-precision solar position: good to about a degree, which is plenty to tell day from night and to move the light with the clock.
--   position(lat, lon, utcOffset, month, day, hour, year) -> elevation, azimuth   (degrees; azimuth is compass: 0 north, 90 east)
--   utcOffsetFor(lat, lon, dstRule, year, month, day) -> hours east of UTC, the civil time zone the level's clock is in

local M = {}

local rad, deg = math.rad, math.deg

local function dayOfYear(year, month, day)
  local mdays = { 31, (year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)) and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  local n = day
  for i = 1, month - 1 do n = n + mdays[i] end
  return n
end

-- day of week, 0 = Sunday (Sakamoto)
local function dow(y, m, d)
  local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
  if m < 3 then y = y - 1 end
  return (y + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400) + t[m] + d) % 7
end

-- the nth (1-based) Sunday of a month, or the last one (n = 0)
local function sunday(y, m, n)
  if n > 0 then
    local first = 1 + (7 - dow(y, m, 1)) % 7
    return first + 7 * (n - 1)
  end
  local last = ({ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 })[m]
  if m == 2 and y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0) then last = 29 end
  return last - dow(y, m, last)
end

local function dstActive(rule, y, m, d)
  local n = m * 100 + d
  if rule == 'us' then return n >= 300 + sunday(y, 3, 2) and n < 1100 + sunday(y, 11, 1) end
  if rule == 'eu' then return n >= 300 + sunday(y, 3, 0) and n < 1000 + sunday(y, 10, 0) end
  return false
end

function M.utcOffsetFor(lat, lon, rule, y, m, d)
  local std = math.floor(lon / 15 + 0.5)
  if rule == nil or rule == 'auto' then
    rule = lat >= 30 and ((lon > -170 and lon < -30) and 'us' or 'eu') or 'none'      -- (what core_celestial does for the northern temperate belt)
  end
  return std + (dstActive(rule, y, m, d) and 1 or 0)
end

function M.position(lat, lon, utc, month, day, hour, year)
  year = year or 2026
  local n = dayOfYear(year, month, day)
  local g = 2 * math.pi / 365 * (n - 1 + (hour - 12) / 24)
  local decl = 0.006918 - 0.399912 * math.cos(g) + 0.070257 * math.sin(g) - 0.006758 * math.cos(2 * g) + 0.000907 * math.sin(2 * g)
    - 0.002697 * math.cos(3 * g) + 0.00148 * math.sin(3 * g)
  local eqt = 229.18 * (0.000075 + 0.001868 * math.cos(g) - 0.032077 * math.sin(g) - 0.014615 * math.cos(2 * g) - 0.040849 * math.sin(2 * g))
  local solarMinutes = hour * 60 + eqt + 4 * lon - 60 * utc
  local ha = rad(solarMinutes / 4 - 180)
  local la = rad(lat)
  local sinEl = math.sin(la) * math.sin(decl) + math.cos(la) * math.cos(decl) * math.cos(ha)
  local el = math.asin(math.max(-1, math.min(1, sinEl)))
  local cosAz = (math.sin(decl) - math.sin(el) * math.sin(la)) / math.max(1e-9, math.cos(el) * math.cos(la))
  local az = deg(math.acos(math.max(-1, math.min(1, cosAz))))
  if math.sin(ha) > 0 then az = 360 - az end           -- afternoon: the sun is west of south
  return deg(el), az
end

return M
