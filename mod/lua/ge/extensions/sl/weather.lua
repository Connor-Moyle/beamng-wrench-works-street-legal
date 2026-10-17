-- Street Legal: the weather (extension name: sl_weather; #45)
-- Each phase of each career day has a weather state (sl/core/weather): clear, cloudy, rain (light, medium or heavy), or fog banks at night. The level's own sky
-- is moved to it over a few seconds through the game's own environment calls (core_environment: cloud cover, the high cirrus cloud, fog and the number of
-- rain drops; the game no longer has a sky brightness, so a thick overcast is what darkens a rainy sky). The rain's drop count and speed follow how hard it
-- rains. The roads get wet while it rains (sl/core/weather.wetStep) and dry out afterwards: puddle decals stand on flat road spots round the player,
-- drawn each frame from a small list (nothing is kept in the world). The grip of the player's tyres follows the state (slCar.setGrip), and what jobs, purses
-- and prizes pay goes up a little in the wet (sl_career.payOut asks bonus()). The phone shows the forecast. The level's own values are put back when the
-- career stops. The career's clock and time of day are not touched (the game's own weather presets would set the time of day).

local M = {}

local rules = require('sl/core/weather')

local current, target            -- the sky now and where it is going: { drops, cloud, cirrus, density, fog, grip, wet, speed }
local baseline                   -- the level's own values, kept to put back
local stateId = 'clear'
local levelId = 'medium'
local nextId
local blendT, blendFrom = 1, nil
local BLEND_SECONDS = 25
local gripTimer, applyTimer = 0, 0
local lastKey

local wet = 0                    -- how wet the roads are, 0..1
local lastRain                   -- the rain that wet them (core/weather.resolve), for the grip it leaves
local puddles = {}               -- { x, y, z, sx, sy, dx, dy, born }
local puddleTimer = 0
local pool, poolSize, colors = {}, 0, {}
local PUDDLE_TEX = 'art/street_legal/decals/puddle.png'
local PUDDLE_RADIUS = { 8, 70 }  -- puddles stand between these distances from the player; further than FORGET_AT they are dropped
local FORGET_AT = 95
local DEPTH = 1.5

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

local function objects(className)
  local ok, list = pcall(getObjectsByClass, className)
  return ok and type(list) == 'table' and list or {}
end

local function first(className) for _, o in pairs(objects(className)) do return o end end

local function readBaseline()
  if baseline then return end
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
  current = current or { drops = baseline.drops, cloud = baseline.cloud, cirrus = baseline.cirrus, density = baseline.density, fog = baseline.fog, grip = 1, wet = 0, speed = 1 }
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
    try(env.setPrecipitation, math.floor(v.drops + 0.5))
  else
    if rain then pcall(function() rain.numOfDrops = math.floor(v.drops + 0.5) end) end
    if cloud then pcall(function() cloud.coverage = v.cloud if cloud.postApply then cloud:postApply() end end) end
    if info then pcall(function() info.fogDensity = v.fog if info.postApply then info:postApply() end end) end
  end
  -- how fast the drops fall follows how hard it rains (a factor on the level's own speeds)
  if rain and baseline and baseline.minSpeed and v.speed then
    pcall(function() rain.minSpeed, rain.maxSpeed = baseline.minSpeed * v.speed, baseline.maxSpeed * v.speed end)
  end
end

-- the state of this phase of this day; a new one is blended in
local function sync()
  local s = career()
  if not s then return end
  readBaseline()
  local phase = sl_career.phase() or 'day'
  local key = tostring(s.day) .. ':' .. phase
  if key == lastKey then return end
  lastKey = key
  stateId = rules.forecast(s.seed, s.day, phase)
  levelId = stateId == 'rain' and rules.level(s.seed, s.day, phase) or nil
  local np, nd = rules.after(phase, s.day)
  nextId = rules.forecast(s.seed, nd, np)
  local st = rules.resolve(stateId, levelId)
  -- clear skies are the level's own fog, high cloud and speeds, and a lighter cloud cover than its default
  if st.id == 'rain' then lastRain = st end
  -- (rain's grip comes from the wetness, not from the state: a road stays slippery after the rain has stopped)
  target = { drops = st.drops, cloud = st.cloud, fog = st.id == 'clear' and baseline.fog or st.fog, grip = st.id == 'rain' and 1 or st.grip, wet = st.wet or 0,
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
-- puddles: wet road spots near the player, from a short list that is drawn each frame (DynamicDecalMgr keeps nothing)

local function surfaceZ(x, y, zTop)
  local ok, z = pcall(function() return be:getSurfaceHeightBelow(vec3(x, y, zTop)) end)
  if ok and type(z) == 'number' and z > -1e5 then return z end
end

-- a flat spot on a road: the ground under four points round it is level, and a road runs through it
local function roadSpot(x, y, zTop)
  local z = surfaceZ(x, y, zTop)
  if not z then return nil end
  for _, d in ipairs({ { 0.9, 0 }, { -0.9, 0 }, { 0, 0.9 }, { 0, -0.9 } }) do
    local zz = surfaceZ(x + d[1], y + d[2], zTop)
    if not zz or math.abs(zz - z) > 0.05 then return nil end
  end
  local ok, n1, _, dist = pcall(function() return map.findClosestRoad(vec3(x, y, z), 12) end)
  if not (ok and n1) then return nil end
  local radius = 3
  pcall(function() radius = map.getMap().nodes[n1].radius or 3 end)
  if dist > math.max(1.2, radius * 0.7) then return nil end
  return z
end

local function updatePuddles(dtReal)
  local v = getPlayerVehicle(0)
  if not v then return end
  local ok, pos = pcall(function() return v:getPosition() end)
  if not ok or not pos then return end
  local want = rules.puddleCount(wet)
  -- forget the ones left behind, and the extra ones when it has dried out a little
  for i = #puddles, 1, -1 do
    local p = puddles[i]
    local dx, dy = p.x - pos.x, p.y - pos.y
    if dx * dx + dy * dy > FORGET_AT * FORGET_AT or i > want then table.remove(puddles, i) end
  end
  puddleTimer = puddleTimer + (dtReal or 0)
  if puddleTimer < 0.3 or #puddles >= want then return end
  puddleTimer = 0
  -- a few tries a round: anywhere in the ring, more often ahead of the car
  local heading = 0
  pcall(function() local d = v:getDirectionVector() heading = math.atan2(d.y, d.x) end)
  for _ = 1, 3 do
    local a = heading + (math.random() - 0.5) * (math.random() < 0.6 and 2.2 or 6.28)
    local r = PUDDLE_RADIUS[1] + math.random() * (PUDDLE_RADIUS[2] - PUDDLE_RADIUS[1])
    local x, y = pos.x + math.cos(a) * r, pos.y + math.sin(a) * r
    local z = roadSpot(x, y, pos.z + 12)
    if z then
      local rot = math.random() * 6.28
      local size = 0.9 + math.random() * 1.7
      puddles[#puddles + 1] = { x = x, y = y, z = z + 0.02, sx = size, sy = size * (0.6 + math.random() * 0.5), dx = math.cos(rot), dy = math.sin(rot), born = os.clock() }
      break
    end
  end
end

function M.onPreRender()
  if #puddles == 0 or wet < 0.15 then return end
  if not (Engine and Engine.Render and Engine.Render.DynamicDecalMgr) then return end
  local now, idx = os.clock(), 0
  for i = 1, #puddles do
    local p = puddles[i]
    local alpha = rules.puddleAlpha(wet, now - p.born)
    if alpha > 0.02 then
      idx = idx + 1
      if idx > poolSize then
        pool[idx] = { texture = PUDDLE_TEX, position = vec3(0, 0, 0), forwardVec = vec3(1, 0, 0), color = ColorF(0.8, 0.88, 0.95, 1), scale = vec3(1, 1, DEPTH), fadeStart = 55, fadeEnd = 75 }
        poolSize = idx
      end
      local e = pool[idx]
      e.position:set(p.x, p.y, p.z)
      e.forwardVec:set(p.dx, p.dy, 0)
      e.scale:set(p.sx, p.sy, DEPTH)
      local q = math.floor(alpha * 20 + 0.5)
      e.color = colors[q] or (function() colors[q] = ColorF(0.8, 0.88, 0.95, q / 20) return colors[q] end)()      -- (a handful of cached colours, nothing allocated per frame)
    end
  end
  if idx > 0 then Engine.Render.DynamicDecalMgr.addDecals(pool, idx) end
end

----------------------------------------------------------------------------------------------

function M.onStreetLegalStarted() lastKey = nil sync() end
function M.onStreetLegalPhase() sync() end
function M.onStreetLegalNewDay() sync() end

function M.onUpdate(dtReal)
  if not career() then return end
  if not baseline or not lastKey then sync() end
  dtReal = dtReal or 0
  if target and blendT < 1 then
    blendT = math.min(1, blendT + dtReal / BLEND_SECONDS)
    current = rules.blend(blendFrom, target, blendT)
    applyTimer = applyTimer + dtReal
    if applyTimer > 0.2 or blendT >= 1 then applyTimer = 0 applySky(current) end      -- (the objects are applied a few times a second, not every frame)
  end
  wet = rules.wetStep(wet, target and target.wet or 0, dtReal)
  updatePuddles(dtReal)
  gripTimer = gripTimer + dtReal
  if gripTimer > 2 then gripTimer = 0 pushGrip() end
end

local function reset()
  baseline, current, target, lastKey, blendFrom = nil, nil, nil, nil, nil
  wet, puddles, lastRain = 0, {}, nil
end

function M.onStreetLegalStopped()
  if baseline then applySky(baseline) end
  local v = getPlayerVehicle(0)
  if v and v:getJBeamFilename() ~= 'unicycle' then v:queueLuaCommand('if slCar and slCar.setGrip then slCar.setGrip(1) end') end
  reset()
end

function M.onClientEndMission() reset() end

return M
