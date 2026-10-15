-- Street Legal Racing: racing on the street (extension name: sl_streets)
-- After dark the city's racers are out in their own cars. Drive up behind one and flash your
-- high beams: if they think you are worth it, it is a race to the other side of town, for
-- their usual stake. Some nights there is a meet in a car park; roll in and pick somebody to
-- race - for money, high stakes or pink slips. Pink slips are real: win and their car is
-- delivered to your garage, lose and you walk home.
-- The races here are point to point on the road network, run by this file; the map's own
-- night races (slrrValoRaces) stay the map's.

local M = {}

local roster = require('sl/core/roster')
local rngLib = require('sl/core/rng')
local progression = require('sl/core/progression')
local carsLib = require('sl/core/cars')
local stateLib = require('sl/core/state')
local builder = require('sl/carBuilder')
local builds = require('sl/core/builds')

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
local busy = false        -- a job is spawning something
local circuitPath, updateCircuit   -- (further down, with the ROC)

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function night() return progression.isNight(sl_career.hour()) end
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
local function nodeAround(from, minD, maxD, rng)
  local best, bestName
  local tries = 0
  for name, n in pairs(roadNodes()) do
    tries = tries + 1
    local d = (n.pos - from):length()
    if d > minD and d < maxD and (n.radius or 0) >= MIN_ROAD and rng:chance(0.08) then
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
  return best and bestD < 400 and ('near ' .. best.name) or 'across town'
end

----------------------------------------------------------------------------------------------
-- a racer's own car (they keep it, until somebody wins it off them)

-- Every racer drives their own custom car: a stock car of their class, built up to the stage of
-- their tier, with a nickname and a paint job - the same car every night (it is rebuilt from the
-- same recipe, so nothing big goes in the save).
local function racerCar(s, racer)
  if racer.car and racer.car.model then
    if not racer.car.seed and not racer.car.setup then
      racer.car.seed = rngLib.hash(racer.id .. ':' .. s.seed)
      racer.car.stage = builds.stageFor(racer.tier)
    end
    return racer.car
  end
  local seed = rngLib.hash(racer.id .. ':' .. s.seed)
  local pick = carsLib.pickConfig(builder.configs(), racer.class, rngLib.new(seed))
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

local function aiGo(vid, destNode, skill)
  local v = getObjectByID(vid)
  if not v then return end
  local aggression = 0.35 + 0.6 * (skill or 0.5)
  -- a cruiser comes out of traffic mode with the legal speed limit still set: racing, it is off
  v:queueLuaCommand(string.format("controller.setFreeze(0) input.event('parkingbrake', 0, FILTER_DIRECT) ai.setSpeedMode('off') ai.setRecoverOnCrash(true) ai.setAggression(%f) ai.setAvoidCars('on') ai.driveInLane('off') ai.driveUsingPath({wpTargetList = {%q}, aggression = %f})",
    aggression, destNode, aggression))
end

-- start a race against a racer whose car is out in the world (rolling: no countdown; standing: 3, 2, 1)
local function startRace(racer, vid, stake, bet, standing, maxD)
  local v = playerCar()
  if not v or race then return false end
  local dest, destNode, distance = farSide(v:getPosition(), maxD or CITY_RACE)
  if not dest then return false end
  race = { racer = racer.id, name = roster.displayName(racer), vid = vid, stake = stake, bet = bet, dest = dest, destNode = destNode,
    destName = placeNear(dest), distance = distance, t = 0, countdown = standing and 3.5 or nil, skill = racer.skill }
  if core_groundMarkers then core_groundMarkers.setPath(dest) end
  if sl_markers then sl_markers.flareRoute(v:getPosition(), dest) end        -- the way lit by flares, start to finish
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
  local opp = getObjectByID(r.vid)
  if r.stake == 'pink' then
    if playerWon and opp then
      -- their car is yours: it goes on a truck to your garage
      opp:queueLuaCommand('ai.setMode("disabled") controller.setFreeze(1)')
      local car = sl_fleet.registerVehicle(r.vid, { name = racer.car and racer.car.name or 'their car', value = racer.car and racer.car.value or 0, condition = 0.85 })
      local mine = sl_fleet.currentCar()
      if car then
        car.out = false
        car.where = nil
        if mine then s.activeCar = mine.id end
      end
      opp:delete()
      racer.car = nil                                           -- they will turn up in something else
      if ui_message then ui_message(string.format('You won the %s off %s. It is waiting at your garage.', car and car.name or 'car', r.name), 8, 'streetLegal') end
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
        if ui_message then ui_message(r.name .. ' takes your car. You are walking home.', 8, 'streetLegal') end
      end
      if opp then opp:delete() end
    end
  else
    if ui_message then
      ui_message(playerWon and string.format('You beat %s: +$%d, %+d reputation.', r.name, r.bet, repDelta)
        or string.format('%s won. -$%d, %+d reputation.', r.name, r.bet, repDelta), 7, 'streetLegal')
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
        local aggression = 0.35 + 0.6 * (race.skill or 0.5)
        if #wps >= #race.circuit.cps * 0.8 then
          opp:queueLuaCommand(string.format("controller.setFreeze(0) input.event('parkingbrake', 0, FILTER_DIRECT) ai.setSpeedMode('off') ai.setRecoverOnCrash(true) ai.setAvoidCars('on') ai.driveInLane('off') ai.setAggression(%f) ai.driveUsingPath(%s)",
            aggression, serialize({ wpTargetList = wps, noOfLaps = race.circuit.laps, aggression = aggression })))
        else
          opp:queueLuaCommand('controller.setFreeze(0) input.event("parkingbrake", 0, FILTER_DIRECT) ai.startFollowing(' ..
            serialize({ path = circuitPath(race.circuit.cps, race.circuit.laps, race.skill or 0.5) }) .. ', 0, 1, "neverReset")')
        end
      else
        aiGo(race.vid, race.destNode, race.skill)
      end
      if ui_message then ui_message('GO!', 2, 'streetLegal') end
    end
    return
  end
  race.t = race.t + dt
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
  local racer = list[rng:int(#list)]
  local node = nodeAround(v:getPosition(), 180, 450, rng)
  if not node then return end
  busy = true
  core_jobsystem.create(function(job)
    local veh = spawnRacer(job, s, racer, node.pos + vec3(0, 0, 0.5), nil)
    busy = false
    if not veh then return end
    veh:queueLuaCommand('ai.setMode("traffic") ai.setAggression(0.5)')
    cruisers[racer.id] = veh:getID()
  end)
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
  if night() and count < MAX_CRUISERS and spawnTimer > 8 and not race then
    spawnTimer = 0
    spawnCruiser(s)
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

local function onFlash()
  local s = career()
  if not s or race then return end
  local id, vid = racerAhead()
  if not id then return end
  local racer = stateLib.racer(s, id)
  if not night() then return end
  local answer = roster.respond(racer, 'race', { rep = s.rep, money = s.money, hasCar = sl_fleet.currentCar() ~= nil }, rngLib.new(rngLib.hash(id .. s.day)))
  if not answer.accept then
    if ui_message then ui_message(roster.displayName(racer) .. ': "' .. answer.text .. '"', 6, 'streetLegal') end
    return
  end
  s.known[id] = true                            -- after a race you have their number
  if startRace(racer, vid, 'money', answer.bet, false) and ui_message then
    ui_message(string.format('%s takes you on: $%d, to %s. Go!', roster.displayName(racer), answer.bet, race.destName), 6, 'streetLegal')
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

local function startMeet(s)
  local list = {}
  for _, p in pairs(sl_career.getPlaces() or {}) do if p.kind == 'meet' then list[#list + 1] = p end end
  if #list == 0 or busy then return end
  local rng = rngLib.new(rngLib.hash('meet' .. s.day .. math.floor(sl_career.hour())))
  local place = list[rng:int(#list)]
  local racers = {}
  for _, r in ipairs(s.racers) do
    if math.abs(r.rep - s.rep) < 1500 + s.rep * 0.5 and not cruisers[r.id] then racers[#racers + 1] = r end
  end
  if #racers == 0 then return end
  meet = { place = place, cars = {}, day = s.day }
  busy = true
  local count = math.min(#racers, rng:int(3, 6))
  core_jobsystem.create(function(job)
    for i = 1, count do
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
    busy = false
  end)
  local who = racers[1] or s.racers[1]
  sl_career.sendText(s.known[who.id] and who.id or 'benny', 'Meet tonight at ' .. place.name .. '. Bring something fast.', 2)
end

local function endMeet()
  if not meet then return end
  for _, vid in pairs(meet.cars) do despawn(vid) end
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
  guihooks.trigger('slMeet', { open = true, name = meet.place.name, racers = list, money = s.money })
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
  if here and not meet.shown then
    meet.shown = true
    sendMeet(true)
  elseif not here and meet.shown then
    meet.shown = false
    sendMeet(false)
  end
  -- a marker over the meet so it can be found
  if v and (v:getPosition() - meet.place.pos):length() < 400 then
    debugDrawer:drawCylinder(meet.place.pos, meet.place.pos + vec3(0, 0, 4), 0.25, ColorF(0.7, 0.2, 1, 0.5))
    debugDrawer:drawTextAdvanced(meet.place.pos + vec3(0, 0, 4.5), String('Car meet'), ColorF(1, 1, 1, 1), true, false, ColorI(60, 0, 90, 200))
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
    spawn.safeTeleport(opp, v:getPosition() + right * 3.6 + vec3(0, 0, 0.3), quat(v:getRotation()), true)
  end
  startRace(racer, vid, answer.stake, answer.bet or 0, true)
end

function M.closeMeet() sendMeet(false) end

----------------------------------------------------------------------------------------------
-- circuits: the ROC track's checkpoints (races.json, key "roc"), laps instead of a finish point

local ROC_LAPS = 2

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
  return { name = roc.name or 'ROC', cps = cps }
end

-- The opponent's line round the circuit, with a time for every point: as fast as the bends
-- allow (sideways grip), with the accelerating and braking a car can do. skill sets the limits.
circuitPath = function(cps, laps, skill)
  local pts = {}
  for _ = 1, laps do for _, c in ipairs(cps) do pts[#pts + 1] = c.pos end end
  pts[#pts + 1] = cps[1].pos
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
  race = { racer = racer.id, name = roster.displayName(racer), vid = vid, stake = stake, bet = bet, destName = track.name .. ', ' .. ROC_LAPS .. ' laps',
    t = 0, countdown = 3.5, skill = racer.skill, circuit = { cps = track.cps, laps = ROC_LAPS, me = { k = 0 }, them = { k = 0 } } }
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  if sl_markers then sl_markers.flareCircuit(track.cps) end
  cruisers[racer.id] = nil
  sendRace()
  return true
end

updateCircuit = function(v, opp)
  local c = race.circuit
  local total = c.laps * #c.cps + 1
  circuitStep(c.me, v:getPosition(), c.cps)
  circuitStep(c.them, opp:getPosition(), c.cps)
  if c.me.k >= total then finish(true) return true end
  if c.them.k >= total then finish(false) return true end
  return false
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
  if not s or race or busy then return false, 'Not now.' end
  if not progression.rocOpen(s) then return false, 'The ROC is for the top garage and the top names.' end
  local roc = M.rocRound(s)
  if roc.champion then return false, 'You are the champion. Nobody is left to beat.' end
  local v = playerCar()
  if not v or not sl_fleet.currentCar() then return false, 'Bring your own car to the ROC.' end
  if roc.round == 0 and not sl_career.addMoney(-progression.ROC.entry, 'ROC entry') then return false, string.format('Entry is $%d.', progression.ROC.entry) end
  local rival = champions(s)[3 - roc.round] or champions(s)[1]
  if not rival then return false, 'Nobody to race.' end
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
      pcall(function() rot = quat(spot:getRotation()) end)
    end
    spawn.safeTeleport(v, start + vec3(0, 0, 0.5), rot, true)
    job.sleep(0.5)
    right = right or v:getDirectionVector():cross(vec3(0, 0, 1)):normalized()
    local veh = spawnRacer(job, s, rival, start + right * 4.4 + vec3(0, 0, 0.5), rot or quat(v:getRotation()), true)
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
      if ui_message then ui_message(string.format('ROC round %d of 3: %s. $%d.', roc.round + 1, roster.displayName(rival), bet), 6, 'streetLegal') end
    end
  end)
  return true, 'To the ROC.'
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
      sl_career.addMoney(250000, 'ROC champion')
      stateLib.addRep(s, 2000)
      sl_career.sendText('benny', 'You won the ROC. Champion of Valo City. I always said you had it in you. (I did not.)', 3)
    else
      sl_career.sendText('benny', string.format('Round %d of the ROC done. Two more, then one. Call it in from the phone when you are ready.', roc.round), 3)
    end
  else
    roc.round = 0
    sl_career.sendText('benny', 'Out of the ROC. The entry fee is gone; come back when you are ready to pay it again.', 3)
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
