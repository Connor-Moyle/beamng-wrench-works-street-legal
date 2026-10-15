-- Street Legal Racing: gas stations (extension name: sl_station)
-- In the career the game's free "refuel" at the map's gas stations becomes a paid pump: four grades
-- (a little more power for the better ones), paid by the litre; the shop sells what goes in the
-- trunk (fuel cans, oil, coolant, a battery); a fuel can is filled with the grade you choose.
-- The pump and the shop are the phone's 'slStation' panel.

local M = {}

local rules = require('sl_carcare')

local open                -- { name } while at the pump
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
  for _, f in ipairs(rules.FUELS) do fuels[#fuels + 1] = { id = f.id, name = f.name, price = f.pricePerLitre } end
  for _, id in ipairs({ 'fuelCan', 'oil', 'coolant', 'battery' }) do
    local it = rules.ITEMS[id]
    items[#items + 1] = { id = id, name = it.name, price = it.price }
  end
  guihooks.trigger('slStation', {
    open = true, name = open.name, money = s.money, fuels = fuels, items = items,
    car = car and car.name or nil, inTank = c and rules.fuel(c.fuel).name or nil,
    tank = c and c.fuelLevel or nil, litresToFull = c and c.fuelCapacity and c.fuelLitres and math.max(0, c.fuelCapacity - c.fuelLitres) or nil,
    trunk = c and #c.trunk or 0, trunkSlots = rules.TRUNK_SLOTS,
  })
end

function M.open(name)
  if not career() then return end
  open = { name = name or 'Gas station' }
  send()
end

function M.close() open = nil send() end

local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end

-- fill the tank with a grade (as much as the tank takes, or as much as the money pays for)
function M.fill(fuelId)
  local s = career()
  local car, c = careOfCurrent()
  if not s or not car then toast('Fill what? Drive one of your cars up to the pump.') return end
  local veh = sl_fleet.vehicleOf(car.id)
  local player = getPlayerVehicle(0)
  if not veh or not player or veh:getID() ~= player:getID() then toast('Drive your car up to the pump first.') return end
  local litres = c.litresToFull or (c.fuelCapacity and c.fuelLitres and c.fuelCapacity - c.fuelLitres) or 40
  local price = rules.fuel(fuelId).pricePerLitre
  litres = math.min(litres, math.floor(s.money / price))
  if litres < 1 then toast('That will not buy any fuel.') return end
  local cost = rules.fillCost(fuelId, litres)
  sl_career.addMoney(-cost, string.format('%d L of %s', litres, rules.fuel(fuelId).name))
  sl_carcare.refill(car.id, 'fuel', litres, fuelId)
  c.fuelLitres = (c.fuelLitres or 0) + litres
  toast(string.format('%d L of %s. $%.2f.', litres, rules.fuel(fuelId).name, cost))
  send()
end

-- the shop: into the trunk of the car you came in (a fuel can takes the grade chosen)
function M.buy(itemId, fuelId)
  local car, c = careOfCurrent()
  if not car then toast('You need a car to put it in.') return end
  local ok, text = sl_carcare.buyItem(car.id, itemId)
  if ok and itemId == 'fuelCan' then c.canFuel = fuelId or c.fuel end
  toast(text or '')
  send()
end

-- the game's own pump: in the career it opens ours
local function patch()
  if patched or not freeroam_gasStations or not freeroam_gasStations.refuelCar then return end
  original = freeroam_gasStations.refuelCar
  freeroam_gasStations.refuelCar = function(elem, fuelTypes, veh)
    if career() then
      M.open(elem and elem.facility and elem.facility.name)
    else
      return original(elem, fuelTypes, veh)
    end
  end
  patched = true
end

function M.onStreetLegalStarted() patch() end
function M.onUpdate() if career() and not patched then patch() end
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
function M.onClientEndMission() open, patched = nil, false end
function M.request() send() end

return M
