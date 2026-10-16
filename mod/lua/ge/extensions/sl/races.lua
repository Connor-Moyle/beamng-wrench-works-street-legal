-- Wrench Works: Street Legal: the career's own street races (extension name: sl_races; W3), for a map with no
-- race mod of its own (progression.MAPS[level].races = 'sl_races'). The same contract the career consumes from
-- Valo City's slrrValoRaces (docs/integration.md): listRaces(), launch(missionId, offer), getState(),
-- acceptsVehicleId, and the hooks onSlrrRaceStarted(missionId, raceId) / onSlrrRaceFinished({ ... }), so nothing
-- else in the career branches on the map. Night sprints: a start line at every meet and at a few wide straight
-- roads, a route 1.5-4 km along the navgraph to a junction; both cars line up facing the route's first edge, a
-- countdown, the first car within 10 m of the goal wins, the other has 60 s. The geometry is in sl/core/races.

local M = {}

local races = require('sl/core/races')
local rngLib = require('sl/core/rng')

local ROAD_STARTS, MIN_APART = 7, 400         -- start lines on the roads, and the least distance between any two
local COUNTDOWN, BEHIND_S = 3, 60             -- seconds
local LINGER = 30                             -- seconds the opponent stays after the race

local list, listLevel                         -- the races of the level loaded
local state = 'idle'                          -- 'idle' | 'countdown' | 'racing'
local cur                                     -- { race, offer, playerVid, oppVid, ready, t, shown, done = { vid -> seconds } }

local function tell(text, seconds) if ui_message then ui_message(text, seconds or 5, 'streetLegal') end end
local function level() return getCurrentLevelIdentifier and getCurrentLevelIdentifier() or '' end
local function p3(v) return { x = v.x, y = v.y, z = v.z } end
local function v3(p) return vec3(p.x, p.y, p.z) end

-- the navgraph as plain tables (sl/core/races has no game calls)
local function graph()
  local ok, m = pcall(function() return map.getMap() end)
  local out = {}
  for name, n in pairs(ok and type(m) == 'table' and m.nodes or {}) do
    out[name] = { pos = p3(n.pos), radius = n.radius or 0, links = n.links or {} }
  end
  return out
end

-- the races of this level, made once from its navgraph and the career's meets (the same for a level every time)
local function build()
  local lvl = level()
  if list and listLevel == lvl then return list end
  list, listLevel = {}, lvl
  local nodes = graph()
  if not next(nodes) then return list end
  local rng = rngLib.new(rngLib.hash('races:' .. lvl))
  local function pathFn(a, b) return map.getPath(a, b, nil, 1e4) or {} end     -- (one-way roads respected)
  local starts = {}
  local meets = {}
  for id, p in pairs(sl_career and sl_career.getPlaces and sl_career.getPlaces() or {}) do
    if p.kind == 'meet' then meets[#meets + 1] = { id = id, place = p } end
  end
  table.sort(meets, function(a, b) return a.id < b.id end)
  for _, m in ipairs(meets) do
    local n1, n2 = map.findClosestRoad(m.place.pos)         -- the start is the road outside the meet
    if n1 and n2 and nodes[n1] and nodes[n2] then starts[#starts + 1] = { node = n1, pos = nodes[n1].pos, name = m.place.name } end
  end
  for _, s in ipairs(races.pickStarts(nodes, rng, ROAD_STARTS, MIN_APART)) do starts[#starts + 1] = s end
  for i, s in ipairs(starts) do
    local goal, path, len = races.pickGoal(nodes, s.node, pathFn, rng)
    local dir = goal and races.routeDir(nodes, path)
    if dir then
      list[#list + 1] = { id = 'sr' .. i, missionId = lvl .. '/slRace/sr' .. i, kind = 'night',
        name = s.name and (s.name .. ' sprint') or string.format('Sprint %d (%.1f km)', #list + 1, len / 1000),
        start = s.pos, finish = nodes[goal].pos, path = path, dir = dir, metres = math.floor(len) }
    end
  end
  log('I', 'sl_races', string.format('%s: %d sprints from %d start lines', lvl, #list, #starts))
  return list
end

-- the career reads these as Valo City's: id, missionId, name, kind, start, finish
function M.listRaces()
  local out = {}
  for _, r in ipairs(build()) do
    out[#out + 1] = { id = r.id, missionId = r.missionId, name = r.name, kind = r.kind, start = r.start, finish = r.finish, metres = r.metres }
  end
  return out
end
M.getState = function() return state end
M.acceptsVehicleId = true                     -- the offer may bring the racer's own car (offer.vehicleId)

-- a money bet moves through the shared wallet, as the map's races do; without Wrench Works the career settles it
local function changeMoney(amount, label)
  local ok, parts = pcall(require, 'slrr/garageParts')
  if ok and type(parts) == 'table' and parts.changeMoney then parts.changeMoney(amount, label) end
end

local function finish(won, abandoned)
  local c = cur
  cur, state = nil, 'idle'
  local o = c.offer
  local opp = c.oppVid and getObjectByID(c.oppVid)
  local pv = getObjectByID(c.playerVid)
  if pv then pv:queueLuaCommand('controller.setFreeze(0)') end
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  if o.stake == 'money' and tonumber(o.bet) and o.bet > 0 then
    changeMoney(won and o.bet or -o.bet, (won and 'Won' or (abandoned and 'Called off' or 'Lost')) .. ' a street race against ' .. tostring(o.name))
  end
  -- pink slips (not when called off): won, their car is handed over (the career parks it at your garage); lost, you
  -- walk and your car goes with them (sl_fleet notes the car gone, the career takes it off My cars)
  if o.stake == 'pink' and not abandoned then
    if won and opp then
      opp:queueLuaCommand('ai.setMode("disabled")')
      local vid = c.oppVid
      core_jobsystem.create(function(job) job.sleep(2) if getObjectByID(vid) then extensions.hook('onSlrrPinkCarDelivered', vid, nil) end end)
      opp = nil
    elseif not won and pv then
      local vid = c.playerVid
      if gameplay_walk then gameplay_walk.setWalkingMode(true, nil, nil, true) end
      core_jobsystem.create(function(job) job.sleep(1) local v = getObjectByID(vid) if v then v:delete() end end)
    end
  end
  extensions.hook('onSlrrRaceFinished', { won = won, stake = o.stake, bet = o.bet or 0, value = o.value, raceId = c.race.id,
    opponent = o.name, racerId = o.racerId, time = c.done[c.playerVid], missionId = c.race.missionId, place = won and 1 or 2,
    abandoned = abandoned or false, opponentVid = c.oppVid })
  if opp then                                 -- they drive off, and are gone after a while
    opp:queueLuaCommand('controller.setFreeze(0) input.event("parkingbrake", 0, FILTER_DIRECT) ai.setMode("traffic") ai.setAggression(0.5)')
    local vid = c.oppVid
    core_jobsystem.create(function(job) job.sleep(LINGER) local v = getObjectByID(vid) if v then v:delete() end end)
  end
end

-- the career calls this at the start line with its arranged race (offer: name, racerId, class, skill, aggression,
-- stake, bet, car, vehicleId, laps); nil offer: a race for nothing against nobody is not run here
function M.launch(missionId, offer)
  if state ~= 'idle' or type(offer) ~= 'table' then return false end
  local race
  for _, r in ipairs(build()) do if r.missionId == missionId then race = r end end
  local veh = getPlayerVehicle(0)
  if not race or not veh or veh:getJBeamFilename() == 'unicycle' then return false end
  local line = races.lineUp(race.start, race.dir)
  local rot = quatFromDir(vec3(race.dir.x, race.dir.y, 0), vec3(0, 0, 1))
  spawn.safeTeleport(veh, v3(line.player.pos) + vec3(0, 0, 0.3), rot, true, nil, nil, nil, false)   -- (8th: a reset would repair it)
  veh:queueLuaCommand('controller.setFreeze(1)')
  cur = { race = race, offer = offer, playerVid = veh:getID(), t = 0, done = {} }
  state = 'countdown'
  if core_groundMarkers then core_groundMarkers.setPath(v3(race.finish)) end
  local function withOpponent(opp)
    if not cur or cur.race ~= race then if opp then opp:delete() end return end
    if not opp then
      cur, state = nil, 'idle'
      veh:queueLuaCommand('controller.setFreeze(0)')
      tell('Nobody showed up.', 5)
      return
    end
    cur.oppVid = opp:getID()
    spawn.safeTeleport(opp, v3(line.opponent.pos) + vec3(0, 0, 0.3), rot, true, nil, nil, nil, false)
    opp:queueLuaCommand('controller.setFreeze(1) input.event("parkingbrake", 1, FILTER_DIRECT)')
    cur.t, cur.ready = 0, true
  end
  local own = offer.vehicleId and getObjectByID(offer.vehicleId)
  if own then
    withOpponent(own)
  elseif offer.racerId and sl_streets and sl_streets.buildRacerCar then
    if not sl_streets.buildRacerCar(offer.racerId, v3(line.opponent.pos) + vec3(0, 0, 0.5), rot, withOpponent) then withOpponent(nil) end
  else
    withOpponent(nil)
  end
  tell(string.format('%s: %s, %.1f km to the finish.', race.name, tostring(offer.name), race.metres / 1000), 6)
  return true
end

local function go()
  local c = cur
  state, c.t = 'racing', 0
  local pv, opp = getObjectByID(c.playerVid), c.oppVid and getObjectByID(c.oppVid)
  if pv then pv:queueLuaCommand('controller.setFreeze(0)') end
  if opp then
    local a = tonumber(c.offer.aggression) or 0.6
    opp:queueLuaCommand(string.format("controller.setFreeze(0) input.event('parkingbrake', 0, FILTER_DIRECT) ai.setSpeedMode('off') ai.setRecoverOnCrash(true) ai.setAvoidCars('on') ai.driveInLane('off') ai.setAggression(%f) ai.driveUsingPath({path = %s, aggression = %f})", a, serialize(c.race.path), a))
  end
  extensions.hook('onSlrrRaceStarted', c.race.missionId, c.race.id)
  tell('GO!', 2)
end

function M.onUpdate(dtReal)
  if not cur or not cur.ready then return end
  cur.t = cur.t + dtReal
  local pv = getObjectByID(cur.playerVid)
  if not pv or pv:getJBeamFilename() == 'unicycle' then return finish(false, true) end     -- out of the car: called off
  if state == 'countdown' then
    local left = COUNTDOWN - cur.t
    if left <= 0 then go()
    elseif math.ceil(left) ~= cur.shown then cur.shown = math.ceil(left) tell(tostring(cur.shown), 1) end
    return
  end
  local opp = cur.oppVid and getObjectByID(cur.oppVid)
  for _, v in ipairs({ pv, opp }) do
    local vid = v:getID()
    if not cur.done[vid] and races.nearGoal(p3(v:getPosition()), cur.race.finish) then cur.done[vid] = cur.t end
  end
  local mine, theirs = cur.done[cur.playerVid], opp and cur.done[cur.oppVid]
  if mine then return finish(not theirs or mine <= theirs) end
  if theirs and cur.t - theirs > BEHIND_S then return finish(false) end
end

local function drop()
  if cur then
    local pv = getObjectByID(cur.playerVid)
    if pv then pv:queueLuaCommand('controller.setFreeze(0)') end
  end
  cur, state = nil, 'idle'
end

M.onStreetLegalStopped = drop
M.onClientEndMission = function() drop() list, listLevel = nil, nil end
M.onExtensionUnloaded = drop

return M
