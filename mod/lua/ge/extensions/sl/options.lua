-- Wrench Works: Street Legal: its own settings (extension name: sl_options; X53), a "Street Legal" group on
-- Wrench Works' settings screen (through its onWrenchWorksSettingsDefs / onWrenchWorksSetting hooks).
-- What changes the game's balance is the career's own (kept in its save, per slot, and shown only while one is
-- played); the rest is the player's, for every career (/settings/street_legal/options.json).

local M = {}

local strings = require('sl/core/strings')

local FILE = '/settings/street_legal/options.json'
local GROUP = strings.t('options.street_legal')

local LEVELS = { { id = 'all', label = strings.t('options.every_text') }, { id = 'important', label = strings.t('options.racers_only') }, { id = 'off', label = 'None' } }
M.defs = {
  { key = 'slPolice', career = true, title = 'Police', type = 'bool', default = true,
    desc = strings.t('options.patrols_at_night_heat_from') },
  { key = 'slPoliceLevel', career = true, title = strings.t('options.police_aggression'), type = 'range', min = 0.5, max = 2, step = 0.25, default = 1, unit = 'x',
    desc = strings.t('options.how_many_patrols_and_how') },
  { key = 'slEconomy', career = true, title = 'Pay', type = 'range', min = 0.5, max = 2, step = 0.25, default = 1, unit = 'x',
    desc = strings.t('options.what_jobs_purses_and_season') },
  { key = 'slHardcore', career = true, title = 'Hardcore', type = 'bool', default = false,
    desc = strings.t('options.no_paid_pull_back_to') },
  { key = 'slRaids', career = true, title = strings.t('options.crew_raids'), type = 'bool', default = true,
    desc = strings.t('options.a_crew_you_took_a') },
  { key = 'slRaceTraffic', title = strings.t('options.traffic_in_street_races'), type = 'choice', default = 'normal',
    options = { { id = 'normal', label = strings.t('options.as_usual') }, { id = 'light', label = 'Light' }, { id = 'none', label = 'None' } },
    desc = strings.t('options.thins_out_the_town_s') },
  { key = 'slMarkers', title = strings.t('options.race_flares_and_start_lines'), type = 'bool', default = true,
    desc = strings.t('options.the_flares_along_a_race') },
  { key = 'slNotify', title = strings.t('options.text_pop_ups'), type = 'choice', default = 'all', options = LEVELS,
    desc = strings.t('options.which_new_texts_pop_up') },
  { key = 'slClock', title = strings.t('options.clock_speed'), type = 'choice', default = 'slow',
    options = { { id = 'slow', label = strings.t('options.slow_2_5_min_an') }, { id = 'normal', label = strings.t('options.normal_1_25_min_an') }, { id = 'fast', label = strings.t('options.fast_0_6_min_an') } },
    desc = strings.t('options.how_fast_the_in_game') },
  { key = 'slDashboard', title = strings.t('options.slrr_dashboard'), type = 'bool', default = false,
    desc = strings.t('options.the_slrr_gauges_map_and') },
  { key = 'slReplay', title = strings.t('options.record_street_races'), type = 'bool', default = true,
    desc = strings.t('options.records_a_street_race_with') },
  { key = 'slTextScale', title = strings.t('settings.textSize'), type = 'choice', default = 'normal',
    options = { { id = 'normal', label = strings.t('settings.textNormal') }, { id = 'large', label = strings.t('settings.textLarge') }, { id = 'huge', label = strings.t('settings.textHuge') } },
    desc = strings.t('settings.textSizeDesc') },
  { key = 'slPerf', title = strings.t('options.performance_overlay'), type = 'bool', default = false,
    desc = strings.t('options.a_small_box_top_left') },
  { key = 'slWallpaper', title = strings.t('options.laptop_wallpaper'), type = 'choice', default = 'windows',
    options = { { id = 'windows', label = strings.t('options.my_windows_wallpaper') }, { id = 'builtin', label = 'Built-in' } },
    desc = strings.t('options.the_laptop_s_desktop_your') },
  { key = 'slWeather', needs = 'weather', title = 'Weather', type = 'bool', default = true,
    desc = strings.t('options.rain_wet_roads_and_night') },
  { key = 'slRain', needs = 'weather', title = 'Rain', type = 'range', min = 0, max = 0.5, step = 0.02, default = 0.12, unit = '/h',
    desc = strings.t('options.how_often_a_shower_starts') },
}
local byKey = {}
for _, d in ipairs(M.defs) do d.group = GROUP byKey[d.key] = d end

local global

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

local function sanitize(d, v)
  if d.type == 'bool' then if type(v) == 'boolean' then return v end return d.default end
  if d.type == 'choice' then for _, o in ipairs(d.options) do if o.id == v then return v end end return d.default end
  v = tonumber(v)
  return v and math.max(d.min, math.min(d.max, v)) or d.default
end

local function loadGlobal()
  if global then return global end
  local data = jsonReadFile(FILE)
  global = type(data) == 'table' and data or {}
  return global
end

-- the value of a setting now (the career's own for the career's settings; their default with no career)
function M.get(key)
  local d = byKey[key]
  if not d then return nil end
  if d.needs == 'weather' then
    local w = slrrValoWeather and slrrValoWeather.getState and slrrValoWeather.getState() or {}
    if key == 'slWeather' then return w.enabled ~= false end
    return w.rainChance or d.default
  end
  local src = d.career and ((career() or {}).options or {}) or loadGlobal()
  local v = src[key]
  if v == nil then return d.default end
  return sanitize(d, v)
end

local function set(key, value)
  local d = byKey[key]
  if not d then return false end
  value = sanitize(d, value)
  if d.needs == 'weather' then
    if not slrrValoWeather then return false end
    if key == 'slWeather' and slrrValoWeather.setEnabled then slrrValoWeather.setEnabled(value) end
    if key == 'slRain' and slrrValoWeather.setRainChance then slrrValoWeather.setRainChance(value) end
  elseif d.career then
    local s = career()
    if not s then return false end
    s.options = s.options or {}
    s.options[key] = value
    extensions.hook('onStreetLegalChanged')
  else
    loadGlobal()[key] = value
    jsonWriteFile(FILE, global, true)
  end
  extensions.hook('onStreetLegalOption', key, value)
  return true
end
M.set = set

-- Wrench Works' settings screen: the group (the career's settings only while a career is played)
function M.onWrenchWorksSettingsDefs(defs)
  local inCareer = career() ~= nil
  for _, d in ipairs(M.defs) do
    local show = (not d.career or inCareer) and (d.needs ~= 'weather' or (slrrValoWeather and slrrValoWeather.setEnabled))
    if show then
      local c = deepcopy(d)
      c.value = M.get(d.key)
      defs[#defs + 1] = c
    end
  end
end

function M.onWrenchWorksSetting(key, value)
  if key == '__reset' then
    global = {}
    jsonWriteFile(FILE, global, true)
    local s = career()
    if s then s.options = {} end
    return
  end
  set(key, value)
end

----------------------------------------------------------------------------------------------
-- traffic in street races: thinned while a race runs, put back after (and after 15 minutes whatever happens)

local saved, savedAt
local function restoreTraffic()
  if saved and gameplay_traffic and gameplay_traffic.setActiveAmount then gameplay_traffic.setActiveAmount(saved) end
  saved, savedAt = nil, nil
end
local function thinTraffic()
  local mode = M.get('slRaceTraffic')
  if mode == 'normal' or saved or not (gameplay_traffic and gameplay_traffic.setActiveAmount and gameplay_traffic.getTrafficVars) then return end
  saved = (gameplay_traffic.getTrafficVars() or {}).activeAmount or math.huge
  savedAt = os.clock()
  gameplay_traffic.setActiveAmount(mode == 'none' and 0 or math.min(3, saved))
end
M.onStreetLegalRaceStarted = thinTraffic
M.onSlrrRaceStarted = function() if career() then thinTraffic() end end
M.onStreetLegalRaceResult = restoreTraffic
M.onSlrrRaceFinished = restoreTraffic
M.onStreetLegalStopped = restoreTraffic
function M.onUpdate() if savedAt and os.clock() - savedAt > 900 then restoreTraffic() end end
function M.onClientEndMission() saved, savedAt = nil, nil end

return M
