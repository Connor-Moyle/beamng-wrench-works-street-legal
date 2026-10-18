-- Wrench Works: Street Legal: its own settings (extension name: sl_options; X53), a "Street Legal" group on
-- the Mods menu in the pause menu (Wrench Works' slrr_settings registry; docs/MODS_MENU.md on its branch mods-menu): this list is the data model, the page is generated from it.
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
  { key = 'slColorBlind', title = strings.t('settings.colorBlind'), type = 'bool', default = false,
    desc = strings.t('settings.colorBlindDesc') },
  { key = 'slCaptions', title = strings.t('settings.captions'), type = 'bool', default = true,
    desc = strings.t('settings.captionsDesc') },
  { key = 'slPerf', title = strings.t('options.performance_overlay'), type = 'bool', default = false,
    desc = strings.t('options.a_small_box_top_left') },
  { key = 'slWallpaper', title = strings.t('options.laptop_wallpaper'), type = 'choice', default = 'windows',
    options = { { id = 'windows', label = strings.t('options.my_windows_wallpaper') }, { id = 'builtin', label = 'Built-in' } },
    desc = strings.t('options.the_laptop_s_desktop_your') },
  { key = 'slAutoPhoto', title = strings.t('options.photo_of_a_new_car'), type = 'bool', default = true,
    desc = strings.t('options.a_new_car_is_photographed') },
  { key = 'slWeather', needs = 'weather', title = 'Weather', type = 'bool', default = true,
    desc = strings.t('options.rain_wet_roads_and_night') },
  { key = 'slRain', needs = 'weather', title = 'Rain', type = 'range', min = 0, max = 0.5, step = 0.02, default = 0.12, unit = '/h',
    desc = strings.t('options.how_often_a_shower_starts') },
}
-- where each setting is on the Mods menu page: { tab, group }
local PLACE = {
  slPolice = { 'Difficulty', 'Police' }, slPoliceLevel = { 'Difficulty', 'Police' }, slRaids = { 'Difficulty', 'Crews' },
  slEconomy = { 'Difficulty', 'Money' }, slHardcore = { 'Difficulty', 'Hardcore' },
  slRaceTraffic = { 'Street racing', 'Races' }, slMarkers = { 'Street racing', 'Races' }, slReplay = { 'Street racing', 'Recording' },
  slClock = { 'Clock and weather', 'Time' }, slWeather = { 'Clock and weather', 'Weather' }, slRain = { 'Clock and weather', 'Weather' },
  slNotify = { 'Screens and texts', 'Texts' }, slDashboard = { 'Screens and texts', 'Dashboard' }, slWallpaper = { 'Screens and texts', 'Laptop' }, slAutoPhoto = { 'Screens and texts', 'Camera' },
  slTextScale = { 'Accessibility', 'Reading' }, slColorBlind = { 'Accessibility', 'Colours' }, slCaptions = { 'Accessibility', 'Rally' },
  slPerf = { 'Developer', 'Performance' },
}
local byKey = {}
for _, d in ipairs(M.defs) do
  d.group = GROUP
  byKey[d.key] = d
  local at = PLACE[d.key]
  if at then d.tab, d.sub = d.tab or at[1], d.sub or at[2] end
end

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

-- The Mods menu page of Street Legal (slrr_settings): every setting above by its tab and group. The career's own settings (police, pay, hardcore, raids) are kept in the
-- career's save: they show their start values and take a change only while a career is played. Developer: the all-the-money button.
function M.onSlrrSettingsReady()
  local S = rawget(_G, 'slrr_settings')
  if not (S and S.fromDefs) then return end
  local defs = {}
  for _, d in ipairs(M.defs) do
    if d.needs ~= 'weather' or (slrrValoWeather and slrrValoWeather.setEnabled) then
      local c = deepcopy(d)
      if d.career then c.desc = tostring(d.desc or '') .. ' ' .. strings.t('options.saved_with_the_career') end
      if d.key == 'slPerf' then c.advanced = true end
      defs[#defs + 1] = c
    end
  end
  local fields, tabs = S.fromDefs(defs, { tabOf = function(d) return d.tab or 'More' end, get = M.get, set = set })
  local developer
  for _, t in ipairs(tabs) do if t.id == 'Developer' then developer = t end end
  if not developer then developer = { id = 'Developer', title = 'Developer' } tabs[#tabs + 1] = developer end
  -- the dashboard's parts (kept in hud.json by sl_hud): once the dashboard itself is on
  local function hudField(key, label, tip, kind, extra)
    local f = { id = 'hud_' .. key, tab = 'Screens and texts', group = 'Dashboard', type = kind, label = label, tooltip = tip, default = extra and extra.default,
      visibleIf = { field = 'slDashboard', equals = true },
      store = { kind = 'custom', get = function() local h = sl_hud and sl_hud.getSettings and sl_hud.getSettings() return h and h[key] end,
        set = function(v) if sl_hud and sl_hud.setOption then sl_hud.setOption(key, v) end end } }
    for k, v in pairs(extra or {}) do f[k] = v end
    fields[#fields + 1] = f
  end
  hudField('tacho', 'Rev counter', 'The rev counter of the Street Legal dashboard.', 'bool', { default = true })
  hudField('speedo', 'Speedometer', 'The speedometer of the Street Legal dashboard.', 'bool', { default = true })
  hudField('map', 'Map', 'The map that turns with the car.', 'bool', { default = true })
  hudField('damage', 'Damage diagram', 'The diagram of the car\'s damage.', 'bool', { default = true })
  hudField('units', 'Units', 'Speed in km/h or mph on the dashboard.', 'enum', { default = 'kmh', options = { { id = 'kmh', label = 'km/h' }, { id = 'mph', label = 'mph' } } })
  hudField('freeroam', 'Also outside the career', 'Shows the dashboard in freeroam as well.', 'bool', { default = false })
  fields[#fields + 1] = { id = 'devMoney', tab = 'Developer', group = 'Testing', type = 'button', label = strings.t('ui.give_all_the_money'), advanced = true,
    tooltip = strings.t('ui.for_testing_the_money_goes'),
    action = function() local ok, text = sl_career.devMoney() return text or '' end }
  for _, f in ipairs(fields) do if f.tab == 'Accessibility' then f.group = f.group or 'Reading' end end
  S.register({ mod = 'street_legal', title = 'Street Legal', icon = 'wrench', order = 20, tabs = tabs, fields = fields })
end
M.onExtensionLoaded = M.onSlrrSettingsReady

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
M.onStreetLegalRaceCancelled = restoreTraffic
M.onSlrrRaceFinished = restoreTraffic
M.onStreetLegalStopped = restoreTraffic
function M.onUpdate() if savedAt and os.clock() - savedAt > 900 then restoreTraffic() end end
function M.onClientEndMission() saved, savedAt = nil, nil end

return M
