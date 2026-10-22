-- Wrench Works: Street Legal: the career's own street races (extension name: sl_races; W3), for a map with no
-- race mod of its own (progression.MAPS[level].races = 'sl_races'). The same contract the career consumes from
-- Valo City's slrrValoRaces (docs/integration.md): listRaces(), launch(missionId, offer), getState(),
-- acceptsVehicleId, and the hooks onSlrrRaceStarted(missionId, raceId) / onSlrrRaceFinished({ ... }), so nothing
-- else in the career branches on the map. Night sprints: a start line at every meet and at a few wide straight
-- roads, a route 1.5-4 km along the navgraph to a junction; both cars line up facing the route's first edge, a
-- countdown, the first car within 10 m of the goal wins, the other has 60 s. The geometry is in sl/core/races.

local M = {}

local strings = require('sl/core/strings')

local races = require('sl/core/races')
local preview = require('sl/core/routepreview')
local cancel = require('sl/core/racecancel')
local racelog = require('sl/racelog')
local rngLib = require('sl/core/rng')

local ROAD_STARTS, MIN_APART = 7, 400         -- start lines on the roads, and the least distance between any two
local COUNTDOWN = 3                           -- seconds
local LINGER = 30                             -- seconds the opponent stays after the race
local prof = {frames = 0, ms = 0, max = 0}    -- onUpdate's cost (getProfile)

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
    local dir = goal and races.routeDir(nodes, path, 25)
    if dir then
      list[#list + 1] = { id = 'sr' .. i, missionId = lvl .. '/slRace/sr' .. i, kind = 'night',
        name = s.name and (strings.t('races.1_sprint', (s.name))) or string.format(strings.t('races.sprint_d_1f_km'), #list + 1, len / 1000),
        start = s.pos, finish = nodes[goal].pos, path = path, dir = dir, metres = math.floor(len), wps = races.waypoints(path, 12) }
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
-- the phase as the career reads it (string), and the rest for QA: slrrValoRaces returns a bare string, so the
-- career takes either
M.getState = function()
  if not cur then return { phase = state } end
  return { phase = state, raceId = cur.race.id, missionId = cur.race.missionId, start = cur.race.start, goal = cur.race.finish,
           playerVid = cur.playerVid, opponentVid = cur.oppVid, ready = cur.ready or false, t = cur.t, done = cur.done }
end
-- the race's route as a small map for the phone (#18): { points, start, finish, w, h, metres }, made once per race
local previews = {}
function M.preview(raceId)
  if previews[raceId] ~= nil then return previews[raceId] or nil end
  previews[raceId] = false
  local nodes
  for _, r in ipairs(build()) do
    if r.id == raceId then
      nodes = nodes or graph()
      local pts = {}
      for _, name in ipairs(r.path or {}) do
        local n = nodes[name]
        if n then pts[#pts + 1] = { x = n.pos.x, y = n.pos.y } end
      end
      previews[raceId] = preview.fit(preview.thin(pts, 70), 240, 140, 12) or false
    end
  end
  return previews[raceId] or nil
end
M.acceptsVehicleId = true                     -- the offer may bring the racer's own car (offer.vehicleId)

-- a money bet moves through the shared wallet, as the map's races do; without Wrench Works the career settles it
local function changeMoney(amount, label)
  local ok, parts = pcall(require, 'slrr/garageParts')
  if ok and type(parts) == 'table' and parts.changeMoney then parts.changeMoney(amount, label) end
end

local function finish(won, abandoned, why)
  local c = cur
  cur, state = nil, 'idle'
  racelog.add('sprint', abandoned and 'cancelled' or 'finish', { race = c.race.id, won = won and 'yes' or 'no', t = c.t, why = why or '', player = racelog.car(getObjectByID(c.playerVid)), opponent = racelog.car(c.oppVid and getObjectByID(c.oppVid)) })
  if why then tell(why, 6) end
  local o = c.offer
  local opp = c.oppVid and getObjectByID(c.oppVid)
  local pv = getObjectByID(c.playerVid)
  if pv then pv:queueLuaCommand('controller.setFreeze(0)') end
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  if o.stake == 'money' and tonumber(o.bet) and o.bet > 0 then
    changeMoney(won and o.bet or -o.bet, strings.t('races.1_a_street_race_against', (won and 'Won' or (abandoned and strings.t('races.called_off') or 'Lost')), (tostring(o.name))))
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
  local mine, theirs = c.done.player, c.oppVid and c.done.opponent
  extensions.hook('onSlrrRaceFinished', { won = won, stake = o.stake, bet = o.bet or 0, value = o.value, raceId = c.race.id,
    opponent = o.name, racerId = o.racerId, time = mine, missionId = c.race.missionId, place = won and 1 or 2,
    abandoned = abandoned or false, opponentVid = c.oppVid, margin = mine and theirs and math.abs(theirs - mine) or nil })
  if opp then                                 -- they drive off, and are gone after a while
    opp:queueLuaCommand('controller.setFreeze(0) input.event("parkingbrake", 0, FILTER_DIRECT) ai.setMode("traffic") ai.setAggression(0.5)')
    local vid = c.oppVid
    core_jobsystem.create(function(job) job.sleep(LINGER) local v = getObjectByID(vid) if v then v:delete() end end)
  end
end

-- the career calls this at the start line with its arranged race (offer: name, racerId, class, skill, aggression,
-- stake, bet, car, vehicleId, laps); nil offer: a race for nothing against nobody is not run here
local function refuse(missionId, why)
  log('W', 'sl_races', 'launch ' .. tostring(missionId) .. ' refused: ' .. why)
  return false
end

function M.launch(missionId, offer)
  if state ~= 'idle' then return refuse(missionId, 'a race is on (' .. state .. ')') end
  if type(offer) ~= 'table' then return refuse(missionId, strings.t('races.no_offer_name_racerid_stake')) end
  local race
  for _, r in ipairs(build()) do if r.missionId == missionId then race = r end end
  if not race then return refuse(missionId, strings.t('races.not_one_of_this_level') .. #build() .. ' sprints (listRaces)') end
  local veh = getPlayerVehicle(0)
  if not veh or veh:getJBeamFilename() == 'unicycle' then return refuse(missionId, strings.t('races.the_player_is_not_in')) end
  -- the opponent: the car the offer brings, else the racer's own car built by the career (sl_streets, career only)
  local own = offer.vehicleId and getObjectByID(offer.vehicleId)
  local canBuild = offer.racerId and sl_streets and sl_streets.buildRacerCar and sl_career and sl_career.isActive and sl_career.isActive()
  if not own and not canBuild then
    return refuse(missionId, strings.t('races.no_opponent_the_offer_brings'))
  end
  local line = races.lineUp(race.start, race.dir)
  local rot = quatFromDir(vec3(race.dir.x, race.dir.y, 0), vec3(0, 0, 1))
  -- the car's centre on the line, no reset (a reset would repair it), no traffic removed
  spawn.safeTeleport(veh, v3(line.player.pos) + vec3(0, 0, 0.3), rot, true, nil, false, true, false)
  veh:queueLuaCommand('controller.setFreeze(1)')
  cur = { race = race, offer = offer, playerVid = veh:getID(), t = 0, done = {} }
  state = 'countdown'
  do
    local nodes, route = graph(), {}
    for _, name in ipairs(race.path or {}) do if nodes[name] then route[#route + 1] = { x = nodes[name].pos.x, y = nodes[name].pos.y } end end
    cur.route, cur.limit = route, cancel.timeLimit(race.metres)
  end
  racelog.add('sprint', 'setup', { race = race.id, name = race.name, start = race.start, finish = race.finish, dir = string.format('(%.2f,%.2f)', race.dir.x, race.dir.y), metres = race.metres,
    opponent = offer.name, racerId = offer.racerId, car = offer.car, stake = offer.stake, bet = offer.bet or 0, player = racelog.car(veh), lineP = v3(line.player.pos), lineO = v3(line.opponent.pos) })
  if core_groundMarkers then core_groundMarkers.setPath(race.wps) end           -- the race's own route, not the planner's choice from here
  local function withOpponent(opp)
    if not cur or cur.race ~= race then if opp then opp:delete() end return end
    if not opp then
      cur, state = nil, 'idle'
      veh:queueLuaCommand('controller.setFreeze(0)')
      if core_groundMarkers then core_groundMarkers.setPath(nil) end
      log('W', 'sl_races', 'launch ' .. race.missionId .. ': the opponent\'s car was not built')
      tell(strings.t('races.nobody_showed_up'), 5)
      return
    end
    cur.oppVid = opp:getID()
    racelog.add('sprint', 'opponent', { race = race.id, model = opp:getJBeamFilename(), vid = cur.oppVid })
    spawn.safeTeleport(opp, v3(line.opponent.pos) + vec3(0, 0, 0.3), rot, true, nil, false, true, false)
    opp:queueLuaCommand('controller.setFreeze(1) input.event("parkingbrake", 1, FILTER_DIRECT)')
    cur.t, cur.ready = 0, true
  end
  if own then
    withOpponent(own)
  elseif not sl_streets.buildRacerCar(offer.racerId, v3(line.opponent.pos) + vec3(0, 0, 0.5), rot, withOpponent) then
    log('W', 'sl_races', 'launch ' .. missionId .. ': the career has no racer ' .. tostring(offer.racerId) .. ' (nobody came)')
    withOpponent(nil)
  end
  tell(string.format(strings.t('races.s_s_1f_km_to'), race.name, tostring(offer.name), race.metres / 1000), 6)
  return true
end

local function go()
  local c = cur
  state, c.t = 'racing', 0
  local pv, opp = getObjectByID(c.playerVid), c.oppVid and getObjectByID(c.oppVid)
  if pv then pv:queueLuaCommand('controller.setFreeze(0)') end
  if opp then
    -- one target, the goal node: the car's own AI plans the route (as sl_streets' races do). A full node list as
    -- `path` had the vehicle AI replanning hundreds of names each frame, and the whole game waits for vehicle Lua
    local a = tonumber(c.offer.aggression) or 0.6
    opp:queueLuaCommand(string.format("controller.setFreeze(0) input.event('parkingbrake', 0, FILTER_DIRECT) ai.setSpeedMode('off') ai.setRecoverOnCrash(true) ai.setAvoidCars('on') ai.driveInLane('off') ai.setAggression(%f) ai.driveUsingPath({wpTargetList = %s, aggression = %f})", a, serialize(c.race.wps), a))
  end
  local function fwd(v) local f = v and v:getDirectionVector() return f and string.format('(%.2f, %.2f)', f.x, f.y) or 'none' end
  racelog.add('sprint', 'go', { race = c.race.id, player = racelog.car(pv), opponent = racelog.car(opp) })
  log('I', 'sl_races', string.format('GO %s: player faces %s, opponent faces %s, route %s', c.race.id, fwd(pv), fwd(opp), string.format('(%.2f, %.2f)', c.race.dir.x, c.race.dir.y)))
  extensions.hook('onSlrrRaceStarted', c.race.missionId, c.race.id)
  tell('GO!', 2)
end

-- racing: two positions against the goal, once a frame, and nothing else (sl/core/races.step)
-- the finish: a tall red line and its name over it, from wherever you are, for the whole race (#18)
local finishColor, finishBg, finishRing = ColorF(1, 0.25, 0.2, 1), ColorI(0, 0, 0, 170), ColorF(1, 0.25, 0.2, 0.5)
local drawcache = require('sl/core/drawcache')
local function drawFinish(c)
  local f = c.race.finish
  local m = drawcache.get('finish:' .. tostring(c.race.id) .. ':' .. f.x .. ',' .. f.y, function()          -- (built once per finish, not every frame)
    local base = vec3(f.x, f.y, f.z)
    return { base = base, ringTop = base + vec3(0, 0, 0.1), pillarTop = base + vec3(0, 0, 90), label = vec3(f.x, f.y, f.z + 93), text = String('FINISH') }
  end)
  debugDrawer:drawCylinder(m.base, m.ringTop, 7, finishRing)              -- (a ring on the road and a tall pillar: seen from the start, not a thin line)
  debugDrawer:drawCylinder(m.base, m.pillarTop, 0.6, finishColor)
  debugDrawer:drawTextAdvanced(m.label, m.text, finishColor, true, false, finishBg)
end

function M.onUpdate(dtReal)
  if cur and debugDrawer then pcall(drawFinish, cur) end        -- (from the launch: the opponent may take a while to be built)
  if not cur or not cur.ready then return end
  local t0 = os.clock()
  cur.t = cur.t + dtReal
  local pv = getObjectByID(cur.playerVid)
  if not pv or pv:getJBeamFilename() == 'unicycle' then return finish(false, true) end     -- out of the car: called off
  if state == 'countdown' then
    -- both cars face the route (B66: they sat facing the wrong way): checked once the teleport has settled, turned if not
    if not cur.faced and cur.t > 0.6 then
      cur.faced = true
      -- the ground route from where the car stands now: set at the launch it began at the old spot, the teleport not yet applied
      if core_groundMarkers then core_groundMarkers.setPath(cur.race.wps) end
      local race = cur.race
      local opp0 = cur.oppVid and getObjectByID(cur.oppVid)
      local line = races.lineUp(race.start, race.dir)
      local rot = quatFromDir(vec3(race.dir.x, race.dir.y, 0), vec3(0, 0, 1))
      for _, side in ipairs({ { pv, line.player }, { opp0, line.opponent } }) do
        local v = side[1]
        if v then
          local f = v:getDirectionVector()
          if not races.facingOk({ x = f.x, y = f.y }, race.dir) then
            log('W', 'sl_races', 'a car faced away from the route: turned')
            racelog.add('sprint', 'turned', { race = race.id, car = racelog.car(v) })
            spawn.safeTeleport(v, v3(side[2].pos) + vec3(0, 0, 0.3), rot, true, nil, false, true, false)
          end
        end
      end
    end
    local left = COUNTDOWN - cur.t
    if left <= 0 then go()
    elseif math.ceil(left) ~= cur.shown then cur.shown = math.ceil(left) tell(tostring(cur.shown), 1) end
    return
  end
  local opp = cur.oppVid and getObjectByID(cur.oppVid)
  local why = cancel.reason(cur.t, cur.limit, cur.route and #cur.route > 0 and cancel.distCached(cur, cur.t, p3(pv:getPosition()), cur.route) or nil)
  if why then return finish(false, true, why) end
  local result = races.step(cur.race.finish, p3(pv:getPosition()), opp and p3(opp:getPosition()) or nil, cur.t, cur.done)
  local ms = (os.clock() - t0) * 1000
  prof.frames, prof.ms, prof.max = prof.frames + 1, prof.ms + ms, math.max(prof.max, ms)
  if result then finish(result == 'won') end
end
-- ms per onUpdate since the last call: { frames, avg, max }
M.getProfile = function()
  local out = { frames = prof.frames, avg = prof.frames > 0 and prof.ms / prof.frames or 0, max = prof.max }
  prof.frames, prof.ms, prof.max = 0, 0, 0
  return out
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

-- (the Mods menu's Parts of the game: with this part off, the hooks above do nothing)
require('sl/core/features').gate('races', M)

return M
