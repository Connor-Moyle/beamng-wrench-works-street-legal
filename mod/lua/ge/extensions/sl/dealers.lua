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
  local yard = sl_fleet.forecourt(s, 0)
  local away = metres(place.pos, yard)
  if not sl_career.addMoney(-offer.price, strings.t('dealers.bought_arriving', offer.name, rules.delayHours(away))) then toast(string.format('It is $%d.', offer.price)) return end
  local order = rules.place(s, offer, placeId, away, now(s))
  toast(string.format(strings.t('dealers.the_s_will_be_at'), offer.name, order.hours))
  extensions.hook('onStreetLegalChanged')
  M.offers(placeId)
  M.list()
end

-- the car is built at the garage forecourt and becomes one of yours (the car you drive stays the one you drive)
local building = false
local retryAt = 0
-- the cars bought here (and from private sellers) that are still on their way, for the phone's and the laptop's My cars: { name, dealer, day, hour }
function M.ordersList()
  local s, out = career(), {}
  local places = sl_career and sl_career.getPlaces and sl_career.getPlaces() or {}
  for _, o in ipairs(s and s.orders or {}) do
    out[#out + 1] = { name = o.offer and o.offer.name or '?', dealer = places[o.place] and places[o.place].name or nil, day = math.floor((o.due or 0) / 24), hour = (o.due or 0) % 24,
      hours = math.max(1, math.ceil((o.due or 0) - now(s))) }
  end
  return out
end

local told = {}                 -- order -> true once the player was told that the forecourt is full
local function deliver(s, order)
  building = true
  core_jobsystem.create(function(job)
    -- the first spot of the forecourt with no vehicle within 4 m (the player's car included); every spot taken: wait, and say so once
    local pos, rot = sl_fleet.freeForecourt(s, #s.cars % 6)
    if not pos and sl_fleet.forecourt(s, 0) then
      if not told[order] then
        told[order] = true
        sl_career.sendText('benny', strings.t('dealers.your_car_is_here_but'), 2)
      end
      retryAt = os.clock() + 30
      building = false
      return
    end
    local veh = pos and builder.buildOffer(job, order.offer, pos, rot)
    if not veh then
      retryAt = os.clock() + 30               -- (the order stays; try again)
      building = false
      local gone, back = rules.buildFailed(s, order)
      if gone then      -- (the car cannot be built at all: the order is cancelled and the price comes back)
        if back > 0 then sl_career.addMoney(back, strings.t('dealers.order_cancelled', (order.offer and order.offer.name) or '?')) end
        sl_career.sendText('benny', string.format(strings.t('dealers.order_cancelled_text'), (order.offer and order.offer.name) or '?', back), 2)
        extensions.hook('onStreetLegalChanged')
      end
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
    if sl_phone and sl_phone.routeGarage then pcall(sl_phone.routeGarage) end      -- the route to the garage where it stands
    extensions.hook('onStreetLegalCarDelivered', o)
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
