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

-- rain comes in three strengths (the state stays 'rain'; the level of it is drawn from the seed too). A level changes what the sky does:
-- drops (Precipitation numOfDrops), speed (a factor on the drops' own speeds), cloud (CloudLayer coverage; the game has no sky brightness any more, a thick
-- overcast is what darkens it), cirrus / density (the high cloud over it), fog (kept thin: a thick fog takes the sun's colour, and at dawn that is an orange
-- dust storm), tint (0..1: how far the sky's sun, fog and ambient colours are pulled to grey), dark (0..1: how much darker the sky's light, ambient, fog and clouds are made: moody, still day), grip, pay, wet (how wet the roads get at most, 0..1)
M.RAIN_LEVELS = {
  light = { id = 'light', name = 'Light rain', drops = 600, speed = 0.85, cloud = 1.3, cirrus = 0.6, density = 0.6, fog = 0.0005, grip = 0.88, pay = 1.04, wet = 0.45, tint = 0.5, dark = 0.4 },
  medium = { id = 'medium', name = 'Rain', drops = 1500, speed = 1, cloud = 1.8, cirrus = 0.85, density = 0.85, fog = 0.0006, grip = 0.78, pay = 1.08, wet = 0.8, tint = 0.75, dark = 0.65 },
  heavy = { id = 'heavy', name = 'Heavy rain', drops = 3000, speed = 1.25, cloud = 2.4, cirrus = 1, density = 1, fog = 0.0008, grip = 0.68, pay = 1.12, wet = 1, tint = 0.95, dark = 0.85 },
}
M.LEVEL_ODDS = { { 'light', 0.35 }, { 'medium', 0.45 }, { 'heavy', 0.20 } }

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

-- how hard it rains in a phase of a day (only meaningful when the state is rain)
function M.level(seed, day, phase)
  phase = phase == 'night' and 'night' or 'day'
  local r = rngLib.new(rngLib.hash('rainlevel:' .. tostring(seed) .. ':' .. tostring(day) .. ':' .. phase)):float()
  local acc = 0
  for _, o in ipairs(M.LEVEL_ODDS) do
    acc = acc + o[2]
    if r < acc then return o[1] end
  end
  return 'heavy'
end

-- the sky numbers of a state (and rain level): a copy, with the keys the sky blend moves. cirrus / density / speed are nil where the level's own are kept.
function M.resolve(id, level)
  local base = M.state(id)
  local out = { id = base.id, name = base.name, drops = base.drops, cloud = base.cloud, fog = base.fog, grip = base.grip, pay = base.pay, wet = 0 }
  if base.id == 'rain' then
    local l = M.RAIN_LEVELS[level] or M.RAIN_LEVELS.medium
    for k, v in pairs(l) do out[k] = v end
    out.id = 'rain'
  elseif base.id == 'cloudy' then
    out.cirrus, out.density, out.tint, out.dark = 0.45, 0.4, 0.35, 0.18        -- grey, no rain
  elseif base.id == 'fog' then
    out.cirrus, out.density = 0.3, 0.3
  end
  return out
end

-- how wet the roads are, 0..1: it rises while it rains (a few minutes to soak) and dries slowly afterwards. wetTarget is the state's wet (0 when dry), dt in seconds
M.SOAK_SECONDS, M.DRY_SECONDS = 120, 420
function M.wetStep(wet, wetTarget, dt)
  wet, wetTarget, dt = wet or 0, wetTarget or 0, dt or 0
  if wet < wetTarget then return math.min(wetTarget, wet + dt / M.SOAK_SECONDS) end
  return math.max(wetTarget, wet - dt / M.DRY_SECONDS)
end

-- a shower is not steady: gusts (the drop count swells and ebbs between 55 and 100 % of the state's number over tens of seconds), a wind that drifts the drops'
-- angle, ripples on the puddles (how many per puddle by how hard it rains), the damp patches breathing a little. All smooth functions of time t (seconds) and a seed.
function M.gust(t, seed)
  seed = (seed or 0) % 97
  local g = 0.62 + 0.22 * math.sin((t or 0) / 37 + seed) + 0.16 * math.sin((t or 0) / 11.3 + seed * 2.1)
  return math.max(0.3, math.min(1, g))
end
function M.dropsAt(base, t, seed) return (base or 0) * (0.55 + 0.45 * M.gust(t, seed)) end
function M.windAngle(t, seed)                   -- radians off the mean wind direction, slow
  seed = (seed or 0) % 97
  return 0.45 * math.sin((t or 0) / 53 + seed) + 0.2 * math.sin((t or 0) / 19 + seed * 1.7)
end
-- intensity 0..1 (the drop count of the state over the heaviest rain's): none when it does not rain
function M.rippleCount(intensity)
  intensity = intensity or 0
  if intensity <= 0.02 then return 0 end
  return math.min(3, math.ceil(intensity * 3))
end
function M.shimmer(t, id, intensity) return 1 + 0.07 * math.min(1, (intensity or 0) * 1.5) * math.sin((t or 0) / 2.3 + (id or 0) * 1.7) end

-- a colour pulled towards the grey of the same brightness: c = { r, g, b }, amount 0..1
function M.greyer(c, amount)
  amount = math.max(0, math.min(1, amount or 0))
  local lum = 0.3 * c[1] + 0.59 * c[2] + 0.11 * c[3]
  return { c[1] + (lum - c[1]) * amount, c[2] + (lum - c[2]) * amount, c[3] + (lum - c[3]) * amount }
end

-- how much of its brightness each part of the sky keeps at darkness 0..1: the light of the sun most, the ambient least (it must still read as day), the fog and the cloud
-- exposure in between, the sky brightness (the ScatterSky field) the least
M.DARK_KEEP = { sun = 0.55, ambient = 0.35, fog = 0.5, cloud = 0.45, sky = 0.5, colorize = 0.5 }
function M.keep(part, dark) return 1 - (M.DARK_KEEP[part] or 0.4) * math.max(0, math.min(1, dark or 0)) end
-- low sun (dawn, dusk): the sky is dark and orange by itself, so the darkening is cut to a quarter at the horizon and the colours are greyed all the way (no orange
-- band); in full daylight (sun 35 degrees and up) both are as the state asks. elevation in degrees.
function M.skyFactors(elevation, dark, amount)
  local e = elevation or 45
  local dayK = math.max(0.25, math.min(1, e / 35))
  local grey = amount or 0
  if e < 25 then grey = math.max(grey, 0.98) end
  return (dark or 0) * dayK, grey
end
function M.darker(c, factor) return { c[1] * factor, c[2] * factor, c[3] * factor } end

-- the tyres' grip follows how wet the road is, not the state: it falls as the road soaks and comes back as it dries. rain is the state table of the rain that
-- wet it (grip = the grip at its wettest, wet = how wet that is); no rain yet = dry grip.
function M.wetGrip(wet, rain)
  if not rain or not rain.grip or (rain.wet or 0) <= 0 then return 1 end
  return 1 - (1 - rain.grip) * math.min(1, math.max(0, wet or 0) / rain.wet)
end

-- puddles: how many may stand at this wetness, and how opaque they are (nothing below a damp road)
M.MAX_PUDDLES = 18
function M.puddleCount(wet) return wet < 0.15 and 0 or math.floor(M.MAX_PUDDLES * math.min(1, (wet - 0.1) / 0.9) + 0.5) end
function M.puddleAlpha(wet, age)
  local fade = math.min(1, (age or 0) / 6)
  return math.max(0, math.min(1, (wet - 0.1) / 0.5)) * 0.8 * fade
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
function M.text(phase, nowId, nextId, nowLevel)
  local now = M.state(nowId)
  local nextPhase = M.after(phase, 1)
  local word = WORDS[now.id]
  if now.id == 'rain' and M.RAIN_LEVELS[nowLevel] then word = M.RAIN_LEVELS[nowLevel].name end
  local line = string.format('%s %s', word, phase == 'night' and 'tonight' or 'today')
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
  for _, k in ipairs({ 'drops', 'cloud', 'fog', 'grip', 'wet', 'cirrus', 'density', 'speed', 'tint', 'dark' }) do
    local x, y = a[k], b[k]
    if x ~= nil and y ~= nil then out[k] = x + (y - x) * t else out[k] = y ~= nil and y or x end
  end
  return out
end

return M
