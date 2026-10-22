-- Street Legal Racing: gas stations (extension name: sl_station)
-- In the career the game's free "refuel" at the map's gas stations becomes a paid pump: four grades
-- (a little more power for the better ones), paid by the litre; the shop sells what goes in the
-- trunk (fuel cans, oil, coolant, a battery); a fuel can is filled with the grade you choose.
-- The pump and the shop are the phone's 'slStation' panel.
-- And the car wash: the map's wash bays (places of kind 'carwash'), $15 to roll through.

local M = {}

local strings = require('sl/core/strings')

local rules = require('sl_carcare')

local open                -- { name, scale } while at the pump (scale: the pump's own prices against ours)
local patched, original

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

local function careOfCurrent()
  local car = sl_fleet and sl_fleet.currentCar and sl_fleet.currentCar()
  return car, car and sl_carcare and sl_carcare.careOf(car)
end

local function send()
  local s = career()
  if not open or not s then guihooks.trigger('slStation', { open = false }) return end
  local car, c = careOfCurrent()
  local fuels, items = {}, {}
  for _, f in ipairs(rules.FUELS) do fuels[#fuels + 1] = { id = f.id, name = f.name, price = math.floor(f.pricePerLitre * open.scale * 100 + 0.5) / 100 } end
  for _, id in ipairs({ 'fuelCan', 'oil', 'coolant', 'battery' }) do
    local it = rules.ITEMS[id]
    items[#items + 1] = { id = id, name = it.name, price = it.price }
  end
  guihooks.trigger('slStation', {
    open = true, name = open.name, money = s.money, fuels = fuels, items = items, washPrice = M.WASH_PRICE,
    car = car and car.name or nil, inTank = c and rules.fuel(c.fuel).name or nil,
    tank = c and c.fuelLevel or nil, litresToFull = c and c.fuelCapacity and c.fuelLitres and math.max(0, c.fuelCapacity - c.fuelLitres) or nil,
    trunk = c and #c.trunk or 0, trunkSlots = rules.TRUNK_SLOTS,
  })
end

-- the pump's own price of petrol (the stock station's sign), as a scale on ours; stationId is the facility's id
local function pumpScale(stationId)
  local fp = freeroam_facilities_fuelPrice
  local ok, price = pcall(function() return fp and fp.getFuelPrice and stationId and fp.getFuelPrice(stationId, 'gasoline') end)
  return rules.scaleFor(ok and price or nil)
end

function M.open(name, stationId)
  if not career() then return end
  open = { name = name or strings.t('jobs.gas_station'), scale = pumpScale(stationId) }
  send()
end

function M.close() open = nil send() end

local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end

-- fill the tank with a grade (as much as the tank takes, or as much as the money pays for)
function M.fill(fuelId)
  local s = career()
  local car, c = careOfCurrent()
  if not s or not car then toast(strings.t('station.fill_what_drive_one_of')) return end
  local veh = sl_fleet.vehicleOf(car.id)
  local player = getPlayerVehicle(0)
  if not veh or not player or veh:getID() ~= player:getID() then toast(strings.t('station.drive_your_car_up_to')) return end
  local litres = c.litresToFull or (c.fuelCapacity and c.fuelLitres and c.fuelCapacity - c.fuelLitres) or 40
  if litres < 1 then toast(strings.t('station.the_tank_is_full')) return end      -- (nothing to fill: the money is not the reason)
  local price = rules.fuel(fuelId).pricePerLitre
  price = price * (open and open.scale or 1)
  litres = math.min(litres, math.floor(s.money / price))
  if litres < 1 then toast(strings.t('station.that_will_not_buy_any')) return end
  local cost = rules.fillCost(fuelId, litres, open and open.scale)
  if not sl_career.addMoney(-cost, string.format('%d L of %s', litres, rules.fuel(fuelId).name)) then toast(strings.t('station.that_will_not_buy_any')) return end      -- (the fuel is handed over only when the money was taken)
  sl_carcare.refill(car.id, 'fuel', litres, fuelId)
  c.fuelLitres = (c.fuelLitres or 0) + litres
  toast(string.format('%d L of %s. $%.2f.', litres, rules.fuel(fuelId).name, cost))
  send()
end

-- the shop: into the trunk of the car you came in (a fuel can takes the grade chosen)
function M.buy(itemId, fuelId)
  local car, c = careOfCurrent()
  if not car then toast(strings.t('station.you_need_a_car_to')) return end
  local ok, text = sl_carcare.buyItem(car.id, itemId)
  if ok and itemId == 'fuelCan' then c.canFuel = fuelId or c.fuel end
  toast(text or '')
  send()
end

-- the game's own pump: in the career it opens ours
local function patch()
  if patched then return end
  -- not every way into the level loads the game's pumps (the map's facilities file has them)
  if not extensions.isExtensionLoaded('freeroam_gasStations') then
    extensions.load('freeroam_facilities', 'freeroam_gasStations')
    if gameplay_rawPois then gameplay_rawPois.clear() end
  end
  if not freeroam_gasStations or not freeroam_gasStations.refuelCar then return end
  original = freeroam_gasStations.refuelCar
  freeroam_gasStations.refuelCar = function(elem, fuelTypes, veh)
    if career() then
      M.open(elem and elem.facility and elem.facility.name, elem and elem.facility and elem.facility.id)
    else
      return original(elem, fuelTypes, veh)
    end
  end
  patched = true
end

-- the car wash (X3a): the map's wash bays (places of kind 'carwash'); roll in slowly in one of your cars and it
-- is washed: Surface FX's built-up dirt comes off (when that mod is there), and it counts as fresh for the
-- day's show and shine
M.WASH_PRICE = 15
local WASH_RADIUS, WASH_SPEED = 4, 1.0
local washedOn = {}        -- car id -> career day of its last wash (for the day; not saved)
local inBay                -- the bay we are in, so a wash happens once per visit
local washTimer = 0

function M.washedToday(carId) local s = career() return s ~= nil and carId ~= nil and washedOn[carId] == s.day end

-- wash the car you are in: the fee, the dirt off (Surface FX), fresh for the day's show and shine. Both day and night.
local function washCar(carId, s)
  if not sl_career.addMoney(-M.WASH_PRICE, strings.t('station.car_wash')) then toast(strings.t('station.a_wash_is_1', (M.WASH_PRICE))) return false end
  if surfaceFXBody and surfaceFXBody.wash then surfaceFXBody.wash() end
  local washed = sl_fleet and sl_fleet.vehicleOf(carId)
  if washed and sl_surfacefx then if not sl_surfacefx.washOff(washed:getID()) then sl_surfacefx.wash(washed:getID()) end end      -- (Car Surface FX: the dirt splats and the dirt on the paint come off, the car you rolled in)
  washedOn[carId] = s.day
  toast(string.format(strings.t('station.washed_and_dried_d_it'), M.WASH_PRICE))
  return true
end

-- at a pump: a wash is offered with the fuel (the stock stations have no bay of their own)
function M.wash()
  local s = career()
  local car = careOfCurrent()
  local veh = car and sl_fleet.vehicleOf(car.id)
  local player = getPlayerVehicle(0)
  if not s or not car or not veh or not player or veh:getID() ~= player:getID() then toast(strings.t('station.drive_your_car_up_to')) return end
  if washCar(car.id, s) then send() end
end

local function updateWash(dt)
  washTimer = washTimer + dt
  if washTimer < 0.25 then return end
  washTimer = 0
  local s, v = career(), getPlayerVehicle(0)
  local carId = v and sl_fleet and sl_fleet.carOfVehicle and sl_fleet.carOfVehicle(v:getID())
  if not s or not carId then inBay = nil return end
  local here, bay = v:getPosition(), nil
  for id, p in pairs(sl_career.getPlaces() or {}) do
    if p.kind == 'carwash' and p.pos and (here - vec3(p.pos.x, p.pos.y, p.pos.z)):length() < WASH_RADIUS then bay = id end
  end
  if bay ~= inBay and bay and v:getVelocity():length() < WASH_SPEED then
    inBay = bay
    washCar(carId, s)
  elseif not bay then
    inBay = nil
  end
end

-- free roam (the master and the 'wash' switch of sl_mode): the same bays, free, for whatever car you drive. No career, no money, no record of the wash.
local freeInBay, freeTimer = nil, 0
function M.freeWash(v)
  if surfaceFXBody and surfaceFXBody.wash then surfaceFXBody.wash() end
  if sl_surfacefx then if not sl_surfacefx.washOff(v:getID()) then sl_surfacefx.wash(v:getID()) end end
  toast(strings.t('station.washed_free'))
end
local function updateFreeWash(dt)
  freeTimer = freeTimer + dt
  if freeTimer < 0.25 then return end
  freeTimer = 0
  local v = getPlayerVehicle(0)
  if not v or v:getJBeamFilename() == 'unicycle' then freeInBay = nil return end
  local here, bay = v:getPosition(), nil
  for id, p in pairs(sl_career and sl_career.getPlaces and sl_career.getPlaces() or {}) do
    if p.kind == 'carwash' and p.pos and (here - vec3(p.pos.x, p.pos.y, p.pos.z)):length() < WASH_RADIUS then bay = id end
  end
  if bay and bay ~= freeInBay and v:getVelocity():length() < WASH_SPEED then
    freeInBay = bay
    M.freeWash(v)
  elseif not bay then
    freeInBay = nil
  end
end

function M.onStreetLegalStarted() patch() end
function M.onUpdate(dtReal) if career() and not patched then patch() end
  if career() then updateWash(dtReal or 0)
  elseif sl_mode and sl_mode.enabled('wash') then updateFreeWash(dtReal or 0) end
  -- driven off: the pump closes
  if open then
    local v = getPlayerVehicle(0)
    if v and v:getVelocity():length() > 3 then M.close() end
  end
end
function M.onStreetLegalStopped()
  open = nil
  if patched and freeroam_gasStations then freeroam_gasStations.refuelCar = original end
  patched = false
end
function M.onClientEndMission() open, patched, inBay, freeInBay = nil, false, nil, nil end
function M.request() send() end

return M
