-- Street Legal: the weather (extension name: sl_weather; #45)
-- Each phase of each career day has a weather state (sl/core/weather): clear, cloudy, rain (light, medium or heavy), or fog banks at night. The level's own sky
-- is moved to it over a few seconds through the game's own environment calls (core_environment: cloud cover, the high cirrus cloud, fog and the number of
-- rain drops; the game no longer has a sky brightness, so a thick overcast is what darkens a rainy sky). The rain's drop count and speed follow how hard it
-- rains. The roads get wet while it rains (sl/core/weather.wetStep) and dry out afterwards: puddles stand on flat road spots round the player (sl/puddlefx.lua:
-- warped planes, wheel spray, wet trails, aquaplaning). The tyres' grip follows how wet the road is (slCar.setGrip), and what jobs, purses and prizes pay goes up
-- a little in the wet (sl_career.payOut asks bonus()). The phone shows the forecast. The level's own values are put back when the career stops. The career's clock
-- and time of day are not touched (the game's own weather presets would set the time of day).

local M = {}

local rules = require('sl/core/weather')

local current, target            -- the sky now and where it is going: { drops, cloud, cirrus, density, fog, grip, wet, speed }
local baseline                   -- the level's own values, kept to put back
local stateId = 'clear'
local levelId = 'medium'
local nextId
local blendT, blendFrom = 1, nil
local BLEND_SECONDS = 25
local gripTimer, applyTimer, gustTimer = 0, 0, 0
M.flags = { gust = true }      -- the shower swells and ebbs, its wind drifts (sl/core/weather.gust, windAngle); sl_weather.flags.gust = false keeps it steady
local gustSeed = 0
local windBase                 -- the level's own ground wind, put back when the career stops
local lastKey
local ticks, errors = 0, {}   -- onUpdate frames run, and the first error of each part (a failing part must not hide the others, nor stay unseen)
local function guarded(name, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and not errors[name] then errors[name] = tostring(err) log('E', 'sl_weather', name .. ' failed: ' .. tostring(err)) end
end
local forced = false       -- a game test put the weather in a state (debugForce): the career's own weather does not replace it, and no career is needed for it to run

local wet = 0                    -- how wet the roads are, 0..1
local lastRain                   -- the rain that wet them (core/weather.resolve), for the grip it leaves

local TAG = 'sl_weather'
local tintBase = {}              -- the sky colours the game's own gradients set, last seen; the tint pulls them to grey
local tintTimer = 0

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

local function objects(className)
  local ok, list = pcall(getObjectsByClass, className)
  return ok and type(list) == 'table' and list or {}
end

local function first(className) for _, o in pairs(objects(className)) do return o end end

-- the level's rain: WCUSA has one (WCA_rain, numDrops 0); a level without one gets one made, as the editor makes it (datablock rain_drop)
local function ensureRain()
  if first('Precipitation') then return end
  local ok, err = pcall(function()
    local o = createObject('Precipitation')
    o:setField('dataBlock', 0, 'rain_drop')
    o:setField('boxWidth', 0, '50') o:setField('boxHeight', 0, '50')
    o:setField('dropSize', 0, '0.2') o:setField('splashSize', 0, '0.2')
    o:setField('minSpeed', 0, '0.35') o:setField('maxSpeed', 0, '0.4')
    o:setField('hitVehicles', 0, 'true') o:setField('useTurbulence', 0, 'true')
    o:setField('numDrops', 0, '0')
    o:registerObject('sl_weather_rain')
    local group = scenetree.findObject('MissionGroup')
    if group and group.addObject then group:addObject(o) end
  end)
  log(ok and 'I' or 'W', TAG, ok and 'the level had no Precipitation: one was made (datablock rain_drop)' or ('could not make a Precipitation: ' .. tostring(err)))
end

local function readBaseline()
  if baseline then return end
  ensureRain()
  baseline = { drops = 0, cloud = 1, fog = 0.00035, grip = 1, wet = 0 }
  local rain, cloud, info = first('Precipitation'), first('CloudLayer'), first('LevelInfo')
  if rain then
    baseline.drops = tonumber(rain.numOfDrops) or tonumber(rain.numDrops) or baseline.drops
    baseline.minSpeed, baseline.maxSpeed = tonumber(rain.minSpeed), tonumber(rain.maxSpeed)
  end
  if cloud then
    baseline.cloud = tonumber(cloud.coverage) or baseline.cloud
    baseline.cirrus, baseline.density = tonumber(cloud.cirrusCoverage), tonumber(cloud.cirrusDensity)
  end
  if info then baseline.fog = tonumber(info.fogDensity) or baseline.fog end
  baseline.speed = 1
  pcall(function() if core_environment and core_environment.getGroundWind then local w = core_environment.getGroundWind() windBase = { x = w.x, y = w.y, z = w.z } end end)
  current = current or { drops = baseline.drops, cloud = baseline.cloud, cirrus = baseline.cirrus, density = baseline.density, fog = baseline.fog, grip = 1, wet = 0, speed = 1, tint = 0 }
  pcall(function() log('I', TAG, string.format('level sky: Precipitation %s (numOfDrops %s, numDrops %s, dataBlock %s), CloudLayer %s (coverage %s), LevelInfo fog %s, ScatterSky %s, core_environment %s, decal manager %s',
    tostring(rain ~= nil), tostring(rain and rain.numOfDrops), tostring(rain and rain.numDrops), tostring(rain and rain:getField('dataBlock', 0)), tostring(cloud ~= nil), tostring(cloud and cloud.coverage),
    tostring(info and info.fogDensity), tostring(first('ScatterSky') ~= nil), tostring(core_environment ~= nil), tostring(Engine and Engine.Render and Engine.Render.DynamicDecalMgr ~= nil))) end)
end

-- the game's own environment calls (they apply the change to the object: a plain field write on a CloudLayer or the fog is not seen until the object is
-- applied); the fields are the way back where a call is missing
local function try(fn, ...) if fn then pcall(fn, ...) end end
local function applySky(v)
  local env = core_environment
  local rain, cloud, info = first('Precipitation'), first('CloudLayer'), first('LevelInfo')
  if env and env.setCloudCover then
    try(env.setCloudCover, v.cloud)
    if v.cirrus then try(env.setCloudCirrusCoverage, v.cirrus) end
    if v.density then try(env.setCloudCirrusDensity, v.density) end
    try(env.setFogDensity, v.fog)
    try(env.setPrecipitation, math.floor((M.flags.gust and rules.dropsAt(v.drops, os.clock(), gustSeed) or v.drops) + 0.5))
  else
    if rain then pcall(function() rain.numOfDrops = math.floor(v.drops + 0.5) end) end
    if cloud then pcall(function() cloud.coverage = v.cloud if cloud.postApply then cloud:postApply() end end) end
    if info then pcall(function() info.fogDensity = v.fog if info.postApply then info:postApply() end end) end
  end
  -- how fast the drops fall follows how hard it rains (a factor on the level's own speeds)
  if rain and baseline and baseline.minSpeed and v.speed then
    pcall(function() rain.minSpeed, rain.maxSpeed = baseline.minSpeed * v.speed, baseline.maxSpeed * v.speed end)
  end
  -- fatter drops in heavier rain (they are thin streaks at the level's own 0.2)
  if rain then pcall(function() rain:setField('dropSize', 0, tostring(0.2 + math.min(1, v.drops / 3000) * 0.25)) end) end
  -- every drop count change is logged once (what the object says before and after): the rain that is not seen is found here
  local want = math.floor(v.drops + 0.5)
  if rain and want ~= M.lastLoggedDrops then
    M.lastLoggedDrops = want
    local after = tonumber(rain.numOfDrops) or tonumber(rain.numDrops)
    local hidden
    pcall(function() hidden = rain.isHidden and rain:isHidden() or rain.hidden end)
    log('I', TAG, string.format('rain drops set to %d: the object now says %s (hidden %s, enabled %s)', want, tostring(after), tostring(hidden), tostring(rain.isEnabled)))
    pcall(function() if rain.setHidden then rain:setHidden(false) end end)
  end
end

-- the sky's sun, fog and ambient colours come from gradients that follow the time of day (at dawn they are orange, and a fog in them is an orange dust storm).
-- In rain they are pulled towards grey of the same brightness; the game rewrites them with the time of day, so this is repeated twice a second while it is on.
local TINT_FIELDS = { 'sunScale', 'fogScale', 'ambientScale' }
local function applyTint(amount)
  local sky = first('ScatterSky')
  if not sky then return end
  for _, k in ipairs(TINT_FIELDS) do
    pcall(function()
      local text = sky:getField(k, 0)
      local r, g, b, a = tostring(text):match('([%-%d%.e]+)%s+([%-%d%.e]+)%s+([%-%d%.e]+)%s*([%-%d%.e]*)')
      if not r then return end
      local c = rules.greyer({ tonumber(r), tonumber(g), tonumber(b) }, amount)
      sky:setField(k, 0, string.format('%f %f %f %s', c[1], c[2], c[3], a ~= '' and a or '1'))
    end)
  end
  pcall(function() if sky.postApply then sky:postApply() end end)
end

-- the state of this phase of this day; a new one is blended in
local function sync()
  if forced then return end
  local s = career()
  if not s then return end
  readBaseline()
  local phase = sl_career.phase() or 'day'
  local key = tostring(s.day) .. ':' .. phase
  if key == lastKey then return end
  lastKey = key
  stateId = rules.forecast(s.seed, s.day, phase)
  gustSeed = type(s.seed) == 'number' and s.seed or 0
  levelId = stateId == 'rain' and rules.level(s.seed, s.day, phase) or nil
  local np, nd = rules.after(phase, s.day)
  nextId = rules.forecast(s.seed, nd, np)
  local st = rules.resolve(stateId, levelId)
  -- clear skies are the level's own fog, high cloud and speeds, and a lighter cloud cover than its default
  if st.id == 'rain' then lastRain = st end
  -- (rain's grip comes from the wetness, not from the state: a road stays slippery after the rain has stopped)
  target = { drops = st.drops, cloud = st.cloud, fog = st.id == 'clear' and baseline.fog or st.fog, grip = st.id == 'rain' and 1 or st.grip, wet = st.wet or 0, tint = st.tint or 0,
    cirrus = st.cirrus or baseline.cirrus, density = st.density or baseline.density, speed = st.speed or 1 }
  blendFrom, blendT = current, 0
  extensions.hook('onStreetLegalWeather', stateId)
end

function M.state() return stateId end
function M.level() return levelId end
function M.wetness() return wet end
function M.bonus() return career() and rules.pay(stateId) or 1 end
-- the grip factor now: fog's own, or what the wet road leaves (whichever is less)
function M.grip() return career() and math.min(current and current.grip or 1, rules.wetGrip(wet, lastRain)) or 1 end
function M.forecast()
  if not career() then return nil end
  return { state = stateId, level = levelId, name = rules.state(stateId).name, text = rules.text(sl_career.phase() or 'day', stateId, nextId, levelId), wet = stateId == 'rain' }
end

-- the car's tyres take the grip (the player's own car; a car swapped in is told at the next look)
local function pushGrip(force)
  local v = getPlayerVehicle(0)
  if not v or v:getJBeamFilename() == 'unicycle' then return end
  v:queueLuaCommand(string.format('if slCar and slCar.setGrip then slCar.setGrip(%f) end', M.grip()))
end

----------------------------------------------------------------------------------------------

-- the level's rain is a box of drops at a fixed place (WCUSA's WCA_rain sits ~100 m from where you drive): it follows the camera (followCam where the object has it,
-- and moved to the camera each frame as well)
local followLogged = false
local noCamLogged = false
local function followRain()
  local rain = first('Precipitation')
  if not rain then return end
  -- where the player looks from: the active camera; failing that the player's own vehicle (the rain box must be over the player, wherever it was left)
  local ok, cam = pcall(function() return core_camera and core_camera.getPosition and core_camera.getPosition() end)
  local source = 'camera'
  if not (ok and cam and cam.x) then
    local v = getPlayerVehicle and getPlayerVehicle(0)
    ok, cam = pcall(function() return v and v:getPosition() end)
    source = 'player vehicle'
  end
  if not (ok and cam and cam.x) then
    if not noCamLogged then noCamLogged = true log('W', TAG, 'rain cannot follow the player: no camera position and no player vehicle') end
    return
  end
  if not followLogged then
    followLogged = true
    local f, at = nil, nil
    pcall(function() f = rain:getField('followCam', 0) at = rain:getPosition() end)
    pcall(function() rain:setField('followCam', 0, 'true') rain:setField('boxWidth', 0, '70') rain:setField('boxHeight', 0, '70') end)
    log('I', TAG, string.format('rain follows the %s: followCam was %s, the rain stood at %s, the %s is at %s', source, tostring(f), tostring(at), source, tostring(cam)))
  end
  pcall(function() rain:setPosition(vec3(cam.x, cam.y, cam.z)) end)
end

-- (the debug helpers moved with the puddles: sl_puddlefx.puddleNear(), .flag(name, on), .stats())
function M.puddleNear() return sl_puddlefx and sl_puddlefx.puddleNear() or 'sl_puddlefx is not loaded' end

function M.onStreetLegalStarted() lastKey = nil sync() end
function M.onStreetLegalPhase() sync() end
function M.onStreetLegalNewDay() sync() end

function M.onUpdate(dtReal)
  if not career() and not forced then return end
  if not baseline or not lastKey then sync() end
  dtReal = dtReal or 0
  if target and blendT < 1 then
    blendT = math.min(1, blendT + dtReal / BLEND_SECONDS)
    current = rules.blend(blendFrom, target, blendT)
    applyTimer = applyTimer + dtReal
    if applyTimer > 0.2 or blendT >= 1 then applyTimer = 0 applySky(current) end      -- (the objects are applied a few times a second, not every frame)
  end
  wet = rules.wetStep(wet, target and target.wet or 0, dtReal)
  ticks = ticks + 1
  if current and (current.drops or 0) > 0 then guarded('followRain', followRain) end
  -- the shower is not steady: every second the drop count and the wind follow the gust (while the sky is still blending applySky does it)
  gustTimer = gustTimer + dtReal
  if gustTimer > 1 and current and (current.drops or 0) > 0 and blendT >= 1 and M.flags.gust then
    gustTimer = 0
    local env, t = core_environment, os.clock()
    if env and env.setPrecipitation then pcall(env.setPrecipitation, math.floor(rules.dropsAt(current.drops, t, gustSeed) + 0.5)) end
    if env and env.setGroundWind then
      local speed = 1 + 3.5 * math.min(1, current.drops / 3000) * rules.gust(t, gustSeed)
      local a = 1.1 + rules.windAngle(t, gustSeed)
      pcall(env.setGroundWind, math.cos(a) * speed, math.sin(a) * speed, 0)
    end
  end
  if sl_puddlefx then guarded('puddlefx.update', sl_puddlefx.update, dtReal, wet, current and math.min(1, (current.drops or 0) / 3000) or 0) else guarded('no puddlefx', function() error('sl_puddlefx is not loaded') end) end      -- (puddles, ripples, wheel spray, wet trails: sl/puddlefx.lua)
  tintTimer = tintTimer + dtReal
  if tintTimer > 0.5 then
    tintTimer = 0
    local amount = current and current.tint or 0
    if amount > 0.02 then applyTint(amount) end
  end
  gripTimer = gripTimer + dtReal
  if gripTimer > 2 then gripTimer = 0 pushGrip() end
end

-- for a game test: put the weather in this state at once (no blend), e.g. sl_weather.debugForce('rain', 'heavy')
function M.debugForce(id, level)
  forced = true
  readBaseline()
  stateId, levelId = id or 'rain', level or 'medium'
  local st = rules.resolve(stateId, levelId)
  if st.id == 'rain' then lastRain = st end
  target = { drops = st.drops, cloud = st.cloud, fog = st.id == 'clear' and baseline.fog or st.fog, grip = st.id == 'rain' and 1 or st.grip, wet = st.wet or 0, tint = st.tint or 0,
    cirrus = st.cirrus or baseline.cirrus, density = st.density or baseline.density, speed = st.speed or 1 }
  current, blendT = rules.blend(current, target, 1), 1
  wet = target.wet
  M.lastLoggedDrops = nil
  applySky(current)
  return stateId, levelId
end

-- ends a debugForce: the career's own weather takes over again at once
function M.debugRelease() forced = false lastKey = nil return 'released' end

-- the numbers a game test looks at: what the objects say now
function M.diagnose()
  local rain, cloud, info, sky = first('Precipitation'), first('CloudLayer'), first('LevelInfo'), first('ScatterSky')
  local out = { state = stateId, level = levelId, wet = wet, ticks = ticks, errors = errors, forced = forced, blendT = blendT, followLogged = followLogged, puddlefxLoaded = sl_puddlefx ~= nil, puddles = sl_puddlefx and select(2, sl_puddlefx.stats()) or 0, stats = sl_puddlefx and (sl_puddlefx.stats()) or nil,
    rain = rain and { numOfDrops = rain.numOfDrops, numDrops = rain.numDrops, minSpeed = rain.minSpeed, maxSpeed = rain.maxSpeed } or false,
    cloud = cloud and { coverage = cloud.coverage, cirrusCoverage = cloud.cirrusCoverage, cirrusDensity = cloud.cirrusDensity } or false,
    fog = info and info.fogDensity or false, tint = current and current.tint, sunScale = sky and sky:getField('sunScale', 0) or false, fogScale = sky and sky:getField('fogScale', 0) or false }
  log('I', TAG, 'diagnose: ' .. (dumps and dumps(out) or tostring(out)))
  return out
end

local function reset()
  forced = false
  if sl_puddlefx then sl_puddlefx.clear() end
  baseline, current, target, lastKey, blendFrom = nil, nil, nil, nil, nil
  wet, lastRain, followLogged = 0, nil, false
end

function M.onStreetLegalStopped()
  if baseline then applySky(baseline) end
  if windBase and core_environment and core_environment.setGroundWind then pcall(core_environment.setGroundWind, windBase.x, windBase.y, windBase.z) end
  windBase = nil
  local v = getPlayerVehicle(0)
  if v and v:getJBeamFilename() ~= 'unicycle' then v:queueLuaCommand('if slCar and slCar.setGrip then slCar.setGrip(1) end') end
  reset()
end

function M.onClientEndMission() reset() end

return M
