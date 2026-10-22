-- Wrench Works: Street Legal: the tow truck (extension name: sl_tow; playtest #4, Design 5)
-- Paid for in My cars (sl_fleet.tow): a rollback pulls up on a city lane a little way off and drives to the car
-- with the game's AI (placed beside it if it has not made it in three minutes). Then, behind a fade, the car
-- is loaded and taken to the garage forecourt as it is (v1: off-screen; Design 5 v2, the car really on the deck,
-- waits for a game test). Standing by the car, you ride along; otherwise the truck just drives off with it.

local M = {}

local strings = require('sl/core/strings')

local roadspot = require('sl/core/roadspot')

local MODEL, CONFIG = 'pickup', 'vehicles/pickup/d45_diesel_rollback_M.pc'
local ARRIVE_RADIUS = 15
local GIVE_UP_SECONDS = 180
local RIDE_RADIUS = 30
local DRIVE_OFF_SECONDS = 25

local call                     -- { truck, carId, car (vehicle id), waited }
local leaving = {}             -- truck id -> seconds until it is gone

local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end
local function rightHand() return not map.getRoadRules().rightHandDrive end
local function drop(id) local v = getObjectByID(id) if v then v:delete() end end
-- the fee was paid when the truck was sent: a tow that ends without the car being taken (the car is gone, the level ends, the career is stopped) gives it back, once. The career stop refunds in
-- onStreetLegalStopping (the career is still active and the save is not written yet); onStreetLegalStopped runs after the career is inactive and cannot pay.
local function refund(t)
  if not (t and (t.fee or 0) > 0 and not t.refunded) then return end
  t.refunded = true
  if sl_career and sl_career.isActive and sl_career.isActive() then sl_career.addMoney(t.fee, strings.t('tow.refund')) end
end

local function laneNear(pos, minD, maxD)
  local others = {}
  for _, v in ipairs(getAllVehicles()) do others[#others + 1] = v:getPosition() end
  local list = {}
  for _, c in ipairs(roadspot.candidates(map.getMap().nodes, pos, rightHand(), maxD)) do
    if c.dist >= minD then list[#list + 1] = c end
  end
  return roadspot.pick(list, others)
end

local function put(veh, c)
  spawn.safeTeleport(veh, vec3(c.x, c.y, c.z + 0.4), quatFromDir(vec3(c.dx, c.dy, 0), vec3(0, 0, 1)), true, nil, nil, nil, false)
end

-- the truck, on its way to the car (the fee is paid); false when no truck can come here
function M.send(carId, carVeh, fee)
  if call or not carVeh then return false end
  local target = carVeh:getPosition()
  local c = laneNear(target, 150, 350) or laneNear(target, 40, 350)
  if not c then return false end
  local ok, truck = pcall(core_vehicles.spawnNewVehicle, MODEL, { config = CONFIG, pos = vec3(c.x, c.y, c.z + 0.5), autoEnterVehicle = false, canSpawnAnotherVehicleCheck = false })
  if not ok or not truck then return false end
  put(truck, c)
  local node = map.findClosestRoad(target)
  truck:queueLuaCommand(string.format('electrics.set_warn_signal(1) ai.driveUsingPath({ wpTargetList = { %q }, driveInLane = "on", avoidCars = "on", routeSpeed = 13, routeSpeedMode = "limit" })', tostring(node)))
  call = { truck = truck:getID(), carId = carId, car = carVeh:getID(), waited = 0, fee = fee }
  if core_groundMarkers then core_groundMarkers.setPath(target) end
  return true
end

-- at the car: fade, the car goes on the truck and on to the garage; you with it if you stood by it
local function load()
  local t = call
  call = nil
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  core_jobsystem.create(function(job)
    local car, me = getObjectByID(t.car), getPlayerVehicle(0)
    local ride = car and me and (me:getID() == t.car or (me:getPosition() - car:getPosition()):length() < RIDE_RADIUS)
    guihooks.trigger('slFade', { on = true })
    job.sleep(0.8)
    sl_fleet.deliver(t.carId)                -- (gets you out first if you were sitting in it)
    job.sleep(1.2)
    local truck = getObjectByID(t.truck)
    local s = sl_career.getState()
    local yard = s and sl_fleet.forecourt(s, 0)
    if ride and yard then
      local c = laneNear(yard, 0, 200)
      if truck and c then put(truck, c) end
      local walker = getPlayerVehicle(0)
      if walker and walker:getJBeamFilename() == 'unicycle' then
        spawn.safeTeleport(walker, (c and vec3(c.x, c.y, c.z) or yard) + vec3(0, 0, 0.3) + (c and vec3(c.dy, -c.dx, 0) * 3 or vec3(0, 0, 0)), quatFromDir(vec3(0, 1, 0), vec3(0, 0, 1)), true)
      end
    end
    job.sleep(0.6)
    guihooks.trigger('slFade', { on = false })
    toast(ride and strings.t('tow.the_truck_dropped_you_and') or strings.t('tow.the_truck_has_your_car'))
    if truck then
      truck:queueLuaCommand('electrics.set_warn_signal(0) ai.setMode("traffic")')
      leaving[t.truck] = DRIVE_OFF_SECONDS
    end
  end)
end

function M.onUpdate(dtReal)
  for id, t in pairs(leaving) do
    leaving[id] = t - dtReal
    if leaving[id] <= 0 then leaving[id] = nil drop(id) end
  end
  if not call then return end
  local truck, car = getObjectByID(call.truck), getObjectByID(call.car)
  if not car then if truck then drop(call.truck) end refund(call) call = nil return end       -- (the car is gone: no tow, no fee)
  if not truck then load() return end
  call.waited = call.waited + dtReal
  if (truck:getPosition() - car:getPosition()):length() < ARRIVE_RADIUS then load() return end
  if call.waited > GIVE_UP_SECONDS then
    local c = laneNear(car:getPosition(), 6, 80)
    if c then put(truck, c) end
    load()
  end
end

function M.busy() return call ~= nil end

function M.onStreetLegalStopping() refund(call) end
function M.onStreetLegalStopped()
  if call then drop(call.truck) end
  for id in pairs(leaving) do drop(id) end
  call, leaving = nil, {}
end
function M.onClientEndMission() refund(call) call, leaving = nil, {} end
function M.testCall(c) call = c end      -- (for the tests: a tow on its way without a truck)

-- (the Mods menu's Parts of the game: with this part off, the hooks above do nothing)
require('sl/core/features').gate('tow', M, nil, nil, { 'send' })

return M
