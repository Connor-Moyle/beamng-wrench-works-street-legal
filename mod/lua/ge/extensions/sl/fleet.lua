-- Street Legal Racing: the player's cars (extension name: sl_fleet)
-- Every car the player owns is a record in the career save: its full setup, its dents, where
-- it was left. The cars that are out in the world are real vehicles; the rest wait in the
-- garage. From here: a towing service, swapping which car you drive, selling and scrapping,
-- and keeping the records up to date as the cars are driven, modified and bent.

local M = {}

local builder = require('sl/carBuilder')
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

-- note where every car out in the world is and how it is built (the dents follow, a moment later)
function M.snapshot(withDamage)
  local s = career()
  if not s then return end
  for carId, vid in pairs(spawned) do
    local car, veh = carById(s, carId), getObjectByID(vid)
    if car and veh then
      car.config = builder.configOf(vid) or car.config
      car.where = placeOf(veh)
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
    extensions.hook('onStreetLegalChanged')
  end
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
  spawned[car.id] = vid
  s.activeCar = car.id
  veh:queueLuaCommand('controller.setFreeze(0) extensions.load("slrrGarageVeh")')
  extensions.hook('onStreetLegalChanged')
  return car
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
  if not car then return false, 'No such car.' end
  local veh = M.vehicleOf(carId)
  local pos, rot = M.forecourt(s, 0)
  if not pos then return false, 'Your garage is not on this map.' end
  local from = veh and veh:getPosition() or pos
  if veh and (from - pos):length() < 25 then return false, 'It is at the garage already.' end
  local fee = progression.towFee((from - pos):length())
  if not sl_career.addMoney(-fee, 'Tow: ' .. car.name) then return false, string.format('The tow is $%d. You have $%d.', fee, s.money) end
  core_jobsystem.create(function(job)
    local player = getPlayerVehicle(0)
    if veh and player and player:getID() == veh:getID() and gameplay_walk then
      gameplay_walk.setWalkingMode(true, nil, nil, true)          -- out of the car: it goes on the truck
      job.sleep(0.5)
    end
    if veh then
      spawn.safeTeleport(veh, pos, rot, true)
    else
      local v = builder.spawnOwned(job, car, pos, rot)
      if v then spawned[car.id] = v:getID() end
    end
    car.out = true
    M.snapshot(false)
    extensions.hook('onStreetLegalChanged')
  end)
  return true, string.format('The truck has it. $%d, delivered to your garage.', fee)
end

-- drive another of your cars: it comes out of the garage, the one you had goes in
function M.setActive(carId)
  local s = career()
  local car = s and carById(s, carId)
  if not car then return false, 'No such car.' end
  if car.impounded then return false, string.format('It is in the police impound: $%d to get it back.', car.impounded) end
  if s.activeCar == carId and M.vehicleOf(carId) then return false, 'You have that one out already.' end
  local player = getPlayerVehicle(0)
  if not player or not M.atGarage(player:getPosition(), s) then return false, 'Swap cars at your garage.' end
  local old = s.activeCar and carById(s, s.activeCar)
  local oldVeh = old and M.vehicleOf(old.id)
  if oldVeh and not M.atGarage(oldVeh:getPosition(), s) then return false, 'Bring the ' .. old.name .. ' back to the garage first (or have it towed).' end
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
    end
    s.activeCar = carId
    extensions.hook('onStreetLegalChanged')
  end)
  return true, 'The ' .. car.name .. ' is out front.'
end

-- sold to a lot or scrapped: where the player stands decides who buys it and for how much
function M.sell(carId, to)
  local s = career()
  local car = s and carById(s, carId)
  if not car then return false, 'No such car.' end
  local price = to == 'scrap' and market.scrapValue(car) or market.resaleValue(car)
  local veh = M.vehicleOf(carId)
  local player = getPlayerVehicle(0)
  if veh and player and player:getID() == veh:getID() and gameplay_walk then gameplay_walk.setWalkingMode(true, nil, nil, true) end
  if veh then veh:delete() end
  spawned[carId] = nil
  stateLib.removeCar(s, carId)
  sl_career.addMoney(price, (to == 'scrap' and 'Scrapped: ' or 'Sold: ') .. car.name)
  extensions.hook('onStreetLegalCarSold', car, price, to)       -- (the job board counts the profit)
  extensions.hook('onStreetLegalChanged')
  return true, string.format('%s the %s for $%d.', to == 'scrap' and 'Scrapped' or 'Sold', car.name, price), price
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
    local where = 'In the garage'
    if veh then
      where = M.atGarage(veh:getPosition(), s) and 'At the garage' or 'Out on the street'
      if player and player:getID() == veh:getID() then where = 'You are driving it' end
    end
    out[#out + 1] = {
      id = c.id, name = c.name, brand = c.brand, active = s.activeCar == c.id, where = where, out = veh ~= nil,
      condition = c.condition, faults = c.faults, value = c.value,
      scrap = market.scrapValue(c), resale = market.resaleValue(c), towFee = veh and progression.towFee((veh:getPosition() - (M.forecourt(s, 0) or veh:getPosition())):length()) or nil,
      care = sl_carcare and sl_carcare.summary and sl_carcare.summary(c) or nil,
      impounded = c.impounded,
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

function M.onUpdate(dtReal)
  if not career() then return end
  -- every minute the dents of the cars out in the world are read again (for the save)
  snapshotTimer = snapshotTimer + dtReal
  if snapshotTimer > 60 then
    snapshotTimer = 0
    M.snapshot(true)
  end
end

return M
