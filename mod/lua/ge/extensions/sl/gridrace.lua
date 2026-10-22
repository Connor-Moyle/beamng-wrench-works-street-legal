-- Street Legal: the grid runner (extension name: sl_gridrace). A race meeting on one of the closed layouts a map brings (race.race.json with a
-- standing grid, a mainPrefab and camera paths; West Coast: gameplay/trackLayers/dockyards/001-006), run by the game's own race object
-- (lua/ge/extensions/gameplay/race/race.lua): the layout's barriers and markings are placed for the race and removed after; the player takes the
-- default grid spot, 3 to 7 AI cars in the player's performance class (gameplay_vehiclePerformance) take the others, built one at a time behind the
-- fade under the shared black-time budget; the intro camera path, a countdown, the laps, the finish camera path; the result (place, time) goes to
-- whoever started it. Rules in sl/core/gridrace. No career state of its own: the caller (sl_calendar, later the invitationals) pays and records.
--
-- API (keep it small; docs/GRID_RUNNER.md):
--   sl_gridrace.start(spec, done) -> ok, text
--     spec = { layer = '003' (a dockyards layout) or dir = '/levels/<level>/.../' (a folder with race.race.json; mainPrefab.prefab.json and
--             introFwd/finishFwd.camPath.json when it has them), name = 'the title', laps = 3, purse = 800 (shown only),
--             field = 'offroad' (a roster of ours, sl/core/gridrace.ROSTERS; nil: the AI pool in the player's class), grid = n (a cap on the AI cars) }
--     done(result) once, result = { place = 1.. or nil (a DNF or an abort), time = seconds, grid = cars on the grid, aborted = true|nil }
--     rival = <racer id> (the one AI car is that rival's own car, built by sl_streets.buildRacerCar; the pool fills the rest of the grid),
--     onTick = function(ctx, dt) (called after the race object's update while the race runs, ctx = { race, playerId, ais }: a scorer such as the hill duel)
--   sl_gridrace.startRound(ctx) -> ok, why    the series interface (docs/DESIGN_CAREER_TRAVEL.md section 11.2): ctx.def.track, .laps, .field, .title;
--     reports to sl_series.report(ctx.series, ctx.round, { place, time, dnf, racers }) once, or sl_series.abort(ctx.series, ctx.round, why)
--   sl_gridrace.abort()        ends a running race (a career stop, a level end, a vehicle change); done gets { aborted = true }
--   sl_gridrace.running()      the running spec or nil
-- Settings: slGridCars (AI cars, 3 to 7; the Performance preset 3), slGridCams (the camera paths).

local M = {}

local rules = require('sl/core/gridrace')
local strings = require('sl/core/strings')
local builder = require('sl/carBuilder')
local rngLib = require('sl/core/rng')

local RACE_LIB = '/lua/ge/extensions/gameplay/race/race'
local cur = nil          -- { spec, race, playerId, ais = { { id, aggression } }, prefab, phase = 'build'|'race'|'finish', t, done }

local function opt(key, default)
  if not (sl_options and sl_options.get) then return default end
  local v = sl_options.get(key)
  if v == nil then return default end
  return v
end
local function fade(on) guihooks.trigger('slFade', { on = on }) end
local function say(text, s) if ui_message then ui_message(text, s or 5, 'streetLegal') end end
local function dirOf(spec) return spec.dir or ('/levels/' .. tostring(sl_career and sl_career.LEVEL or 'west_coast_usa') .. '/gameplay/trackLayers/dockyards/' .. tostring(spec.layer) .. '/') end
local function hasFile(f) return FS and FS.fileExists and FS:fileExists(f) == true end

-- the performance class of each AI pool car (the game's saved Performance Data of the config), read a few at a time: a job started with the career
-- scans the pool in the background; a race that comes first finishes the scan inside its own black-time budget, or goes with what is known
local classOf, scanAt = {}, 1
local function classFor(c)
  local k = c.model .. '/' .. c.config
  if classOf[k] == nil then
    local ok, d = pcall(function() return gameplay_vehiclePerformance.getClassFromConfig(c.model, c.config) end)
    classOf[k] = ok and type(d) == 'table' and type(d.class) == 'table' and d.class.name or false
  end
  return classOf[k] or nil
end
local function scanSome(n, until_)          -- n configs, or until the clock passes until_; true when the pool is done
  local pool = builder.aiPool()
  local stop = math.min(#pool, scanAt + n - 1)
  while scanAt <= stop do
    if until_ and os.clock() > until_ then return false end
    classFor(pool[scanAt])
    scanAt = scanAt + 1
  end
  return scanAt > #pool
end
local scanning = false
local function scanInBackground()
  if scanning or scanAt > #builder.aiPool() or not (core_jobsystem and core_jobsystem.create) then return end
  scanning = true
  core_jobsystem.create(function(job)
    while not scanSome(25) do job.sleep(0.05) end
    scanning = false
  end)
end
local function candidates()
  local out = {}
  for _, c in ipairs(builder.aiPool()) do
    local cls = classOf[c.model .. '/' .. c.config]
    if cls then out[#out + 1] = { model = c.model, config = c.config, class = cls } end
  end
  return out
end
function M.onStreetLegalStarted() pcall(scanInBackground) end
local function playerClass(vid)
  local ok, d = pcall(function() return gameplay_vehiclePerformance.getClassFromVehId(vid) end)
  return ok and type(d) == 'table' and type(d.class) == 'table' and d.class.name or 'B'
end

local function playCam(job, file, cap)
  if not (opt('slGridCams', true) and core_paths and core_paths.loadPath and hasFile(file)) then return end
  local ok, path = pcall(core_paths.loadPath, file)
  local seconds = ok and path and rules.camSeconds(path, cap) or 0
  if seconds <= 0 then return end
  pcall(core_paths.playPath, path)
  job.sleep(seconds)
  pcall(core_paths.stopCurrentPath)
  if core_camera and core_camera.setByName then pcall(core_camera.setByName, 0, 'orbit') end
end

local function cleanup()
  local c = cur
  cur = nil
  if not c then return end
  for _, a in ipairs(c.ais) do local v = getObjectByID(a.id) if v then pcall(v.delete, v) end end
  if c.prefab then pcall(removePrefab, c.prefab) end
  if sl_markers and sl_markers.clear then pcall(sl_markers.clear) end
  if c.frozePlayer then local v = getObjectByID(c.playerId) if v then v:queueLuaCommand('controller.setFreeze(0)') end end
  return c
end

local function finishRace(place, time)
  local c = cur
  if not c or c.phase == 'finish' then return end
  c.phase = 'finish'
  pcall(function() c.race:stopRace() end)
  say(place and strings.t('gridrace.you_finished_1', rules.placeWord(place)) or strings.t('gridrace.did_not_finish'), 6)
  core_jobsystem.create(function(job)
    job.sleep(1.5)
    if place then playCam(job, dirOf(c.spec) .. 'finishFwd.camPath.json', rules.CAM_FINISH_S) end
    cleanup()
    if c.done then pcall(c.done, { place = place, time = time, grid = #c.ais + 1 }) end
  end)
end

local function build(job)
  local c = cur
  local spec, r = c.spec, c.race
  fade(true)
  job.sleep(0.6)
  job.slFadeT0 = job.slFadeT0 or os.clock()
  -- the layout's barriers and markings (a layout without them: none)
  local prefabFile = dirOf(spec) .. 'mainPrefab.prefab.json'
  if hasFile(prefabFile) then
    c.prefab = 'sl_grid_' .. tostring(spec.layer or 'round')
    local okp, obj = pcall(spawnPrefab, c.prefab, prefabFile, '0 0 0', '0 0 0 1', '1 1 1')
    if not okp or not obj then c.prefab = nil end
  end
  -- the grid: the player on the default spot, the AI on the rest
  local sps, mine = {}, r.path.startPositions.objects[r.path.defaultStartPosition]
  for _, sp in ipairs(r.path.startPositions.sorted) do if sp ~= mine and not sp.missing then sps[#sps + 1] = sp end end
  mine = mine or table.remove(sps, 1)
  local pv = getObjectByID(c.playerId)
  if not pv then error('the player car is gone') end
  mine:moveResetVehicleTo(c.playerId, false, false)          -- (false: no repair; the car as it is)
  pv:queueLuaCommand('controller.setFreeze(1)')
  c.frozePlayer = true
  job.sleep(0.4)
  -- the field
  local s = sl_career and sl_career.isActive() and sl_career.getState() or nil
  local rng = rngLib.new(rngLib.hash(tostring(spec.name) .. ':' .. tostring(s and s.day or 0) .. ':' .. tostring(s and s.seed or 0)))
  local want = rules.gridSize(opt('slGridCars', rules.MAX), #sps + 1)
  if tonumber(spec.grid) then want = math.min(want, math.max(0, math.floor(spec.grid))) end
  if not spec.field then scanSome(1e9, job.slFadeT0 + rules.BUILD_S * 0.5) end      -- (the classes still unread: up to half the budget, then what is known)
  -- a named rival first: their own car (sl_streets builds racers' cars), on the first slot, waited for inside the budget
  if spec.rival and sl_streets and sl_streets.buildRacerCar and sps[1] then
    local sp, veh = table.remove(sps, 1), nil
    local started = sl_streets.buildRacerCar(spec.rival, sp.pos + vec3(0, 0, 0.5), sp.rot, function(v) veh = v or false end)
    while started and veh == nil and os.clock() - job.slFadeT0 < rules.BUILD_S do job.sleep(0.1) end
    if not veh then error('the rival car did not build') end      -- (never a race against a pool car in the rival's place: the pcall around build() aborts and pays nothing)
    sp:moveResetVehicleTo(veh:getID(), false, false)
    veh:queueLuaCommand('controller.setFreeze(1) electrics.setLightsState(1)')
    c.ais[#c.ais + 1] = { id = veh:getID(), aggression = rules.aggression(s and s.rep or 0) }
    want = math.max(0, want - 1)
  end
  local field = rules.field(rules.candidatesFor(spec.field, candidates), playerClass(c.playerId), want, rng)
  local aggression = rules.aggression(s and s.rep or 0)
  for i, f in ipairs(field) do
    if os.clock() - job.slFadeT0 > rules.BUILD_S then break end
    local sp = sps[i]
    if not sp then break end
    local veh = builder.spawn(job, f.model, f.config, sp.pos + vec3(0, 0, 0.5), sp.rot)
    if veh then
      sp:moveResetVehicleTo(veh:getID(), false, false)
      veh:queueLuaCommand('controller.setFreeze(1) electrics.setLightsState(1)')
      if slrrDrivers and slrrDrivers.setDriver then pcall(slrrDrivers.setDriver, veh:getID(), i % 2 == 0 and 'slrr_opponent1' or 'slrr_opponent2') end
      c.ais[#c.ais + 1] = { id = veh:getID(), aggression = aggression }
    end
  end
  if sl_markers and sl_markers.flareCircuit then
    local nodes = {}
    for _, nid in ipairs(r.path.config.linearPathnodes or {}) do nodes[#nodes + 1] = r.path.pathnodes.objects[nid] end
    pcall(sl_markers.flareCircuit, rules.cps(nodes))
  end
  fade(false)
  job.sleep(0.3)
  playCam(job, dirOf(spec) .. 'introFwd.camPath.json', rules.CAM_INTRO_S)
  -- the countdown and the start
  local ids = { c.playerId }
  for _, a in ipairs(c.ais) do ids[#ids + 1] = a.id end
  r:setVehicleIds(ids)
  for n = 3, 1, -1 do say(tostring(n), 1) job.sleep(1) end
  if cur ~= c then return end                 -- (aborted during the build)
  r:startRace()
  for _, a in ipairs(c.ais) do r:startAiVehicle(a.id, a.aggression) end
  pv:queueLuaCommand('controller.setFreeze(0)')
  c.frozePlayer = nil
  c.phase = 'race'
  c.t = 0
  say(strings.t('gridrace.go_1_laps', spec.laps or 3), 3)
end

function M.start(spec, done)
  if cur then return false, strings.t('career.not_now') end
  local pv = getPlayerVehicle(0)
  if not pv then return false, strings.t('gridrace.no_car') end
  local ok, raceLib = pcall(require, RACE_LIB)
  if not ok or type(raceLib) ~= 'function' then return false, strings.t('gridrace.no_race_object') end
  local r = raceLib()
  r.useLapTimesApp, r.useHotlappingApp = false, false
  local okFile = pcall(function() r:setPathFile(dirOf(spec) .. 'race.race.json') end)
  if not okFile or not r.path or not r.path.startPositions or #(r.path.startPositions.sorted or {}) < 2 then return false, strings.t('gridrace.no_track') end
  r.lapCount = tonumber(spec.laps) or 3
  cur = { spec = spec, race = r, playerId = pv:getID(), ais = {}, done = done, t = 0, phase = 'build' }
  core_jobsystem.create(function(job)
    local okb, err = pcall(build, job)
    if not okb then
      log('E', 'sl_gridrace', 'the grid race could not start: ' .. tostring(err))
      fade(false)
      M.abort()
    end
  end)
  return true, strings.t('gridrace.to_the_grid')
end

function M.abort()
  local c = cur
  if not c then return end
  pcall(function() c.race:stopRace() end)
  cleanup()
  if c.done then pcall(c.done, { place = nil, aborted = true, grid = #c.ais + 1 }) end
end
function M.running() return cur and cur.spec or nil end

-- a series round (sl_series, section 11.2): the round's track folder, laps and field; the result goes to sl_series.report once, an abort to sl_series.abort
function M.startRound(ctx)
  if type(ctx) ~= 'table' or type(ctx.def) ~= 'table' or not ctx.def.track then return false, strings.t('gridrace.no_track') end
  local d = ctx.def
  return M.start({ dir = rules.roundDir(d.track), name = d.title or tostring(d.track), laps = d.laps or 3, field = d.field, grid = ctx.rivals }, function(res)
    if not sl_series then return end
    if res.aborted then
      if sl_series.abort then sl_series.abort(ctx.series, ctx.round, 'aborted') end
    elseif sl_series.report then
      sl_series.report(ctx.series, ctx.round, { place = res.place, time = res.time, dnf = res.place == nil, racers = res.grid })
    end
  end)
end

function M.onUpdate(dtReal, dtSim)
  local c = cur
  if not c or c.phase ~= 'race' then return end
  local dt = dtSim or dtReal
  c.t = c.t + dt
  local ok, err = pcall(function() c.race:onUpdate(dt) end)
  if not ok then log('E', 'sl_gridrace', tostring(err)) M.abort() return end
  local st = c.race.states[c.playerId]
  if c.spec.onTick then local okt, errt = pcall(c.spec.onTick, { race = c.race, playerId = c.playerId, ais = c.ais }, dt) if not okt then log('E', 'sl_gridrace', 'onTick: ' .. tostring(errt)) end end
  if st and st.complete then finishRace(st.placement, st.endTime) return end
  if c.t > rules.MAX_RACE_S then finishRace(nil, c.t) end
end

function M.onVehicleSwitched(old, new) if cur and new ~= cur.playerId then M.abort() end end
function M.onStreetLegalStopped() M.abort() end
function M.onClientEndMission() cur = nil end

function M.status()
  if not cur then return 'no grid race' end
  local st = cur.race.states and cur.race.states[cur.playerId]
  return string.format('%s: %s, %d AI, lap %s, t %.0f s', tostring(cur.spec.name), cur.phase, #cur.ais, st and tostring((st.currentLap or 0) + 1) or '-', cur.t or 0)
end

return M
