-- Street Legal: car mastery (extension name: sl_mastery; career expansion #13). Rules in sl/core/mastery. Kilometres (the odometer since you bought the car) and clean races
-- earn levels for that one car: sl_mastery.factor(kind, car) answers the multiplier for 'insurance' | 'trade' | 'service' | 'tyres' (nil with the part off or no career).
-- The counters are car.mastery = { km, clean, seenWrecks } in the save; the market, the shops and the bank ask here.

local M = {}

local mastery = require('sl/core/mastery')
local wear = require('sl/core/wear')
local market = require('sl/core/market')

local function career() return sl_career and sl_career.isActive and sl_career.isActive() and sl_career.getState() or nil end
local function carById(s, id) for _, c in ipairs(s and s.cars or {}) do if c.id == id then return c end end end
local function activeCar() local s = career() return s and carById(s, s.activeCar) end

-- the counters of a car with the odometer folded in (the odometer is the car record's care.engineKm; it never counts backwards)
local function sync(car)
  local km = car.care and wear.kmSince(car.care.engineKm, car.mileage) or 0
  car.mastery = mastery.bump(car.mastery, km, false)
  return car.mastery
end

function M.levelOf(car) return car and mastery.level(sync(car)) or 0 end

-- the view for My cars and the car card: { level, max, points, toNext, label, perks }
function M.of(carId)
  local s = career()
  local car = s and carById(s, carId)
  return car and mastery.view(sync(car)) or nil
end

-- the multiplier for a kind: of the given car record, or the car being driven
function M.factor(kind, car)
  if not career() then return nil end
  car = car or activeCar()
  if not car then return 1 end
  return mastery.factor(kind, M.levelOf(car))
end

-- a finished race: a clean run when the car has not been wrecked since the last one
function M.onStreetLegalRaceResult()
  local car = activeCar()
  if not car then return end
  local h = car.history or {}
  local m = sync(car)
  local clean = not h.wreckedNow and (m.seenWrecks == nil or (h.wrecks or 0) == m.seenWrecks)
  car.mastery = mastery.bump(m, 0, clean)
  car.mastery.seenWrecks = h.wrecks or 0
end

local registered = false
function M.refresh()
  if rawget(_G, 'sl_shops') and sl_shops.setPriceFactor then
    pcall(sl_shops.setPriceFactor, 'mastery', function(_, shop) if shop and shop.kind == 'tyre' then return M.factor('tyres') or 1 end return 1 end)
    registered = true
  end
  market.masteryFactor = function(car) return M.factor('trade', car) end
end
function M.onStreetLegalStarted() M.refresh() end
function M.onStreetLegalStopped()
  market.masteryFactor = nil
  if registered and rawget(_G, 'sl_shops') and sl_shops.setPriceFactor then pcall(sl_shops.setPriceFactor, 'mastery', nil) end
  registered = false
end

require('sl/core/features').gate('mastery', M, nil, nil, { 'of', 'factor', 'levelOf' }, { 'refresh' })

return M
