-- Wrench Works: Street Legal: the job board (extension name: sl_jobs)
-- Jobs on the phone's Jobs app: part runs, courier parcels and more (docs: DESIGN3_jobs.md). One
-- machinery for all of them: a job is a list of legs (places to stop at in order); the clock starts
-- at the first stop, the pay is settled at the last, docked for lateness and for damage done on the
-- way. A new kind of job is one row in TYPES: what it is, when it unlocks, and how to make an offer.

local M = {}

local strings = require('sl/core/strings')

local jobsLib = require('sl/core/jobs')
local contractLib = require('sl/core/contract')
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
  return { places = places, shops = shops, garage = byId[(progression.garages[s.garageLevel or 1] or progression.garages[1]).site], byId = byId }
end

M.context = function(s) return context(s or career()) end      -- (the tutorial makes its part run with it)

local function leg(p) return { id = p.id, name = p.name, x = p.x, y = p.y, z = p.z, radius = p.radius } end

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

-- a random city kerb (for other extensions: the used-parts market's sellers)
function M.randomKerb(rng) local s = career() return s and kerbNear(context(s), rng, nil, 0, 0) or nil end

-- the diners (the gas stations' food counters: the game's own facilities)
local function diners()
  local out = {}
  local f = freeroam_facilities and freeroam_facilities.getFacilities and freeroam_facilities.getFacilities(getCurrentLevelIdentifier())
  for _, g in ipairs(f and f.gasStations or {}) do
    local c, r = nil, 0
    if freeroam_gasStations and freeroam_gasStations.gasStationCenterRadius then c, r = freeroam_gasStations.gasStationCenterRadius(g) end
    -- the stop is the middle of the pumps; a car at the far pump is as far as the pumps spread, and a car's length more
    if c then out[#out + 1] = { id = 'diner:' .. tostring(g.id or g.name), name = strings.t('jobs.1_diner', (g.name or strings.t('jobs.gas_station'))), x = c.x, y = c.y, z = c.z,
      radius = math.min(30, math.max(STOP_RADIUS, (tonumber(r) or 0) + 6)) } end
  end
  return out
end

-- the valet stands (the map's places of kind "valet": a kerb drop-off and parking bays)
local function valetStands()
  local out = {}
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier() or ''
  for _, f in ipairs(FS:findFiles('/street_legal/places/', '*.json', 0, false, false) or {}) do
    local d = jsonReadFile(f)
    for _, p in ipairs(type(d) == 'table' and type(d[level]) == 'table' and d[level].places or {}) do
      if p.kind == 'valet' and type(p.pos) == 'table' and type(p.bays) == 'table' and #p.bays > 0 then out[#out + 1] = p end
    end
  end
  return out
end

local STREETS = { strings.t('jobs.a_side_street'), strings.t('jobs.an_apartment_block'), strings.t('jobs.a_house_on_the_corner'), strings.t('jobs.an_office'), strings.t('jobs.a_back_street'), strings.t('jobs.a_corner_shop') }

-- the kinds of job: { kind, title, unlock = rep, night = true (only after dark), offer = function(ctx, rng) -> job }
-- a job is { item, legs = { stop, stop... }, pay, seconds, fragile }
local splitphase = require('sl/core/splitphase')
local TYPES = {
  { kind = 'part', title = strings.t('jobs.part_run'), unlock = 0, offer = function(ctx, rng)
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
  { kind = 'food', title = strings.t('jobs.food_delivery'), unlock = 0, night = true, offer = function(ctx, rng)
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
      return { item = strings.t('jobs.three_orders'), legs = legs, metres = math.floor(metres), fragile = false,
        seconds = math.max(180, math.floor(metres * 1.4 / jobsLib.SPEED * 1.2)), pay = 120 + math.floor(metres / 1000 * 60 / 10) * 10 }
    end },
  -- taxi fares: a fare at the kerb, to one of the city's places
  { kind = 'taxi', title = strings.t('jobs.taxi_fare'), unlock = 0, offer = function(ctx, rng)
      local k = kerbNear(ctx, rng, nil, 0, 0)
      if not k or #ctx.places == 0 then return nil end
      local to = ctx.places[rng:int(#ctx.places)]
      local metres = math.sqrt((to.x - k.x) ^ 2 + (to.y - k.y) ^ 2)
      if metres < 600 then return nil end
      return { item = strings.t('jobs.a_fare'), legs = { { id = 'kerb', name = STREETS[rng:int(#STREETS)], x = k.x, y = k.y, z = k.z }, leg(to) }, metres = math.floor(metres),
        fragile = false, comfort = true, passenger = true, seconds = math.max(120, math.floor(metres * 1.4 / jobsLib.SPEED * 1.3)), pay = math.max(60, math.floor((40 + metres / 1000 * 90) / 10) * 10) }
    end },
  -- the junkyard's crushing run: a wreck that barely goes, to the crusher at the scrapyard
  { kind = 'crush', title = strings.t('jobs.crushing_run'), unlock = 0, offer = function(ctx, rng)
      local from, to = ctx.byId.junkyard, ctx.byId.scrapyard
      if not from or not to then return nil end
      local metres = jobsLib.distance(from, to)
      return { item = 'wreck', legs = { leg(from), leg(to) }, metres = math.floor(metres), fragile = false,
        car = { model = ({ 'covet', 'pessima', 'legran', 'midsize' })[rng:int(4)], wear = 0.9 },
        seconds = math.max(240, math.floor(metres * 1.4 / 9 * 1.5)), pay = 250 }
    end },
  -- car transport: a car between the dealer and the lots, without a scratch (fragile: over 5 % damage pays nothing)
  { kind = 'transport', title = strings.t('jobs.car_transport'), unlock = 200, offer = function(ctx, rng)
      local ends = { ctx.byId.dealer, ctx.byId.junkyard, ctx.byId.scrapyard }
      local a, b = ends[rng:int(3)], ends[rng:int(3)]
      if not a or not b or a.id == b.id then return nil end
      local metres = jobsLib.distance(a, b)
      local model = ({ 'vivace', 'sunburst2', 'etk800', 'bastion', 'scintilla' })[rng:int(5)]
      return { item = strings.t('jobs.1_for_the_2', (model), (b.name)), legs = { leg(a), leg(b) }, metres = math.floor(metres), fragile = true,
        car = { model = model, wear = 0.05 },
        seconds = math.max(180, math.floor(metres * 1.4 / jobsLib.SPEED * 1.4)), pay = 300 + math.floor(metres / 1000 * 120 / 10) * 10 }
    end },
  -- the hot car: from a back street to a lock-up, and the police hear more of it every minute (heat)
  { kind = 'hot', title = strings.t('jobs.hot_car'), unlock = 1000, night = true, offer = function(ctx, rng)
      local k = kerbNear(ctx, rng, nil, 0, 0)
      local to = ctx.byId.meet_tuning or ctx.byId.scrapyard
      if not k or not to then return nil end
      local metres = math.sqrt((to.x - k.x) ^ 2 + (to.y - k.y) ^ 2)
      if metres < 1000 then return nil end
      return { item = strings.t('jobs.hot_car_2'), legs = { { id = 'kerb', name = strings.t('jobs.a_back_street'), x = k.x, y = k.y, z = k.z }, leg(to) }, metres = math.floor(metres),
        fragile = false, heat = 0.4, car = { model = ({ 'scintilla', 'sbr', 'bolide', 'etkc' })[rng:int(4)], wear = 0.1 },
        seconds = math.max(240, math.floor(metres * 1.4 / jobsLib.SPEED * 1.3)), pay = 400 + math.floor(metres / 1000 * 220 / 100) * 100 }   -- keep in step with economy_sim's hot_base/hot_per_km (H5: ≤ 2x median $/min)
    end },
  -- test driver: a prototype round the test track's oval against the clock, without a scratch
  { kind = 'testdrive', title = strings.t('jobs.test_driver'), unlock = 600, offer = function(ctx, rng)
      if not sl_career.has('testdrive') then return nil end
      local rl = jsonReadFile('/levels/' .. sl_career.LEVEL .. '/racelines/tt_oval.json')
      local pts = type(rl) == 'table' and rl.points or {}
      if #pts < 8 then return nil end
      local n = #pts
      local function at(i) local q = pts[i] return { id = 'oval', name = strings.t('jobs.the_oval'), x = q[1], y = q[2], z = q[3] } end
      local legs = { at(1) }
      for k = 1, 4 do local stop = at(math.floor(n * k / 4) % n + 1) stop.through = true legs[#legs + 1] = stop end
      legs[#legs].name = strings.t('jobs.the_line')
      local metres, t = 0, 0
      for i = 2, n do
        local a, b = pts[i - 1], pts[i]
        local d = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
        metres, t = metres + d, t + d / math.max(5, ((a[4] or 30) + (b[4] or 30)) / 2)
      end
      local slack = rng:range(1.15, 1.35)                   -- the faster the target, the better the pay
      return { item = 'prototype', legs = legs, metres = math.floor(metres), fragile = true, car = { model = 'scintilla', wear = 0 },
        seconds = math.floor(t * slack + 30), pay = math.floor((1200 - (slack - 1.15) * 3000) / 50) * 50 }
    end },
  -- recovery (Design 3 #6, first version): a stranded motorist's car at the kerb, limping, to the nearest club garage
  { kind = 'recovery', title = 'Recovery', unlock = 300, offer = function(ctx, rng)
      local k = kerbNear(ctx, rng, nil, 0, 0)
      if not k then return nil end
      local best, bd
      for _, p in ipairs(ctx.places) do
        if p.kind == 'garage' then
          local d = math.sqrt((p.x - k.x) ^ 2 + (p.y - k.y) ^ 2)
          if not bd or d < bd then best, bd = p, d end
        end
      end
      if not best or bd < 500 then return nil end
      return { item = strings.t('jobs.broken_down_car'), legs = { { id = 'kerb', name = STREETS[rng:int(#STREETS)], x = k.x, y = k.y, z = k.z }, leg(best) }, metres = math.floor(bd),
        fragile = false, car = { model = ({ 'pessima', 'legran', 'midsize', 'fullsize', 'van' })[rng:int(5)], wear = 0.7, limp = 0.35 },
        seconds = math.max(300, math.floor(bd * 1.4 / 8 * 1.5)), pay = math.floor((200 + bd / 1000 * 150) / 10) * 10 }
    end },
  -- valet (Design 3 #11): a guest's car at the hotel's kerb, parked neatly in one of the bays
  { kind = 'valet', title = 'Valet', unlock = 300, night = true, offer = function(ctx, rng)
      local list = valetStands()
      if #list == 0 then return nil end
      local v = list[rng:int(#list)]
      local bay = v.bays[rng:int(#v.bays)]
      return { item = strings.t('jobs.guest_car'), legs = { { id = v.id, name = v.name, x = v.pos[1], y = v.pos[2], z = v.pos[3] },
          { id = v.id .. ':bay', name = strings.t('jobs.a_parking_bay'), x = bay[1], y = bay[2], z = bay[3], radius = 3 } },
        metres = 60, fragile = true, car = { model = ({ 'etk800', 'bastion', 'sunburst2', 'vivace', 'scintilla' })[rng:int(5)], wear = 0.02 },
        seconds = 90, pay = 40 + rng:int(4) * 10 }
    end },
  -- parts run from the scrapyard (or a parts shop) to a garage across town; the load is fragile
  { kind = 'scrapparts', title = strings.t('jobs.scrapyard_parts'), unlock = 0, offer = function(ctx, rng)
      local froms = { ctx.byId.scrapyard }
      for _, sh in ipairs(ctx.shops) do froms[#froms + 1] = sh end
      local from = froms[rng:int(#froms)]
      local tos = {}
      for _, p in ipairs(ctx.places) do if from and p.kind == 'garage' and p.id ~= from.id and jobsLib.distance(p, from) >= 1200 then tos[#tos + 1] = p end end
      if not from or #tos == 0 then return nil end
      local to = tos[rng:int(#tos)]
      local metres = jobsLib.distance(from, to)
      return { item = jobsLib.PART_ITEMS[rng:int(#jobsLib.PART_ITEMS)], legs = { leg(from), leg(to) }, metres = math.floor(metres), fragile = true,
        seconds = math.max(jobsLib.MIN_SECONDS, math.floor(metres * 1.4 / jobsLib.SPEED * jobsLib.SLACK)),
        pay = math.floor(math.max(jobsLib.MIN_PAY, metres / 1000 * jobsLib.PAY_PER_KM * jobsLib.FRAGILE_BONUS) / 10 + 0.5) * 10 }
    end },
  -- tow job: a dead car at the kerb, to a garage behind your own car on the game's tow coupler (the clock and the damage are the towed car's)
  { kind = 'tow', title = strings.t('jobs.tow_job'), unlock = 300, offer = function(ctx, rng)
      local k = kerbNear(ctx, rng, nil, 0, 0)
      if not k then return nil end
      local tos = {}
      for _, p in ipairs(ctx.places) do if p.kind == 'garage' and math.sqrt((p.x - k.x) ^ 2 + (p.y - k.y) ^ 2) >= 600 then tos[#tos + 1] = p end end
      if #tos == 0 then return nil end
      local to = tos[rng:int(#tos)]
      local metres = math.sqrt((to.x - k.x) ^ 2 + (to.y - k.y) ^ 2)
      local stop = leg(to)
      stop.radius = 14
      return { item = strings.t('jobs.dead_car'), legs = { { id = 'kerb', name = STREETS[rng:int(#STREETS)], x = k.x, y = k.y, z = k.z, radius = 14 }, stop }, metres = math.floor(metres),
        fragile = false, tow = true, hint = strings.t('jobs.hook_it_up'),
        car = { model = ({ 'pessima', 'legran', 'midsize', 'fullsize', 'van' })[rng:int(5)], wear = 0.5, limp = 0 },
        seconds = math.max(360, math.floor(metres * 1.4 / 6 * 1.5)), pay = math.floor((240 + metres / 1000 * 180) / 10) * 10 }
    end },
  -- a new car from the dealer to the customer's door: any scratch (Car Surface FX) or dent and it pays nothing
  { kind = 'dealerdrive', title = strings.t('jobs.dealer_delivery'), unlock = 200, offer = function(ctx, rng)
      local from = ctx.byId.dealer
      local k = from and kerbNear(ctx, rng, from, 800, 3000)
      if not k then return nil end
      local metres = math.sqrt((k.x - from.x) ^ 2 + (k.y - from.y) ^ 2)
      local model = ({ 'vivace', 'sunburst2', 'etk800', 'bastion', 'scintilla' })[rng:int(5)]
      return { item = strings.t('jobs.new_1_for_a_customer', model), legs = { leg(from), { id = 'kerb', name = strings.t('jobs.the_customer_s_door'), x = k.x, y = k.y, z = k.z } },
        metres = math.floor(metres), fragile = true, scratchCheck = true, car = { model = model, wear = 0 },
        seconds = math.max(180, math.floor(metres * 1.4 / jobsLib.SPEED * 1.4)), pay = 320 + math.floor(metres / 1000 * 120 / 10) * 10 }
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
  local phase = sl_career.phase() or 'day'
  local night = phase == 'night'
  local key = s.day .. (night and 'n' or 'd')
  if js.board == key and not force then return end
  js.board = key
  local ctx = context(s)
  local rng = rngLib.new(rngLib.hash('jobs:' .. key .. ':' .. tostring(s.seed)))
  local open = {}
  for _, t in ipairs(TYPES) do
    if (s.rep or 0) >= (t.unlock or 0) and splitphase.available('jobs', t.kind, phase) then open[#open + 1] = t end
  end
  -- offers that came by text (a favour, moving your cars) stay until taken
  local kept = {}
  for _, j in ipairs(js.offers or {}) do if j.kind == 'move' or j.kind == 'errand' then kept[#kept + 1] = j end end
  js.offers = kept
  for i = 1, OFFERS * 2 do
    if #js.offers >= OFFERS + #kept or #open == 0 then break end
    local t = open[(i - 1) % #open + 1]
    local ok, j = pcall(t.offer, ctx, rng)
    if ok and j and j.legs and #j.legs >= 2 then
      j.id, j.kind, j.title = key .. ':' .. i, t.kind, t.title
      if not t.night and j.pay then j.pay = math.floor(j.pay * jobsLib.DAY_PAY / 10 + 0.5) * 10 end
      js.offers[#js.offers + 1] = j
    end
  end
  -- contracts: a few of the part runs and courier parcels come with terms and pay more when they are kept
  if require('sl/core/features').on('contracts') and (s.rep or 0) >= contractLib.MIN_REP then
    local crng = rngLib.new(rngLib.hash('contracts:' .. key .. ':' .. tostring(s.seed)))
    local wet = sl_weather and sl_weather.wetness and (sl_weather.wetness() or 0) >= 0.3
    local made = 0
    for _, j in ipairs(js.offers) do
      if made >= contractLib.COUNT then break end
      if (j.kind == 'part' or j.kind == 'courier') and not j.contract and crng:chance(0.5) and contractLib.apply(j, contractLib.pick(crng, wet)) then
        j.title = strings.t('contract.title', j.title)
        made = made + 1
      end
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
  local v = playerCarId()
  if v and j.needCar and sl_fleet.carOfVehicle(v:getID()) ~= j.needCar then return nil end      -- (the job is for that car)
  return v
end

local function spawnJobCar(j, stop)
  local ok, veh = pcall(core_vehicles.spawnNewVehicle, j.car.model, { config = j.car.config, pos = vec3(stop.x, stop.y, (stop.z or 0) + 0.5),
    autoEnterVehicle = false, canSpawnAnotherVehicleCheck = false })
  if not ok or not veh then
    j.spawnError = tostring(ok and strings.t('jobs.no_vehicle') or veh)                 -- (kept on the job: the smoke test reports it; B34)
    log('W', 'sl_jobs', 'the job car (' .. tostring(j.car.model) .. ') did not spawn: ' .. j.spawnError)
    return nil
  end
  if j.car.wear then veh:queueLuaCommand(string.format('partCondition.initConditions(nil, %d, %f, %f)', math.floor(j.car.wear * 300000000), 1 - j.car.wear * 0.5, 1 - j.car.wear)) end
  if slrrDrivers and slrrDrivers.setDriver then slrrDrivers.setDriver(veh:getID(), nil) end
  -- a breakdown: the engine down to limp power, a tyre going down
  if j.car.limp then
    veh:queueLuaCommand(string.format('local e = powertrain.getDevice("mainEngine") if e then e.outputTorqueState = %f end ' ..
      'for id, w in pairs(v.data.wheels or {}) do if w.name == "FR" and beamstate.deflateTire then beamstate.deflateTire(id) end end', j.car.limp))
  end
  return veh
end

local function routeTo(stop)
  if core_groundMarkers and stop then core_groundMarkers.setPath(vec3(stop.x, stop.y, stop.z or 0)) end
end

function M.take(jobId)
  local s = career()
  if not s then return false, strings.t('bank.no_career_running') end
  local js = jobsState(s)
  if js.active then return false, strings.t('classifieds.finish_the_job_you_are') end
  if sl_hospital and not sl_hospital.canDrive() then return false, strings.t('jobs.not_with_those_injuries_rest') end
  if sl_streets and sl_streets.isRacing and sl_streets.isRacing() then return false, strings.t('jobs.not_in_the_middle_of') end
  for i, j in ipairs(js.offers) do
    if j.id == jobId then
      if not j.car and not playerCarId() then return false, strings.t('jobs.you_need_to_be_in') end
      if j.needCar and sl_fleet.carOfVehicle(playerCarId():getID()) ~= j.needCar then return false, strings.t('jobs.that_job_is_for_your', (j.item or strings.t('wwjobs.other_car'))) end
      table.remove(js.offers, i)
      j.leg = 1
      js.active = j
      M.passengerAt(j)
      routeTo(j.legs[1])
      extensions.hook('onStreetLegalChanged')
      return true, string.format('%s: go to %s.', j.title, j.legs[1].name)
    end
  end
  return false, strings.t('jobs.that_job_has_gone')
end

function M.giveUp()
  local s = career()
  local js = s and jobsState(s)
  if not js or not js.active then return false, strings.t('jobs.you_are_not_on_a') end
  local j = js.active
  if j.car and j.carVid then
    if gameplay_walk and not j.tow then gameplay_walk.setWalkingMode(true, nil, nil, true) end
    local veh = getObjectByID(j.carVid)
    if veh then veh:delete() end
  end
  M.dropPassenger(j)
  js.active = nil
  stateLib.addRep(s, -5)
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('jobs.job_dropped_word_gets_round')
end

-- the first hour: "new in town" doubles job pay, tapering to nothing at 150 rep, and ends the moment
-- the first part is bought in Wrench Works; the first two jobs of each kind pay a bonus (balance pass)
local NEW_IN_TOWN_REP, FIRST_TIMES, FIRST_BONUS = 150, 2, 150
local function boost(s, js)
  if js.upgraded then return 1 end
  return 1 + math.max(0, 1 - (s.rep or 0) / NEW_IN_TOWN_REP)
end
M.boost = function() local s = career() return s and boost(s, jobsState(s)) or 1 end

function M.onWrenchWorksPartBought(vid, slotPath, part, price)
  local s = career()
  if not s or not (sl_fleet and sl_fleet.carOfVehicle and sl_fleet.carOfVehicle(vid)) then return end
  local js = jobsState(s)
  if not js.upgraded then
    js.upgraded = true
    sl_career.sendText('benny', strings.t('jobs.first_upgrade_on_the_car'), 3)
  end
end

-- a job's pay with the new-in-town boost and the first-times bonus (the phone shows offers the same way)
function M.bonusPay(s, js, j, pay)
  if pay <= 0 then return pay end
  js.kindDone = js.kindDone or {}
  local n = (js.kindDone[j.kind] or 0) + 1
  js.kindDone[j.kind] = n
  return math.floor(pay * boost(s, js) / 10) * 10 + (n <= FIRST_TIMES and FIRST_BONUS or 0)
end

-- a job called off before it was done (no pay, no rep, not counted as done)
function M.cancel(s, js, j, text)
  M.dropPassenger(j)
  js.active = nil
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  if text then toast(text) end
  extensions.hook('onStreetLegalChanged')
end

-- the end of any job: pay (the one money path), rep, the record, the text. Jobs settled elsewhere (settle = 'ww':
-- Wrench Works' repair, tune and salvage jobs in sl_wwjobs) end here too
function M.finishWith(s, js, j, pay, rep, text)
  js.active = nil
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  if pay > 0 and sl_perks then pay = math.floor(pay * (sl_perks.factor('jobs') or 1) / 10 + 0.5) * 10 end      -- (tier perks)
  if pay > 0 and sl_crews then pay = math.floor(pay * sl_crews.perksHere().pay / 10 + 0.5) * 10 end   -- (+10 % ending in one of your districts)
  if pay > 0 then sl_career.payOut(pay, j.title .. ': ' .. (j.item or 'delivery')) end
  stateLib.addRep(s, rep)
  js.done, js.earned = js.done + 1, js.earned + pay
  toast(text)
  extensions.hook('onStreetLegalChanged')
end

local function finish(s, js, j, v)
  local elapsed = j.startedAt and (os.clock() - j.startedAt) or 0
  local d0, d1 = j.damage0 or 0, damageOf(v:getID())
  local damage = math.max(0, math.min(1, ((d1 or 0) - d0) / DAMAGE_FULL))
  if j.scratchCheck and j.carVid and sl_surfacefx then       -- (Car Surface FX: a new scratch on the paint counts as a wrecked load)
    local l = sl_surfacefx.level(j.carVid)
    if l and (tonumber(l.scratches) or 0) > (j.scratches0 or 0) + 0.001 then damage = 1 end
  end
  local kept
  if j.contract then          -- the terms are checked at the drop; missed (or the part switched off since): the normal pay
    local car = sl_fleet and sl_fleet.currentCar and sl_fleet.currentCar()
    kept = require('sl/core/features').on('contracts') and contractLib.met(j.contract.req, { damage = damage, elapsed = elapsed, seconds = j.seconds,
      wet = sl_weather and sl_weather.wetness and (sl_weather.wetness() or 0) >= 0.3 or false, carValue = car and car.value })
    if not kept then j.pay = j.basePay or j.pay end
  end
  local pay, verdict = jobsLib.settle(j, elapsed, damage)
  pay = M.bonusPay(s, js, j, pay)
  local tip = 0
  if j.comfort and pay > 0 and j.ride then
    tip = jobsLib.tip(pay, jobsLib.comfortScore(j.ride))
    pay = pay + tip
  end
  if j.car and j.carVid then
    local id = j.carVid
    local tow = j.tow
    core_jobsystem.create(function(job)
      if gameplay_walk and not tow then gameplay_walk.setWalkingMode(true, nil, nil, true) end
      job.sleep(1)
      local veh = getObjectByID(id)
      if veh then veh:delete() end
    end)
  end
  if j.heat then s.heat = math.max(0, (s.heat or 0) - j.heat) end
  M.finishWith(s, js, j, pay, verdict == 'broken' and -5 or (verdict == 'late' and 4 or (j.kind == 'errand' and 15 or 10)),
    verdict == 'broken' and string.format(strings.t('jobs.the_s_is_broken_no'), j.item or 'load')
    or string.format(strings.t('jobs.s_delivered_s_d'), j.item or 'Delivery', verdict == 'late' and strings.t('jobs.late') or '', pay)
      .. (tip > 0 and ' ' .. string.format(strings.t('jobs.tip_d_for_a_smooth_ride'), tip) or ''))
  if j.contract and pay > 0 then
    if kept then stateLib.addRep(s, contractLib.BONUS_REP) toast(strings.t('contract.kept', contractLib.label(j.contract.req), pay))
    else toast(strings.t('contract.missed', contractLib.label(j.contract.req), pay)) end
  end
end

-- passengers (taxi fares): a walker waits at the first stop and is gone when you pull up; during the ride the car's pushes are counted
local walkerList
function M.passengerAt(j)
  if not j.passenger or not (slrrPedestrians and slrrPedestrians.playActor) then return end
  if not walkerList then
    walkerList = {}
    for _, d in ipairs(slrrDrivers and slrrDrivers.getDrivers and slrrDrivers.getDrivers() or {}) do
      local did = type(d) == 'table' and d.id or d
      if type(did) == 'string' and FS:directoryExists('/art/slrr_drivers/' .. did .. '/walker/') then walkerList[#walkerList + 1] = did end
    end
  end
  if #walkerList == 0 then return end
  local stop = j.legs[1]
  j.actor = slrrPedestrians.playActor('/art/slrr_drivers/' .. walkerList[math.random(#walkerList)] .. '/walker/', { vec3(stop.x, stop.y, stop.z or 0) })
end
function M.dropPassenger(j)
  if j and j.actor and slrrPedestrians and slrrPedestrians.stopActor then slrrPedestrians.stopActor(j.actor) end
  if j then j.actor = nil end
end

local ridePrev = 0
local function sampleRide(j, dtReal)
  local v = getPlayerVehicle(0)
  if not (j.comfort and j.ride and j.leg >= 2 and v) then return end
  ridePrev = ridePrev + dtReal
  if ridePrev < 0.1 then return end
  local vel = v:getVelocity()
  jobsLib.comfortStep(j.ride, ridePrev, vel.x, vel.y, vel.z)
  ridePrev = 0
end

local timer, pinSig = 0, nil
function M.onUpdate(dtReal)
  local s = career()
  if not s then return end
  local act = jobsState(s).active
  if act then sampleRide(act, dtReal) end
  timer = timer + dtReal
  if timer < 0.5 then return end
  timer = 0
  refresh(s)
  -- the big map lists the job stops it was last built with: a new offer, a taken job or the next leg asks for a rebuild
  local sig = {}
  for _, p in ipairs(M.pins()) do sig[#sig + 1] = p.id .. ':' .. math.floor(p.x) .. ',' .. math.floor(p.y) end
  sig = table.concat(sig, ';')
  if sig ~= pinSig then
    pinSig = sig
    if sl_pois and sl_pois.refresh then sl_pois.refresh() end
  end
  local js = jobsState(s)
  local j = js.active
  if not j or (j.settle and not j.car) then return end    -- (settle: it ends somewhere else; a car job still picks up its car)
  local v = (j.car and j.leg == 1) and getPlayerVehicle(0) or jobVehicle(j)
  if not v then return end
  if j.car and j.carVid then askDamage(v) end
  if j.heat and j.startedAt then s.heat = math.min(1, (s.heat or 0) + j.heat / 120) end    -- a hot car: the police hear more of it every second
  local stop = j.legs[j.leg]
  local here = v:getPosition()
  -- how far from the stop along the ground: a stop's z is recorded data (a raceline, a kerb node) and the car
  -- stands on whatever the surface is now, so height counts only when it is far off (under a bridge, a floor up)
  local dz = stop.z and math.abs(here.z - stop.z) or 0
  local d = dz < 12 and math.sqrt((here.x - stop.x) ^ 2 + (here.y - stop.y) ^ 2) or math.huge
  if (stop.through and d < 15) or (d < (stop.radius or STOP_RADIUS) and v:getVelocity():length() < 2) then
    if j.leg == 1 then
      if j.car then
        local veh = spawnJobCar(j, stop)
        if not veh then return end
        j.carVid = veh:getID()
        if not j.tow and gameplay_walk and gameplay_walk.getInVehicle then gameplay_walk.getInVehicle(veh) end      -- (a tow job stays in your own car)
        v = veh
        if j.scratchCheck and sl_surfacefx then j.scratches0 = (sl_surfacefx.level(veh:getID()) or {}).scratches or 0 end
      end
      M.dropPassenger(j)
      if j.comfort then j.ride = jobsLib.comfortNew() end
      if j.hint then toast(j.hint) end
      j.startedAt = os.clock()
      j.damage0 = damageOf(v:getID())
      toast(string.format(strings.t('jobs.picked_up_the_s_s'), j.item or 'load', j.fragile and ' (fragile)' or '', math.floor(j.seconds / 60), j.seconds % 60, j.legs[2].name))
    end
    if j.leg >= #j.legs then if not j.settle then finish(s, js, j, v) end return end
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
    sl_career.payOut(bonus, strings.t('jobs.flip_bonus_1', (car.name or 'car')))
    stateLib.addRep(s, 25)
    sl_career.sendText('benny', string.format(strings.t('jobs.the_junkyard_owner_says_you'),
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
    sl_career.payOut(t[2], strings.t('jobs.1_target_2_3', (what), (t[1]), (unit)))
    stateLib.addRep(s, 15)
    paid = paid + t[2]
    js[key] = js[key] + 1
  end
  if paid > 0 then toast(string.format(strings.t('jobs.s_s_s_beats_the'), what, tostring(value), unit, paid)) end
end

-- the quarter mile: a drag race's time down the test track's 1/4 mile
function M.onSlrrRaceFinished(r)
  local s = career()
  if not s or type(r) ~= 'table' or r.abandoned or type(r.time) ~= 'number' or r.time <= 0 then return end
  local quarter
  for _, x in ipairs(sl_career.racesList() or {}) do
    if x.drag and (x.id == r.raceId or (r.missionId and x.missionId == r.missionId)) and tostring(x.name):find('1/4', 1, true) then quarter = true end
  end
  if quarter then challenge(s, 'quarter', QUARTER, math.floor(r.time * 100) / 100, function(v, t) return v <= t end, ' s', strings.t('jobs.quarter_mile')) end
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

local SPONSORS = { { rep = 1500, name = strings.t('jobs.valo_tyre_wheel'), weekly = 500 }, { rep = 3000, name = strings.t('jobs.redline_speed_shop'), weekly = 1500 },
  { rep = 6000, name = strings.t('jobs.nightrun_energy'), weekly = 5000 } }
local CREW = { strings.t('crews.the_southside_kings'), strings.t('crews.riverbed_runners'), strings.t('crews.the_north_end_crew'), strings.t('crews.ring_road_ghosts') }

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
      sl_career.payOut(c.pay, strings.t('jobs.crew_contract_1', (c.boss)))
      stateLib.addRep(s, 30)
      sl_career.sendText('benny', string.format(strings.t('jobs.word_from_s_contract_done'), c.boss, c.pay), 3)
    end
  end
end

-- (both the map's races and Street Legal's own say so: won, the opponent's name, their racer id)
function M.onStreetLegalRaceResult(won, opponent, racerId)
  local s = career()
  if s and won then countWin(s, racerId) end
  -- a racer you have just beaten sometimes asks a favour (Design 3 #17): fetch them a part to their meet spot
  local r = s and won and racerId and stateLib.racer(s, racerId)
  if not r then return end
  local rng = rngLib.new(rngLib.hash('errand:' .. racerId .. ':' .. s.day .. ':' .. tostring(#(s.ledger or {}))))
  if not rng:chance(0.3) then return end
  local ctx = context(s)
  local meets = {}
  for _, p in ipairs(ctx.places) do if p.kind == 'meet' then meets[#meets + 1] = p end end
  if #ctx.shops == 0 or #meets == 0 then return end
  local shop, meet = ctx.shops[rng:int(#ctx.shops)], meets[rng:int(#meets)]
  local j = jobsLib.make('part', shop, meet, rng)
  j.legs, j.title, j.kind, j.id = { leg(shop), leg(meet) }, strings.t('jobs.favour_for_1', (r.name or strings.t('carcare.a_racer'))), 'errand', 'errand:' .. racerId .. ':' .. s.day
  j.pay = math.floor(j.pay * 0.5 / 10) * 10
  local js = jobsState(s)
  js.offers[#js.offers + 1] = j
  sl_career.sendText(racerId, string.format(strings.t('jobs.fair_race_do_me_a'),
    j.item, shop.name, meet.name), 60)
end

function M.onStreetLegalNewDay(day)
  local s = career()
  if not s then return end
  local js = jobsState(s)
  -- the crew contract: a new one when the last is done or has run out (from 300 rep)
  if (s.rep or 0) >= 300 and (not js.crew or js.crew.done or day > js.crew.untilDay) then
    newContract(s, js)
    sl_career.sendText('benny', string.format(strings.t('jobs.s_want_somebody_to_beat'),
      js.crew.boss, js.crew.need, js.crew.tier, js.crew.pay), 5)
  end
  -- sponsors: the best one your name gets you; paid weekly, as long as you win two races a week
  local best
  if require('sl/core/features').on('sponsors') and sl_sponsor then
    js.sponsor = nil          -- (the brand sponsorships of sl_sponsor take over: one system)
  else
  for _, sp in ipairs(SPONSORS) do if (s.rep or 0) >= sp.rep then best = sp end end
  end
  if best and (not js.sponsor or js.sponsor.name ~= best.name) then
    js.sponsor = { name = best.name, weekly = best.weekly, since = day }
    js.weekWins = 0
    sl_career.sendText('benny', string.format(strings.t('jobs.s_want_their_name_on'), best.name, best.weekly), 4)
  elseif js.sponsor and (day - js.sponsor.since) % 7 == 0 and day ~= js.sponsor.since then
    if (js.weekWins or 0) >= 2 then
      sl_career.payOut(js.sponsor.weekly, strings.t('jobs.sponsor_1', (js.sponsor.name)))
    else
      sl_career.sendText('benny', strings.t('jobs.1_saw_you_did_not', (js.sponsor.name)), 3)
    end
    js.weekWins = 0
  end
end

----------------------------------------------------------------------------------------------
-- moving garage (Design 3 #18): drive each of your cars over yourself and get 5 % of the move back for each

function M.onStreetLegalGarageMoved(fromLevel, toLevel, cost)
  local s = career()
  if not s then return end
  local ctx = context(s)
  local from, to = ctx.byId[(progression.garages[fromLevel] or {}).site], ctx.byId[(progression.garages[toLevel] or {}).site]
  if not from or not to then return end
  local js = jobsState(s)
  for _, car in ipairs(s.cars) do
    if not car.impounded then
      js.offers[#js.offers + 1] = { id = 'move:' .. car.id .. ':' .. s.day, kind = 'move', title = 'Moving', item = car.name, needCar = car.id,
        legs = { leg(from), leg(to) }, metres = math.floor(jobsLib.distance(from, to)), fragile = false, seconds = 3600,
        pay = math.floor((cost or 0) * 0.05 / 10) * 10 }
    end
  end
  extensions.hook('onStreetLegalChanged')
end

-- for the phone
function M.summary()
  local s = career()
  if not s then return nil end
  refresh(s)
  local js = jobsState(s)
  local out = { offers = {}, done = js.done, earned = js.earned, boost = boost(s, js), flip = js.flip or { target = FLIP_FIRST, best = 0, flips = 0 },
    quarter = QUARTER[js.quarter or 1] and QUARTER[js.quarter or 1][1] or nil, dyno = DYNO[js.dyno or 1] and DYNO[js.dyno or 1][1] or nil,
    crew = js.crew and not js.crew.done and { boss = js.crew.boss, tier = js.crew.tier, need = js.crew.need, won = js.crew.won, daysLeft = js.crew.untilDay - s.day, pay = js.crew.pay } or nil,
    sponsor = (sl_sponsor and sl_sponsor.current and sl_sponsor.current()) or (js.sponsor and { name = js.sponsor.name, weekly = js.sponsor.weekly, weekWins = js.weekWins or 0 }) or nil }
  for _, j in ipairs(js.offers) do
    out.offers[#out.offers + 1] = { id = j.id, title = j.title, item = j.item, from = j.legs[1].name, to = j.legs[#j.legs].name,
      pay = math.floor(j.pay * boost(s, js) / 10) * 10 + (((js.kindDone or {})[j.kind] or 0) < FIRST_TIMES and FIRST_BONUS or 0), seconds = j.seconds, fragile = j.fragile, metres = j.metres,
      contract = j.contract and { req = j.contract.req, label = contractLib.label(j.contract.req), mult = j.contract.mult, basePay = j.basePay } or nil }
  end
  local a = js.active
  if a then
    out.active = { title = a.title, item = a.item, next = a.legs[a.leg].name, to = a.legs[#a.legs].name, pay = a.pay, fragile = a.fragile,
      timeLeft = a.startedAt and (a.seconds or 0) > 0 and math.floor(a.seconds - (os.clock() - a.startedAt)) or nil,
      contract = a.contract and { req = a.contract.req, label = contractLib.label(a.contract.req), mult = a.contract.mult } or nil }
  end
  return out
end

-- the map's pins for jobs: the stop you are heading for, and where each job on the board starts (legs are { id, name, x, y, z })
function M.pins()
  local s = career()
  if not s then return {} end
  local js = jobsState(s)
  local out = {}
  local a = js.active
  if a and a.legs[a.leg] then
    local l = a.legs[a.leg]
    out[#out + 1] = { id = 'job_active', name = l.name, x = l.x, y = l.y, z = l.z, active = true }
  end
  for _, j in ipairs(js.offers or {}) do
    local l = j.legs[1]
    if l and l.x then out[#out + 1] = { id = 'job_' .. tostring(j.id), name = j.title .. ' · ' .. tostring(l.name), x = l.x, y = l.y, z = l.z } end
  end
  return out
end

function M.showWay()
  local s = career()
  local a = s and jobsState(s).active
  if a then routeTo(a.legs[a.leg]) end
end

function M.onStreetLegalStopped()
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  local s = sl_career and sl_career.getState and sl_career.getState()
  local a = s and s.jobs and s.jobs.active
  local veh = a and a.carVid and getObjectByID(a.carVid)
  if veh then veh:delete() end                 -- (a job's car does not outlive the career)
end

-- a job you were on when the game was left (its clock and its car are gone): called off, no penalty
function M.onStreetLegalStarted()
  local s = career()
  local js = s and s.jobs
  if js and js.active then
    js.active = nil
    sl_career.sendText('benny', strings.t('jobs.the_job_you_were_on'), 4)
  end
end

-- (the Mods menu's Parts of the game: with this part off, the hooks above do nothing)
require('sl/core/features').gate('jobs', M)

return M
