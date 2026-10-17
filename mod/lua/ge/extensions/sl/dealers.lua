-- Wrench Works: Street Legal: the stock dealers on the laptop (extension name: sl_dealers; docs/LAPTOP_DESIGN.md L3)
-- The Dealers tile lists the map's stock dealers and each one's cars: the same offers as walking onto its lot
-- (sl_lot.offersFor), looked at without spawning anything. Buy takes the money once and the car is built and delivered
-- to the garage forecourt a few game hours later (rules: sl/core/dealers; the order is in the career save).

local M = {}

local strings = require('sl/core/strings')

local rules = require('sl/core/dealers')
local builder = require('sl/carBuilder')
local carInfo = require('sl/carInfo')
local carreport = require('sl/core/carreport')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function now(s) return rules.clock(s.day, sl_career.hour()) end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end

-- the map's stock dealers: career places with a stock filter, kind 'dealer' (new) or 'used', in name order
local function dealers()
  local out = {}
  for id, p in pairs(sl_career.getPlaces() or {}) do
    if p.stock then out[#out + 1] = p end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local function metres(a, b) return a and b and (a - b):length() or 0 end

-- a listing as the stock shop shows one: the config's picture, year, brand, mileage, price, the seller, how far it is and when it arrives
local function card(o, place, yard)
  local info = carInfo.of(o)
  local away = metres(place.pos, yard)
  return { id = o.id, name = o.name, brand = info.brand or o.brand, title = o.title, mileage = o.mileage, condition = o.condition, price = o.price,
    faults = o.faults or {}, kind = o.kind, preview = info.preview, year = info.year, specs = info.specs,
    seller = place.name, metres = math.floor(away), hours = rules.delayHours(away), report = carreport.build(o) }
end

-- sent to the laptop: the dealers (name, distance, how many cars today) and what is on the way
function M.list()
  local s = career()
  if not s then return end
  local v = getPlayerVehicle(0)
  local pos = v and v:getPosition()
  local list = {}
  for _, p in ipairs(dealers()) do
    local offers = sl_lot.offersFor(p, s)
    list[#list + 1] = { id = p.id, name = p.name, metres = math.floor(metres(pos, p.pos)), count = #offers }
  end
  local coming = {}
  for _, o in ipairs(s.orders or {}) do
    coming[#coming + 1] = { name = o.offer.name, hours = math.max(0, math.ceil(o.due - now(s))) }
  end
  guihooks.trigger('slLaptopDealers', { dealers = list, coming = coming })
end

-- one dealer's cars
function M.offers(placeId)
  local s = career()
  if not s then return end
  local place = (sl_career.getPlaces() or {})[placeId]
  if not (place and place.stock) then return end
  local cards = {}
  local yard = sl_fleet.forecourt(s, 0)
  for _, o in ipairs(sl_lot.offersFor(place, s)) do cards[#cards + 1] = card(o, place, yard) end
  guihooks.trigger('slLaptopOffers', { dealer = place.id, name = place.name, offers = cards, money = s.money })
end

-- buy a car: the money once, the offer gone from the lot, the car due at the garage after the delay
function M.buy(placeId, offerId)
  local s = career()
  local place = s and (sl_career.getPlaces() or {})[placeId]
  if not (place and place.stock) then return end
  local offer
  for _, o in ipairs(sl_lot.offersFor(place, s)) do if o.id == offerId then offer = o end end
  local ok, why = rules.canBuy(s, offer)
  if not ok then toast(why) M.offers(placeId) return end
  if not sl_career.addMoney(-offer.price, strings.t('carcare.bought_1', (offer.name))) then toast(string.format('It is $%d.', offer.price)) return end
  local yard = sl_fleet.forecourt(s, 0)
  local order = rules.place(s, offer, placeId, metres(place.pos, yard), now(s))
  toast(string.format(strings.t('dealers.the_s_will_be_at'), offer.name, order.hours))
  extensions.hook('onStreetLegalChanged')
  M.offers(placeId)
  M.list()
end

-- the car is built at the garage forecourt and becomes one of yours (the car you drive stays the one you drive)
local building = false
local retryAt = 0
local function deliver(s, order)
  building = true
  core_jobsystem.create(function(job)
    local slot = #s.cars % 6
    local pos, rot = sl_fleet.forecourt(s, slot)
    local veh = pos and builder.buildOffer(job, order.offer, pos, rot)
    if not veh then
      retryAt = os.clock() + 30               -- (the order stays; try again)
      building = false
      return
    end
    local active = s.activeCar
    local o = order.offer
    local car = sl_fleet.registerVehicle(veh:getID(), { name = o.name, brand = o.brand, value = o.value, condition = o.condition,
      faults = o.faults, mileage = o.mileage, price = o.price })
    s.activeCar = active
    veh:queueLuaCommand('input.event("parkingbrake", 0, FILTER_DIRECT)')
    rules.remove(s, order)
    sl_career.sendText('benny', string.format(strings.t('dealers.your_s_has_been_delivered'), o.name), 2)
    extensions.hook('onStreetLegalChanged')
    building = false
  end)
end

local timer = 0
function M.onUpdate(dtReal)
  timer = timer + (dtReal or 0)
  if timer < 3 or building then return end
  timer = 0
  local s = career()
  if not s or os.clock() < retryAt then return end
  local order = rules.nextDue(s, now(s))
  if order then deliver(s, order) end
end

function M.onStreetLegalStopped() building = false end

return M
