-- Street Legal: the seasons of the career (campaign idea #11; the control repo's docs/SEASONS.md). Pure, no game calls: tested by tools/seasons_test.lua through tools/luatest.js.
-- A season is four weeks of the week counter (28 days), in the order spring, summer, autumn, winter; a year is 112 days and the career starts in spring. A season only changes
-- (1) the odds of the weather states (sl/core/weather.lua draws a state from the save's seed: here the same draw with the odds of the season), (2) the air temperature (sea level and
-- a fall with height), which is what makes the rain of a cold phase fall as snow in Car Surface FX (precipitation with the air below 1.5 C), (3) whether clear weather counts as hot
-- for thirst (sl/core/needs.lua), and (4) a few percent on what some events pay. Nothing here touches a material: more rain is more rain drops and more wetness of the game's own
-- weather, never more material reloads (the wet world is the terrain layers only, and off by default).

local rngLib = require('sl/core/rng')

local M = {}

M.DAYS_PER_SEASON = 28
M.ORDER = { 'spring', 'summer', 'autumn', 'winter' }
M.NAMES = { spring = 'Spring', summer = 'Summer', autumn = 'Autumn', winter = 'Winter' }

-- the season of a career day (day 1 is the first day of spring) and the week of it (1 to 4)
function M.season(day)
  local d = math.max(1, math.floor(tonumber(day) or 1))
  local i = math.floor((d - 1) / M.DAYS_PER_SEASON) % #M.ORDER + 1
  return M.ORDER[i], math.floor(((d - 1) % M.DAYS_PER_SEASON) / 7) + 1
end

-- chance of each weather state by season and phase; every list adds up to 1; fog banks only at night (as the plain odds of sl/core/weather.lua, which are the spring-summer middle)
M.ODDS = {
  spring = { day = { { 'clear', 0.50 }, { 'cloudy', 0.25 }, { 'rain', 0.25 } }, night = { { 'clear', 0.38 }, { 'cloudy', 0.20 }, { 'rain', 0.26 }, { 'fog', 0.16 } } },
  summer = { day = { { 'clear', 0.72 }, { 'cloudy', 0.18 }, { 'rain', 0.10 } }, night = { { 'clear', 0.55 }, { 'cloudy', 0.18 }, { 'rain', 0.12 }, { 'fog', 0.15 } } },
  autumn = { day = { { 'clear', 0.45 }, { 'cloudy', 0.28 }, { 'rain', 0.27 } }, night = { { 'clear', 0.32 }, { 'cloudy', 0.20 }, { 'rain', 0.22 }, { 'fog', 0.26 } } },
  winter = { day = { { 'clear', 0.40 }, { 'cloudy', 0.30 }, { 'rain', 0.30 } }, night = { { 'clear', 0.28 }, { 'cloudy', 0.20 }, { 'rain', 0.26 }, { 'fog', 0.26 } } },
}

function M.odds(season, phase)
  local s = M.ODDS[season] or M.ODDS.spring
  return s[phase == 'night' and 'night' or 'day']
end

-- the state id of a phase of a day: the draw of sl/core/weather.lua forecast (the same key, so the same random number) with the odds of the season
function M.forecast(seed, day, phase)
  phase = phase == 'night' and 'night' or 'day'
  local list = M.odds((M.season(day)), phase)
  local r = rngLib.new(rngLib.hash('weather:' .. tostring(seed) .. ':' .. tostring(day) .. ':' .. phase)):float()
  local acc = 0
  for _, o in ipairs(list) do
    acc = acc + o[2]
    if r < acc then return o[1] end
  end
  return list[#list][1]
end

-- ---- air temperature (C): by season and phase at sea level, falling with height; the game's own sea-level temperature is what Car Surface FX reads for snow
M.SEA_LEVEL = {
  spring = { day = 18, night = 11 }, summer = { day = 29, night = 19 }, autumn = { day = 18, night = 10 }, winter = { day = 10, night = 5 },
}
M.LAPSE = 0.0065                  -- C lost per metre of height (the standard atmosphere)
M.RAIN_COOL = 2                   -- rain and cloud take this much off a phase's air (clear is as listed)

function M.airC(season, phase, state, altitude)
  local s = M.SEA_LEVEL[season] or M.SEA_LEVEL.spring
  local t = s[phase == 'night' and 'night' or 'day']
  if state == 'rain' or state == 'cloudy' then t = t - M.RAIN_COOL end
  return t - M.LAPSE * math.max(0, tonumber(altitude) or 0)
end

M.SNOW_BELOW = 1.5               -- C: what Car Surface FX counts as cold enough for snow (rules.SNOW_AIR there)

-- does the rain of this phase fall as snow at this height (the same rule Car Surface FX applies to the air temperature it reads)
function M.snows(season, phase, state, altitude)
  return state == 'rain' and M.airC(season, phase, state, altitude) < M.SNOW_BELOW
end

-- the lowest height at which a rainy phase snows, or nil when it never does (for the phone's weather line: "snow above 640 m")
function M.snowLine(season, phase)
  local sea = M.airC(season, phase, 'rain', 0)
  if sea < M.SNOW_BELOW then return 0 end
  return math.ceil((sea - M.SNOW_BELOW) / M.LAPSE)
end

-- ---- thirst: clear weather by day counts as hot only in summer (needs.lua: ctx.hot); the milder seasons do not raise thirst
function M.hot(season, phase, state)
  return phase ~= 'night' and state == 'clear' and season == 'summer'
end

-- ---- events: a few percent on the purse by kind and season. kind: 'sprint' (the weekend sprints), 'series' (the monthly series), 'rally' (the gravel series), 'meet' (car meets and shows)
M.PURSE = {
  sprint = { spring = 1.00, summer = 1.00, autumn = 1.00, winter = 1.08 },
  series = { spring = 1.00, summer = 1.05, autumn = 1.00, winter = 1.00 },
  rally = { spring = 1.00, summer = 1.00, autumn = 1.10, winter = 1.10 },
  meet = { spring = 1.00, summer = 1.15, autumn = 1.00, winter = 0.90 },
}
function M.purse(kind, season)
  local k = M.PURSE[kind]
  return k and k[season] or 1
end

-- a one-line weather note for the phone: "Winter, week 2: snow above 940 m on rainy nights"
function M.note(day)
  local season, week = M.season(day)
  local line = M.snowLine(season, 'night')
  local text = string.format('%s, week %d', M.NAMES[season], week)
  if line and line < 1500 then text = text .. (line == 0 and ': rain falls as snow at night' or string.format(': snow above %d m on rainy nights', line)) end
  return text
end

return M
