-- Street Legal: what is for sale, and for how much.
-- Three places sell cars: the dealership (new, full price), the used-car lot at the junkyard
-- (everything from a tidy stock car to a modified wreck) and the scrap yard (cars that barely
-- hold together, for almost nothing - and it buys your wrecks). What each has changes from
-- day to day. Pure: the game hands in the cars it knows about, this decides the offers
-- (tested by tools/luatest.js). Turning an offer into a real car - the dents, the swapped
-- parts, what is missing - is done in the game (sl/carBuilder).

local M = {}

local rngLib = require('sl/core/rng')

-- condition of a used car: how it looks and runs, and what that does to the price
M.CONDITIONS = {
  { id = 'good_stock', title = 'Good, stock', weight = 3, condition = { 0.75, 0.95 }, damage = { 0, 0.05 }, mods = 0, broken = 0, price = 0.75 },
  { id = 'tired_stock', title = 'Tired, stock', weight = 3, condition = { 0.45, 0.75 }, damage = { 0.05, 0.25 }, mods = 0, broken = 0.15, price = 0.5 },
  { id = 'damaged_stock', title = 'Damaged, stock', weight = 2, condition = { 0.2, 0.5 }, damage = { 0.3, 0.7 }, mods = 0, broken = 0.4, price = 0.3 },
  { id = 'modified_good', title = 'Modified, good', weight = 2, condition = { 0.7, 0.95 }, damage = { 0, 0.1 }, mods = { 2, 5 }, broken = 0, price = 0.95 },
  { id = 'modified_broken', title = 'Modified, needs work', weight = 2, condition = { 0.25, 0.55 }, damage = { 0.2, 0.6 }, mods = { 1, 4 }, broken = 0.6, price = 0.45 },
}

-- what can be wrong with it; the car is built without these (or with them damaged)
M.STARTER_PRICE = 3500     -- the used lot's cheapest car is never dearer (start money $5,000, fuel and a part to spare)

M.FAULTS = { 'engine', 'gearbox', 'radiator', 'battery', 'tyres', 'brakes', 'exhaust' }

-- a fault is put right by a new part in its place (a slot path, as Wrench Works reports a part bought)
M.FAULT_SLOTS = { engine = { 'engine' }, gearbox = { 'transmission', 'gearbox' }, radiator = { 'radiator' }, battery = { 'battery' },
  tyres = { 'tire', 'tyre' }, brakes = { 'brake' }, exhaust = { 'exhaust' } }
function M.fixes(fault, slotPath)
  slotPath = tostring(slotPath or ''):lower()
  for _, key in ipairs(M.FAULT_SLOTS[fault] or {}) do if slotPath:find(key, 1, true) then return true end end
  return false
end

local function weightedPick(rng, list)
  local total = 0
  for _, c in ipairs(list) do total = total + c.weight end
  local x = rng:float() * total
  for _, c in ipairs(list) do
    x = x - c.weight
    if x < 0 then return c end
  end
  return list[#list]
end

local function round(x, step) return math.floor(x / step + 0.5) * step end

local function between(rng, pair)
  if type(pair) ~= 'table' then return pair end
  return rng:range(pair[1], pair[2])
end

-- cars: { { model, config, name, brand, value, year } } - the stock configurations the game has
-- kind: 'dealer' | 'used' | 'scrap'    seed: the career's seed; day: the in-game day number
-- Returns a list of offers.
function M.offers(cars, kind, seed, day, count, noStarter)
  local rng = rngLib.new(rngLib.hash(kind .. ':' .. tostring(seed) .. ':' .. tostring(day)))
  local pool = {}
  for _, c in ipairs(cars or {}) do
    if type(c.value) == 'number' and c.value > 0 then pool[#pool + 1] = c end
  end
  table.sort(pool, function(a, b) return a.config < b.config end)        -- the same day gives the same cars
  local out, used = {}, {}
  count = math.min(count or 8, #pool)
  local tries = 0
  while #out < count and tries < count * 20 do
    tries = tries + 1
    local car = pool[rng:int(#pool)]
    -- the dealer has the dear new cars, the scrap yard the cheap old ones
    local fits = true
    if kind == 'scrap' and car.value > 25000 and rng:chance(0.85) then fits = false end
    if kind == 'used' and car.value > 120000 and rng:chance(0.7) then fits = false end
    if fits and not used[car.config] then
      used[car.config] = true
      local offer = { id = string.format('%s-%d-%d', kind, day or 0, #out + 1), model = car.model, config = car.config,
        name = car.name, brand = car.brand, value = car.value, kind = kind, faults = {}, mods = 0 }
      if kind == 'dealer' then
        offer.condition, offer.damage, offer.mileage = 1, 0, rng:int(5, 60)
        offer.title = 'New'
        offer.price = round(car.value * rng:range(1.0, 1.08), 50)
        -- now and then a quick car comes ready for the track: built and stripped, at a price
        if car.value > 30000 and rng:chance(0.3) then
          offer.build, offer.title = 'race', 'Track special'
          offer.price = round(offer.price * 1.6, 50)
        end
      elseif kind == 'scrap' then
        offer.condition = rng:range(0.03, 0.2)
        offer.damage = rng:range(0.6, 1)
        offer.mileage = rng:int(180000, 450000)
        offer.title = 'Scrap'
        for _, f in ipairs(M.FAULTS) do
          if rng:chance(0.55) then offer.faults[#offer.faults + 1] = f end
        end
        offer.price = round(math.max(150, car.value * rng:range(0.03, 0.08)), 50)
      else
        local c = weightedPick(rng, M.CONDITIONS)
        offer.title = c.title
        offer.condition = between(rng, c.condition)
        offer.damage = between(rng, c.damage)
        offer.mods = math.floor(between(rng, c.mods) + 0.5)
        offer.mileage = rng:int(40000, 260000)
        for _, f in ipairs(M.FAULTS) do
          if rng:chance(c.broken / 3) then offer.faults[#offer.faults + 1] = f end
        end
        local p = car.value * c.price * (0.85 + 0.3 * offer.condition)
        p = p * (1 - 0.06 * #offer.faults) * rng:range(0.92, 1.08)
        offer.price = round(math.max(200, p), 50)
      end
      offer.condition = math.floor(offer.condition * 100 + 0.5) / 100
      offer.damage = math.floor(offer.damage * 100 + 0.5) / 100
      out[#out + 1] = offer
    end
  end
  -- a starter: the used lot always has something a new player's $5,000 buys (the tutorial sends them there for
  -- "something that runs"); the game's own car values start near $10,000, so the cheapest car on the lot is
  -- a tired or damaged one at the starter price when nothing else is that cheap
  if kind == 'used' and #out > 0 and not noStarter then
    local cheapest = out[1]
    for _, o in ipairs(out) do if o.price < cheapest.price then cheapest = o end end
    if cheapest.price > M.STARTER_PRICE then
      local car = pool[1]
      for _, c in ipairs(pool) do if c.value < car.value then car = c end end
      local c = M.CONDITIONS[rng:chance(0.5) and 2 or 3]                                   -- tired or damaged stock
      local o = { id = string.format('%s-%d-starter', kind, day or 0), model = car.model, config = car.config, name = car.name,
        brand = car.brand, value = car.value, kind = kind, faults = {}, mods = 0, title = c.title,
        condition = math.floor(between(rng, c.condition) * 100 + 0.5) / 100, damage = math.floor(between(rng, c.damage) * 100 + 0.5) / 100,
        mileage = rng:int(120000, 260000) }
      for _, f in ipairs(M.FAULTS) do if rng:chance(c.broken / 3) then o.faults[#o.faults + 1] = f end end
      o.price = math.min(M.STARTER_PRICE, round(math.max(200, car.value * c.price * (0.85 + 0.3 * o.condition)), 50))
      for i = #out, 1, -1 do if out[i].config == car.config then table.remove(out, i) end end
      if #out >= count then                                                                -- (in place of the dearest)
        local di = 1
        for i, x in ipairs(out) do if x.price > out[di].price then di = i end end
        table.remove(out, di)
      end
      out[#out + 1] = o
    end
  end
  table.sort(out, function(a, b) return a.price < b.price end)
  return out
end

-- No money loop: a car you bought never sells back (or scraps) for more than 90 % of what you paid, as you bought
-- it. What you put into it since counts: repairs done in your own garage (car.repaired, $) bring the car up (its
-- condition, to 0.95 at most) and come back with a margin, REPAIR_BACK of what they cost: buying a wreck, fixing it
-- and selling it pays (the SLRR flip), but only as far as the car is worth fixed. Parts added since count at their
-- value (what the shop charges: no gain there). partsNow: its parts' value now, if built.
M.SELL_BACK = 0.9
M.REPAIR_BACK = 1.35
M.REPAIR_CONDITION = 3        -- condition gained per share of the car's value spent repairing it
local function condition(car)
  local c = car.condition or 0.5
  return math.min(math.max(c, 0.95), c + M.REPAIR_CONDITION * (car.repaired or 0) / math.max(1, car.value or 0))
end
-- the faults whose slot holds a part in a Wrench Works parts tree (a fault's word in a fitted slot's path)
function M.faultsFitted(partsTree, faults)
  local paths = {}
  local function walk(node)
    local chosen = node.chosenPartName ~= nil and node.chosenPartName ~= ''
    if node.path and chosen then paths[#paths + 1] = tostring(node.path):lower() end
    if node.path == nil or chosen then for _, c in pairs(node.children or {}) do walk(c) end end
  end
  walk(partsTree or {})
  local fitted = {}
  for _, f in ipairs(faults or {}) do
    for _, p in ipairs(paths) do if M.fixes(f, p) then fitted[f] = true break end end
  end
  return fitted
end

-- a car's faults still open (car.fixed[fault] = what the part in its slot cost, set at drive-out; nil or 0 = still
-- wrong: one rule for the premium and the penalty alike)
function M.unfixed(car)
  local out = {}
  for _, f in ipairs(car.faults or {}) do if not (car.fixed and (car.fixed[f] or 0) > 0) then out[#out + 1] = f end end
  return out
end

-- a fault takes 5 % off; one put right with a part gets that back only as far as REPAIR_BACK x what the part cost
-- (a $60 exhaust is not worth 5 % of the car: the flip's rule, no fault wash)
local function faultPenalty(car, base)
  local p = 0
  for _, f in ipairs(car.faults or {}) do
    local paid = car.fixed and (car.fixed[f] or 0) > 0 and car.fixed[f]
    p = p + (paid and math.max(0, 0.05 * base - M.REPAIR_BACK * paid) or 0.05 * base)
  end
  return p
end
local function rawResale(car)
  local base = (car.value or 0) * (0.25 + 0.45 * condition(car))
  return math.max(150, base - faultPenalty(car, base))
end
local function capped(car, raw, partsNow, step)
  if not car.boughtFor or car.boughtFor <= 0 then return round(raw, step) end       -- (a pink slip won: nothing paid)
  local parts = math.max(0, (partsNow or 0) - (car.partsAtBuy or partsNow or 0))
  local cap = car.boughtFor * M.SELL_BACK + M.REPAIR_BACK * (car.repaired or 0) + parts
  return math.min(round(raw, step), math.floor(cap / step) * step)                      -- (never rounded up past the cap)
end

-- what the scrap yard pays for a car of yours: its metal, plus a little for what still works
function M.scrapValue(car, partsNow)
  local base = math.max(100, (car.value or 0) * 0.05)
  return capped(car, base * (0.6 + 0.8 * condition(car)), partsNow, 10)
end

-- a car you brought back yourself: bought below 0.9, repaired to 0.9 or better, nothing wrong with it. Private
-- buyers pay a premium for one (the flip's reward; a car bought good never gets it, so it is no loop)
M.REBUILT_PREMIUM = 1.15
function M.rebuilt(car)
  return (car.condition or 1) < 0.9 and (car.repaired or 0) > 0 and condition(car) >= 0.9 - 1e-9 and #M.unfixed(car) == 0
end

-- what a private buyer at the lot pays for a car of yours
function M.resaleValue(car, partsNow)
  local v = capped(car, rawResale(car), partsNow, 50)
  if M.rebuilt(car) then v = math.floor(v * M.REBUILT_PREMIUM / 50) * 50 end
  return v
end

return M
