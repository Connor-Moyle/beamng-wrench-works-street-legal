-- Street Legal: the weather (extension name: sl_weather; #45)
-- Each phase of each career day has a weather state (sl/core/weather): clear, cloudy, rain, or fog banks at night. The level's own sky objects are
-- moved to it over a few seconds (rain drops, cloud cover, fog density); the grip of the player's tyres follows (slCar.setGrip), and what jobs, purses
-- and prizes pay goes up a little in the wet (sl_career.payOut asks bonus()). The phone shows the forecast. The level's own values are put back when the
-- career stops. The career's clock and time of day are not touched (the game's own weather presets would set the time of day).

local M = {}

local rules = require('sl/core/weather')

local current, target            -- the sky now and where it is going: { drops, cloud, fog, grip }
local baseline                   -- the level's own values, kept to put back
local stateId = 'clear'
local nextId
local blendT, blendFrom = 1, nil
local BLEND_SECONDS = 25
local gripTimer = 0
local lastKey

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

local function objects(className)
  local ok, list = pcall(getObjectsByClass, className)
  return ok and type(list) == 'table' and list or {}
end

local function readBaseline()
  if baseline then return end
  baseline = { drops = 0, cloud = 1, fog = 0.00035, grip = 1 }
  for _, o in pairs(objects('Precipitation')) do baseline.drops = tonumber(o.numDrops) or baseline.drops break end
  for _, o in pairs(objects('CloudLayer')) do baseline.cloud = tonumber(o.coverage) or baseline.cloud break end
  for _, o in pairs(objects('LevelInfo')) do baseline.fog = tonumber(o.fogDensity) or baseline.fog break end
  current = current or { drops = baseline.drops, cloud = baseline.cloud, fog = baseline.fog, grip = 1 }
end

local function applySky(v)
  for _, o in pairs(objects('Precipitation')) do o.numDrops = math.floor(v.drops + 0.5) end
  for _, o in pairs(objects('CloudLayer')) do o.coverage = v.cloud end
  for _, o in pairs(objects('LevelInfo')) do
    o.fogDensity = v.fog
    if o.postApply then o:postApply() end
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
  local np, nd = rules.after(phase, s.day)
  nextId = rules.forecast(s.seed, nd, np)
  local st = rules.state(stateId)
  -- clear skies are the level's own fog and a lighter cloud cover than its default
  target = { drops = st.drops, cloud = st.cloud, fog = st.id == 'clear' and baseline.fog or st.fog, grip = st.grip }
  blendFrom, blendT = current, 0
  extensions.hook('onStreetLegalWeather', stateId)
end

function M.state() return stateId end
function M.bonus() return career() and rules.pay(stateId) or 1 end
function M.grip() return career() and rules.grip(stateId) or 1 end
function M.forecast()
  if not career() then return nil end
  return { state = stateId, name = rules.state(stateId).name, text = rules.text(sl_career.phase() or 'day', stateId, nextId), wet = stateId == 'rain' }
end

-- the car's tyres take the grip (the player's own car; a car swapped in is told at the next look)
local function pushGrip(force)
  local v = getPlayerVehicle(0)
  if not v or v:getJBeamFilename() == 'unicycle' then return end
  v:queueLuaCommand(string.format('if slCar and slCar.setGrip then slCar.setGrip(%f) end', current and current.grip or 1))
end

function M.onStreetLegalStarted() lastKey = nil sync() end
function M.onStreetLegalPhase() sync() end
function M.onStreetLegalNewDay() sync() end

function M.onUpdate(dtReal)
  if not career() then return end
  if not baseline or not lastKey then sync() end
  if target and blendT < 1 then
    blendT = math.min(1, blendT + (dtReal or 0) / BLEND_SECONDS)
    current = rules.blend(blendFrom, target, blendT)
    applySky(current)
  end
  gripTimer = gripTimer + (dtReal or 0)
  if gripTimer > 2 then gripTimer = 0 pushGrip() end
end

function M.onStreetLegalStopped()
  if baseline then applySky(baseline) end
  local v = getPlayerVehicle(0)
  if v and v:getJBeamFilename() ~= 'unicycle' then v:queueLuaCommand('if slCar and slCar.setGrip then slCar.setGrip(1) end') end
  baseline, current, target, lastKey, blendFrom = nil, nil, nil, nil, nil
end

function M.onClientEndMission() baseline, current, target, lastKey, blendFrom = nil, nil, nil, nil, nil end

return M
