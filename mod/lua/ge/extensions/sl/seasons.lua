-- Street Legal: the seasons (extension name: sl_seasons; the part: Mods > Street Legal > Parts of the game > Seasons, off by default; docs: Graph SEASONS.md). Rules in sl/core/seasons.
-- A season is four weeks of the career's days. It gives the weather its odds (sl_weather asks forecast), the air its temperature through the game's own day curve (a profile on every phase change)
-- and Car Surface FX the fall with height, makes clear summer days hot for thirst (sl_needs asks hot), changes a few purses (the calendar and the series ask purse) and puts a line on the weather text.

local M = {}

local rules = require('sl/core/seasons')
local features = require('sl/core/features')

local function opt(key, default) local v = sl_options and sl_options.get and tonumber(sl_options.get(key)) return v or default end
local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function seasonOf() local s = career() rules.DAYS_PER_SEASON = opt('slSeasonDays', 28) return s and rules.season(s.day) or nil end

-- the weather state of a phase with the season's odds (nil with the part off: sl_weather then draws its own)
function M.forecast(seed, day, phase) rules.DAYS_PER_SEASON = opt('slSeasonDays', 28) return rules.forecast(seed, day, phase) end
-- is this clear day hot (nil with the part off)
function M.hot(state) local season = seasonOf() return season and rules.hot(season, 'day', state) or false end
-- the factor on a purse of this kind ('sprint', 'series', 'rally', 'meet')
function M.purse(kind) local season = seasonOf() return season and (1 + (rules.purse(kind, season) - 1) * opt('slSeasonPurse', 100) / 100) or 1 end
function M.note() local s = career() rules.DAYS_PER_SEASON = opt('slSeasonDays', 28) return s and rules.note(s.day) or nil end

-- ---- the air: the game's own day curve gets the season's night low and day high; applied once per phase and weather, taken back when the part ends
local applied, lapseOld = false, nil
local function apply()
  local s = career()
  local env = rawget(_G, 'core_environment')
  if not (s and env and env.setTemperatureProfile) then return end
  rules.DAYS_PER_SEASON = opt('slSeasonDays', 28)
  local season = rules.season(s.day)
  local state = sl_weather and sl_weather.state and sl_weather.state() or 'clear'
  local ok, err = pcall(env.setTemperatureProfile, (function() local p = rules.profile(season, state) local o = opt('slSeasonTemp', 0) return { minC = p.minC + o, maxC = p.maxC + o } end)())          -- (a level without the day curve ignores it)
  if ok then applied = true else log('W', 'sl_seasons', 'the temperature profile was refused: ' .. tostring(err)) end
  -- the fall with height only through Car Surface FX (weather.lapse), never also in the profile
  local csfx = rawget(_G, 'carSurfaceFx')
  if csfx and csfx.setSetting and lapseOld == nil then
    local ok2, old = pcall(csfx.setSetting, 'weather', 'lapse', true)
    if ok2 then lapseOld = old == nil and false or old end
  end
end
local function restore()
  if applied and rawget(_G, 'core_environment') and core_environment.resetTemperatureProfile then pcall(core_environment.resetTemperatureProfile) end
  local csfx = rawget(_G, 'carSurfaceFx')
  if lapseOld ~= nil and csfx and csfx.setSetting then pcall(csfx.setSetting, 'weather', 'lapse', lapseOld) end
  applied, lapseOld = false, nil
end

function M.onStreetLegalStarted() apply() end
function M.onStreetLegalWeather() apply() end
function M.onStreetLegalPhase() apply() end
function M.onStreetLegalNewDay() apply() end
function M.onStreetLegalOption(key) if key == 'slSeasons' then if features.on('seasons') then apply() else restore() end end end
function M.onStreetLegalStopped() restore() end
function M.onClientEndMission() applied, lapseOld = false, nil end

function M.status()
  local s = career()
  if not s then return 'no career' end
  rules.DAYS_PER_SEASON = opt('slSeasonDays', 28)
  local season, week = rules.season(s.day)
  return string.format('%s, week %d; profile %s; lapse %s', season, week, tostring(applied), tostring(lapseOld ~= nil))
end

features.gate('seasons', M, nil, { 'onStreetLegalOption' }, { 'forecast', 'hot', 'purse', 'note', 'status' })

return M
