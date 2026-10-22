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
local drawcache = require('sl/core/drawcache')
local chaseLib = require('sl/core/chase')
local spawnplan = require('sl/core/spawnplan')
local rngLib = require('sl/core/rng')

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
-- the state the police run on: the career's, or in free roam (Mods > Street Legal > Free roam > Police) the sandbox of sl_mode (its heat goes with the session, nothing is saved)
local function state() local m = rawget(_G, 'sl_mode') return career() or (m and m.state and m.state('police')) or nil end
local function phase() local s = state() return s and s.phase or 'day' end
local function night() return phase() == 'night' end
local function opt(key) return not sl_options or sl_options.get(key) ~= false end      -- (a Mods menu switch; on without the options)
local function propYaw(default) return sl_options and tonumber(sl_options.get('slPoliceStripYaw')) or default end
local function toast(text) if ui_message then ui_message(text, 4, 'streetLegal') end end

-- heat is the night's: by day it is nothing
function M.heat()
  local s = state()
  return s and night() and (s.heat or 0) or 0
end
function M.level() return heatLib.level(M.heat()) end

local function addHeat(x)
  local s = state()
  if sl_patrol and sl_patrol.active and sl_patrol.active() then return end      -- (P12: no heat while you wear the badge)
  if s and night() then
    local before = heatLib.level(s.heat or 0)
    s.heat = heatLib.raised(s.heat, x)
    local now = heatLib.level(s.heat)
    if now > before and career() then extensions.hook('onStreetLegalHeatUp', now, before) end      -- (for the screen banners; a career only: free roam fires no career events)
  end
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
  local levels = opt('slPoliceLevels')
  local suspended = sl_justice ~= nil and sl_justice.suspended ~= nil and sl_justice.suspended() == true      -- (P8: a suspended licence: the police watch by day too)
  local patrol = sl_patrol ~= nil and sl_patrol.active ~= nil and sl_patrol.active() == true                   -- (P12: on a patrol shift the suspects keep coming)
  local key = tostring(phase()) .. level .. tostring(levels) .. tostring(suspended) .. tostring(patrol)
  if key == appliedVars then return end
  appliedVars = key
  local vars = chaseLib.patrolVars(chaseLib.suspendedVars(chaseLib.vars(phase(), level), suspended), patrol)
  if levels and phase() == 'night' then vars.scoreLevels = chaseLib.scoreLevels(level) end      -- (P1: the hotter, the sooner the game's chase climbs a level)
  gameplay_police.setPoliceVars(vars)
end
function M.refreshVars() appliedVars = nil applyVars() end      -- (sl_patrol: the shift starts or ends)

-- ---- P6: radio chatter (text): the game's message line, and the last lines for the dashboard (chaseState.chatter)
local radio = {}
local function say(event, ctx)
  if not opt('slPoliceChatter') then return end
  local v = getPlayerVehicle(0)
  ctx = ctx or {}
  if v and not ctx.vx then local vel = v:getVelocity() ctx.vx, ctx.vy = vel.x, vel.y end
  if v and not ctx.district then
    local d = sl_crews and sl_crews.districtAt and career() and sl_crews.districtAt(v:getPosition())
    ctx.district = d and d.name or strings.t('police.radio_the_area')
  end
  if not ctx.car then
    local car = career() and sl_fleet and sl_fleet.currentCar and sl_fleet.currentCar()
    ctx.car = car and car.name or (v and v:getJBeamFilename()) or strings.t('police.radio_the_suspect')
  end
  local key, unit, car, where, heading = chaseLib.chatter(event, ctx)
  if not key then return end
  local text = strings.t(key, unit, car, where, heading)
  radio[#radio + 1] = text
  while #radio > 3 do table.remove(radio, 1) end
  if ui_message then ui_message(text, 4, 'slPoliceRadio') end
end
function M.radioSay(event, ctx) say(event, ctx) end      -- (sl_pursuit: the box and PIT lines)
function M.radio() return radio end

local nodeAround              -- (defined below)
-- the chase, once a second: out of sight or under a roof the game's evade timer runs faster (core/chase), and the HUD gets the meters.
-- chaseState is nil outside a chase; stripsHit counts the strips this chase has put under you (the escape pays for them)
local chaseState, lastEvade, stripsHit = nil, 0, 0
local chaseGuard = { fails = 0, off = false }
local seen = {}                 -- what the radio has said this chase: { lostAt, roadblocks, units }
local cooldownUntil = -1e9      -- (P3) after an escape: the patrols leave you alone and the heat cools fast until then
local function chaseTick(dt)
  local v = getPlayerVehicle(0)
  local pur = v and night() and gameplay_police and gameplay_police.getPursuitData and gameplay_police.getPursuitData(v:getID())
  if not (pur and (pur.mode or 0) >= 1 and pur.timers) then
    if chaseState and M.stripReset then M.stripReset() end
    chaseState, lastEvade, stripsHit, seen = nil, 0, 0, {}
    return
  end
  local up = castRayStatic and castRayStatic(v:getPosition() + vec3(0, 0, 1), vec3(0, 0, 1), 30) or 30
  local covered, hidden = chaseLib.covered(up), pur.policeVisible == false
  local rate = chaseLib.evadeRate(hidden, covered)
  -- (P3) parked out of sight at a garage or a fuel station: the timer runs x3
  local spot = opt('slPoliceHide') and sl_career.getPlaces and chaseLib.atHideSpot(sl_career.getPlaces(), v:getPosition(), v:getVelocity():length()) or nil
  rate = chaseLib.hideRate(rate, hidden, spot ~= nil)
  local tm = pur.timers
  if rate > 1 and (tm.evade or 0) > lastEvade then tm.evade = tm.evade + (rate - 1) * dt end      -- (only while the game is counting: patrols far enough off)
  lastEvade = tm.evade or 0
  chaseState = { evade = tm.evadeValue or 0, arrest = tm.arrestValue or 0, hidden = hidden, covered = covered, rate = rate, strip = M.stripWarning and M.stripWarning() or false,
                 hiding = spot ~= nil and hidden, mode = pur.mode, chatter = radio }
  if M.stripTick then M.stripTick(v) end
  -- (P6) the radio: lost and regained sight, a roadblock going up, more units
  if hidden and not seen.lost then seen.lost = true say('lost') elseif not hidden and seen.lost then seen.lost = nil say('visual') end
  if (pur.roadblocks or 0) > (seen.roadblocks or 0) then seen.roadblocks = pur.roadblocks say('roadblock') end
  local n = 0
  for _ in pairs(gameplay_police.getPoliceVehicles and gameplay_police.getPoliceVehicles() or {}) do n = n + 1 end
  if seen.units and n > seen.units then say('backup', { unit = n }) end
  seen.units = n
  if rate > 1 then log('D', 'street_legal', string.format('chase: hidden=%s covered=%s hiding=%s rate=%.2f evade=%.2f', tostring(hidden), tostring(covered), tostring(spot ~= nil), rate, lastEvade)) end
end
function M.chaseHud() return chaseState end
function M.stripsSurvived() return stripsHit end

-- the words for why the chase ended in a bust, with a space after (empty when it is not known): core/chase bustCause
function M.bustCause(pursuit)
  local v = getPlayerVehicle(0)
  if not v then return '' end
  local p = v:getPosition()
  local cops = 0
  for id in pairs(gameplay_police and gameplay_police.getPoliceVehicles and gameplay_police.getPoliceVehicles() or {}) do
    local c = getObjectByID(id)
    if c and id ~= v:getID() and (c:getPosition() - p):length() < 25 then cops = cops + 1 end
  end
  local car = sl_fleet and sl_fleet.currentCar and sl_fleet.currentCar()
  local care = car and sl_carcare and sl_carcare.careOf and sl_carcare.careOf(car)
  local key, n = chaseLib.bustCause({
    fuelLitres = care and care.fuelLitres, strips = stripsHit, cops = cops,
    roadblockDist = type(pursuit) == 'table' and (pursuit.roadblocks or 0) > 0 and pursuit.roadblockPos and (pursuit.roadblockPos - p):length() or nil })
  if not key then return '' end
  return (n and string.format(strings.t('police.bust_' .. key), n) or strings.t('police.bust_' .. key)) .. ' '
end

-- the spike strip (heat 3+, in a chase): the game's own 'spikestrip' prop (ground material 32: its tyre code deflates what rolls over it).
-- One strip is built at night from heat 3 (the patrol build rule), parked out of play and switched off, and moved onto the road ahead of you
-- 150-250 m down your route (core/chase stripSpot: on a straight, not under a roof, not on a bridge), with a warning on the HUD and a message.
-- It is parked again 8 s after you pass it or after 30 s.
M.STRIP = true                        -- false: no strips
M.STRIP_CONFIG = 'vehicles/spikestrip/flexr_dual.pc'
M.STRIP_YAW = 0                       -- degrees, to turn the prop across the road (its long side is not known offline: checked in game)
local stripId, stripBusy, stripPark, stripPos, stripAt, stripPassed = nil, false, nil, nil, -1e9, false
local lastStrip = -1e9
local function stripVeh()
  local v = stripId and getObjectByID(stripId)
  if not v then stripId = nil end
  return v
end
local function parkStrip()
  local sv = stripVeh()
  if sv and stripPark then
    spawn.safeTeleport(sv, stripPark, quat(0, 0, 0, 1), true, nil, nil, nil, false)
    sv:setActive(0)
  end
  stripPos = nil
end
local function stripOk(pt)
  local up, dn = vec3(0, 0, 1), vec3(0, 0, -1)
  local p = vec3(pt.x, pt.y, pt.z)
  return castRayStatic(p + vec3(0, 0, 1), up, 30) >= 30 and castRayStatic(p + vec3(0, 0, 2), dn, 12) < 5      -- no roof; ground close below (not a bridge)
end
-- the road ahead as points: the road graph from here to a node 250-400 m off in the direction of travel
local function routeAhead(v)
  local ok, nodes = pcall(function() return map.getMap().nodes end)
  if not ok or type(nodes) ~= 'table' then return nil end
  local p = v:getPosition()
  local dir = v:getVelocity()
  if dir:length() < 3 then dir = v:getDirectionVector() end
  dir = dir:normalized()
  local okc, a = pcall(function() return (map.findClosestRoad(p)) end)
  if not (okc and a) then return nil end
  local goal, best, tries = nil, 0.8, 0
  for name, n in pairs(nodes) do
    tries = tries + 1
    local off = n.pos - p
    local d = off:length()
    if d > 250 and d < 400 then
      local dot = off:dot(dir) / d
      if dot > best then goal, best = name, dot end
    end
    if tries > 20000 then break end
  end
  if not goal then return nil end
  local okp, path = pcall(map.getPath, a, goal)
  if not okp or type(path) ~= 'table' then return nil end
  local pts = { p }
  for _, name in ipairs(path) do
    local n = nodes[name]
    if n and (#pts > 1 or (n.pos - p):dot(dir) > 0) then pts[#pts + 1] = n.pos end      -- (nodes behind you are dropped from the start)
  end
  return pts
end
local function placeStrip(v)
  local sv = stripVeh()
  if not sv then return end
  local pts = routeAhead(v)
  local spot, d = chaseLib.stripPlan(pts, stripOk)
  if not spot then return end
  local pos = vec3(spot.x, spot.y, spot.z + 0.3)
  local across = vec3(-d.y, d.x, 0):normalized()
  local rot = quatFromDir(across, vec3(0, 0, 1))
  local yaw = propYaw(M.STRIP_YAW)
  if yaw ~= 0 then rot = rot * quatFromAxisAngle(vec3(0, 0, 1), math.rad(yaw)) end
  sv:setActive(1)
  spawn.safeTeleport(sv, pos, rot, true, nil, nil, nil, false)
  stripPos, stripAt, stripPassed, lastStrip = pos, os.clock(), false, os.clock()
  if ui_message then ui_message(strings.t('police.strip_ahead'), 4, 'streetLegal') end
  log('I', 'street_legal', string.format('chase: strip placed %.0f m ahead at %.0f,%.0f', (pos - v:getPosition()):length(), pos.x, pos.y))
end
-- every frame while a strip is out: counts the pass (the tyres are the game's), parks it afterwards
local function stripWatch()
  if not stripPos then return end
  local v = getPlayerVehicle(0)
  if not v then return end
  local now = os.clock()
  if not stripPassed and (stripPos - v:getPosition()):length() < 8 then
    stripPassed, stripAt = true, now
    stripsHit = stripsHit + 1
    log('I', 'street_legal', 'chase: strip passed, strips this chase ' .. stripsHit)
  end
  if (stripPassed and now - stripAt > 8) or now - stripAt > 30 then parkStrip() end
end
function M.stripWarning() return stripPos ~= nil and not stripPassed end
function M.stripReset() parkStrip() if M.breakerReset then M.breakerReset() end end
function M.stripTick(v)       -- (from the chase tick)
  if M.STRIP and opt('slPoliceStrips') and not stripPos and stripVeh() and chaseLib.stripDue(phase(), M.level(), true, os.clock() - lastStrip) then placeStrip(v) say('strip') end
end
-- a build gate for the chase props (the strip, the wall): the patrol rule, but heat 4-5 is urgent (as for the patrols: at 15 m/s with cruisers
-- being built the rule held the strip back for minutes). The reason it said no is logged, at most once in 30 s.
local heldAt = -1e9
local function propGate(what, v)
  local sBusy, sSince = false, 1e9
  if sl_streets and sl_streets.buildGate then sBusy, sSince = sl_streets.buildGate() end
  local speed, since = v:getVelocity():length(), math.min(sSince or 1e9, os.clock() - lastBuild)
  if spawnplan.patrolOk(speed, since, sBusy, M.level() >= 4) then return true end
  if os.clock() - heldAt > 30 then
    heldAt = os.clock()
    log('I', 'street_legal', string.format('chase: %s build held (speed %.0f m/s, %.0f s since the last build, busy=%s)', what, speed, since, tostring(sBusy)))
  end
  return false
end
-- the strip itself, built once at night from heat 3 while nobody is after you (a spawn is a hitch)
local function updateStrip(v)
  if not M.STRIP or not opt('slPoliceStrips') or stripId or stripBusy or not night() or M.level() < 3 or M.inPursuit() or not gameplay_traffic then return end
  local node = nodeAround(v:getPosition(), 500, 900)
  if not node then return end
  if not propGate('strip', v) then return end
  stripBusy, lastBuild = true, os.clock()
  if sl_streets and sl_streets.noteBuild then sl_streets.noteBuild() end
  core_jobsystem.create(function(job)
    local ok, sv = pcall(core_vehicles.spawnNewVehicle, 'spikestrip', { config = M.STRIP_CONFIG, pos = node.pos + vec3(0, 0, 0.5), autoEnterVehicle = false, canSpawnAnotherVehicleCheck = false })
    if ok and sv then
      job.sleep(1)
      stripId, stripPark = sv:getID(), node.pos + vec3(0, 0, 0.5)
      sv:setActive(0)
      log('I', 'street_legal', 'chase: strip built, parked out of play')
    else
      log('W', 'street_legal', 'chase: strip could not be built: ' .. tostring(sv))
    end
    stripBusy = false
  end)
end

-- pursuit breakers (heat 2+, in a chase): up to 3 marked spots on straight wide roads near you (core/chase breakerSpots, an orange post at night).
-- Pass one at speed with a patrol 25-55 m behind and a wall of tyres (the game's 'tirestacks' wall, a pooled prop like the strip) drops across
-- the road behind you; it is parked 25 s later, and a breaker is ready again after 60 s.
M.BREAKERS = true                     -- false: no breakers
M.BREAKER_CONFIG = 'vehicles/tirestacks/wall.pc'
M.BREAKER_YAW = 0                     -- degrees, to turn the prop across the road (checked in game)
local spots, spotsAt, prevD = nil, nil, nil
local wallId, wallBusy, wallPark, wallAt, lastBreaker = nil, false, nil, -1e9, -1e9
local wallOut = false
local function wallVeh()
  local v = wallId and getObjectByID(wallId)
  if not v then wallId = nil end
  return v
end
local function parkWall()
  local wv = wallVeh()
  if wv and wallPark and wallOut then
    spawn.safeTeleport(wv, wallPark, quat(0, 0, 0, 1), true, nil, nil, nil, false)
    wv:setActive(0)
  end
  wallOut = false
end
function M.breakerReset() parkWall() end
local function dropWall(v)
  local wv = wallVeh()
  if not wv then return end
  local dir = v:getVelocity()
  dir = vec3(dir.x, dir.y, 0)
  if dir:length() < 1 then return end
  dir = dir:normalized()
  local p = v:getPosition()
  local rot = quatFromDir(vec3(-dir.y, dir.x, 0), vec3(0, 0, 1))
  local yaw = propYaw(M.BREAKER_YAW)
  if yaw ~= 0 then rot = rot * quatFromAxisAngle(vec3(0, 0, 1), math.rad(yaw)) end
  wv:setActive(1)
  spawn.safeTeleport(wv, p - dir * 15 + vec3(0, 0, 0.3), rot, true, nil, nil, nil, false)
  wallOut, wallAt, lastBreaker = true, os.clock(), os.clock()
  if ui_message then ui_message(strings.t('police.breaker'), 4, 'streetLegal') end
  log('I', 'street_legal', string.format('chase: breaker dropped at %.0f,%.0f', p.x, p.y))
end
-- every frame at night from heat 2: the posts, and the pass
local function breakerWatch()
  if not (M.BREAKERS and opt('slPoliceBreakers') and spots and #spots > 0 and night() and M.level() >= 2) then return end
  local v = getPlayerVehicle(0)
  if not v then return end
  local p = v:getPosition()
  local near, nearD = nil, 1e9
  for _, s in ipairs(spots) do
    local d = math.sqrt((s.x - p.x) ^ 2 + (s.y - p.y) ^ 2)
    if d < nearD then near, nearD = s, d end
    if d < 300 and debugDrawer then
      -- (the post's two points and the colour are built once and the colour's alpha is moved, not a new vec3 pair and ColorF for every post every frame)
      local post = drawcache.get('breaker:' .. s.x .. ',' .. s.y, function() return { vec3(s.x, s.y, s.z), vec3(s.x, s.y, s.z + 7), ColorF(1, 0.55, 0.1, 0.5) } end)
      post[3].a = 0.35 + 0.35 * (0.5 + 0.5 * math.sin(os.clock() * 4))
      debugDrawer:drawCylinder(post[1], post[2], 0.35, post[3])
    end
  end
  if wallOut and os.clock() - wallAt > 25 then parkWall() end
  if not (chaseState and wallVeh() and not wallOut and chaseLib.breakerReady(os.clock() - lastBreaker)) then prevD = nil return end
  local d = nearD < 60 and nearD or nil
  if prevD and d and prevD < 8 and d > prevD then
    local cop = gameplay_police and gameplay_police.getNearestPoliceVehicle and gameplay_police.getNearestPoliceVehicle(v:getID(), false, true)
    local c = cop and getObjectByID(cop)
    if chaseLib.breakerPassed(prevD, d, v:getVelocity():length(), c and (c:getPosition() - p):length() or nil) then dropWall(v) end
  end
  prevD = d
end
-- the spots (when none yet, or over 1200 m from where they were chosen) and the wall (built once, like the strip, with the patrol build rule)
local function updateBreakers(v)
  if not M.BREAKERS or not opt('slPoliceBreakers') or not night() or M.level() < 2 then return end
  local p = v:getPosition()
  if not spots or not spotsAt or (spotsAt - p):length() > 1200 then
    local ok, nodes = pcall(function() return map.getMap().nodes end)
    if ok and type(nodes) == 'table' then
      spots, spotsAt = chaseLib.breakerSpots(nodes, 3, p, 1800, rngLib.new(rngLib.hash('breakers' .. math.floor(p.x / 1000) .. ',' .. math.floor(p.y / 1000)))), p
      log('I', 'street_legal', 'chase: ' .. #spots .. ' breaker spots near ' .. string.format('%.0f,%.0f', p.x, p.y))
    end
  end
  if wallId or wallBusy or #(spots or {}) == 0 or M.inPursuit() then return end
  local node = nodeAround(p, 500, 900)
  if not node then return end
  if not propGate('breaker wall', v) then return end
  wallBusy, lastBuild = true, os.clock()
  if sl_streets and sl_streets.noteBuild then sl_streets.noteBuild() end
  core_jobsystem.create(function(job)
    local ok, wv = pcall(core_vehicles.spawnNewVehicle, 'tirestacks', { config = M.BREAKER_CONFIG, pos = node.pos + vec3(0, 0, 0.5), autoEnterVehicle = false, canSpawnAnotherVehicleCheck = false })
    if ok and wv then
      job.sleep(1)
      wallId, wallPark, wallOut = wv:getID(), node.pos + vec3(0, 0, 0.5), false
      wv:setActive(0)
      log('I', 'street_legal', 'chase: breaker wall built, parked out of play')
    else
      log('W', 'street_legal', 'chase: breaker wall could not be built: ' .. tostring(wv))
    end
    wallBusy = false
  end)
end

-- a road node some way off, to start a patrol where you will not see it appear
function nodeAround(from, minD, maxD)
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
  local target = (policeOn() and not (slrrValoNight and slrrValoNight.setPolice)) and math.floor((sl_options and sl_options.get('slPatrols') or PATROLS) * level() + 0.5) or 0
  if policeOn() then target = target + math.floor(heatLib.extraPatrols(phase(), M.level()) * level() + 0.5) end      -- (D3) one more a heat level, on top of the map's own
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
  local pool = opt('slPoliceUnits') and chaseLib.configsFor(M.level()) or CONFIGS      -- (P4: highway patrol from heat 3, an unmarked car and the van from heat 4)
  local cfg = pool[math.random(#pool)]
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

-- for the tests (run_lua): a patrol 80-160 m from you and a chase started with it. Returns the words for the log.
-- a chase from where the player stands (the impound lot's fence, P10): the tester's debugChase does the same
function M.chaseFromHere() return M.debugChase() end
function M.debugChase()
  local v = getPlayerVehicle(0)
  if not (v and gameplay_police and gameplay_traffic) then return 'no player or no police' end
  local node = nodeAround(v:getPosition(), 80, 160)
  if not node then return 'no road node 80-160 m away, try again' end
  local cfg = CONFIGS[1]
  core_jobsystem.create(function(job)
    local ok, veh = pcall(core_vehicles.spawnNewVehicle, cfg[1], { config = cfg[2], pos = node.pos + vec3(0, 0, 0.5), autoEnterVehicle = false, canSpawnAnotherVehicleCheck = false })
    if not (ok and veh) then log('W', 'street_legal', 'chase: debug patrol could not be built') return end
    job.sleep(1.5)
    units[#units + 1] = veh:getID()
    if slrrDrivers and slrrDrivers.setDriver then slrrDrivers.setDriver(veh:getID(), 'slrr_police') end
    gameplay_traffic.insertTraffic(veh:getID())
    playerInTraffic()
    job.sleep(0.5)
    gameplay_police.setPursuitMode(1, v:getID(), { veh:getID() })
    log('I', 'street_legal', 'chase: debug chase started with patrol ' .. veh:getID())
  end)
  return 'building a patrol, the chase starts in about 3 s'
end

-- a chase on the player: the nearest patrols within `reach` m join (how many and at which mode by the heat: core/chase P1). Returns true when one started.
local function startChase(v, reach)
  local lvl = M.level()
  local cops, p = {}, v:getPosition()
  for cid in pairs(gameplay_police.getPoliceVehicles and gameplay_police.getPoliceVehicles() or {}) do
    local c = getObjectByID(cid)
    local d = c and cid ~= v:getID() and (c:getPosition() - p):length()
    if d and d <= reach then cops[cid] = d end
  end
  local levels = opt('slPoliceLevels')
  local ids = chaseLib.nearest(cops, levels and chaseLib.joiners(lvl) or 1)
  if #ids == 0 then return false end
  gameplay_police.setPursuitMode(levels and chaseLib.modeFor(lvl) or 1, v:getID(), ids)
  return true
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
  if startChase(v, chaseLib.FINISH_REACH * 10) then toast(strings.t('police.police_lose_them_or_lose')) end
end

M.onStreetLegalRaceStarted = M.onRaceStart
M.onSlrrRaceStarted = M.onRaceStart

-- (P13) cops at the finish: when a street race ends, a patrol that was near the route may be waiting; the chance by heat and aggression
function M.onStreetLegalRaceResult()
  local s = career()
  if not s or not policeOn() or not opt('slPoliceFinish') or not gameplay_police or M.inPursuit() then return end
  if math.random() > chaseLib.finishChance(phase(), M.level(), level()) then return end
  local v = getPlayerVehicle(0)
  if v then playerInTraffic() if startChase(v, chaseLib.FINISH_REACH) then toast(strings.t('police.finish_cops')) end end
end

-- (P3) after an escape the patrols leave you alone for a while (the game's ignorePursuit flag on the player's traffic entry) and the heat cools fast
local ignoredVid               -- the vehicle whose traffic entry carries the flag: cleared by that id (a stop or a vehicle change must never leave it set: the game's police skip a flagged entry for good)
local function setIgnore(on)
  local data = gameplay_traffic and gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData()
  if ignoredVid then
    local t = data and data[ignoredVid]
    if t then t.ignorePursuit = nil end
    ignoredVid = nil
  end
  if not on then return end
  local v = getPlayerVehicle(0)
  local t = v and data and data[v:getID()]
  if t then t.ignorePursuit = true ignoredVid = v:getID() end
end
function M.inCooldown() return os.clock() < cooldownUntil end
function M.onVehicleSwitched() if M.inCooldown() then setIgnore(true) else setIgnore(false) end end      -- (the flag follows the player's car)
-- the game's pursuit events for the player: the career settles money and reputation itself (sl_career.onPursuitAction); here the cool-down, the radio,
-- and in free roam (no career) the whole bust: heat and a message, no money (the sandbox has no wallet)
function M.onPursuitAction(id, action, pursuit)
  local v = getPlayerVehicle(0)
  if not v or v:getID() ~= id or not state() then return end
  if action == 'start' then seen = {} say('start')
  elseif action == 'evade' then
    say('evade')
    if opt('slPoliceHide') then cooldownUntil = os.clock() + chaseLib.COOLDOWN_S setIgnore(true) end
    if not career() then addHeat(heatLib.ESCAPE) toast(strings.t('police.free_lost_them')) end
  elseif action == 'arrest' then
    say('arrest')
    if not career() then
      local offences = type(pursuit) == 'table' and type(pursuit.offensesList) == 'table' and #pursuit.offensesList or 1
      local fine = math.floor(heatLib.fine(require('sl/core/progression').policeFine(offences, false), phase(), M.level()) + 0.5)
      addHeat(heatLib.BUST)
      toast(strings.t('police.free_busted_1', fine))
    end
  end
end
-- (P3) a repaint at night: the patrols know the car less; one level off the heat, once a night
local repainted = false
function M.onWrenchWorksPainted(vid)
  local v = getPlayerVehicle(0)
  if not (opt('slPoliceHide') and v and v:getID() == vid and night() and not repainted) then return end
  local s = state()
  if not s or (s.heat or 0) <= 0 then return end
  repainted = true
  s.heat = math.max(0, (s.heat or 0) - chaseLib.REPAINT_DROP)
  toast(strings.t('police.repainted'))
end

function M.onStreetLegalNewDay() local s = career() if s then s.heat = (s.heat or 0) * 0.7 end end

-- a phase switch: the day clears the heat (the career did), the police's rules and our extra patrols follow
function M.onStreetLegalPhase(ph)
  appliedVars, repainted = nil, false
  if ph ~= 'night' then
    for i = #units, 1, -1 do despawn(units[i]) units[i] = nil end
    if stripId then despawn(stripId) stripId, stripPos = nil, nil end
    if wallId then despawn(wallId) wallId, wallOut, spots = nil, false, nil end
  end
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
  if not state() then
    if #units > 0 then for _, id in ipairs(units) do despawn(id) end units = {} end
    if stripId then despawn(stripId) stripId, stripPos = nil, nil end
    if wallId then despawn(wallId) wallId, wallOut, spots = nil, false, nil end
    return
  end
  if cooldownUntil > -1e9 and not M.inCooldown() then cooldownUntil = -1e9 setIgnore(false) end      -- (the cool-down is over: the patrols see you again)
  timer = timer + dtReal
  nearTimer = nearTimer + dtReal
  stripWatch()
  breakerWatch()
  if nearTimer > 1 then
    local ok, err, off = chaseLib.guarded(chaseGuard, chaseTick, nearTimer)
    if err then log('E', 'street_legal', 'chase tick failed' .. (off and ', switched off for this session' or '') .. ': ' .. tostring(err)) end
    nearTimer = 0
    nearMiss(os.clock())
  end
  if timer > 5 then
    timer = 0
    updatePatrols()
    local pv = getPlayerVehicle(0)
    if pv then updateStrip(pv) updateBreakers(pv) end
    local s = state()
    if night() then
      if not M.inPursuit() then s.heat = heatLib.cooled(s.heat, chaseLib.coolingMinutes(5 / 60, M.inCooldown())) end      -- heat cools as time passes while nobody is after you (five times as fast in the cool-down)
      if career() then bankAtGarage() end
    end
    applyVars()
  end
end

function M.onStreetLegalStopped() for _, id in ipairs(units) do despawn(id) end units = {} if stripId then despawn(stripId) stripId, stripPos = nil, nil end if wallId then despawn(wallId) wallId, wallOut, spots = nil, false, nil end cooldownUntil, radio, repainted = -1e9, {}, false setIgnore(false) end
function M.onClientEndMission() units = {} busy = false stripId, stripPos, stripBusy = nil, nil, false wallId, wallOut, wallBusy, spots = nil, false, false, nil cooldownUntil, radio, seen = -1e9, {}, {} pcall(setIgnore, false) end

return M
