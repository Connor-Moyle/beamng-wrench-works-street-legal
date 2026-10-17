-- Street Legal: the weather of the career (#45). Pure, tested by tools/luatest.js. One weather state per phase (day or night) of each career day, drawn from the
-- save's seed so it is the same when you come back to it: clear, cloudy, rain or (at night) fog. A state sets the sky (rain drops, cloud cover, fog), the
-- grip of the tyres, and a little extra on what jobs and races pay.

local rngLib = require('sl/core/rng')

local M = {}

local strings = require('sl/core/strings')

-- drops: the level's Precipitation numDrops; cloud: CloudLayer coverage; fog: LevelInfo fogDensity (the level's own clear air is 0.00035)
-- grip: a factor on tyre friction; pay: a factor on what is earned
M.STATES = {
  clear = { id = 'clear', name = 'Clear', drops = 0, cloud = 0.35, fog = 0.00035, grip = 1, pay = 1 },
  cloudy = { id = 'cloudy', name = 'Cloudy', drops = 0, cloud = 1, fog = 0.0006, grip = 1, pay = 1 },
  rain = { id = 'rain', name = 'Rain', drops = 350, cloud = 1, fog = 0.0016, grip = 0.78, pay = 1.08 },
  fog = { id = 'fog', name = 'Fog', drops = 0, cloud = 0.8, fog = 0.02, grip = 0.96, pay = 1.04 },
}

-- chance of each state by phase (cumulative order below); fog banks only at night
local ODDS = {
  day = { { 'clear', 0.55 }, { 'cloudy', 0.25 }, { 'rain', 0.20 } },
  night = { { 'clear', 0.40 }, { 'cloudy', 0.20 }, { 'rain', 0.22 }, { 'fog', 0.18 } },
}

-- the state id of a phase of a day, from the career seed
function M.forecast(seed, day, phase)
  phase = phase == 'night' and 'night' or 'day'
  local r = rngLib.new(rngLib.hash('weather:' .. tostring(seed) .. ':' .. tostring(day) .. ':' .. phase)):float()
  local acc = 0
  for _, o in ipairs(ODDS[phase]) do
    acc = acc + o[2]
    if r < acc then return o[1] end
  end
  return ODDS[phase][#ODDS[phase]][1]
end

-- the phase after this one: { phase, day } (the night is followed by the next day)
function M.after(phase, day)
  if phase == 'night' then return 'day', (day or 1) + 1 end
  return 'night', day or 1
end

function M.state(id) return M.STATES[id] or M.STATES.clear end
function M.grip(id) return M.state(id).grip end
function M.pay(id) return M.state(id).pay end

local WORDS = {
  clear = 'Clear', cloudy = 'Cloudy', rain = 'Rain', fog = strings.t('weather.fog_banks'),
}

-- the forecast line: now and what the next phase brings
function M.text(phase, nowId, nextId)
  local now = M.state(nowId)
  local nextPhase = M.after(phase, 1)
  local line = string.format('%s %s', WORDS[now.id], phase == 'night' and 'tonight' or 'today')
  if now.id == 'rain' then line = strings.t('weather.1_wet_roads_less_grip', (line))
  elseif now.id == 'fog' then line = strings.t('weather.1_visibility_is_poor_by', (line)) end
  if nextId then line = line .. string.format('. %s %s', WORDS[M.state(nextId).id], nextPhase == 'night' and 'tonight' or strings.t('weather.by_day')) end
  return line .. '.'
end

-- an amount earned in the weather: pays a little more in the wet (rounded to ten like the career's own pay)
function M.earned(amount, id) return math.floor((amount or 0) * M.pay(id) / 10 + 0.5) * 10 end

-- the sky value between two states, t 0..1 (the change takes a while)
function M.blend(a, b, t)
  t = math.max(0, math.min(1, t or 1))
  local out = {}
  for _, k in ipairs({ 'drops', 'cloud', 'fog', 'grip' }) do out[k] = a[k] + (b[k] - a[k]) * t end
  return out
end

return M
