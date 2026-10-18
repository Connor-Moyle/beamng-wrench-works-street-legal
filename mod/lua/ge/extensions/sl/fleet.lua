-- Street Legal Racing: the player's cars (extension name: sl_fleet)
-- Every car the player owns is a record in the career save: its full setup, its dents, where
-- it was left. The cars that are out in the world are real vehicles; the rest wait in the
-- garage. From here: a towing service, swapping which car you drive, selling and scrapping,
-- and keeping the records up to date as the cars are driven, modified and bent.

local M = {}

local strings = require('sl/core/strings')

local builder = require('sl/carBuilder')
local carsLib = require('sl/core/cars')
local stateLib = require('sl/core/state')
local progression = require('sl/core/progression')
local market = require('sl/core/market')

local spawned = {}          -- car id -> vehicle id, for cars that are out in the world
local damageWait            -- { id, done } while a car's dents are being read
local snapshotTimer = 0

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

local function carById(s, id)
  for _, c in ipairs(s.cars) do if c.id == id then return c end end
end

function M.vehicleOf(carId)
  local vid = spawned[carId]
  if vid and getObjectByID(vid) then return getObjectByID(vid) end
  spawned[carId] = nil
end

-- which of the player's cars a vehicle is (nil: not theirs)
function M.carOfVehicle(vid)
  for carId, v in pairs(spawned) do if v == vid then return carId end end
end

-- the car the player sits in, if it is one of theirs
function M.currentCar()
  local s, v = career(), getPlayerVehicle(0)
  if not s or not v then return nil end
  local id = M.carOfVehicle(v:getID())
  return id and carById(s, id) or nil
end

----------------------------------------------------------------------------------------------
-- the garage the player has now, and its forecourt

local function garageSite(s)
  local ok, sites = pcall(require, 'slrr/garageSites')
  local wanted = (progression.garages[s.garageLevel] or progression.garages[1]).site
  for _, g in ipairs(ok and sites.getSites() or {}) do
    if g.id == wanted then return g, sites end
  end
end

-- in front of the garage door, facing in: from there you drive in and Wrench Works takes over
function M.forecourt(s, slot)
  local site, sites = garageSite(s)
  if not site then return nil end
  local side = ((slot or 0) % 3 - 1) * 3                -- a second and third car park beside the first
  return sites.point(site, site.doorDist - 4 - math.floor((slot or 0) / 3) * 6, side, 0.6), quatFromDir(site.dir, vec3(0, 0, 1))
end

-- the first forecourt spot (starting at slot `first`, then the others in order) with no vehicle within 4 m; `except` is a vehicle id that does not count (the car being moved).
-- pos, rot, slot; nil when every spot is taken
function M.freeForecourt(s, first, except)
  local forecourt = require('sl/core/forecourt')
  local spots, others = {}, {}
  for i = 0, forecourt.SPOTS - 1 do
    local slot = ((first or 0) + i) % forecourt.SPOTS
    local pos = M.forecourt(s, slot)
    if not pos then return nil end
    spots[#spots + 1] = { x = pos.x, y = pos.y, slot = slot }
  end
  for _, v in ipairs(getAllVehicles()) do
    if v:getID() ~= except then local p = v:getPosition() others[#others + 1] = { x = p.x, y = p.y } end
  end
  local i = forecourt.pick(spots, others)
  if not i then return nil end
  local pos, rot = M.forecourt(s, spots[i].slot)
  return pos, rot, spots[i].slot
end

function M.atGarage(pos, s)
  local site = garageSite(s)
  return site and (pos - site.spot):length() < math.max(30, -site.doorDist + 20)
end

----------------------------------------------------------------------------------------------
-- keeping the records up to date: setup, place, dents

local function placeOf(veh)
  local p, r = veh:getPosition(), quat(veh:getRotation())
  return { pos = { p.x, p.y, p.z + 0.3 }, rot = { r.x, r.y, r.z, r.w } }
end

local fxApplied = {}           -- vehicle id -> true once the car's kept dirt and scratches were put back on it

-- note where every car out in the world is and how it is built (the dents follow, a moment later)
function M.snapshot(withDamage)
  local s = career()
  if not s then return end
  for carId, vid in pairs(spawned) do
    local car, veh = carById(s, carId), getObjectByID(vid)
    if car and veh then
      car.config = builder.configOf(vid) or car.config
      car.where = placeOf(veh)
      if sl_surfacefx and fxApplied[vid] then local fx = sl_surfacefx.save(vid) if fx ~= nil then car.fx = fx or nil end end      -- (Car Surface FX: its dirt and scratches stay with the car when it is put away or the game is saved)
      if withDamage then veh:queueLuaCommand('extensions.load("slrrGarageVeh") if slrrGarageVeh then slrrGarageVeh.capture() end') end
    elseif not veh then
      spawned[carId] = nil
    end
  end
end

-- Wrench Works' vehicle extension reports the dents it found
function M.onWrenchWorksDamage(vid, data)
  local s = career()
  local carId = M.carOfVehicle(vid)
  if not s or not carId then return end
  local car = carById(s, carId)
  if car then
    car.damage = { nodes = data.nodes or {}, beams = data.beams or {}, latches = data.latches }   -- latches: shut doors are shut again
    -- a part that fell off on the road is not part of the car in the garage (A13)
    if type(data.lost) == 'table' and #data.lost > 0 and car.config and car.config.partsTree then
      local before = deepcopy(car.config)                      -- (kept: if the stripped setup will not spawn, the whole one does)
      local gone = carsLib.stripParts(car.config.partsTree, data.lost)
      if #gone > 0 then car.fullConfig = car.fullConfig or before end
      if #gone > 0 then log('I', 'street_legal', 'parts that fell off, taken out of ' .. tostring(car.name) .. ': ' .. table.concat(gone, ' ')) end
    end
    extensions.hook('onStreetLegalChanged')
  end
end

-- repaired in your own garage: what it cost stays with the car (its worth to a buyer goes up with it; core/market)
function M.onWrenchWorksRepaired(vid, cost)
  local s = career()
  local car = s and carById(s, M.carOfVehicle(vid))
  if car and tonumber(cost) then car.repaired = (car.repaired or 0) + tonumber(cost) end
  if car and sl_surfacefx then sl_surfacefx.repair(vid) local fx = sl_surfacefx.save(vid) if fx ~= nil then car.fx = fx or nil end end      -- (the scratches are buffed out with the dents)
end

-- a paint job in the garage: the car is cleaned and unscratched under the new paint
function M.onWrenchWorksPainted(vid)
  local s = career()
  local car = s and carById(s, M.carOfVehicle(vid))
  if car and sl_surfacefx then sl_surfacefx.wash(vid) sl_surfacefx.repair(vid) local fx = sl_surfacefx.save(vid) if fx ~= nil then car.fx = fx or nil end end
end

-- a new part bought for a fault's slot: remembered by price; the fault is put right only once the car drives out
-- with a part in that slot (B25: buying and selling a part back cleared faults for nothing)
function M.onWrenchWorksPartBought(vid, slotPath, part, price)
  local s = career()
  local car = s and carById(s, M.carOfVehicle(vid))
  if not car or not car.faults then return end
  for _, f in ipairs(car.faults) do
    if market.fixes(f, slotPath) then car.partPaid = car.partPaid or {} car.partPaid[f] = tonumber(price) or 0 end
  end
end

-- as a car of yours leaves the garage: a fault whose slot holds a part is fixed (worth what the part cost), one
-- whose slot is empty again is back
function M.onWrenchWorksDriveOut(vid, info)
  local s = career()
  local car = s and carById(s, M.carOfVehicle(vid))
  if not car or not car.faults or #car.faults == 0 or type(info) ~= 'table' or not info.partsTree then return end
  local fitted = market.faultsFitted(info.partsTree, car.faults)
  local fixed = {}
  for _, f in ipairs(car.faults) do
    -- (a part with no price on record, off the shelf or another car, leaves the fault open everywhere: B38)
    if fitted[f] then fixed[f] = (car.partPaid or {})[f] or (car.fixed or {})[f] end
  end
  car.fixed = fixed
  extensions.hook('onStreetLegalChanged')
end

-- the garage put somebody else behind the wheel (SLRR Drivers mod): it stays with the car
function M.onWrenchWorksDriverChanged(vid, driverId)
  local s = career()
  local car = s and carById(s, M.carOfVehicle(vid))
  if car then car.driver = driverId or 'none' extensions.hook('onStreetLegalChanged') end
end

----------------------------------------------------------------------------------------------
-- bringing cars into the world

-- a live vehicle becomes the player's (bought, won): returns the car record
function M.registerVehicle(vid, info)
  local s = career()
  local veh = getObjectByID(vid)
  if not s or not veh then return nil end
  info = info or {}
  local car = stateLib.addCar(s, {
    model = veh:getJBeamFilename(), name = info.name or veh:getJBeamFilename(), brand = info.brand,
    value = info.value or 0, condition = info.condition or 1, faults = info.faults or {}, mileage = info.mileage or 0,
    config = builder.configOf(vid), where = placeOf(veh), boughtFor = info.price, boughtDay = s.day,
  })
  if info.price then car.partsAtBuy = builder.partsValue(vid) end   -- (the sell-back cap: parts added after this count)
  spawned[car.id] = vid
  s.activeCar = car.id
  veh:queueLuaCommand('controller.setFreeze(0) extensions.load("slrrGarageVeh")')
  extensions.hook('onStreetLegalChanged')
  return car
end

-- a car's world vehicle is now `vid` (the lot rebuilt a bought car from its record: the old one is already gone)
function M.adopt(carId, vid)
  local s = career()
  local car = s and carById(s, carId)
  if not car or not getObjectByID(vid) then return false end
  spawned[carId], car.out = vid, true
  extensions.hook('onStreetLegalChanged')
  return true
end

-- the cars that were out in the world when the career was saved come back
function M.restore(job)
  local s = career()
  if not s then return end
  for _, car in ipairs(s.cars) do
    if not M.vehicleOf(car.id) and (car.out ~= false) and (car.id == s.activeCar or car.where) then
      local pos, rot
      if car.where and car.where.pos then
        pos = vec3(car.where.pos[1], car.where.pos[2], car.where.pos[3])
        local r = car.where.rot
        rot = r and quat(r[1], r[2], r[3], r[4]) or nil
      end
      if not pos then pos, rot = M.forecourt(s, 0) end
      if pos then
        local veh = builder.spawnOwned(job, car, pos, rot)
        if veh then spawned[car.id] = veh:getID() end
      end
    end
  end
end

----------------------------------------------------------------------------------------------
-- what the phone's Garage app can do

-- a breakdown truck brings the car to the garage forecourt
function M.tow(carId)
  local s = career()
  local car = s and carById(s, carId)
  if not car then return false, strings.t('carcare.no_such_car') end
  local veh = M.vehicleOf(carId)
  local pos, rot = M.forecourt(s, 0)
  if not pos then return false, strings.t('fleet.your_garage_is_not_on') end
  local from = veh and veh:getPosition() or pos
  if veh and (from - pos):length() < 25 then return false, strings.t('fleet.it_is_at_the_garage') end
  local fee = progression.towFee((from - pos):length())
  if not sl_career.addMoney(-fee, strings.t('fleet.tow_1', (car.name))) then return false, string.format(strings.t('fleet.the_tow_is_d_you'), fee, s.money) end
  -- a real truck comes for a car out on the street (sl_tow); one not spawned is simply brought round
  if veh and sl_tow and sl_tow.send(carId, veh, fee) then return true, string.format(strings.t('fleet.a_tow_truck_is_on'), car.name, fee) end
  M.deliver(carId)
  return true, string.format(strings.t('fleet.the_truck_has_it_d'), fee)
end

-- the car is put on the garage forecourt as it is (the tow's end)
function M.deliver(carId)
  local s = career()
  local car = s and carById(s, carId)
  local veh = M.vehicleOf(carId)
  local pos, rot = M.freeForecourt(s, 0, veh and veh:getID())      -- (not on top of another car; a full forecourt takes the first spot as it did)
  if not pos then pos, rot = M.forecourt(s, 0) end
  if not car or not pos then return end
  core_jobsystem.create(function(job)
    local player = getPlayerVehicle(0)
    if veh and player and player:getID() == veh:getID() and gameplay_walk then
      gameplay_walk.setWalkingMode(true, nil, nil, true)          -- out of the car: it goes on the truck
      job.sleep(0.5)
    end
    if veh then
      spawn.safeTeleport(veh, pos, rot, true, nil, nil, nil, false)     -- (8th: resetVehicle, true by default, would repair it)
    else
      local v = builder.spawnOwned(job, car, pos, rot)
      if v then spawned[car.id] = v:getID()
      else
        -- not built: the car stays in the garage (it was marked out although nothing stood there, and could then neither be put away nor brought out again)
        log('W', 'street_legal', 'deliver: ' .. tostring(car.name) .. ' could not be built; it stays in the garage')
        guihooks.trigger('slPhoneToast', { text = tostring(car.name) .. ' could not be brought out. It is still in the garage.' })
        extensions.hook('onStreetLegalChanged')
        return
      end
    end
    car.out = true
    M.snapshot(false)
    extensions.hook('onStreetLegalChanged')
  end)
end

-- put a car away: its dents are kept, the car leaves the world and waits in the garage (the record stays; nothing is sold). Also for a car
-- left on the street. If you sit in it you get out first.
function M.despawn(carId)
  local s = career()
  local car = s and carById(s, carId)
  if not car then return false, strings.t('carcare.no_such_car') end
  local veh = M.vehicleOf(carId)
  if not veh then return false, strings.t('fleet.the_1_is_in_the', (car.name)) end
  core_jobsystem.create(function(job)
    local player = getPlayerVehicle(0)
    if player and player:getID() == veh:getID() and gameplay_walk then gameplay_walk.setWalkingMode(true, nil, nil, true) job.sleep(0.6) end
    M.snapshot(true)                                              -- its dents too: the car is about to go
    if sl_carcare and sl_carcare.askConditions then sl_carcare.askConditions(veh:getID()) end
    job.sleep(0.5)
    car.out, car.where = false, nil
    veh:delete()
    spawned[carId] = nil
    extensions.hook('onStreetLegalChanged')
  end)
  return true, strings.t('fleet.the_1_is_put_away', (car.name))
end

-- go into the garage with a car of yours (bringing it out front first when it is stored): the Wrench Works garage opens on it
function M.workOn(carId)
  local s = career()
  local car = s and carById(s, carId)
  if not car then return false, strings.t('carcare.no_such_car') end
  if car.impounded then return false, strings.t('fleet.it_is_in_the_police') end
  if not (slrr_garage and slrr_garage.enterWith) then return false, strings.t('classifieds.wrench_works_is_not_running') end
  core_jobsystem.create(function(job)
    if not M.vehicleOf(carId) then
      local ok = M.setActive(carId)
      if not ok then return end
      local t = 0
      while not M.vehicleOf(carId) and t < 20 do job.sleep(0.25) t = t + 0.25 end
      job.sleep(0.5)
    end
    local veh = M.vehicleOf(carId)
    if veh then
      s.activeCar = carId
      local ok, why = slrr_garage.enterWith(veh:getID(), 'work')
      if not ok then guihooks.trigger('slPhoneToast', { text = why or strings.t('career.not_now') }) end
    end
  end)
  return true, strings.t('fleet.the_1_goes_in', (car.name))
end

-- drive another of your cars: it comes out of the garage, the one you had goes in
-- fade, then ask the car to take the player up to five times (a car just built may not on the first call), logging what the player is in
local function seatPlayer(job, veh)
  guihooks.trigger('slFade', { on = true })
  job.sleep(0.5)
  for try = 1, 5 do
    local ok, err = pcall(function() if gameplay_walk and gameplay_walk.getInVehicle then gameplay_walk.getInVehicle(veh) else be:enterVehicle(0, veh) end end)
    job.sleep(0.4)
    local now = be:getPlayerVehicleID(0)
    if now == veh:getID() then break end
    log('W', 'street_legal', string.format('Drive this one: attempt %d, the player is in vehicle %s, wanted %s%s', try, tostring(now), tostring(veh:getID()), ok and '' or (' (error: ' .. tostring(err) .. ')')))
  end
  guihooks.trigger('slFade', { on = false })
end

function M.setActive(carId)
  local s = career()
  local car = s and carById(s, carId)
  if not car then return false, strings.t('carcare.no_such_car') end
  if car.impounded then return false, string.format(strings.t('fleet.it_is_in_the_police_2'), car.impounded) end
  local outVeh = s.activeCar == carId and M.vehicleOf(carId)
  if outVeh and be:getPlayerVehicleID(0) == outVeh:getID() then return false, strings.t('fleet.you_have_that_one_out') end      -- (on foot beside it: the tap seats you)
  local player = getPlayerVehicle(0)
  local anyOut = M.vehicleOf(carId)
  if anyOut and player and player:getJBeamFilename() == 'unicycle' then       -- on foot (after the hospital, say) and the car is already out: seat the player wherever they stand
    core_jobsystem.create(function(job)
      seatPlayer(job, anyOut)
      s.activeCar = carId
      extensions.hook('onStreetLegalChanged')
    end)
    return true, strings.t('fleet.the_1_is_out_front', (car.name))
  end
  if not player or not M.atGarage(player:getPosition(), s) then return false, strings.t('fleet.swap_cars_at_your_garage') end
  local old = s.activeCar and carById(s, s.activeCar)
  local oldVeh = old and M.vehicleOf(old.id)
  if oldVeh and not M.atGarage(oldVeh:getPosition(), s) then return false, strings.t('fleet.bring_the_1_back_to', (old.name)) end
  core_jobsystem.create(function(job)
    if oldVeh then
      M.snapshot(true)                                              -- its dents too: the car is about to go
      if sl_carcare and sl_carcare.askConditions then sl_carcare.askConditions(oldVeh:getID()) end
      job.sleep(0.5)                                                -- (the car answers a frame or two later)
      if player:getID() == oldVeh:getID() and gameplay_walk then gameplay_walk.setWalkingMode(true, nil, nil, true) job.sleep(0.5) end
      old.out = false
      old.where = nil
      oldVeh:delete()
      spawned[old.id] = nil
    end
    local pos, rot = M.forecourt(s, 0)
    local veh = M.vehicleOf(carId) or builder.spawnOwned(job, car, pos, rot)
    if veh then
      spawned[carId] = veh:getID()
      car.out = true
      if be:getPlayerVehicleID(0) ~= veh:getID() then               -- "Drive this one": the player ends up in it (fade, seat), not left on foot; a car already out front (just delivered) too
        seatPlayer(job, veh)
      end
    end
    s.activeCar = carId
    extensions.hook('onStreetLegalChanged')
  end)
  return true, strings.t('fleet.the_1_is_out_front', (car.name))
end

-- sold to a lot or scrapped: where the player stands decides who buys it and for how much
function M.sell(carId, to)
  local s = career()
  local car = s and carById(s, carId)
  if not car then return false, strings.t('carcare.no_such_car') end
  local veh = M.vehicleOf(carId)
  local parts = veh and builder.partsValue(veh:getID())
  local price = to == 'scrap' and market.scrapValue(car, parts) or market.resaleValue(car, parts)
  local player = getPlayerVehicle(0)
  if veh and player and player:getID() == veh:getID() and gameplay_walk then gameplay_walk.setWalkingMode(true, nil, nil, true) end
  if veh then veh:delete() end
  spawned[carId] = nil
  stateLib.removeCar(s, carId)
  sl_career.addMoney(price, (to == 'scrap' and strings.t('fleet.scrapped') or strings.t('fleet.sold')) .. car.name)
  extensions.hook('onStreetLegalCarSold', car, price, to)       -- (the job board counts the profit)
  extensions.hook('onStreetLegalChanged')
  return true, string.format(strings.t('fleet.s_the_s_for_d'), to == 'scrap' and 'Scrapped' or 'Sold', car.name, price), price
end

-- lost (a pink slip): the car is gone, with the player out of it
function M.lose(carId)
  local s = career()
  local car = s and carById(s, carId)
  if not car then return end
  local veh = M.vehicleOf(carId)
  local player = getPlayerVehicle(0)
  if veh and player and player:getID() == veh:getID() and gameplay_walk then gameplay_walk.setWalkingMode(true, nil, nil, true) end
  spawned[carId] = nil
  stateLib.removeCar(s, carId)
  extensions.hook('onStreetLegalChanged')
  return car, veh
end

-- for the phone
function M.list()
  local s = career()
  if not s then return {} end
  local out = {}
  local player = getPlayerVehicle(0)
  for _, c in ipairs(s.cars) do
    local veh = M.vehicleOf(c.id)
    local where = strings.t('fleet.in_the_garage')
    if veh then
      where = M.atGarage(veh:getPosition(), s) and strings.t('fleet.at_the_garage') or strings.t('fleet.out_on_the_street')
      if player and player:getID() == veh:getID() then where = strings.t('fleet.you_are_driving_it') end
    end
    out[#out + 1] = {
      id = c.id, name = c.name, brand = c.brand, active = s.activeCar == c.id, seated = veh ~= nil and player ~= nil and player:getID() == veh:getID(), where = where, out = veh ~= nil,
      condition = c.condition, faults = market.unfixed(c), value = c.value,
      scrap = market.scrapValue(c), resale = market.resaleValue(c), towFee = veh and progression.towFee((veh:getPosition() - (M.forecourt(s, 0) or veh:getPosition())):length()) or nil,
      care = sl_carcare and sl_carcare.summary and sl_carcare.summary(c) or nil,
      impounded = c.impounded,
      look = veh and sl_surfacefx and sl_surfacefx.lookText(veh:getID()) or nil,      -- ('Clean, no scratches': Car Surface FX, when it is there)
      report = (function() local ok, r = pcall(sl_carcare.reportOf, c) return ok and r or nil end)(),       -- (#30: with the wear since you bought it)
    }
  end
  return out
end

----------------------------------------------------------------------------------------------
-- hooks

function M.onStreetLegalStarted()
  spawned = {}
  core_jobsystem.create(function(job)
    job.sleep(1)
    M.restore(job)
    extensions.hook('onStreetLegalChanged')
  end)
end

function M.onStreetLegalStopped()
  M.snapshot(false)
  spawned = {}
end

-- the career saves on its own clock; the records are refreshed just before
function M.onStreetLegalBeforeSave() M.snapshot(false) end

-- a car somebody deleted (or the game removed) is not out in the world any more
function M.onVehicleDestroyed(vid)
  local carId = M.carOfVehicle(vid)
  if carId then
    spawned[carId] = nil
    M.lastGone = { carId = carId, at = os.clock() }      -- (a race lost for pink slips deletes the car)
  end
end

local fxTimer = 0
function M.onUpdate(dtReal)
  if not career() then return end
  -- a car that came out (spawned from the save, delivered, brought out of the garage) gets the dirt and scratches it had when it was put away
  fxTimer = fxTimer + dtReal
  if fxTimer > 2 and sl_surfacefx then
    fxTimer = 0
    local s = career()
    for carId, vid in pairs(spawned) do
      if not fxApplied[vid] and getObjectByID(vid) then
        fxApplied[vid] = true
        local car = carById(s, carId)
        if car and car.fx then sl_surfacefx.restore(vid, car.fx) end
      end
    end
  end
  -- every minute the dents of the cars out in the world are read again (for the save)
  snapshotTimer = snapshotTimer + dtReal
  if snapshotTimer > 60 then
    snapshotTimer = 0
    M.snapshot(true)
  end
end

return M
