-- Street Legal Racing: the police (extension name: sl_police)
-- As in SLRR, the city is patrolled after dark and street racing draws them. Two patrol cars stay
-- around you at night (the game's own police: they patrol, chase and arrest); every street race
-- raises your "heat", and the hotter you are the likelier a patrol joins in when a race starts.
-- Heat cools off day by day. Busted: a fine (the career's), and a car you cannot pay for goes to
-- the impound until you can.

local M = {}

local PATROLS = 2
local CONFIGS = {
  { 'fullsize', 'vehicles/fullsize/police.pc' },
  { 'midsize', 'vehicles/midsize/police.pc' },
  { 'roamer', 'vehicles/roamer/sheriff.pc' },
}

local units = {}          -- vehicle ids of our patrol cars
local timer, busy = 0, false

local HEAT_COOLING = 0.01   -- per real minute (balance pass, tools/economy_sim.py)
local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function night() return sl_career and sl_career.hour and require('sl/core/progression').isNight(sl_career.hour()) end

function M.heat()
  local s = career()
  return s and (s.heat or 0) or 0
end

local function addHeat(x)
  local s = career()
  if s then s.heat = math.max(0, math.min(1, (s.heat or 0) + x)) end
end

-- a road node some way off, to start a patrol where you will not see it appear
local function nodeAround(from, minD, maxD)
  local ok, nodes = pcall(function() return map.getMap().nodes end)
  if not ok or type(nodes) ~= 'table' then return nil end
  local pick, tries = nil, 0
  for _, n in pairs(nodes) do
    tries = tries + 1
    local d = (n.pos - from):length()
    if d > minD and d < maxD and (n.radius or 0) >= 1.5 and math.random() < 0.05 then pick = n break end
    if tries > 20000 then break end
  end
  return pick
end

-- the player has to be in the traffic system for the police to see them
local function playerInTraffic()
  local v = getPlayerVehicle(0)
  if not v or not gameplay_traffic then return end
  local data = gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {}
  if not data[v:getID()] then gameplay_traffic.insertTraffic(v:getID(), true) end
end

local function despawn(id)
  local v = getObjectByID(id)
  if v then v:delete() end
end

-- the career's settings (sl_options): police on or off, and how many patrols and how keen
local function policeOn() return not sl_options or sl_options.get('slPolice') ~= false end
local function level() return sl_options and sl_options.get('slPoliceLevel') or 1 end

local function updatePatrols()
  local v = getPlayerVehicle(0)
  if not v then return end
  -- the map turns traffic cars into night patrols itself (slrrValoNight): then no extra cars of ours on the road
  if slrrValoNight and slrrValoNight.setPolice then
    local want = policeOn()
    if (slrrValoNight.getState and slrrValoNight.getState() or {}).police ~= want then slrrValoNight.setPolice(want) end
  end
  local target = (policeOn() and not (slrrValoNight and slrrValoNight.setPolice)) and math.floor(PATROLS * level() + 0.5) or 0
  for i = #units, 1, -1 do
    local u = getObjectByID(units[i])
    if not u or (u:getPosition() - v:getPosition()):length() > 1600 or not night() or i > target then
      despawn(units[i])
      table.remove(units, i)
    end
  end
  if not night() or busy or #units >= target or not gameplay_traffic then return end
  local node = nodeAround(v:getPosition(), 400, 800)
  if not node then return end
  local cfg = CONFIGS[math.random(#CONFIGS)]
  busy = true
  core_jobsystem.create(function(job)
    local ok, veh = pcall(core_vehicles.spawnNewVehicle, cfg[1], { config = cfg[2], pos = node.pos + vec3(0, 0, 0.5), autoEnterVehicle = false, canSpawnAnotherVehicleCheck = false })
    if ok and veh then
      job.sleep(1.5)
      units[#units + 1] = veh:getID()
      if slrrDrivers and slrrDrivers.setDriver then slrrDrivers.setDriver(veh:getID(), 'slrr_police') end
      gameplay_traffic.insertTraffic(veh:getID())                         -- a police config: the game makes it a patrol
      playerInTraffic()
    end
    busy = false
  end)
end

-- a street race has started: heat, and maybe a patrol on your tail
function M.onRaceStart()
  local s = career()
  if not s or not policeOn() then return end
  addHeat(0.12 * (sl_crews and sl_crews.perksHere().heat or 1))       -- (half in your own districts: people look away)
  local chance = math.min(0.95, (0.15 + 0.55 * (s.heat or 0)) * level())
  if math.random() > chance or not gameplay_police then return end
  local v = getPlayerVehicle(0)
  if not v then return end
  playerInTraffic()
  local copId = gameplay_police.getNearestPoliceVehicle and gameplay_police.getNearestPoliceVehicle(v:getID(), false, true)
  if copId then
    gameplay_police.setPursuitMode(1, v:getID(), { copId })
    if ui_message then ui_message('Police! Lose them, or lose the race and pay.', 4, 'streetLegal') end
  end
end

M.onStreetLegalRaceStarted = M.onRaceStart
M.onSlrrRaceStarted = M.onRaceStart

function M.onStreetLegalNewDay() local s = career() if s then s.heat = (s.heat or 0) * 0.7 end end

function M.onUpdate(dtReal)
  if not career() then
    if #units > 0 then for _, id in ipairs(units) do despawn(id) end units = {} end
    return
  end
  timer = timer + dtReal
  if timer > 5 then
    timer = 0
    updatePatrols()
    local s = career()
    s.heat = math.max(0, (s.heat or 0) - HEAT_COOLING * 5 / 60)      -- heat cools as time passes, not only overnight
  end
end

function M.onStreetLegalStopped() for _, id in ipairs(units) do despawn(id) end units = {} end
function M.onClientEndMission() units = {} busy = false end

return M
