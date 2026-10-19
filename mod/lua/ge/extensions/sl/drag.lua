-- Street Legal: the drag strip in the career (extension name: sl_drag; #23)
-- The strip at Alder (West Coast USA) is the game's own freeroam drag: stage and pre-stage lights, the Christmas tree, reaction time, ET and trap
-- speed, the timeslip, a bracket race with a dial-in and its handicap start (gameplay_drag_*). The game offers it in freeroam only when its
-- "enableDragRaceInFreeroam" setting is on, and a stock career would be needed otherwise. Here, while this career runs, it is on BY DAY (a
-- day event, D2) and off at night, bracket racing is the type of every strip, and the other lane is a career racer's car, dialled by its estimated
-- ET, driven by the game's own drag AI. A run costs the entry fee and a win pays (rules: sl/core/drag).

local M = {}

local strings = require('sl/core/strings')

local patch = require('sl/core/patch')
local rules = require('sl/core/drag')
local stateLib = require('sl/core/state')
local rngLib = require('sl/core/rng')
local cancel = require('sl/core/racecancel')
local racelog = require('sl/racelog')

local savedCore, savedPoi = {}, {}
local run                      -- { practice, racerName, aiVid, lane, fee }

local function careerOn() return sl_career ~= nil and sl_career.isActive() == true and not (career_career and career_career.isActive and career_career.isActive() == true) end
local function dayOn() return careerOn() and sl_career.phase() == 'day' end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) if ui_message then ui_message(text, 7, 'streetLegal') end end
local function core() return gameplay_drag_core end

----------------------------------------------------------------------------------------------
-- the game's drag, switched on for the career's days

local function isDragEnabled()
  if careerOn() then return dayOn() end
  local orig = savedCore.isDragEnabled and savedCore.isDragEnabled.original
  return orig and orig() or false
end

-- every strip is a bracket race while the career runs (the dial-in and the handicap start)
local function applyUserRulesToData(data, stripId, levelId)
  local orig = savedPoi.applyUserRulesToData and savedPoi.applyUserRulesToData.original
  if orig then orig(data, stripId, levelId) end
  if careerOn() and type(data) == 'table' then data.dragType = 'bracketRace' end
end

local function install()
  if not careerOn() then return end
  if extensions and extensions.load and not core() then pcall(extensions.load, 'gameplay_drag_core') end        -- (the core brings the bridge with it)
  local changed = false
  if core() then changed = patch.install(core(), 'isDragEnabled', isDragEnabled, savedCore) or changed end
  if gameplay_drag_poi then changed = patch.install(gameplay_drag_poi, 'applyUserRulesToData', applyUserRulesToData, savedPoi) or changed end
  if changed and gameplay_rawPois and gameplay_rawPois.clear then gameplay_rawPois.clear() end        -- (the strip's stage markers are listed now)
end

local function restore()
  if core() then patch.restore(core(), 'isDragEnabled', savedCore) end
  if gameplay_drag_poi then patch.restore(gameplay_drag_poi, 'applyUserRulesToData', savedPoi) end
  if gameplay_rawPois and gameplay_rawPois.clear then gameplay_rawPois.clear() end
end

-- for the console: what the patch sees (sl_drag.status())
function M.status()
  local out = { careerOn = careerOn(), phase = careerOn() and sl_career.phase() or nil, coreLoaded = core() ~= nil, pokeLoaded = gameplay_drag_poi ~= nil,
    patched = savedCore.isDragEnabled ~= nil, enabledNow = core() and core().isDragEnabled and core().isDragEnabled() or false,
    setting = settings and settings.getValue and settings.getValue('enableDragRaceInFreeroam') or false }
  log('I', 'sl_drag', 'status ' .. dumps(out))
  return out
end

-- the game's drag modules may load after the career starts: looked for every few seconds until the patch is in
local installTimer = 0
local removeOpponent, laneSpawn      -- (defined with the opponent, further down)
local RUN_LIMIT = 300             -- seconds a run may last before it is called off
local function cancelRun(why)
  local r = run
  if not r or r.cancelled then return end
  r.cancelled = true
  racelog.add('drag', 'cancelled', { why = why, t = os.clock() - (r.t0 or os.clock()), opponent = racelog.car(r.aiVid and getObjectByID(r.aiVid)) })
  toast(why)
  if core() and core().clear then pcall(core().clear, { hooks = true }) end
  removeOpponent()
end

function M.onUpdate(dtReal)
  if not careerOn() then return end
  -- the game's drag bridge updates every frame and asks gameplay_drag_core, which is not always loaded with it (A8: an error a frame, the opponent never left)
  if gameplay_drag_dragBridge and not core() and extensions and extensions.load then pcall(extensions.load, 'gameplay_drag_core') end
  if run and run.t0 and not run.cancelled then
    local data = core() and core().getData and core().getData()
    local at = data and laneSpawn(data, 1)
    local pv = getPlayerVehicle(0)
    local off = at and pv and cancel.distToRoute({ x = pv:getPosition().x, y = pv:getPosition().y }, { { x = at.x, y = at.y } }) or nil
    local why = cancel.reason(os.clock() - run.t0, RUN_LIMIT, off)
    if why then cancelRun(why) end
  end
  installTimer = installTimer + (dtReal or 0)
  if installTimer > 3 then
    installTimer = 0
    -- the game's own UI (the strip's rules, history and timeslip panels) calls gameplay_drag_dragBridge by name at any time: while the career runs both are kept loaded
    -- (a FATAL LUA ERROR 'index global gameplay_drag_dragBridge' twice in a session without a race)
    if extensions and extensions.load then
      if not core() then pcall(extensions.load, 'gameplay_drag_core') end
      if not gameplay_drag_dragBridge then pcall(extensions.load, 'gameplay_drag_dragBridge') end
    end
    if not savedCore.isDragEnabled then install() end
  end
end
-- The stock HUD (the tree-lights app) and the drag panels call gameplay_drag_dragBridge by name from the first frame of a level, with or without a career:
-- a FATAL LUA ERROR at 53 s, before any career. So the game's drag core (which loads the bridge) is loaded whenever a level starts.
local function loadDragModules()
  if extensions and extensions.load and not gameplay_drag_dragBridge then pcall(extensions.load, 'gameplay_drag_core') end
end
M.onClientStartMission = loadDragModules
M.onWorldReadyState = loadDragModules
M.onExtensionLoaded = loadDragModules
M.onStreetLegalStarted = install
M.onStreetLegalPhase = install              -- (pois.lua clears the marker list on the phase: the strip comes and goes with it)
M.onStreetLegalPlacesChanged = install
M.onClientPostStartMission = function() loadDragModules() install() end
M.onStreetLegalStopped = restore
M.onExtensionUnloaded = restore

----------------------------------------------------------------------------------------------
-- the opponent: a career racer's car in the other lane, the game's drag AI does the rest

function removeOpponent()
  local r = run
  run = nil
  if r and r.aiVid then
    local vid = r.aiVid
    core_jobsystem.create(function(job) job.sleep(15) local v = getObjectByID(vid) if v then v:delete() end end)
  end
end

function laneSpawn(data, laneIndex)
  local lane = data.strip and data.strip.lanes and data.strip.lanes[laneIndex]
  local t = lane and lane.waypoints and lane.waypoints.spawn and lane.waypoints.spawn.transform
  if not (t and t.position and t.rot) then return nil end
  return vec3(t.position), t.rot
end

local function addOpponent(data, myLane, racer)
  local other = myLane == 1 and 2 or 1
  local pos, rot = laneSpawn(data, other)
  if not pos then
    run.practice = true
    toast(strings.t('drag.drag_strip_the_other_lane'))
    return
  end
  if not (sl_streets and sl_streets.buildRacerCar) then run.practice = true return end
  local started = sl_streets.buildRacerCar(racer.racerId, pos + vec3(0, 0, 0.4), rot, function(veh)
    if not run or not veh then
      if veh then veh:delete() end
      if run then run.practice = true toast(strings.t('drag.nobody_showed_up_at_the')) end
      return
    end
    local vid = veh:getID()
    run.aiVid = vid
    veh:queueLuaCommand('input.event("parkingbrake", 0, FILTER_DIRECT) controller.setFreeze(0)')
    local c = core()
    local d = c and c.getData()
    if not (d and d.racers) then return end
    c.setupRacer(vid, other)
    local r = d.racers[vid]
    if not r then run.practice = true return end
    r.isPlayable = false                    -- the game's drag AI stages, launches and stops it
    r.canBeReseted = false
    local details = core_vehicles and core_vehicles.getVehicleDetails and core_vehicles.getVehicleDetails(vid)
    local cfg = details and details.configs
    local et = rules.etEstimate(cfg and cfg.Power, cfg and cfg.Weight)
    local dial = rules.aiDial(et, racer.skill, rngLib.new(vid):range(-1, 1))
    c.setRacerDial(vid, dial)
    racelog.add('drag', 'opponent', { name = racer.name, model = veh:getJBeamFilename(), place = racelog.car(veh), dial = dial })
    log('I', 'sl_drag', string.format('opponent %s: %s, dial %.2f (estimate %s)', racer.name, tostring(details and details.configs and details.configs.Name), dial, et and string.format('%.2f', et) or 'none'))
  end)
  if not started then run.practice = true end
end

-- the player has lined up: the entry fee, and the other lane
function M.onDragRacersSetup(data)
  if not dayOn() or type(data) ~= 'table' then return end
  removeOpponent()
  local myLane
  for _, r in pairs(data.racers or {}) do if r.isPlayable then myLane = r.lane end end
  if not myLane then return end
  run = { fee = rules.ENTRY_FEE, lane = myLane, t0 = os.clock() }
  racelog.add('drag', 'setup', { lane = myLane, player = racelog.car(getPlayerVehicle(0)), fee = rules.ENTRY_FEE })
  if not sl_career.addMoney(-run.fee, strings.t('drag.drag_strip_entry')) then
    run.practice = true
    toast(string.format(strings.t('drag.drag_strip_d_to_line'), rules.ENTRY_FEE))
    return
  end
  local racer = (sl_career.racersForRace('drag', 1) or {})[1]
  if not racer then run.practice = true return end
  run.racerName = racer.name
  racelog.add('drag', 'racer', { name = racer.name, racerId = racer.racerId or racer.id })
  toast(string.format(strings.t('drag.drag_strip_s_lines_up'), racer.name))
  addOpponent(data, myLane, racer)
end

----------------------------------------------------------------------------------------------
-- the result: the game lights the winner's lane when every car has run

local function playerRacer(data)
  for _, r in pairs(data and data.racers or {}) do if r.isPlayable then return r end end
end

function M.onWinnerLightOn(lane)
  local r = run
  if not r then return end
  local data = core().getData()
  local me = playerRacer(data)
  if not me then removeOpponent() return end
  local important = data.importantTimerId or 'time_1_4'
  local timers = me.timers or {}
  local speedId = (important:gsub('^time_', 'velAt_'))
  local slip = rules.slip({
    et = timers[important] and timers[important].isSet and timers[important].value or nil,
    speed = timers[speedId] and timers[speedId].isSet and timers[speedId].value or nil,
    reaction = gameplay_drag_times and gameplay_drag_times.getReactionTimerValue and gameplay_drag_times.getReactionTimerValue(me) or nil,
    dial = timers.dial and timers.dial.value, dq = me.isDisqualified and tostring(me.disqualifiedReason or 'disqualified') or nil })
  local won = me.lane == lane and not me.isDisqualified
  racelog.add('drag', 'result', { won = won and 'yes' or 'no', lane = lane })
  local text = rules.slipText(slip)
  if r.practice then
    toast(strings.t('drag.practice_run_1', (text)))
  else
    local pay = rules.purse(won, r.fee)
    local s = sl_career.getState()
    if pay.money > 0 then sl_career.payOut(pay.money, strings.t('drag.drag_strip_win')) end
    if pay.rep ~= 0 and s then stateLib.addRep(s, pay.rep) end
    s = s or {}
    s.dragRuns = (s.dragRuns or 0) + 1
    if won then s.dragWins = (s.dragWins or 0) + 1 end
    toast(string.format('%s: %s. %s', won and strings.t('drag.you_won') or (strings.t('drag.you_lost_to_1', (tostring(r.racerName or strings.t('drag.the_other_lane'))))), text,
      pay.money > 0 and string.format(strings.t('drag.d_and_d_reputation'), pay.money, pay.rep) or strings.t('drag.nothing_paid')))
    extensions.hook('onStreetLegalChanged')
  end
  if won and slrrPedestrians and slrrPedestrians.cheer then slrrPedestrians.cheer(6) end          -- the crowd at the strip (#40)
  removeOpponent()
end

-- the run is called off (the strip was cleared, the career stopped): the other car goes
M.onDragClear = function() removeOpponent() end
local restoreAll = restore
M.onStreetLegalStopped = function() removeOpponent() restoreAll() end

-- (the Mods menu's Parts of the game: with this part off, the hooks above do nothing)
require('sl/core/features').gate('races', M)

return M
