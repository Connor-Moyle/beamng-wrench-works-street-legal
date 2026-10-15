-- Wrench Works: Street Legal: the job board (extension name: sl_jobs)
-- Jobs on the phone's Jobs app: part runs, courier parcels and more (docs: DESIGN3_jobs.md). One
-- machinery for all of them: a job is a list of legs (places to stop at in order); the clock starts
-- at the first stop, the pay is settled at the last, docked for lateness and for damage done on the
-- way. A new kind of job is one row in TYPES: what it is, when it unlocks, and how to make an offer.

local M = {}

local jobsLib = require('sl/core/jobs')
local rngLib = require('sl/core/rng')
local progression = require('sl/core/progression')
local stateLib = require('sl/core/state')

local OFFERS = 6               -- on the board at a time
local STOP_RADIUS = 9          -- metres from a stop, and slow, to count as there
local DAMAGE_FULL = 30000      -- BeamNG damage counted as a wrecked load (a hard crash is ~25000)

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) if ui_message then ui_message(text, 5, 'streetLegal') end end

-- where things are: the career's places, the parts shops (Wrench Works' sites for this level), your garage
local function context(s)
  local places, byId = {}, {}
  for id, p in pairs(sl_career.getPlaces() or {}) do
    local x = { id = id, name = p.name, kind = p.kind, x = p.pos.x, y = p.pos.y, z = p.pos.z }
    places[#places + 1], byId[id] = x, x
  end
  table.sort(places, function(a, b) return a.id < b.id end)
  local shops = {}
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier() or ''
  for _, f in ipairs(FS:findFiles('/wrench_works/sites/', '*.json', 0, false, false) or {}) do
    local d = jsonReadFile(f)
    for _, sh in ipairs(type(d) == 'table' and type(d[level]) == 'table' and d[level].shops or {}) do
      if type(sh.pos) == 'table' then
        local x = { id = 'shop:' .. tostring(sh.id), name = sh.name or sh.id, kind = 'shop', x = sh.pos[1], y = sh.pos[2], z = sh.pos[3] or 0 }
        shops[#shops + 1], byId[x.id] = x, x
      end
    end
  end
  table.sort(shops, function(a, b) return a.id < b.id end)
  return { places = places, shops = shops, garage = byId['slrrGarage' .. tostring(s.garageLevel or 1)], byId = byId }
end

local function leg(p) return { id = p.id, name = p.name, x = p.x, y = p.y, z = p.z } end

-- kerbside stops for fares and food: road nodes in the city, not on a track, a link road, the valley
-- or a freeway (the map names its AI roads: ai_lane_ city, ai_roc / ai_tt_ / ai_slrr_mb_ tracks,
-- ai_link_ / ai_valley links; road_check.py), inside the box round the career's places
local NOT_CITY = { '^ai_roc', '^ai_tt_', '^ai_slrr_mb_', '^ai_link_', '^ai_valley' }
local kerbCache
local function kerbs(ctx)
  if kerbCache and kerbCache.level == (getCurrentLevelIdentifier and getCurrentLevelIdentifier()) then return kerbCache.list end
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, p in ipairs(ctx.places) do x0, y0, x1, y1 = math.min(x0, p.x), math.min(y0, p.y), math.max(x1, p.x), math.max(y1, p.y) end
  local list = {}
  local ok, nodes = pcall(function() return map.getMap().nodes end)
  for name, n in pairs(ok and type(nodes) == 'table' and nodes or {}) do
    local city = type(name) == 'string'
    for _, pat in ipairs(NOT_CITY) do if city and name:find(pat) then city = false end end
    local r = n.radius or 0
    if city and r >= 2 and r <= 6 and n.pos.x > x0 - 200 and n.pos.x < x1 + 200 and n.pos.y > y0 - 200 and n.pos.y < y1 + 200 then
      list[#list + 1] = { x = n.pos.x, y = n.pos.y, z = n.pos.z }
    end
  end
  kerbCache = { level = getCurrentLevelIdentifier and getCurrentLevelIdentifier(), list = list }
  return list
end

local function kerbNear(ctx, rng, from, minD, maxD)
  local list = kerbs(ctx)
  if #list == 0 then return nil end
  for _ = 1, 40 do
    local k = list[rng:int(#list)]
    local d = from and math.sqrt((k.x - from.x) ^ 2 + (k.y - from.y) ^ 2) or minD
    if d >= minD and d <= maxD then return k end
  end
end

-- the diners (the gas stations' food counters: the game's own facilities)
local function diners()
  local out = {}
  local f = freeroam_facilities and freeroam_facilities.getFacilities and freeroam_facilities.getFacilities(getCurrentLevelIdentifier())
  for _, g in ipairs(f and f.gasStations or {}) do
    local c = freeroam_gasStations and freeroam_gasStations.gasStationCenterRadius and freeroam_gasStations.gasStationCenterRadius(g)
    if c then out[#out + 1] = { id = 'diner:' .. tostring(g.id or g.name), name = (g.name or 'Gas station') .. ' diner', x = c.x, y = c.y, z = c.z } end
  end
  return out
end

local STREETS = { 'a side street', 'an apartment block', 'a house on the corner', 'an office', 'a back street', 'a corner shop' }

-- the kinds of job: { kind, title, unlock = rep, night = true (only after dark), offer = function(ctx, rng) -> job }
-- a job is { item, legs = { stop, stop... }, pay, seconds, fragile }
local TYPES = {
  { kind = 'part', title = 'Part run', unlock = 0, offer = function(ctx, rng)
      local list = jobsLib.offers(ctx.shops, {}, ctx.garage, rng, 1)
      local j = list[1]
      if not j then return nil end
      j.legs = { leg(ctx.byId[j.from]), leg(ctx.byId[j.to]) }
      return j
    end },
  { kind = 'courier', title = 'Courier', unlock = 0, offer = function(ctx, rng)
      local list = jobsLib.offers({}, ctx.places, nil, rng, 2)      -- (the second slot is a courier one)
      local j = list[1]
      if not j then return nil end
      j.legs = { leg(ctx.byId[j.from]), leg(ctx.byId[j.to]) }
      return j
    end },
  -- night food delivery: three drops from a diner, the food going cold
  { kind = 'food', title = 'Food delivery', unlock = 0, night = true, offer = function(ctx, rng)
      local list = diners()
      if #list == 0 then return nil end
      local d = list[rng:int(#list)]
      local legs, last, metres = { leg(d) }, d, 0
      for i = 1, 3 do
        local k = kerbNear(ctx, rng, last, 250, 1200)
        if not k then return nil end
        legs[#legs + 1] = { id = 'kerb', name = STREETS[rng:int(#STREETS)], x = k.x, y = k.y, z = k.z }
        metres = metres + math.sqrt((k.x - last.x) ^ 2 + (k.y - last.y) ^ 2)
        last = k
      end
      return { item = 'three orders', legs = legs, metres = math.floor(metres), fragile = false,
        seconds = math.max(180, math.floor(metres * 1.4 / jobsLib.SPEED * 1.2)), pay = 120 + math.floor(metres / 1000 * 60 / 10) * 10 }
    end },
  -- taxi fares: a fare at the kerb, to one of the city's places
  { kind = 'taxi', title = 'Taxi fare', unlock = 0, offer = function(ctx, rng)
      local k = kerbNear(ctx, rng, nil, 0, 0)
      if not k or #ctx.places == 0 then return nil end
      local to = ctx.places[rng:int(#ctx.places)]
      local metres = math.sqrt((to.x - k.x) ^ 2 + (to.y - k.y) ^ 2)
      if metres < 600 then return nil end
      return { item = 'a fare', legs = { { id = 'kerb', name = STREETS[rng:int(#STREETS)], x = k.x, y = k.y, z = k.z }, leg(to) }, metres = math.floor(metres),
        fragile = false, seconds = math.max(120, math.floor(metres * 1.4 / jobsLib.SPEED * 1.3)), pay = math.max(60, math.floor((40 + metres / 1000 * 90) / 10) * 10) }
    end },
  -- the junkyard's crushing run: a wreck that barely goes, to the crusher at the scrapyard
  { kind = 'crush', title = 'Crushing run', unlock = 0, offer = function(ctx, rng)
      local from, to = ctx.byId.junkyard, ctx.byId.scrapyard
      if not from or not to then return nil end
      local metres = jobsLib.distance(from, to)
      return { item = 'wreck', legs = { leg(from), leg(to) }, metres = math.floor(metres), fragile = false,
        car = { model = ({ 'covet', 'pessima', 'legran', 'midsize' })[rng:int(4)], wear = 0.9 },
        seconds = math.max(240, math.floor(metres * 1.4 / 9 * 1.5)), pay = 150 }
    end },
  -- car transport: a car between the dealer and the lots, without a scratch (fragile: over 5 % damage pays nothing)
  { kind = 'transport', title = 'Car transport', unlock = 200, offer = function(ctx, rng)
      local ends = { ctx.byId.dealer, ctx.byId.junkyard, ctx.byId.scrapyard }
      local a, b = ends[rng:int(3)], ends[rng:int(3)]
      if not a or not b or a.id == b.id then return nil end
      local metres = jobsLib.distance(a, b)
      local model = ({ 'vivace', 'sunburst2', 'etk800', 'bastion', 'scintilla' })[rng:int(5)]
      return { item = model .. ' for the ' .. b.name, legs = { leg(a), leg(b) }, metres = math.floor(metres), fragile = true,
        car = { model = model, wear = 0.05 },
        seconds = math.max(180, math.floor(metres * 1.4 / jobsLib.SPEED * 1.4)), pay = 300 + math.floor(metres / 1000 * 120 / 10) * 10 }
    end },
  -- the hot car: from a back street to a lock-up, and the police hear more of it every minute (heat)
  { kind = 'hot', title = 'Hot car', unlock = 1000, night = true, offer = function(ctx, rng)
      local k = kerbNear(ctx, rng, nil, 0, 0)
      local to = ctx.byId.meet_tuning or ctx.byId.scrapyard
      if not k or not to then return nil end
      local metres = math.sqrt((to.x - k.x) ^ 2 + (to.y - k.y) ^ 2)
      if metres < 1000 then return nil end
      return { item = 'hot car', legs = { { id = 'kerb', name = 'a back street', x = k.x, y = k.y, z = k.z }, leg(to) }, metres = math.floor(metres),
        fragile = false, heat = 0.4, car = { model = ({ 'scintilla', 'sbr', 'bolide', 'etkc' })[rng:int(4)], wear = 0.1 },
        seconds = math.max(240, math.floor(metres * 1.4 / jobsLib.SPEED * 1.3)), pay = 1000 + math.floor(metres / 1000 * 600 / 100) * 100 }
    end },
}
M.TYPES = TYPES

local function jobsState(s)
  s.jobs = s.jobs or { offers = {}, done = 0, earned = 0 }
  return s.jobs
end

-- a fresh board each morning and each dusk
local function refresh(s, force)
  local js = jobsState(s)
  local night = progression.isNight(sl_career.hour())
  local key = s.day .. (night and 'n' or 'd')
  if js.board == key and not force then return end
  js.board = key
  local ctx = context(s)
  local rng = rngLib.new(rngLib.hash('jobs:' .. key .. ':' .. tostring(s.seed)))
  local open = {}
  for _, t in ipairs(TYPES) do
    if (s.rep or 0) >= (t.unlock or 0) and (not t.night or night) then open[#open + 1] = t end
  end
  js.offers = {}
  for i = 1, OFFERS * 2 do
    if #js.offers >= OFFERS or #open == 0 then break end
    local t = open[(i - 1) % #open + 1]
    local ok, j = pcall(t.offer, ctx, rng)
    if ok and j and j.legs and #j.legs >= 2 then
      j.id, j.kind, j.title = key .. ':' .. i, t.kind, t.title
      js.offers[#js.offers + 1] = j
    end
  end
end

local function playerCarId()
  local v = getPlayerVehicle(0)
  local car = v and sl_fleet and sl_fleet.carOfVehicle and sl_fleet.carOfVehicle(v:getID())
  return car and v or nil
end

-- car jobs ("car" in the job: { model, config, wear }): the car is waiting at the first stop; you get in
-- there (yours stays parked), it is taken off you at the last. Its damage is read from its own Lua.
local carDamage = {}
function M.onJobCarDamage(vid, d) carDamage[vid] = d end
local function askDamage(veh)
  veh:queueLuaCommand('obj:queueGameEngineLua("if sl_jobs then sl_jobs.onJobCarDamage(" .. obj:getId() .. "," .. tostring(beamstate.damage or 0) .. ") end")')
end
local function damageOf(vid)
  if sl_carcare and sl_carcare.damageOf and sl_carcare.damageOf(vid) then return sl_carcare.damageOf(vid) end
  return carDamage[vid] or 0
end

local function jobVehicle(j)
  if j.car then return j.carVid and getObjectByID(j.carVid) end
  return playerCarId()
end

local function spawnJobCar(j, stop)
  local ok, veh = pcall(core_vehicles.spawnNewVehicle, j.car.model, { config = j.car.config, pos = vec3(stop.x, stop.y, (stop.z or 0) + 0.5),
    autoEnterVehicle = false, canSpawnAnotherVehicleCheck = false })
  if not ok or not veh then return nil end
  if j.car.wear then veh:queueLuaCommand(string.format('partCondition.initConditions(nil, %d, %f, %f)', math.floor(j.car.wear * 300000000), 1 - j.car.wear * 0.5, 1 - j.car.wear)) end
  if slrrDrivers and slrrDrivers.setDriver then slrrDrivers.setDriver(veh:getID(), nil) end
  return veh
end

local function routeTo(stop)
  if core_groundMarkers and stop then core_groundMarkers.setPath(vec3(stop.x, stop.y, stop.z or 0)) end
end

function M.take(jobId)
  local s = career()
  if not s then return false, 'No career running.' end
  local js = jobsState(s)
  if js.active then return false, 'Finish the job you are on first.' end
  if sl_streets and sl_streets.isRacing and sl_streets.isRacing() then return false, 'Not in the middle of a race.' end
  for i, j in ipairs(js.offers) do
    if j.id == jobId then
      if not j.car and not playerCarId() then return false, 'You need to be in one of your cars.' end
      table.remove(js.offers, i)
      j.leg = 1
      js.active = j
      routeTo(j.legs[1])
      extensions.hook('onStreetLegalChanged')
      return true, string.format('%s: go to %s.', j.title, j.legs[1].name)
    end
  end
  return false, 'That job has gone.'
end

function M.giveUp()
  local s = career()
  local js = s and jobsState(s)
  if not js or not js.active then return false, 'You are not on a job.' end
  local j = js.active
  if j.car and j.carVid then
    if gameplay_walk then gameplay_walk.setWalkingMode(true, nil, nil, true) end
    local veh = getObjectByID(j.carVid)
    if veh then veh:delete() end
  end
  js.active = nil
  stateLib.addRep(s, -5)
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  extensions.hook('onStreetLegalChanged')
  return true, 'Job dropped. Word gets round: -5 reputation.'
end

local function finish(s, js, j, v)
  local elapsed = j.startedAt and (os.clock() - j.startedAt) or 0
  local d0, d1 = j.damage0 or 0, damageOf(v:getID())
  local damage = math.max(0, math.min(1, ((d1 or 0) - d0) / DAMAGE_FULL))
  local pay, verdict = jobsLib.settle(j, elapsed, damage)
  js.active = nil
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  if pay > 0 then sl_career.addMoney(pay, j.title .. ': ' .. (j.item or 'delivery')) end
  stateLib.addRep(s, verdict == 'broken' and -5 or (verdict == 'late' and 2 or 6))
  js.done, js.earned = js.done + 1, js.earned + pay
  if j.car and j.carVid then
    local id = j.carVid
    core_jobsystem.create(function(job)
      if gameplay_walk then gameplay_walk.setWalkingMode(true, nil, nil, true) end
      job.sleep(1)
      local veh = getObjectByID(id)
      if veh then veh:delete() end
    end)
  end
  if j.heat then s.heat = math.max(0, (s.heat or 0) - j.heat) end
  toast(verdict == 'broken' and string.format('The %s is broken. No pay.', j.item or 'load')
    or string.format('%s delivered%s. $%d.', j.item or 'Delivery', verdict == 'late' and ', late' or '', pay))
  extensions.hook('onStreetLegalChanged')
end

local timer = 0
function M.onUpdate(dtReal)
  local s = career()
  if not s then return end
  timer = timer + dtReal
  if timer < 0.5 then return end
  timer = 0
  refresh(s)
  local js = jobsState(s)
  local j = js.active
  if not j then return end
  local v = (j.car and j.leg == 1) and getPlayerVehicle(0) or jobVehicle(j)
  if not v then return end
  if j.car and j.carVid then askDamage(v) end
  if j.heat and j.startedAt then s.heat = math.min(1, (s.heat or 0) + j.heat / 120) end    -- a hot car: the police hear more of it every second
  local stop = j.legs[j.leg]
  local here = v:getPosition()
  if (here - vec3(stop.x, stop.y, stop.z or here.z)):length() < STOP_RADIUS and v:getVelocity():length() < 2 then
    if j.leg == 1 then
      if j.car then
        local veh = spawnJobCar(j, stop)
        if not veh then return end
        j.carVid = veh:getID()
        if gameplay_walk and gameplay_walk.getInVehicle then gameplay_walk.getInVehicle(veh) end
        v = veh
      end
      j.startedAt = os.clock()
      j.damage0 = damageOf(v:getID())
      toast(string.format('Picked up the %s%s. %d:%02d to %s.', j.item or 'load', j.fragile and ' (fragile)' or '', math.floor(j.seconds / 60), j.seconds % 60, j.legs[2].name))
    end
    if j.leg >= #j.legs then finish(s, js, j, v) return end
    j.leg = j.leg + 1
    routeTo(j.legs[j.leg])
    extensions.hook('onStreetLegalChanged')
  end
end

----------------------------------------------------------------------------------------------
-- lot flipping (Design 3 #16): every sale counts its profit over what you paid; the junkyard's
-- standing challenge pays a bonus for a flip that clears its target, and then asks for more

local FLIP_FIRST, FLIP_GROWTH = 1000, 1.6

function M.onStreetLegalCarSold(car, price, to)
  local s = career()
  if not s or type(car) ~= 'table' or not car.boughtFor then return end
  local js = jobsState(s)
  js.flip = js.flip or { target = FLIP_FIRST, best = 0, flips = 0 }
  local profit = (price or 0) - car.boughtFor
  if profit <= 0 then return end
  js.flip.flips = js.flip.flips + 1
  js.flip.best = math.max(js.flip.best, profit)
  if profit >= js.flip.target then
    local bonus = math.floor(js.flip.target * 0.5 / 10) * 10
    sl_career.addMoney(bonus, 'Flip bonus: ' .. (car.name or 'car'))
    stateLib.addRep(s, 25)
    sl_career.sendText('benny', string.format('The junkyard owner says you made $%d on that %s. He paid you a $%d bonus, and says next time, $%d.',
      profit, car.name or 'car', bonus, math.floor(js.flip.target * FLIP_GROWTH / 100) * 100), 3)
    js.flip.target = math.floor(js.flip.target * FLIP_GROWTH / 100) * 100
  end
end

----------------------------------------------------------------------------------------------
-- tuning challenges (Design 2 G1/G2): targets in order, each paid once
local QUARTER = { { 16, 300 }, { 15, 500 }, { 14, 800 }, { 13, 1200 }, { 12, 2000 }, { 11, 3500 } }        -- seconds, prize
local DYNO = { { 150, 300 }, { 200, 500 }, { 250, 800 }, { 300, 1200 }, { 400, 2000 }, { 500, 3500 } }     -- PS, prize

local function challenge(s, key, list, value, better, unit, what)
  local js = jobsState(s)
  js[key] = js[key] or 1
  local paid = 0
  while list[js[key]] and better(value, list[js[key]][1]) do
    local t = list[js[key]]
    sl_career.addMoney(t[2], what .. ' target ' .. t[1] .. unit)
    stateLib.addRep(s, 15)
    paid = paid + t[2]
    js[key] = js[key] + 1
  end
  if paid > 0 then toast(string.format('%s: %s%s beats the target. $%d.', what, tostring(value), unit, paid)) end
end

-- the quarter mile: a drag race's time down the test track's 1/4 mile
function M.onSlrrRaceFinished(r)
  local s = career()
  if not s or type(r) ~= 'table' or r.abandoned or type(r.time) ~= 'number' or r.time <= 0 then return end
  local quarter
  for _, x in ipairs(sl_career.racesList() or {}) do
    if x.drag and (x.id == r.raceId or (r.missionId and x.missionId == r.missionId)) and tostring(x.name):find('1/4', 1, true) then quarter = true end
  end
  if quarter then challenge(s, 'quarter', QUARTER, math.floor(r.time * 100) / 100, function(v, t) return v <= t end, ' s', 'Quarter mile') end
end

-- the dyno: Wrench Works' car info sheet, for one of your cars
function M.onWrenchWorksDyno(vid, data)
  local s = career()
  if not s or type(data) ~= 'table' or not tonumber(data.maxPower) then return end
  if not (sl_fleet and sl_fleet.carOfVehicle and sl_fleet.carOfVehicle(vid)) then return end
  challenge(s, 'dyno', DYNO, math.floor(data.maxPower), function(v, t) return v >= t end, ' PS', 'Dyno')
end

----------------------------------------------------------------------------------------------
-- contracts on race results (Design 3 #14, #15): a street crew's contract and sponsor deals

local SPONSORS = { { rep = 1500, name = 'Valo Tyre & Wheel', weekly = 500 }, { rep = 3000, name = 'Redline Speed Shop', weekly = 1500 },
  { rep = 6000, name = 'Nightrun Energy', weekly = 5000 } }
local CREW = { 'the Southside Kings', 'Riverbed Runners', 'the North End crew', 'Ring Road Ghosts' }

local function newContract(s, js)
  local rng = rngLib.new(rngLib.hash('crew:' .. s.day .. ':' .. tostring(s.seed)))
  local tier = math.max(1, math.min(5, 1 + math.floor((s.rep or 0) / 800)))
  js.crew = { boss = CREW[rng:int(#CREW)], tier = tier, need = 3, won = 0, untilDay = s.day + 7,
    pay = math.floor(2000 * tier ^ 1.3 / 100) * 100 }
end

-- every race you win counts towards the contract (against a racer of its tier or better) and the sponsor's week
local function countWin(s, racerId)
  local js = jobsState(s)
  js.weekWins = (js.weekWins or 0) + 1
  local c = js.crew
  local r = racerId and stateLib.racer(s, racerId)
  if c and not c.done and r and (r.tier or 1) >= c.tier then
    c.won = c.won + 1
    if c.won >= c.need then
      c.done = true
      sl_career.addMoney(c.pay, 'Crew contract: ' .. c.boss)
      stateLib.addRep(s, 30)
      sl_career.sendText('benny', string.format('Word from %s: contract done. $%d is in your account.', c.boss, c.pay), 3)
    end
  end
end

-- (both the map's races and Street Legal's own say so: won, the opponent's name, their racer id)
function M.onStreetLegalRaceResult(won, opponent, racerId)
  local s = career()
  if s and won then countWin(s, racerId) end
end

function M.onStreetLegalNewDay(day)
  local s = career()
  if not s then return end
  local js = jobsState(s)
  -- the crew contract: a new one when the last is done or has run out (from 300 rep)
  if (s.rep or 0) >= 300 and (not js.crew or js.crew.done or day > js.crew.untilDay) then
    newContract(s, js)
    sl_career.sendText('benny', string.format('%s want somebody to beat %d racers of tier %d or better this week. $%d. It is on your Jobs app.',
      js.crew.boss, js.crew.need, js.crew.tier, js.crew.pay), 5)
  end
  -- sponsors: the best one your name gets you; paid weekly, as long as you win two races a week
  local best
  for _, sp in ipairs(SPONSORS) do if (s.rep or 0) >= sp.rep then best = sp end end
  if best and (not js.sponsor or js.sponsor.name ~= best.name) then
    js.sponsor = { name = best.name, weekly = best.weekly, since = day }
    js.weekWins = 0
    sl_career.sendText('benny', string.format('%s want their name on your car: $%d a week, as long as you win two races a week.', best.name, best.weekly), 4)
  elseif js.sponsor and (day - js.sponsor.since) % 7 == 0 and day ~= js.sponsor.since then
    if (js.weekWins or 0) >= 2 then
      sl_career.addMoney(js.sponsor.weekly, 'Sponsor: ' .. js.sponsor.name)
    else
      sl_career.sendText('benny', js.sponsor.name .. ' saw you did not win two races this week. No cheque. Win some.', 3)
    end
    js.weekWins = 0
  end
end

-- for the phone
function M.summary()
  local s = career()
  if not s then return nil end
  refresh(s)
  local js = jobsState(s)
  local out = { offers = {}, done = js.done, earned = js.earned, flip = js.flip or { target = FLIP_FIRST, best = 0, flips = 0 },
    quarter = QUARTER[js.quarter or 1] and QUARTER[js.quarter or 1][1] or nil, dyno = DYNO[js.dyno or 1] and DYNO[js.dyno or 1][1] or nil,
    crew = js.crew and not js.crew.done and { boss = js.crew.boss, tier = js.crew.tier, need = js.crew.need, won = js.crew.won, daysLeft = js.crew.untilDay - s.day, pay = js.crew.pay } or nil,
    sponsor = js.sponsor and { name = js.sponsor.name, weekly = js.sponsor.weekly, weekWins = js.weekWins or 0 } or nil }
  for _, j in ipairs(js.offers) do
    out.offers[#out.offers + 1] = { id = j.id, title = j.title, item = j.item, from = j.legs[1].name, to = j.legs[#j.legs].name,
      pay = j.pay, seconds = j.seconds, fragile = j.fragile, metres = j.metres }
  end
  local a = js.active
  if a then
    out.active = { title = a.title, item = a.item, next = a.legs[a.leg].name, to = a.legs[#a.legs].name, pay = a.pay, fragile = a.fragile,
      timeLeft = a.startedAt and math.floor(a.seconds - (os.clock() - a.startedAt)) or nil }
  end
  return out
end

function M.showWay()
  local s = career()
  local a = s and jobsState(s).active
  if a then routeTo(a.legs[a.leg]) end
end

function M.onStreetLegalStopped() if core_groundMarkers then core_groundMarkers.setPath(nil) end end

return M
