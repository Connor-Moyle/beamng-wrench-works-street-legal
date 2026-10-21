-- Wrench Works: Street Legal: a real cab (extension name: sl_cab; playtest #5)
-- Booked on the phone (sl_career.taxi checks you can pay; nothing is charged yet): a taxi starts on a road out of your sight and drives up to you
-- (the game's AI), stops beside you and puts its hazards on, a ground marker leading to it. Walk up to it (6 m) and you get in, or wait: a few seconds after
-- it has stopped it takes you in if you are within 30 m. The screen fades, and you step out at the place you asked for (a lot: in its car park in front of the
-- cars; else beside the cab on a road), while it drives off into town; the fare is charged then (sl_career.chargeFare). Never boarded (five minutes), it leaves
-- and nothing was charged.

local M = {}

local strings = require('sl/core/strings')

local roadspot = require('sl/core/roadspot')
local cabplan = require('sl/core/cabplan')

local MODEL, CONFIG = 'fullsize', 'vehicles/fullsize/taxi.pc'
local ARRIVED = 9              -- m from where it was sent: it has come
local WAIT_SECONDS = 300
local DRIVE_OFF_SECONDS = 25
local DRIVE_LIMIT = 40        -- s: a cab not here by then (stuck, slow, lost) is put beside you

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

-- the fare is charged on arrival (fee: what it will be); returns false when no cab can come here
function M.call(destination, fee)
  local me = onFoot()
  if ride or not me then return false end
  local mine = me:getPosition()
  -- starts out of sight, 90 m or more along the road; the old nearest lane when no road gives that
  local cam = { x = mine.x, y = mine.y, fx = 0, fy = 0 }
  local okc, cp = pcall(core_camera.getPosition)
  local okf, cf = pcall(core_camera.getForward)
  if okc and cp and okf and cf then cam = { x = cp.x, y = cp.y, fx = cf.x, fy = cf.y } end
  local cands = roadspot.candidates(map.getMap().nodes, mine, rightHand(), 400)
  local c = cabplan.approach(cands, cam)
  local coming = c ~= nil
  if not c then c = spot(mine, 4) end              -- (no road out of sight: the nearest free lane, close to you)
  if not c then return false end
  local ok, veh = pcall(core_vehicles.spawnNewVehicle, MODEL, { config = CONFIG, pos = vec3(c.x, c.y, c.z + 0.5), autoEnterVehicle = false, canSpawnAnotherVehicleCheck = false })
  if not ok or not veh then return false end
  place(veh, c)
  ride = { vid = veh:getID(), place = destination, fee = fee, waited = 0 }
  local n1 = coming and map.findClosestRoad(mine)
  local node = n1 and map.getMap().nodes[n1]
  if node then
    -- drives up by itself and stops at the road node nearest to you
    veh:queueLuaCommand('input.event("parkingbrake", 0, FILTER_DIRECT) ai.setState({mode = "manual"}) ai.setAggression(0.7) ai.setTarget("' .. n1 .. '")')
    ride.target = node.pos
    ride.here = nil
    toast(string.format(strings.t('cab.your_cab_is_on_its'), math.floor(c.dist + 0.5)))
  else
    veh:queueLuaCommand('electrics.set_warn_signal(1) input.event("parkingbrake", 1, FILTER_DIRECT)')
    if core_groundMarkers then core_groundMarkers.setPath(vec3(c.x, c.y, c.z)) end
    toast(string.format(strings.t('cab.your_cab_is_waiting_d'), math.floor(c.dist + 0.5)))
    ride.here = 0
  end
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
      local drop = cabplan.dropAt(r.place)            -- a lot: out in its car park, in front of the cars, not on a road
      if me and drop then spawn.safeTeleport(me, vec3(drop.x, drop.y, drop.z + 0.3), quatFromDir(vec3(drop.dx, drop.dy, 0), vec3(0, 0, 1)), true)
      elseif me then spawn.safeTeleport(me, out + vec3(0, 0, 0.3), quatFromDir(vec3(-c.dy, c.dx, 0) * side, vec3(0, 0, 1)), true) end
    elseif me then
      spawn.safeTeleport(me, r.place.pos + vec3(0, 0, 0.3), quatFromDir(r.place.dir, vec3(0, 0, 1)), true)
    end
    job.sleep(0.6)
    guihooks.trigger('slFade', { on = false })
    local paid = sl_career and sl_career.chargeFare and sl_career.chargeFare(r.fee, r.place.name) or 0
    toast(string.format(strings.t('cab.s_that_was_d'), r.place.name, paid))
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
    toast(strings.t('cab.the_cab_got_tired_of'))
    if core_groundMarkers then core_groundMarkers.setPath(nil) end
    if cab then drop(ride.vid) end
    ride = nil
    return
  end
  -- the cab has driven up: it stops, hazards on
  if ride.target and not ride.arrived and (cab:getPosition() - ride.target):length() < ARRIVED and cab:getVelocity():length() < 2 then
    ride.arrived, ride.here = true, 0
    if core_groundMarkers then core_groundMarkers.setPath(cab:getPosition()) end
    cab:queueLuaCommand('ai.setState({mode = "disabled"}) electrics.set_warn_signal(1) input.event("parkingbrake", 1, FILTER_DIRECT)')
    toast(strings.t('cab.your_cab_is_here_hazards'))
  end
  -- (a cab that is not here in DRIVE_LIMIT seconds is put at the nearest free lane close to you, hazards on)
  if ride.target and not ride.arrived and ride.waited > DRIVE_LIMIT then
    local mine = onFoot() and onFoot():getPosition()
    local c = mine and spot(mine, 4)
    if c then
      place(cab, c)
      cab:queueLuaCommand('ai.setState({mode = "disabled"}) electrics.set_warn_signal(1) input.event("parkingbrake", 1, FILTER_DIRECT)')
      ride.arrived, ride.here = true, 0
      if core_groundMarkers then core_groundMarkers.setPath(vec3(c.x, c.y, c.z)) end
      toast(strings.t('cab.your_cab_is_here_hazards'))
    end
  end
  local me = onFoot()
  if ride.here then ride.here = ride.here + dtReal end
  if me and (not ride.target or ride.arrived) and cabplan.boardNow((me:getPosition() - cab:getPosition()):length(), ride.here) then board() end
end

function M.busy() return ride ~= nil end

local function clear()
  if ride then drop(ride.vid) end
  for id in pairs(leaving) do drop(id) end
  ride, leaving = nil, {}
end
function M.onStreetLegalStopped() clear() end
function M.onClientEndMission() ride, leaving = nil, {} end

-- (the Mods menu's Parts of the game: with this part off, the hooks above do nothing)
require('sl/core/features').gate('cab', M, nil, nil, { 'call' })

return M
