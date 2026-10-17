-- Wrench Works: Street Legal: a real cab (extension name: sl_cab; playtest #5)
-- Booked on the phone (sl_career.taxi charges the fare): a taxi pulls up on the nearest city lane, hazards on,
-- with the way to it on the road. Walk up to it and you get in: the screen fades, and you step out beside it at
-- the place you asked for, while it drives off into town. Not reached in five minutes, it leaves and the fare
-- comes back.

local M = {}

local roadspot = require('sl/core/roadspot')

local MODEL, CONFIG = 'fullsize', 'vehicles/fullsize/taxi.pc'
local BOARD_RADIUS = 4.5       -- m from the cab's middle
local WAIT_SECONDS = 300
local DRIVE_OFF_SECONDS = 25

local ride                     -- { vid, place, fee, waited }
local leaving = {}             -- vid -> seconds until it is gone

local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end
local function onFoot() local v = getPlayerVehicle(0) return v and v:getJBeamFilename() == 'unicycle' and v or nil end
local function rightHand() return not map.getRoadRules().rightHandDrive end

local function others(except)
  local list = {}
  for _, v in ipairs(getAllVehicles()) do if v:getID() ~= except then list[#list + 1] = v:getPosition() end end
  return list
end

local function spot(from, min)
  local list = {}
  for _, c in ipairs(roadspot.candidates(map.getMap().nodes, from, rightHand(), 300)) do
    if c.dist >= (min or 0) then list[#list + 1] = c end
  end
  return roadspot.pick(list, others())
end

local function place(veh, c)
  spawn.safeTeleport(veh, vec3(c.x, c.y, c.z + 0.4), quatFromDir(vec3(c.dx, c.dy, 0), vec3(0, 0, 1)), true, nil, nil, nil, false)
end

-- the fare is paid; returns false (and the caller refunds) when no cab can come here
function M.call(destination, fee)
  local me = onFoot()
  if ride or not me then return false end
  local c = spot(me:getPosition(), 12)
  if not c then return false end
  local ok, veh = pcall(core_vehicles.spawnNewVehicle, MODEL, { config = CONFIG, pos = vec3(c.x, c.y, c.z + 0.5), autoEnterVehicle = false, canSpawnAnotherVehicleCheck = false })
  if not ok or not veh then return false end
  place(veh, c)
  veh:queueLuaCommand('electrics.set_warn_signal(1) input.event("parkingbrake", 1, FILTER_DIRECT)')
  ride = { vid = veh:getID(), place = destination, fee = fee, waited = 0 }
  if core_groundMarkers then core_groundMarkers.setPath(vec3(c.x, c.y, c.z)) end
  toast(string.format('Your cab is waiting %d m away, hazards on. Walk up to it.', math.floor(c.dist + 0.5)))
  return true
end

local function drop(id) local v = getObjectByID(id) if v then v:delete() end end

-- in the cab: fade, both to the destination's lane, you out beside it, and it drives off
local function board()
  local r = ride
  ride = nil
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  core_jobsystem.create(function(job)
    guihooks.trigger('slFade', { on = true })
    job.sleep(0.8)
    local cab, me = getObjectByID(r.vid), onFoot()
    local c = spot(r.place.pos, 0)
    if cab and c then
      place(cab, c)
      local side = rightHand() and 1 or -1        -- the kerb side
      local out = vec3(c.x, c.y, c.z) + vec3(c.dy, -c.dx, 0) * (2.6 * side)
      if me then spawn.safeTeleport(me, out + vec3(0, 0, 0.3), quatFromDir(vec3(-c.dy, c.dx, 0) * side, vec3(0, 0, 1)), true) end
    elseif me then
      spawn.safeTeleport(me, r.place.pos + vec3(0, 0, 0.3), quatFromDir(r.place.dir, vec3(0, 0, 1)), true)
    end
    job.sleep(0.6)
    guihooks.trigger('slFade', { on = false })
    toast(string.format('%s. That was $%d.', r.place.name, r.fee))
    if cab and c then
      job.sleep(1.5)
      cab:queueLuaCommand('electrics.set_warn_signal(0) input.event("parkingbrake", 0, FILTER_DIRECT) ai.setMode("traffic")')
      leaving[r.vid] = DRIVE_OFF_SECONDS
    else
      drop(r.vid)
    end
  end)
end

function M.onUpdate(dtReal)
  for id, t in pairs(leaving) do
    leaving[id] = t - dtReal
    if leaving[id] <= 0 then leaving[id] = nil drop(id) end
  end
  if not ride then return end
  local cab = getObjectByID(ride.vid)
  ride.waited = ride.waited + dtReal
  if not cab or ride.waited > WAIT_SECONDS then
    if sl_career and ride.fee > 0 then sl_career.addMoney(ride.fee, 'Cab fare back') end
    toast('The cab got tired of waiting. Your fare is back.')
    if core_groundMarkers then core_groundMarkers.setPath(nil) end
    if cab then drop(ride.vid) end
    ride = nil
    return
  end
  local me = onFoot()
  if me and (me:getPosition() - cab:getPosition()):length() < BOARD_RADIUS then board() end
end

function M.busy() return ride ~= nil end

local function clear()
  if ride then drop(ride.vid) end
  for id in pairs(leaving) do drop(id) end
  ride, leaving = nil, {}
end
function M.onStreetLegalStopped() clear() end
function M.onClientEndMission() ride, leaving = nil, {} end

return M
