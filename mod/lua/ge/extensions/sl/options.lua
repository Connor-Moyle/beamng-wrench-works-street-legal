-- Wrench Works: Street Legal: its own settings (extension name: sl_options; X53), a "Street Legal" group on
-- Wrench Works' settings screen (through its onWrenchWorksSettingsDefs / onWrenchWorksSetting hooks).
-- What changes the game's balance is the career's own (kept in its save, per slot, and shown only while one is
-- played); the rest is the player's, for every career (/settings/street_legal/options.json).

local M = {}

local strings = require('sl/core/strings')

local FILE = '/settings/street_legal/options.json'
local GROUP = 'Street Legal'

local LEVELS = { { id = 'all', label = 'Every text' }, { id = 'important', label = 'Racers only' }, { id = 'off', label = 'None' } }
M.defs = {
  { key = 'slPolice', career = true, title = 'Police', type = 'bool', default = true,
    desc = 'Patrols at night, heat from racing, fines. Off: no police at all (this career).' },
  { key = 'slPoliceLevel', career = true, title = 'Police aggression', type = 'range', min = 0.5, max = 2, step = 0.25, default = 1, unit = 'x',
    desc = 'How many patrols, and how likely one joins a street race (this career).' },
  { key = 'slEconomy', career = true, title = 'Pay', type = 'range', min = 0.5, max = 2, step = 0.25, default = 1, unit = 'x',
    desc = 'What jobs, purses and season prizes pay (this career). Bets and prices are not changed.' },
  { key = 'slHardcore', career = true, title = 'Hardcore', type = 'bool', default = false,
    desc = 'No paid pull back to the road (a car off the road needs the tow truck), no free cab when broke, no insurance. A pink slip lost is gone, as always (this career).' },
  { key = 'slRaids', career = true, title = 'Crew raids', type = 'bool', default = true,
    desc = 'A crew you took a district from may smash the lights of a car you left out on the street (never in the garage; you hear of it a day before) (this career).' },
  { key = 'slRaceTraffic', title = 'Traffic in street races', type = 'choice', default = 'normal',
    options = { { id = 'normal', label = 'As usual' }, { id = 'light', label = 'Light' }, { id = 'none', label = 'None' } },
    desc = 'Thins out the town\'s traffic while you race on the street, and puts it back after.' },
  { key = 'slMarkers', title = 'Race flares and start lines', type = 'bool', default = true,
    desc = 'The flares along a race route and the start banners. The route on the road stays.' },
  { key = 'slNotify', title = 'Text pop-ups', type = 'choice', default = 'all', options = LEVELS,
    desc = 'Which new texts pop up on screen. They all still land in Messages.' },
  { key = 'slClock', title = 'Clock speed', type = 'choice', default = 'slow',
    options = { { id = 'slow', label = 'Slow (2.5 min an hour)' }, { id = 'normal', label = 'Normal (1.25 min an hour)' }, { id = 'fast', label = 'Fast (0.6 min an hour)' } },
    desc = 'How fast the in-game clock runs inside the day or the night. It stops at the end of each; Start the night / Start the day moves on.' },
  { key = 'slDashboard', title = 'SLRR dashboard', type = 'bool', default = false,
    desc = 'The SLRR gauges, map and damage diagram instead of the HUD apps of BeamNG itself while you drive the career. Off: the stock BeamNG layout (speedo, rev counter, minimap, damage...) as you have set it up.' },
  { key = 'slReplay', title = 'Record street races', type = 'bool', default = true,
    desc = 'Records a street race with the game\'s replay so the phone can show it again (Watch replay) or keep it (Save clip). The last race that was not saved is deleted when the next one starts.' },
  { key = 'slTextScale', title = strings.t('settings.textSize'), type = 'choice', default = 'normal',
    options = { { id = 'normal', label = strings.t('settings.textNormal') }, { id = 'large', label = strings.t('settings.textLarge') }, { id = 'huge', label = strings.t('settings.textHuge') } },
    desc = strings.t('settings.textSizeDesc') },
  { key = 'slPerf', title = 'Performance overlay', type = 'bool', default = false,
    desc = 'A small box top-left with the frame time, fps, the worst frame of the last 10 seconds, video memory and how many cars, people and objects are about. For reporting stutters. Also a key (Options, Controls: Street Legal: performance overlay).' },
  { key = 'slWallpaper', title = 'Laptop wallpaper', type = 'choice', default = 'windows',
    options = { { id = 'windows', label = 'My Windows wallpaper' }, { id = 'builtin', label = 'Built-in' } },
    desc = 'The laptop\'s desktop. Your own wallpaper is used after tools/wallpaper.ps1 (Wrench Works: Street Legal) has copied it into the game\'s user folder; without that, the built-in one.' },
  { key = 'slWeather', needs = 'weather', title = 'Weather', type = 'bool', default = true,
    desc = 'Rain, wet roads and night fog in Valo City. Off: always clear.' },
  { key = 'slRain', needs = 'weather', title = 'Rain', type = 'range', min = 0, max = 0.5, step = 0.02, default = 0.12, unit = '/h',
    desc = 'How often a shower starts (chance per in-game hour).' },
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
