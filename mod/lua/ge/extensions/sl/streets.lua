-- Street Legal Racing: racing on the street (extension name: sl_streets)
-- After dark the city's racers are out in their own cars. Drive up behind one and flash your
-- high beams: if they think you are worth it, it is a race to the other side of town, for
-- their usual stake. Some nights there is a meet in a car park; roll in and pick somebody to
-- race - for money, high stakes or pink slips. Pink slips are real: win and their car is
-- delivered to your garage, lose and you walk home.
-- The races here are point to point on the road network, run by this file; the map's own
-- night races (slrrValoRaces) stay the map's.

local M = {}

local strings = require('sl/core/strings')

local roster = require('sl/core/roster')
local rngLib = require('sl/core/rng')
local progression = require('sl/core/progression')
local carsLib = require('sl/core/cars')
local spawnplan = require('sl/core/spawnplan')
local stateLib = require('sl/core/state')
local showshine = require('sl/core/showshine')
local builder = require('sl/carBuilder')
local racesLib = require('sl/core/races')
local cancel = require('sl/core/racecancel')
local racelog = require('sl/racelog')
local builds = require('sl/core/builds')
local nightlife = require('sl/core/nightlife')

local MAX_CRUISERS = 3
local FINISH_RADIUS = 22
local MIN_ROAD = 1.5          -- half-width of a road node worth racing on (the map's lanes are 2)
local CITY_RACE = 1800        -- street races stay in town (tunnels run on to the tracks, km away)
local RACE_TIMEOUT = 600

local cruisers = {}       -- racer id -> vehicle id: racers out driving
local meet                -- { place, cars = { racer id -> vehicle id }, until (day hour), shown }
local race                -- the race running: { racer, vid, stake, bet, dest = vec3, destName, t, countdown, started }
local beam = { on = false, onAt = 0 }
local pollTimer, spawnTimer, meetTimer = 0, 0, 0
local tryTimer = 0
local busy = false        -- a job is spawning something
local circuitPath, updateCircuit   -- (further down, with the ROC)

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function night() return sl_career.isNight() end
local function playerCar()
  local v = getPlayerVehicle(0)
  if v and v:getJBeamFilename() ~= 'unicycle' then return v end
end

----------------------------------------------------------------------------------------------
-- the road network: somewhere to spawn, somewhere to race to

local function roadNodes()
  local ok, m = pcall(function() return map.getMap().nodes end)
  return ok and type(m) == 'table' and m or {}
end

-- a node at a distance from a point, wide enough to be a real road
local function nodeAround(from, minD, maxD, rng, accept)
  local best, bestName
  local tries = 0
  for name, n in pairs(roadNodes()) do
    tries = tries + 1
    local d = (n.pos - from):length()
    if d > minD and d < maxD and (n.radius or 0) >= MIN_ROAD and (not accept or accept(n)) and rng:chance(0.08) then
      best, bestName = n, name
      break
    end
    if tries > 20000 then break end
  end
  return best, bestName
end

-- the other side of town: the far end of the road network from here (within maxD, if given:
-- the ROC's island has no road to the city)
local function farSide(from, maxD)
  local best, bestName, bestD = nil, nil, 0
  for name, n in pairs(roadNodes()) do
    local d = (n.pos - from):length()
    if d > bestD and (not maxD or d < maxD) and (n.radius or 0) >= MIN_ROAD then best, bestName, bestD = n, name, d end
  end
  if not best then return nil end
  -- not quite the very edge: somewhere 85% of the way there, on the road
  local target = from + (best.pos - from) * 0.85
  local near, nearName, nearD = best, bestName, math.huge
  for name, n in pairs(roadNodes()) do
    local d = (n.pos - target):length()
    if d < nearD and (n.radius or 0) >= MIN_ROAD then near, nearName, nearD = n, name, d end
  end
  return near.pos, nearName, (near.pos - from):length()
end

local function placeNear(pos)
  local best, bestD
  for _, p in pairs(sl_career.getPlaces() or {}) do
    local d = (p.pos - pos):length()
    if not bestD or d < bestD then best, bestD = p, d end
  end
  return best and bestD < 400 and (strings.t('streets.near_1', (best.name))) or strings.t('streets.across_town')
end

----------------------------------------------------------------------------------------------
-- a racer's own car (they keep it, until somebody wins it off them)

-- Every racer drives their own custom car: a stock car of their class, built up to the stage of
-- their tier, with a nickname and a paint job - the same car every night (it is rebuilt from the
-- same recipe, so nothing big goes in the save).
local function racerCar(s, racer)
  if racer.car and racer.car.model and not racer.car.setup and racer.car.config then
    -- a car picked before the pool was clean (a limousine as an opponent, B66): picked again
    for _, c in ipairs(builder.configs()) do
      if c.config == racer.car.config and not carsLib.racerOk(c) then racer.car = nil end
    end
  end
  if racer.car and racer.car.model then
    if not racer.car.seed and not racer.car.setup then
      racer.car.seed = rngLib.hash(racer.id .. ':' .. s.seed)
      racer.car.stage = builds.stageFor(racer.tier)
    end
    return racer.car
  end
  local seed = rngLib.hash(racer.id .. ':' .. s.seed)
  local pick = carsLib.pickConfig(builder.aiPool(), racer.class, rngLib.new(seed))
  if not pick then return nil end
  local stage = builds.stageFor(racer.tier)
  racer.car = { model = pick.model, config = pick.config, value = pick.value, seed = seed, stage = stage,
    name = pick.name .. (stage > 0 and (' "' .. builds.nickname(seed) .. '"') or '') }
  return racer.car
end

-- raceBuild: the track version of their car (the ROC)
local function spawnRacer(job, s, racer, pos, rot, raceBuild)
  local car = racerCar(s, racer)
  if not car then return nil end
  local veh
  if car.setup and not raceBuild then
    veh = builder.spawn(job, car.model, car.setup, pos, rot)       -- a car they won off the player, as it was
  elseif car.config then
    veh = builder.buildCustom(job, car.model, car.config, { stage = raceBuild and 'race' or car.stage, seed = car.seed }, pos, rot)
  else
    veh = builder.spawn(job, car.model, car.setup, pos, rot)
  end
  if veh then veh:queueLuaCommand('electrics.setLightsState(1)') end
  -- SLRR's opponents behind the wheel (SLRR Drivers mod), the same one for a racer every time
  if veh and slrrDrivers and slrrDrivers.setDriver then
    slrrDrivers.setDriver(veh:getID(), rngLib.hash(racer.id) % 2 == 0 and 'slrr_opponent1' or 'slrr_opponent2')
  end
  return veh
end

local function despawn(vid)
  local v = vid and getObjectByID(vid)
  if v then v:delete() end
end

----------------------------------------------------------------------------------------------
-- the race

local function sendRace()
  if not race then guihooks.trigger('slRace', { on = false }) return end
  local v = playerCar()
  local opp = getObjectByID(race.vid)
  local mine, theirs
  if race.circuit then
    local c = race.circuit
    local function left(p, pos) return (c.laps * #c.cps + 1 - p.k) * 1000 + (pos - c.cps[(p.k % #c.cps) + 1].pos):length() end
    mine = v and left(c.me, v:getPosition()) or nil
    theirs = opp and left(c.them, opp:getPosition()) or nil
    local lap = math.min(c.laps, math.max(1, math.floor((c.me.k - 1) / #c.cps) + 1))
    guihooks.trigger('slRace', { on = true, name = race.name, stake = race.stake, bet = race.bet, destName = race.destName,
      countdown = race.countdown and math.ceil(race.countdown) or nil, lap = lap, laps = c.laps, ahead = mine and theirs and mine < theirs })
    return
  end
  mine = v and (v:getPosition() - race.dest):length() or nil
  theirs = opp and (opp:getPosition() - race.dest):length() or nil
  guihooks.trigger('slRace', { on = true, name = race.name, stake = race.stake, bet = race.bet, destName = race.destName,
    countdown = race.countdown and math.ceil(race.countdown) or nil, mine = mine and math.floor(mine) or nil,
    theirs = theirs and math.floor(theirs) or nil, ahead = mine and theirs and mine < theirs })
end

-- how hard a racer drives: their own skill, and more the bigger your name (the street gets harder)
function M.aggression(skill)
  local s = career()
  return math.min(1, 0.35 + 0.5 * (skill or 0.5) + 0.15 * progression.difficulty(s and s.rep or 0))
end

local function aiGo(vid, destNode, skill)
  local v = getObjectByID(vid)
  if not v then return end
  local aggression = M.aggression(skill)
  -- a cruiser comes out of traffic mode with the legal speed limit still set: racing, it is off
  v:queueLuaCommand(string.format("controller.setFreeze(0) input.event('parkingbrake', 0, FILTER_DIRECT) ai.setSpeedMode('off') ai.setRecoverOnCrash(true) ai.setAggression(%f) ai.setAvoidCars('on') ai.driveInLane('off') ai.driveUsingPath({wpTargetList = {%q}, aggression = %f})",
    aggression, destNode, aggression))
end

-- Both cars on the route's first edge facing along it (A7: in play neither faced the way of the route). The route is the navgraph's from where the
-- player stands to dest; a car that does not face it within 60 degrees is turned where it stands, and for a standing start the opponent is put
-- beside the player. Returns the route's points { { x, y } } and its first direction, or nil without a route.
local function lineUp(v, opp, dest, standing)
  local nodes = map.getMap().nodes
  local path = map.getPointToPointPath and map.getPointToPointPath(v:getPosition(), dest) or {}
  local dir = racesLib.routeDir(nodes, path, 25)
  local route = {}
  for _, name in ipairs(path) do if nodes[name] then route[#route + 1] = { x = nodes[name].pos.x, y = nodes[name].pos.y } end end
  if not dir then racelog.add('race', 'no route', { player = racelog.car(v), dest = dest }) return nil end
  local rot = quatFromDir(vec3(dir.x, dir.y, 0), vec3(0, 0, 1))
  local function turn(car, at)
    spawn.safeTeleport(car, at + vec3(0, 0, 0.3), rot, true, nil, false, true, false)
  end
  local f = v:getDirectionVector()
  if not racesLib.facingOk({ x = f.x, y = f.y }, dir) then turn(v, v:getPosition()) end
  if opp then
    local right = vec3(dir.y, -dir.x, 0)
    local g = opp:getDirectionVector()
    if standing then turn(opp, v:getPosition() + right * 3.6)
    elseif not racesLib.facingOk({ x = g.x, y = g.y }, dir) then turn(opp, opp:getPosition()) end
  end
  return route, dir
end

-- an event called off: nothing won or lost, the other car goes, the markers go
local function cancelRace(why)
  local r = race
  race = nil
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  if sl_markers then sl_markers.clearSoon(8) end
  sendRace()
  if not r then return end
  racelog.add('race', 'cancelled', { racer = r.racer, why = why, t = r.t or 0, player = racelog.car(playerCar()), opponent = racelog.car(getObjectByID(r.vid)) })
  if ui_message then ui_message(why, 7, 'streetLegal') end
  extensions.hook('onStreetLegalRaceCancelled')
  local vid = r.vid
  core_jobsystem.create(function(job) job.sleep(8) despawn(vid) end)
end

-- start a race against a racer whose car is out in the world (rolling: no countdown; standing: 3, 2, 1)
local function startRace(racer, vid, stake, bet, standing, maxD)
  local v = playerCar()
  if not v or race then return false end
  local dest, destNode, distance = farSide(v:getPosition(), maxD or CITY_RACE)
  if not dest then return false end
  race = { racer = racer.id, name = roster.displayName(racer), vid = vid, stake = stake, bet = bet, dest = dest, destNode = destNode,
    destName = placeNear(dest), distance = distance, t = 0, countdown = standing and 3.5 or nil, skill = racer.skill }
  race.route, race.dir = lineUp(v, getObjectByID(vid), dest, standing)
  race.limit = cancel.timeLimit(distance)
  racelog.add('race', 'setup', { racer = racer.id, name = race.name, stake = stake, bet = bet, standing = standing and 'yes' or 'no', dest = dest, destName = race.destName,
    metres = distance, dir = race.dir and string.format('(%.2f,%.2f)', race.dir.x, race.dir.y) or 'none', player = racelog.car(v), opponent = racelog.car(getObjectByID(vid)),
    model = (getObjectByID(vid) or v):getJBeamFilename() })
  if core_groundMarkers then core_groundMarkers.setPath(dest) end
  if sl_markers then sl_markers.flareRoute(v:getPosition(), dest) end        -- the way lit by flares, start to finish
  extensions.hook('onStreetLegalRaceStarted')
  if not standing then aiGo(vid, destNode, racer.skill) end
  cruisers[racer.id] = nil
  if meet then meet.cars[racer.id] = nil end
  sendRace()
  return true
end

local function finish(playerWon)
  local s = career()
  local r = race
  race = nil
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  if sl_markers then sl_markers.clearSoon(8) end
  sendRace()
  if not s or not r then return end
  local racer = stateLib.racer(s, r.racer)
  local repDelta = stateLib.recordRace(s, { racer = r.racer, won = playerWon, stake = r.stake, bet = r.bet, night = night(), at = os.time() })
  if not r.roc and sl_career.afterRace then sl_career.afterRace(r.racer, playerWon, r.margin) end   -- (rematch rule, trash talk)
  extensions.hook('onStreetLegalRaceResult', playerWon, r.name, r.racer, r.stake)
  if playerWon and r.t and r.destName then extensions.hook('onStreetLegalRaceTimed', r.destName, r.destName, r.t) end   -- (personal bests)
  local opp = getObjectByID(r.vid)
  if r.stake == 'pink' then
    if playerWon and opp then
      -- their car is yours: it goes on a truck to your garage
      opp:queueLuaCommand('ai.setMode("disabled") controller.setFreeze(1)')
      local car = sl_fleet.registerVehicle(r.vid, { name = racer.car and racer.car.name or strings.t('streets.their_car'), value = racer.car and racer.car.value or 0, condition = 0.85 })
      local mine = sl_fleet.currentCar()
      if car then
        car.out = false
        car.where = nil
        if mine then s.activeCar = mine.id end
      end
      opp:delete()
      racer.car = nil                                           -- they will turn up in something else
      if ui_message then ui_message(string.format(strings.t('streets.you_won_the_s_off'), car and car.name or 'car', r.name), 8, 'streetLegal') end
    elseif not playerWon then
      local mine = sl_fleet.currentCar()
      if mine then
        racer.car = { model = mine.model, setup = mine.config, name = mine.name, value = mine.value }    -- they drive it now
        local _, lostVeh = sl_fleet.lose(mine.id)
        local lostId = lostVeh and lostVeh:getID()
        core_jobsystem.create(function(job)
          job.sleep(1.5)
          despawn(lostId)                                       -- driven off into the night
        end)
        if ui_message then ui_message(strings.t('streets.1_takes_your_car_you', (r.name)), 8, 'streetLegal') end
      end
      if opp then opp:delete() end
    end
  else
    if ui_message then
      ui_message(playerWon and string.format(strings.t('streets.you_beat_s_d_d'), r.name, r.bet, repDelta)
        or string.format(strings.t('streets.s_won_d_d_reputation'), r.name, r.bet, repDelta), 7, 'streetLegal')
    end
    core_jobsystem.create(function(job) job.sleep(12) despawn(r.vid) end)
  end
  extensions.hook('onStreetLegalChanged')
end

local function updateRace(dt)
  local v, opp = playerCar(), getObjectByID(race.vid)
  if not opp then finish(true) return end                          -- they vanished: a walkover
  if not v then finish(false) return end                           -- you got out of the car
  if race.countdown then
    race.countdown = race.countdown - dt
    if race.countdown <= 0 then
      race.countdown = nil
      if race.circuit then
        -- round the track on its AI roads (the checkpoints alone are too far apart: a line through
        -- them cut a bend and stuck the car - seen in game); a scripted line if there are none
        local nodes, wps, last = map.getMap().nodes, {}, nil
        for _, cp in ipairs(race.circuit.cps) do
          local best, bd
          for name, n in pairs(nodes) do
            local d = (n.pos - cp.pos):length()
            if d < 15 and (not bd or d < bd) then best, bd = name, d end
          end
          if best and best ~= last then wps[#wps + 1] = best last = best end
        end
        local aggression = M.aggression(race.skill)
        local line = race.circuit.line
        if line then
          -- the map's racing line, at its own speeds: a top racer drives it flat out, a novice at 80 %
          local pace, path, t, last = 0.8 + 0.2 * (race.skill or 0.5), {}, 0, nil
          for _ = 1, race.circuit.sprint and 1 or race.circuit.laps do
            for _, q in ipairs(line) do
              if last then t = t + (q.pos - last.pos):length() / math.max(1, (q.speed + last.speed) / 2 * pace) end
              path[#path + 1] = { x = q.pos.x, y = q.pos.y, z = q.pos.z, t = t }
              last = q
            end
          end
          opp:queueLuaCommand('controller.setFreeze(0) input.event("parkingbrake", 0, FILTER_DIRECT) ai.startFollowing(' ..
            serialize({ path = path }) .. ', 0, 1, "neverReset")')
        elseif #wps >= #race.circuit.cps * 0.8 and not race.circuit.sprint then
          opp:queueLuaCommand(string.format("controller.setFreeze(0) input.event('parkingbrake', 0, FILTER_DIRECT) ai.setSpeedMode('off') ai.setRecoverOnCrash(true) ai.setAvoidCars('on') ai.driveInLane('off') ai.setAggression(%f) ai.driveUsingPath(%s)",
            aggression, serialize({ wpTargetList = wps, noOfLaps = race.circuit.laps, aggression = aggression })))
        else
          opp:queueLuaCommand('controller.setFreeze(0) input.event("parkingbrake", 0, FILTER_DIRECT) ai.startFollowing(' ..
            serialize({ path = circuitPath(race.circuit.route or race.circuit.cps, race.circuit.sprint and 1 or race.circuit.laps, race.skill or 0.5, race.circuit.sprint) }) .. ', 0, 1, "neverReset")')
        end
      else
        aiGo(race.vid, race.destNode, race.skill)
      end
      racelog.add('race', 'go', { racer = race.racer, player = racelog.car(v), opponent = racelog.car(opp) })
      if ui_message then ui_message('GO!', 2, 'streetLegal') end
    end
    return
  end
  race.t = race.t + dt
  if not race.circuit then
    local why = cancel.reason(race.t, race.limit, race.route and #race.route > 0 and cancel.distToRoute({ x = v:getPosition().x, y = v:getPosition().y }, race.route) or nil)
    if why then cancelRace(why) return end
  end
  if race.circuit then
    if not updateCircuit(v, opp) and race.t > RACE_TIMEOUT then finish(false) end
    return
  end
  if (v:getPosition() - race.dest):length() < FINISH_RADIUS then finish(true) return end
  if (opp:getPosition() - race.dest):length() < FINISH_RADIUS then finish(false) return end
  if race.t > RACE_TIMEOUT then finish(false) return end
  -- a racer who has crashed or wedged themselves (seen in game: one sat in the canal for the rest of
  -- the race) is put back on the road a little further along and sent on, as SLRR's AI was
  race.stuck = opp:getVelocity():length() < 1 and (race.stuck or 0) + dt or 0
  if race.stuck > 10 then
    race.stuck = 0
    local pos = opp:getPosition()
    local path = map.getPointToPointPath and map.getPointToPointPath(pos, race.dest) or {}
    local nodes = map.getMap().nodes
    for i = 1, #path - 1 do
      local n, nxt = nodes[path[i]], nodes[path[i + 1]]
      if n and nxt and (n.pos - pos):length() > 25 then
        spawn.safeTeleport(opp, n.pos + vec3(0, 0, 0.3), quatFromDir((nxt.pos - n.pos):normalized(), vec3(0, 0, 1)), true)
        aiGo(race.vid, race.destNode, race.skill)
        break
      end
    end
  end
end

----------------------------------------------------------------------------------------------
-- racers cruising at night; flash your high beams at one to race

local function cruiserCandidates(s)
  local list = {}
  for _, r in ipairs(s.racers) do
    if not cruisers[r.id] and not (meet and meet.cars[r.id]) and (not race or race.racer ~= r.id) then list[#list + 1] = r end
  end
  return list
end

local function spawnCruiser(s)
  local v = getPlayerVehicle(0)
  if not v or busy then return end
  local list = cruiserCandidates(s)
  if #list == 0 then return end
  local rng = rngLib.new(rngLib.hash(tostring(os.clock())))
  local mine = 1
  for t, def in ipairs(roster.TIERS) do if (s.rep or 0) >= def.rep[1] then mine = t end end
  local near = {}
  for _, r in ipairs(list) do if math.abs(r.tier - mine) <= 1 then near[#near + 1] = r end end
  if #near > 0 and rng:chance(0.8) then list = near end
  local racer = list[rng:int(#list)]
  -- out of his sight and off his way (#19): not in the camera's view, not ahead of where he is going
  local pp, pv = v:getPosition(), v:getVelocity()
  local player = { x = pp.x, y = pp.y, vx = pv.x, vy = pv.y }
  local cam
  local okc, cp = pcall(core_camera.getPosition)
  local okf, cf = pcall(core_camera.getForward)
  if okc and cp and okf and cf then cam = { x = cp.x, y = cp.y, fx = cf.x, fy = cf.y } end
  local function hidden(n) return spawnplan.hidden({ x = n.pos.x, y = n.pos.y }, player, cam) end
  -- the main strips first (the wider roads), any road if none is in reach
  local node = nodeAround(pp, 180, 450, rng, function(n) return nightlife.mainStrip(n.radius) and hidden(n) end) or nodeAround(pp, 180, 450, rng, hidden)
  if not node then return false end
  busy = true
  core_jobsystem.create(function(job)
    local veh = spawnRacer(job, s, racer, node.pos + vec3(0, 0, 0.5), nil)
    busy = false
    if not veh then return end
    veh:queueLuaCommand('ai.setMode("traffic") ai.setAggression(0.5)')
    cruisers[racer.id] = veh:getID()
  end)
  return true
end

local function updateCruisers(s, dt)
  local v = getPlayerVehicle(0)
  local count = 0
  for id, vid in pairs(cruisers) do
    local c = getObjectByID(vid)
    if not c or not v or (c:getPosition() - v:getPosition()):length() > 700 or not night() then
      despawn(vid)
      cruisers[id] = nil
    else
      count = count + 1
    end
  end
  spawnTimer = spawnTimer + dt
  -- one build at a time, a gap between, and not while he races along (spawnplan.canBuild); the timer restarts only when a car is really begun
  local speed = v and v:getVelocity():length() or 0
  tryTimer = tryTimer + dt
  if tryTimer >= 1 and night() and count < MAX_CRUISERS and not race and spawnplan.canBuild(speed, spawnTimer, busy) then
    tryTimer = 0                                 -- (looking for a hidden road costs a pass over the graph: once a second at most)
    if spawnCruiser(s) then spawnTimer = 0 end
  end
end

-- whose name hangs over their car (so you know who you are flashing)
local labelColor, labelBg = ColorF(1, 0.8, 0.3, 1), ColorI(0, 0, 0, 170)
local function drawLabels(s)
  local v = getPlayerVehicle(0)
  if not v then return end
  local function label(racerId, vid, extra)
    local c = getObjectByID(vid)
    local r = stateLib.racer(s, racerId)
    if c and r and (c:getPosition() - v:getPosition()):length() < 60 then
      debugDrawer:drawTextAdvanced(c:getPosition() + vec3(0, 0, 2.2), String(roster.displayName(r) .. (extra or '')), labelColor, true, false, labelBg)
    end
  end
  for id, vid in pairs(cruisers) do label(id, vid, '  (flash to race)') end
  if meet then for id, vid in pairs(meet.cars) do label(id, vid) end end
end

-- the racer in front of the player, close enough to have seen the lights
local function racerAhead()
  local v = playerCar()
  if not v then return nil end
  local pos, dir = v:getPosition(), v:getDirectionVector()
  for id, vid in pairs(cruisers) do
    local c = getObjectByID(vid)
    if c then
      local rel = c:getPosition() - pos
      local d = rel:length()
      if d < 45 and d > 2 and rel:normalized():dot(dir) > 0.75 then return id, vid end
    end
  end
end

local function challenge(id, vid)
  local s = career()
  if not s or race or not id then return end
  local racer = stateLib.racer(s, id)
  if not night() then return end
  local answer = roster.respond(racer, 'race', { rep = s.rep, money = s.money, hasCar = sl_fleet.currentCar() ~= nil }, rngLib.new(rngLib.hash(id .. s.day)))
  if not answer.accept then
    if ui_message then ui_message(roster.displayName(racer) .. ': "' .. answer.text .. '"', 6, 'streetLegal') end
    return
  end
  s.known[id] = true                            -- after a race you have their number
  if startRace(racer, vid, 'money', answer.bet, false) and ui_message then
    ui_message(string.format(strings.t('streets.s_takes_you_on_d'), roster.displayName(racer), answer.bet, race.destName), 6, 'streetLegal')
  end
end

local function onFlash()
  local id, vid = racerAhead()
  if id then challenge(id, vid) end
end

-- stopped alongside a racer for a moment: the same challenge (#17); a racer who said no is not asked again for a minute
local stoppedFor, askedAt = 0, {}
local function checkBeside(dt)
  local v = playerCar()
  if not v or race then stoppedFor = 0 return end
  local speed = v:getVelocity():length()
  stoppedFor = speed <= nightlife.BESIDE_SPEED and stoppedFor + dt or 0
  if stoppedFor < nightlife.BESIDE_TIME then return end
  local pos, dir = v:getPosition(), v:getDirectionVector()
  for id, vid in pairs(cruisers) do
    local c = getObjectByID(vid)
    if c and os.clock() - (askedAt[id] or -999) > 60 then
      local rel = c:getPosition() - pos
      if nightlife.besideStopped({ x = rel.x, y = rel.y }, { x = dir.x, y = dir.y }, speed, stoppedFor) then
        askedAt[id] = os.clock()
        challenge(id, vid)
        return
      end
    end
  end
end

-- the player's high beams, read from the car a few times a second
function M.onBeam(value)
  local on = (tonumber(value) or 0) > 0.5
  local now = os.clock()
  if on and not beam.on then beam.onAt = now end
  if not on and beam.on and now - beam.onAt < 1.5 then onFlash() end
  beam.on = on
end

local function pollBeams(dt)
  pollTimer = pollTimer + dt
  if pollTimer < 0.12 then return end
  pollTimer = 0
  local v = playerCar()
  if v then v:queueLuaCommand('obj:queueGameEngineLua("if sl_streets then sl_streets.onBeam(" .. tostring((electrics.values.highbeam or 0)) .. ") end")') end
end

----------------------------------------------------------------------------------------------
-- meets: a few racers in a car park after dark

-- is this spot out of the player's sight and off his way, and far enough (the #19 rule for the meets: nobody sees a car pop in)
local MEET_MIN_DIST = 130
local function meetHidden(pos)
  local v = getPlayerVehicle(0)
  if not v then return true end
  local pp, pv = v:getPosition(), v:getVelocity()
  if (pp - pos):length() < MEET_MIN_DIST then return false end
  local cam
  local okc, cp = pcall(core_camera.getPosition)
  local okf, cf = pcall(core_camera.getForward)
  if okc and cp and okf and cf then cam = { x = cp.x, y = cp.y, fx = cf.x, fy = cf.y } end
  return spawnplan.hidden({ x = pos.x, y = pos.y }, { x = pp.x, y = pp.y, vx = pv.x, vy = pv.y }, cam)
end

local function startMeet(s)
  local list = {}
  for _, p in pairs(sl_career.getPlaces() or {}) do if p.kind == 'meet' then list[#list + 1] = p end end
  if #list == 0 or busy then return end
  local rng = rngLib.new(rngLib.hash('meet' .. s.day .. math.floor(sl_career.hour())))
  local place = list[rng:int(#list)]
  if not meetHidden(place.pos) then return false end         -- tried again at the next chance
  local racers = {}
  for _, r in ipairs(s.racers) do
    if math.abs(r.rep - s.rep) < 1500 + s.rep * 0.5 and not cruisers[r.id] then racers[#racers + 1] = r end
  end
  if #racers == 0 then return end
  local theme = nightlife.theme(place.id, s.day)
  meet = { place = place, cars = {}, day = s.day, theme = theme, owners = {} }
  busy = true
  local count = math.min(#racers, rng:int(3, 6))
  core_jobsystem.create(function(job)
    for i = 1, count do
      if not meetHidden(place.pos) then break end                -- he is coming: no more cars appear in front of him
      local r = table.remove(racers, rng:int(#racers))
      local a = (i / count) * math.pi * 2
      local pos = place.pos + vec3(math.cos(a) * 9, math.sin(a) * 9, 0.5)
      local rot = quatFromDir((place.pos - pos):normalized(), vec3(0, 0, 1))
      local veh = spawnRacer(job, s, r, pos, rot)
      if veh and meet then
        veh:queueLuaCommand('controller.setFreeze(1) input.event("parkingbrake", 1, FILTER_DIRECT) electrics.set_warn_signal(1)')
        meet.cars[r.id] = veh:getID()
      end
    end
    -- tonight's theme: parked cars of it, each with its owner standing by (#43)
    local walkers = {}
    if slrrDrivers and slrrDrivers.getDrivers then
      for _, d in ipairs(slrrDrivers.getDrivers() or {}) do
        local did = type(d) == 'table' and d.id or d
        if type(did) == 'string' and FS:directoryExists('/art/slrr_drivers/' .. did .. '/walker/') then walkers[#walkers + 1] = did end
      end
    end
    local cars = nightlife.pickCars(theme.id, builder.aiPool(), rng:int(3, 5), rng)
    for i, c in ipairs(cars) do
      if not meet or not meetHidden(place.pos) then break end
      local a = ((i - 0.5) / #cars) * math.pi * 2 + math.pi / #cars
      local pos = place.pos + vec3(math.cos(a) * 14, math.sin(a) * 14, 0.5)
      local rot = quatFromDir((place.pos - pos):normalized(), vec3(0, 0, 1))
      local veh = builder.buildCustom(job, c.model, c.config, { stage = rng:int(0, 2), seed = rngLib.hash(place.id .. ':' .. s.day .. ':' .. i) }, pos, rot)
      if veh and meet then
        veh:queueLuaCommand('controller.setFreeze(1) input.event("parkingbrake", 1, FILTER_DIRECT)')
        local owner = { name = nightlife.ownerName(rng), vid = veh:getID(), car = c.name or c.model, value = c.value or 0, pos = pos }
        owner.offer = nightlife.offer(theme, rng, { rep = s.rep, value = c.value })
        if #walkers > 0 and slrrPedestrians and slrrPedestrians.playActor then
          local toSpot = (place.pos - pos):normalized()
          local beside = pos + toSpot:cross(vec3(0, 0, 1)):normalized() * 2.2
          owner.actor = slrrPedestrians.playActor('/art/slrr_drivers/' .. walkers[rng:int(#walkers)] .. '/walker/', { vec3(beside.x, beside.y, place.pos.z) })
        end
        meet.owners['o' .. i] = owner
      end
    end
    busy = false
  end)
  local who = racers[1] or s.racers[1]
  sl_career.sendText(s.known[who.id] and who.id or 'benny', strings.t('streets.1_at_2_3_bring', (theme.name), (place.name), (theme.blurb)), 2)
  return true
end

local function endMeet()
  if not meet then return end
  for _, vid in pairs(meet.cars) do despawn(vid) end
  for _, o in pairs(meet.owners or {}) do
    despawn(o.vid)
    if o.actor and slrrPedestrians and slrrPedestrians.stopActor then slrrPedestrians.stopActor(o.actor) end
  end
  meet = nil
  guihooks.trigger('slMeet', { open = false })
end

local function sendMeet(open)
  local s = career()
  if not meet or not s or not open then guihooks.trigger('slMeet', { open = false }) return end
  local list = {}
  for id in pairs(meet.cars) do
    local r = stateLib.racer(s, id)
    if r then
      list[#list + 1] = { id = id, name = roster.displayName(r), car = r.car and r.car.name or '?', tier = r.tier,
        betMin = r.betMin, betMax = r.betMax, pinkTonight = roster.pinkTonight(r, s.day, s.seed) }
    end
  end
  table.sort(list, function(a, b) return a.tier < b.tier end)
  local owners = {}
  for key, o in pairs(meet.owners or {}) do owners[#owners + 1] = { id = key, name = o.name, car = o.car, kind = o.offer and o.offer.kind, talked = o.talked } end
  table.sort(owners, function(a, b) return a.id < b.id end)
  guihooks.trigger('slMeet', { open = true, name = meet.place.name, theme = meet.theme and meet.theme.name, owners = owners, racers = list, money = s.money, canShow = not meet.judged and sl_fleet.currentCar() ~= nil, showFee = showshine.FEE })
end

local function updateMeet(s, dt)
  local v = getPlayerVehicle(0)
  if not meet then
    meetTimer = meetTimer + dt
    if night() and meetTimer > 90 and not race then
      meetTimer = 0
      if rngLib.new(rngLib.hash('m' .. os.clock())):chance(0.35) then startMeet(s) end
    end
    return
  end
  if not night() or s.day ~= meet.day and sl_career.hour() > 6 then endMeet() return end
  local car = playerCar()
  local here = car and (car:getPosition() - meet.place.pos):length() < 22 and car:getVelocity():length() < 1
  -- stopped next to an owner's car: the driver waves out of the window, once in a while (#38)
  if car and car:getVelocity():length() < 1 and slrrDrivers and slrrDrivers.wave and os.clock() - (meet.wavedAt or -999) > 45 then
    local cp = car:getPosition()
    for _, o in pairs(meet.owners or {}) do
      local oc = o.vid and getObjectByID(o.vid)
      if oc and (oc:getPosition() - cp):length() < 7 then
        meet.wavedAt = os.clock()
        slrrDrivers.wave(car:getID(), 3)
        break
      end
    end
  end
  if here and not meet.shown then
    meet.shown = true
    sendMeet(true)
  elseif not here and meet.shown then
    meet.shown = false
    sendMeet(false)
  end
  -- a marker over the meet so it can be found (the map's own markers do it where they are)
  if not slrrValoPois and v and (v:getPosition() - meet.place.pos):length() < 400 then
    debugDrawer:drawCylinder(meet.place.pos, meet.place.pos + vec3(0, 0, 4), 0.25, ColorF(0.7, 0.2, 1, 0.5))
    debugDrawer:drawTextAdvanced(meet.place.pos + vec3(0, 0, 4.5), String(strings.t('streets.car_meet')), ColorF(1, 1, 1, 1), true, false, ColorI(60, 0, 90, 200))
  end
end

-- from the meet's menu: race this racer for money, high stakes or pink slips
function M.meetChallenge(racerId, kind)
  local s = career()
  if not s or not meet or race then return end
  local vid = meet.cars[racerId]
  local racer = stateLib.racer(s, racerId)
  if not vid or not racer then return end
  local answer = roster.respond(racer, kind, { rep = s.rep, money = s.money, hasCar = sl_fleet.currentCar() ~= nil, pinkTonight = roster.pinkTonight(racer, s.day, s.seed) }, rngLib.new(rngLib.hash(racerId .. kind .. os.time())))
  guihooks.trigger('slPhoneToast', { text = roster.displayName(racer) .. ': "' .. answer.text .. '"' })
  if not answer.accept then return end
  s.known[racerId] = true
  sendMeet(false)
  meet.shown = true
  -- they pull up beside you for a standing start
  local v = playerCar()
  local opp = getObjectByID(vid)
  if v and opp then
    local right = v:getDirectionVector():cross(vec3(0, 0, 1)):normalized()
    spawn.safeTeleport(opp, v:getPosition() + right * 3.6 + vec3(0, 0, 0.3), quatFromDir(v:getDirectionVector(), vec3(0, 0, 1)), true)
  end
  startRace(racer, vid, answer.stake, answer.bet or 0, true)
end

-- talk to the owner of a parked car (#43): a tip, a car for sale, or word of a race
function M.meetTalk(key)
  local s = career()
  local o = s and meet and meet.owners and meet.owners[key]
  if not o or not o.offer then return end
  local offer = o.offer
  o.talked = true
  if offer.kind == 'tip' then
    guihooks.trigger('slPhoneToast', { text = o.name .. ': "' .. offer.text .. '"' })
    if not o.tipped then o.tipped = true stateLib.addRep(s, 2) end
  elseif offer.kind == 'sale' then
    local entry
    for _, c in ipairs(builder.aiPool()) do if c.name == o.car or c.model == o.car then entry = c break end end
    local made = entry and require('sl/core/market').offers({ entry }, 'used', rngLib.hash(key .. s.day .. s.seed), s.day, 1, true)[1]
    if made then
      made.price = offer.price
      guihooks.trigger('slPhoneToast', { text = o.name .. ': "' .. offer.text .. '"' })
      sendMeet(false)
      if sl_lot and sl_lot.openPrivate then sl_lot.openPrivate(made, o.pos, o.name) end
    else
      guihooks.trigger('slPhoneToast', { text = strings.t('streets.1_not_today_after_all', (o.name)) })
    end
  else
    guihooks.trigger('slPhoneToast', { text = o.name .. ': "' .. offer.text .. '"' })
  end
  extensions.hook('onStreetLegalChanged')
end

-- where the meet is, while one is on (the ambience puts its music there)
function M.meetPos() return meet and meet.place and meet.place.pos or nil end

function M.closeMeet() sendMeet(false) end

-- show and shine: the judges walk round your car and the racers' cars here tonight (once a meet)
function M.showAndShine()
  local s = career()
  if not s or not meet or meet.judged or race then return end
  local car = sl_fleet.currentCar()
  if not car then return guihooks.trigger('slPhoneToast', { text = strings.t('clubs.bring_one_of_your_cars') }) end
  if not sl_career.addMoney(-showshine.FEE, strings.t('streets.show_and_shine_entry')) then return guihooks.trigger('slPhoneToast', { text = strings.t('streets.not_enough_for_the_entry') }) end
  meet.judged = true
  local rng = rngLib.new(rngLib.hash('shine:' .. s.day .. ':' .. meet.place.id))
  local rivals = {}
  for id in pairs(meet.cars) do
    local r = stateLib.racer(s, id)
    if r then rivals[#rivals + 1] = showshine.rival(r.tier, rng) end
  end
  local mine = showshine.score({ value = car.value, condition = car.condition, dents = car.damage and car.damage.beams and #car.damage.beams or 0,
    washed = sl_station and sl_station.washedToday and sl_station.washedToday(car.id) })
  local place, prize, rep = showshine.result(mine, rivals)
  if prize > 0 then sl_career.payOut(prize, strings.t('streets.show_and_shine_1_2', (place), (place == 1 and 'st' or place == 2 and 'nd' or 'rd'))) end
  if rep > 0 then stateLib.addRep(s, rep) end
  local ord = ({ 'first', 'second', 'third' })[place] or (place .. 'th')
  guihooks.trigger('slPhoneToast', { text = string.format(strings.t('streets.show_and_shine_the_s'), car.name, ord, #rivals + 1,
    prize > 0 and string.format(strings.t('streets.d_d_reputation'), prize, rep) or strings.t('streets.clean_it_up_and_try')) })
  sendMeet(true)
  extensions.hook('onStreetLegalChanged')
end

----------------------------------------------------------------------------------------------
-- circuits: the ROC track's checkpoints (races.json, key "roc"), laps instead of a finish point

local ROC_LAPS = 2

-- a racing line the map brings: /levels/<level>/racelines/<name>.json { points = {{x, y, z, speed m/s}...} }
local function racingLine(...)
  for _, name in ipairs({ ... }) do
    local rl = jsonReadFile('/levels/' .. sl_career.LEVEL .. '/racelines/' .. name .. '.json')
    if type(rl) == 'table' and type(rl.points) == 'table' then
      local line = {}
      for _, q in ipairs(rl.points) do
        if tonumber(q[1]) and tonumber(q[4]) then line[#line + 1] = { pos = vec3(q[1], q[2], q[3] or 0), speed = math.max(3, tonumber(q[4])) } end
      end
      if #line >= 4 then return line end
    end
  end
end

local function rocTrack()
  local data = jsonReadFile('/levels/' .. sl_career.LEVEL .. '/races.json')
  local roc = type(data) == 'table' and data.roc
  if type(roc) ~= 'table' or type(roc.checkpoints) ~= 'table' or #roc.checkpoints < 3 then return nil end
  local cps = {}
  for i, c in ipairs(roc.checkpoints) do
    local p, d = c.pos or {}, c.dir or { 1, 0 }
    local dir = vec3(tonumber(d[1]) or 1, tonumber(d[2]) or 0, 0)
    cps[i] = { pos = vec3(tonumber(p[1]) or 0, tonumber(p[2]) or 0, tonumber(p[3]) or 0), dir = dir:length() > 0.01 and dir:normalized() or vec3(1, 0, 0),
      half = tonumber(c.halfWidth) or 6 }
  end
  return { name = roc.name or 'ROC', cps = cps, line = racingLine('roc') }
end

-- The opponent's line round the circuit, with a time for every point: as fast as the bends
-- allow (sideways grip), with the accelerating and braking a car can do. skill sets the limits.
circuitPath = function(cps, laps, skill, sprint)
  local pts = {}
  for _ = 1, laps do for _, c in ipairs(cps) do pts[#pts + 1] = c.pos end end
  if not sprint then pts[#pts + 1] = cps[1].pos end
  local n = #pts
  local vmax, grip, accel, brake = 32 + 38 * skill, 7 + 4 * skill, 4 + 4 * skill, 7 + 2 * skill
  local v = {}
  for i = 1, n do
    local a, b, c = pts[math.max(1, i - 1)], pts[i], pts[math.min(n, i + 1)]
    local ab, bc, ca = (b - a):length(), (c - b):length(), (a - c):length()
    local twice = (b - a):cross(c - a):length()
    local r = twice > 1e-4 and (ab * bc * ca) / (2 * twice) or 1e9
    v[i] = math.max(8, math.min(vmax, math.sqrt(grip * r)))
  end
  v[1] = 0
  for i = 2, n do v[i] = math.min(v[i], math.sqrt(v[i - 1] ^ 2 + 2 * accel * (pts[i] - pts[i - 1]):length())) end
  for i = n - 1, 2, -1 do v[i] = math.min(v[i], math.sqrt(v[i + 1] ^ 2 + 2 * brake * (pts[i + 1] - pts[i]):length())) end
  local path, t = {}, 0
  for i = 1, n do
    if i > 1 then t = t + (pts[i] - pts[i - 1]):length() / math.max(0.5, (v[i - 1] + v[i]) / 2) end
    path[i] = { x = pts[i].x, y = pts[i].y, z = pts[i].z, t = t }
  end
  return path
end

-- checkpoints passed in order: crossing the start line counts as the first
local function circuitStep(progress, pos, cps)
  local c = cps[(progress.k % #cps) + 1]
  if (pos - c.pos):length() < math.max(c.half, 8) + 4 then progress.k = progress.k + 1 end
end

local function startCircuit(racer, vid, stake, bet, track)
  local v = playerCar()
  if not v or race then return false end
  local laps = track.laps or ROC_LAPS
  race = { racer = racer.id, name = roster.displayName(racer), vid = vid, stake = stake, bet = bet,
    destName = track.name .. (track.sprint and strings.t('streets.to_the_finish') or strings.t('streets.1_laps', (laps))),
    t = 0, countdown = 3.5, skill = racer.skill,
    circuit = { cps = track.cps, laps = laps, sprint = track.sprint, route = track.route, line = track.line, lapEndsAtLast = track.lapEndsAtLast, me = { k = 0 }, them = { k = 0 } } }
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  if sl_markers then sl_markers.flareCircuit(track.cps) end
  cruisers[racer.id] = nil
  sendRace()
  return true
end

updateCircuit = function(v, opp)
  local c = race.circuit
  -- a stage ends at its last checkpoint; a lap at the start line (the ROC's first checkpoint, a venue's last)
  local total = c.sprint and #c.cps or c.laps * #c.cps + (c.lapEndsAtLast and 0 or 1)
  circuitStep(c.me, v:getPosition(), c.cps)
  circuitStep(c.them, opp:getPosition(), c.cps)
  if c.me.k >= total then finish(true) return true end
  if c.them.k >= total then finish(false) return true end
  return false
end

----------------------------------------------------------------------------------------------
-- the race tracks the map brings (SLRR's multibot venues: /levels/<level>/multibot_tracks.json,
-- { <id> = { label, type, start, heading, checkpoints = {{x,y,z}...}, route = {{x,y,z}...} } }):
-- their checkpoints leave out the start line: a circuit's last one is back at the start (a lap
-- ends there), a rally stage's is the finish, far from it

function M.tracks()
  if not sl_career.has('tracks') then return {} end
  local data = jsonReadFile('/levels/' .. sl_career.LEVEL .. '/multibot_tracks.json')
  local out = {}
  local function v3(t) return type(t) == 'table' and tonumber(t[1]) and vec3(tonumber(t[1]), tonumber(t[2]) or 0, tonumber(t[3]) or 0) or nil end
  for id, t in pairs(type(data) == 'table' and data or {}) do
    local cps = {}
    for _, c in ipairs(type(t) == 'table' and t.checkpoints or {}) do
      local p = v3(c)
      if p then cps[#cps + 1] = { pos = p, half = 8 } end
    end
    if #cps >= 3 then
      for i, c in ipairs(cps) do
        local d = cps[i % #cps + 1].pos - c.pos
        d.z = 0
        c.dir = d:length() > 0.01 and d:normalized() or vec3(1, 0, 0)
      end
      local route = {}
      for _, r in ipairs(t.route or {}) do local p = v3(r) if p then route[#route + 1] = { pos = p } end end
      local start = v3(t.start) or cps[#cps].pos
      local line = racingLine('slrr_mb_' .. id:lower(), 'slrr_mb_' .. id)       -- the venue's racing line, if the map has one
      out[#out + 1] = { id = id, name = t.label or id, kind = t.type, cps = cps, start = start, lapEndsAtLast = true, line = line,
        route = #route >= 4 and route or nil, sprint = (cps[#cps].pos - start):length() > 80, laps = 2 }
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- a race at one of them against a racer, for their usual stake: you are taken to the grid
function M.trackRace(racerId, trackId)
  local s = career()
  if not s or race or busy then return false, strings.t('career.not_now') end
  local racer = stateLib.racer(s, racerId)
  local track
  for _, t in ipairs(M.tracks()) do if t.id == trackId then track = t end end
  if not racer or not track then return false, strings.t('career.that_race_is_not_on') end
  local v = playerCar()
  if not v or not sl_fleet.currentCar() then return false, strings.t('streets.bring_your_own_car') end
  local bet = math.floor(((racer.betMin or 100) + (racer.betMax or 300)) / 2 / 50) * 50
  if bet > s.money then return false, string.format(strings.t('streets.d_on_it_and_you'), bet, s.money) end   -- (recordRace only takes what you have: a free roll otherwise)
  busy = true
  core_jobsystem.create(function(job)
    guihooks.trigger('slFade', { on = true })
    job.sleep(0.6)
    -- on the grid, side by side behind the start, facing along the track
    local first = track.start or track.cps[1].pos
    local ahead = track.route and track.route[2] and track.route[2].pos or track.cps[1].pos
    local along = ahead - first
    along.z = 0
    if along:length() < 1 then along = track.cps[2].pos - track.cps[1].pos along.z = 0 end
    along = along:normalized()
    local right = along:cross(vec3(0, 0, 1)):normalized()
    local rot = quatFromDir(along, vec3(0, 0, 1))
    local start = first - along * 6 - right * 2.2
    spawn.safeTeleport(v, start + vec3(0, 0, 0.5), rot, true, nil, nil, nil, false)     -- (your car as it is, dents and all)
    job.sleep(0.5)
    local veh = spawnRacer(job, s, racer, start + right * 4.4 + vec3(0, 0, 0.5), rot, true)
    busy = false
    guihooks.trigger('slFade', { on = false })
    if not veh then return end
    veh:queueLuaCommand('controller.setFreeze(1)')
    if startCircuit(racer, veh:getID(), 'money', bet, track) and ui_message then
      ui_message(string.format('%s: %s. $%d.', track.name, roster.displayName(racer), bet), 6, 'streetLegal')
    end
  end)
  return true, 'To ' .. track.name .. '.'
end

----------------------------------------------------------------------------------------------
-- the ROC (Race of Champions): three rounds against the best in town, on their island

function M.rocRound(s)
  s.roc = s.roc or { round = 0 }
  return s.roc
end

-- the champions, best first
local function champions(s)
  local list = {}
  for _, r in ipairs(s.racers) do if r.tier == 5 then list[#list + 1] = r end end
  table.sort(list, function(a, b) return a.rep > b.rep end)
  return list
end

function M.enterRoc()
  local s = career()
  if not s or race or busy then return false, strings.t('career.not_now') end
  if not sl_career.has('roc') then return false, strings.t('streets.not_here') end
  if not progression.rocOpen(s) then return false, strings.t('streets.the_roc_is_for_the') end
  local roc = M.rocRound(s)
  if roc.champion then return false, strings.t('streets.you_are_the_champion_nobody') end
  local v = playerCar()
  if not v or not sl_fleet.currentCar() then return false, strings.t('streets.bring_your_own_car_to') end
  if roc.round == 0 and not sl_career.addMoney(-progression.ROC.entry, strings.t('activities.roc_entry')) then return false, string.format(strings.t('streets.entry_is_d'), progression.ROC.entry) end
  local rival = champions(s)[3 - roc.round] or champions(s)[1]
  if not rival then return false, strings.t('clubs.nobody_to_race') end
  local spot = scenetree.findObject('spawn_roc')
  local track = rocTrack()
  local start = spot and spot:getPosition() or v:getPosition()
  busy = true
  core_jobsystem.create(function(job)
    guihooks.trigger('slFade', { on = true })
    job.sleep(0.6)
    local rot, right
    if track then
      -- on the grid, side by side, behind the start line
      -- along the road from the first checkpoint to the second (a checkpoint's own "dir" put the
      -- second grid spot on the shoulder - seen in game)
      local c1, c2 = track.cps[1], track.cps[2]
      local along = c2.pos - c1.pos
      along.z = 0
      along = along:length() > 1 and along:normalized() or c1.dir
      right = along:cross(vec3(0, 0, 1)):normalized()
      start = c1.pos - along * 10 - right * 2.2
      rot = quatFromDir(along, vec3(0, 0, 1))
    elseif spot then
      pcall(function() rot = quat(0, 0, 1, 0) * quat(spot:getRotation()) end)      -- a spawn point's own rotation is half a turn from facing
    end
    spawn.safeTeleport(v, start + vec3(0, 0, 0.5), rot, true, nil, nil, nil, false)     -- (your car as it is, dents and all)
    job.sleep(0.5)
    right = right or v:getDirectionVector():cross(vec3(0, 0, 1)):normalized()
    local veh = spawnRacer(job, s, rival, start + right * 4.4 + vec3(0, 0, 0.5), rot or quatFromDir(v:getDirectionVector(), vec3(0, 0, 1)), true)
    busy = false
    guihooks.trigger('slFade', { on = false })
    if not veh then return end
    veh:queueLuaCommand('controller.setFreeze(1)')
    local bet = 10000 * (roc.round + 1)
    local started
    if track then started = startCircuit(rival, veh:getID(), 'money', bet, track)
    else started = startRace(rival, veh:getID(), 'money', bet, true, 1500) end
    if started then
      race.roc = true
      if ui_message then ui_message(string.format(strings.t('streets.roc_round_d_of_3'), roc.round + 1, roster.displayName(rival), bet), 6, 'streetLegal') end
    end
  end)
  return true, strings.t('streets.to_the_roc')
end

local baseFinish = finish
finish = function(playerWon)
  local s, wasRoc = career(), race and race.roc
  baseFinish(playerWon)
  if not wasRoc or not s then return end
  local roc = M.rocRound(s)
  if playerWon then
    roc.round = roc.round + 1
    if roc.round >= 3 then
      roc.champion = true
      sl_career.payOut(250000, strings.t('streets.roc_champion'))
      stateLib.addRep(s, 2000)
      sl_career.sendText('benny', sl_career.mapText(strings.t('streets.you_won_the_roc_champion')), 3)
    else
      sl_career.sendText('benny', string.format(strings.t('streets.round_d_of_the_roc'), roc.round), 3)
    end
  else
    roc.round = 0
    sl_career.sendText('benny', strings.t('streets.out_of_the_roc_the'), 3)
  end
  extensions.hook('onStreetLegalChanged')
end

----------------------------------------------------------------------------------------------
-- hooks

function M.onUpdate(dtReal)
  local s = career()
  if not s then
    if race or meet or next(cruisers) then
      for _, vid in pairs(cruisers) do despawn(vid) end
      cruisers = {}
      endMeet()
      race = nil
    end
    return
  end
  if race then
    updateRace(dtReal)
    if race then
      M._raceSend = (M._raceSend or 0) + dtReal
      if M._raceSend > 0.5 then M._raceSend = 0 sendRace() end
    end
  end
  pollBeams(dtReal)
  checkBeside(dtReal)
  updateCruisers(s, dtReal)
  updateMeet(s, dtReal)
  drawLabels(s)
end

function M.onStreetLegalStopped()
  for _, vid in pairs(cruisers) do despawn(vid) end
  cruisers = {}
  endMeet()
  race = nil
  sendRace()
end

function M.onClientEndMission() cruisers, meet, race = {}, nil, nil end

-- a racer's own car, built and parked (frozen) for a race somebody else runs: the career hands it to
-- the map's race for an arranged race. done(veh or nil) is called when it is ready.
function M.buildRacerCar(racerId, pos, rot, done)
  local s = career()
  local racer = s and stateLib.racer(s, racerId)
  if not racer then return false end
  core_jobsystem.create(function(job)
    local veh = spawnRacer(job, s, racer, pos, rot)
    if veh then veh:queueLuaCommand('controller.setFreeze(1) input.event("parkingbrake", 1, FILTER_DIRECT)') end
    done(veh)
  end)
  return true
end

function M.forfeit() if race then finish(false) end end
function M.isRacing() return race ~= nil end

return M
