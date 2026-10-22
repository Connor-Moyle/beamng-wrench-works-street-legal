-- Street Legal: the patrol shift, "you are the police" (extension name: sl_patrol; police plan P12; switch Mods > Street Legal > Police chase > Patrol shifts).
-- A day job on the jobs board from 300 reputation: pick up a patrol car at the police station, and for a shift (ten minutes or three arrests)
-- the game's own suspects run from you (gameplay_police's random suspects, switched on for the shift); every arrest pays by how fast it came.
-- Bring the car back to the station: the pay, less a charge for the damage on the car. No heat for you while you wear the badge (sl_police asks
-- active()). Rules in sl/core/chase (the P12 block); the job itself rides on sl_jobs (a car job that settles here, not at its last stop).

local M = {}

local rules = require('sl/core/chase')
local strings = require('sl/core/strings')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function on() return not (sl_options and sl_options.get) or sl_options.get('slPolicePatrolJob') ~= false end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end
local function say(text, s) if ui_message then ui_message(text, s or 5, 'streetLegal') end end
local function playerVid() local v = getPlayerVehicle(0) return v and v:getID() or nil end
local function activeJob(s) local j = s and s.jobs and s.jobs.active return j and j.patrol and j or nil end

-- the offer on the board (sl_jobs asks): the police station is the pick-up and the return
function M.offer(ctx, rng)
  if not on() or not ctx or type(ctx.places) ~= 'table' then return nil end
  local st
  for _, p in ipairs(ctx.places) do if p.kind == 'impound' then st = p end end
  if not st then return nil end
  local function stop() return { id = st.id, name = st.name, x = st.x, y = st.y, z = st.z, radius = rules.PATROL.radius } end
  return { item = strings.t('patrol.shift'), legs = { stop(), stop() }, car = { model = rules.PATROL.car, config = rules.PATROL.config }, settle = true, patrol = true,
    hint = strings.t('patrol.hint_1_2', math.floor(rules.PATROL.shiftS / 60), rules.PATROL.arrests), seconds = rules.PATROL.shiftS, pay = rules.PATROL.base, metres = 0 }
end

-- ---- the shift
local shift = nil        -- { t0, vid, arrests = { seconds }, chases = { [id] = t0 }, returning, prevRandom }
local function trafficVars(random)
  if not (gameplay_traffic and gameplay_traffic.setTrafficVars) then return end
  pcall(gameplay_traffic.setTrafficVars, { enableRandomEvents = random })
end
local function startShift(j)
  local prev = nil
  pcall(function() prev = gameplay_traffic.getTrafficVars().enableRandomEvents end)
  shift = { t0 = os.clock(), vid = j.carVid, arrests = {}, chases = {}, returning = false, prevRandom = prev }
  pcall(function() local t = gameplay_traffic.getTrafficData()[j.carVid] if t and t.setRole then t:setRole('police') end end)      -- (the badge: suspects run from this car, patrols leave it alone)
  trafficVars(true)
  if sl_police and sl_police.refreshVars then pcall(sl_police.refreshVars) end
  say(strings.t('patrol.on_shift'), 6)
end
local function endShift()
  if not shift then return end
  trafficVars(shift.prevRandom == true)
  shift = nil
  if sl_police and sl_police.refreshVars then pcall(sl_police.refreshVars) end
end
function M.active() return shift ~= nil end

local function finishShift(s, j)
  local arrests = shift.arrests
  local damage = 0
  pcall(function() damage = tonumber(gameplay_traffic.getTrafficData()[shift.vid].damage) or 0 end)
  local charge = rules.damageCharge(damage)
  local pay = math.max(0, rules.patrolPay(arrests) - charge)
  local vid = shift.vid
  endShift()
  core_jobsystem.create(function(job)
    if gameplay_walk then gameplay_walk.setWalkingMode(true, nil, nil, true) end
    job.sleep(1)
    local veh = getObjectByID(vid)
    if veh then veh:delete() end
  end)
  sl_jobs.finishWith(s, s.jobs, j, pay, 10 + 5 * #arrests, strings.t('patrol.shift_done_1_2_3', #arrests, pay, charge))
end

local tickT = 0
local function tick()
  local s = career()
  local j = activeJob(s)
  if not j or not on() then endShift() return end
  if not j.carVid then return end                               -- (not picked up yet: sl_jobs builds the car at the station and seats you)
  if not shift then startShift(j) return end
  if shift.vid ~= j.carVid then endShift() return end
  local v = getPlayerVehicle(0)
  if not v or v:getID() ~= shift.vid then return end            -- (out of the car: the shift waits)
  local elapsed = os.clock() - shift.t0
  if not shift.returning and rules.shiftOver(elapsed, #shift.arrests) then
    shift.returning = true
    say(strings.t('patrol.shift_over_bring_it_back'), 7)
    if core_groundMarkers and j.legs[2] then core_groundMarkers.setPath(vec3(j.legs[2].x, j.legs[2].y, j.legs[2].z or 0)) end
  end
  local stop = j.legs[#j.legs]
  local p = v:getPosition()
  local d = math.sqrt((p.x - stop.x) ^ 2 + (p.y - stop.y) ^ 2)
  if d <= (stop.radius or rules.PATROL.radius) and v:getVelocity():length() < 2 and (shift.returning or elapsed >= rules.PATROL.earlyS) then finishShift(s, j) end
end
function M.onUpdate(dtReal)
  tickT = tickT + dtReal
  if tickT < 0.5 then return end
  tickT = 0
  local ok, err = pcall(tick)
  if not ok then log('E', 'sl_patrol', tostring(err)) end
end

-- the suspects' chases: an arrest pays by how fast it came
function M.onPursuitAction(id, action, pursuit)
  if not shift or id == playerVid() then return end
  if action == 'start' then shift.chases[id] = os.clock()
  elseif action == 'arrest' then
    local sec = os.clock() - (shift.chases[id] or os.clock())
    shift.chases[id] = nil
    shift.arrests[#shift.arrests + 1] = sec
    say(strings.t('patrol.arrest_1_2_3', #shift.arrests, math.floor(sec + 0.5), rules.arrestPay(sec)), 6)
  elseif action == 'evade' or action == 'release' then
    if shift.chases[id] then say(strings.t('patrol.got_away'), 4) end
    shift.chases[id] = nil
  end
end

function M.onStreetLegalStopped() endShift() end
function M.onClientEndMission() shift = nil end
function M.onStreetLegalOption(key) if key == 'slPolicePatrolJob' and not on() then endShift() end end
function M.status()
  if not shift then return 'no shift' end
  local secs = {}
  for _, a in ipairs(shift.arrests) do secs[#secs + 1] = string.format('%.0f', a) end
  return string.format('on shift %.0f s, arrests %d (%s), returning %s, pay so far $%d', os.clock() - shift.t0, #shift.arrests, table.concat(secs, ','), tostring(shift.returning), rules.patrolPay(shift.arrests))
end

return M
