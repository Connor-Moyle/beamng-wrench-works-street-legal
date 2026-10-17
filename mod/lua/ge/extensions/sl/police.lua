-- Street Legal Racing: the police (extension name: sl_police)
-- As in SLRR, the city is patrolled after dark and street racing draws them. Two patrol cars stay
-- around you at night (the game's own police: they patrol, chase and arrest); every street race
-- raises your "heat", and the hotter you are the likelier a patrol joins in when a race starts.
-- D3: heat exists only at night (the day starts at zero), a level 0-5 (sl/core/heat has the rules): it is raised by street races, by flashing past
-- a patrol and by a chase you escape; the higher it is the more patrols (one more a level), the stricter and the harder to shake the game's police
-- (its pursuit variables), roadblocks from level 4 (the game's own, during a chase), a bigger reputation multiplier and fine; the reputation the
-- night earned is banked when you reach a garage. Busted: a fine (the career's), the unbanked reputation, and a car you cannot pay for (or at
-- level 4-5 any car) goes to the impound until you can.

local M = {}

local strings = require('sl/core/strings')

local heatLib = require('sl/core/heat')
local spawnplan = require('sl/core/spawnplan')

local PATROLS = 2
local CONFIGS = {
  { 'fullsize', 'vehicles/fullsize/police.pc' },
  { 'midsize', 'vehicles/midsize/police.pc' },
  { 'roamer', 'vehicles/roamer/sheriff.pc' },
}

local units = {}          -- vehicle ids of our patrol cars
local timer, busy = 0, false
local lastBuild = -1e9    -- os.clock() of our last patrol build (the racers' builds in sl_streets have their own; sl_streets.buildGate() joins them)
local nearTimer = 0

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function night() return sl_career and sl_career.isNight and sl_career.isNight() end

-- heat is the night's: by day it is nothing
function M.heat()
  local s = career()
  return s and night() and (s.heat or 0) or 0
end
function M.level() return heatLib.level(M.heat()) end

local function addHeat(x)
  local s = career()
  if s and night() then s.heat = heatLib.raised(s.heat, x) end
end

-- the game's police has a chase on the player now
function M.inPursuit()
  local v = getPlayerVehicle(0)
  return v ~= nil and gameplay_police ~= nil and gameplay_police.isVehicleInPursuit ~= nil and gameplay_police.isVehicleInPursuit(v:getID()) == true
end

-- the game's police variables follow the phase and the heat (strictness, roadblocks, how long it takes to lose them)
local appliedVars
local function applyVars()
  if not (gameplay_police and gameplay_police.setPoliceVars) then return end
  local level = M.level()
  local key = tostring(sl_career.phase()) .. level
  if key == appliedVars then return end
  appliedVars = key
  gameplay_police.setPoliceVars(heatLib.policeVars(sl_career.phase(), level))
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
    local want = policeOn() and night()      -- (D3: the phase decides the night, not the clock)
    if (slrrValoNight.getState and slrrValoNight.getState() or {}).police ~= want then slrrValoNight.setPolice(want) end
  end
  local target = (policeOn() and not (slrrValoNight and slrrValoNight.setPolice)) and math.floor(PATROLS * level() + 0.5) or 0
  if policeOn() then target = target + math.floor(heatLib.extraPatrols(sl_career.phase(), M.level()) * level() + 0.5) end      -- (D3) one more a heat level, on top of the map's own
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
  local sBusy, sSince = false, 1e9
  if sl_streets and sl_streets.buildGate then sBusy, sSince = sl_streets.buildGate() end
  local since = math.min(sSince or 1e9, os.clock() - lastBuild)
  local speed = v:getVelocity():length()
  if not spawnplan.patrolOk(speed, since, busy or sBusy, M.inPursuit() or M.level() >= 4) then return end      -- (not lost: the next tick looks again)
  local cfg = CONFIGS[math.random(#CONFIGS)]
  busy = true
  lastBuild = os.clock()
  if sl_streets and sl_streets.noteBuild then sl_streets.noteBuild() end
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
  addHeat(heatLib.RACE * (sl_crews and sl_crews.perksHere().heat or 1))       -- (half in your own districts: people look away)
  local chance = math.min(0.95, (0.15 + 0.55 * M.heat()) * level())
  if math.random() > chance or not gameplay_police then return end
  local v = getPlayerVehicle(0)
  if not v then return end
  playerInTraffic()
  local copId = gameplay_police.getNearestPoliceVehicle and gameplay_police.getNearestPoliceVehicle(v:getID(), false, true)
  if copId then
    gameplay_police.setPursuitMode(1, v:getID(), { copId })
    if ui_message then ui_message(strings.t('police.police_lose_them_or_lose'), 4, 'streetLegal') end
  end
end

M.onStreetLegalRaceStarted = M.onRaceStart
M.onSlrrRaceStarted = M.onRaceStart

function M.onStreetLegalNewDay() local s = career() if s then s.heat = (s.heat or 0) * 0.7 end end

-- a phase switch: the day clears the heat (the career did), the police's rules and our extra patrols follow
function M.onStreetLegalPhase(phase)
  appliedVars = nil
  if phase ~= 'night' then for i = #units, 1, -1 do despawn(units[i]) units[i] = nil end end
end

-- flashing past a patrol at speed: a little heat (once in a while)
local nearMissAt = 0
local function nearMiss(now)
  if not (night() and policeOn() and gameplay_police and gameplay_police.getPoliceVehicles) or now - nearMissAt < 20 then return end
  local v = getPlayerVehicle(0)
  if not v or v:getVelocity():length() < 22 then return end      -- about 80 km/h
  local p = v:getPosition()
  for id in pairs(gameplay_police.getPoliceVehicles() or {}) do
    local c = getObjectByID(id)
    if c and id ~= v:getID() and (c:getPosition() - p):length() < 12 then
      nearMissAt = now
      addHeat(heatLib.NEAR_MISS)
      return
    end
  end
end

-- the reputation the night earned is banked when you get back to a garage
local function bankAtGarage()
  if not (night() and sl_career.atRisk and sl_career.atRisk() > 0 and sl_career.getPlaces) or M.inPursuit() then return end
  local v = getPlayerVehicle(0)
  if not v then return end
  local p = v:getPosition()
  for _, place in pairs(sl_career.getPlaces() or {}) do
    if place.kind == 'garage' and place.pos and (place.pos - p):length() < 35 then
      local n = sl_career.bankRep()
      if n > 0 and ui_message then ui_message(string.format(strings.t('police.back_at_the_garage_d'), n), 5, 'streetLegal') end
      return
    end
  end
end

function M.onUpdate(dtReal)
  if not career() then
    if #units > 0 then for _, id in ipairs(units) do despawn(id) end units = {} end
    return
  end
  timer = timer + dtReal
  nearTimer = nearTimer + dtReal
  if nearTimer > 1 then nearTimer = 0 nearMiss(os.clock()) end
  if timer > 5 then
    timer = 0
    updatePatrols()
    local s = career()
    if night() then
      if not M.inPursuit() then s.heat = heatLib.cooled(s.heat, 5 / 60) end      -- heat cools as time passes while nobody is after you
      bankAtGarage()
    end
    applyVars()
  end
end

function M.onStreetLegalStopped() for _, id in ipairs(units) do despawn(id) end units = {} end
function M.onClientEndMission() units = {} busy = false end

return M
