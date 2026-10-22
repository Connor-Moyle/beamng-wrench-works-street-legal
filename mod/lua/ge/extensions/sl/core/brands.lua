-- Street Legal: brand standing and sponsorships (docs/DESIGN_SPONSORSHIPS.md). A race won in a maker's car, or in a car with three or more parts of an aftermarket brand, builds standing with
-- that brand; a standing of OFFER_AT earns a sponsorship offer, which gives a discount on the brand's parts, a weekly retainer and terms (wins a week, driving its cars) that cost strikes when
-- broken. Pure, no game calls (the brand names of cars and parts come in from Wrench Works' slrr_brands): tested by tools/luatest.js.

local M = {}

M.WIN = 10                 -- standing for a win in a maker's car
M.PART_WIN = 4             -- standing for a win in a car with PART_MIN or more parts of an aftermarket brand
M.PART_MIN = 3
M.DECAY = 1                -- standing lost per day without a win for that brand
M.OFFER_AT = 100
M.IGNORE_DAYS = 3          -- an offer stands this long
M.COOLDOWN = 14            -- days before a brand offers again after being declined or ignored
M.DISCOUNT = { low = 0.10, high = 0.15, at = 300 }
M.STRIKES = 3
M.LOSS_STANDING = 30       -- standing lost when a sponsorship ends by strikes

local function round10(x) return math.floor(x / 10 + 0.5) * 10 end

-- the chosen part names of a saved parts tree ({ chosenPartName, children = { slot = node } }), flat
function M.partNames(tree, out)
  out = out or {}
  if type(tree) ~= 'table' then return out end
  if type(tree.chosenPartName) == 'string' and tree.chosenPartName ~= '' then out[#out + 1] = tree.chosenPartName end
  for _, child in pairs(tree.children or {}) do M.partNames(child, out) end
  return out
end

-- how many of the parts belong to each brand: { [brandId] = n }; ofPart(name) answers a brand id or nil
function M.partCounts(names, ofPart)
  local counts = {}
  for _, n in ipairs(names or {}) do
    local b = ofPart(n)
    if b then counts[b] = (counts[b] or 0) + 1 end
  end
  return counts
end

-- the standing a won race gives: a list { { brand, points } }. carBrand = the maker of the car; counts = the part counts of the car; maker brands in `counts` are not counted twice
function M.credits(carBrand, counts)
  local out = {}
  if carBrand then out[#out + 1] = { brand = carBrand, points = M.WIN } end
  local ids = {}
  for b in pairs(counts or {}) do ids[#ids + 1] = b end
  table.sort(ids)
  for _, b in ipairs(ids) do
    if b ~= carBrand and counts[b] >= M.PART_MIN then out[#out + 1] = { brand = b, points = M.PART_WIN } end
  end
  return out
end

-- st = { [brandId] = { standing, day } } (day = the last day it was credited or decayed)
function M.add(st, brand, points, day)
  local e = st[brand] or { standing = 0, day = day }
  e.standing, e.day = e.standing + points, day
  st[brand] = e
end

-- a new day: every brand loses DECAY for each day since it last gained
function M.decay(st, day)
  for id, e in pairs(st) do
    local days = day - (e.day or day)
    if days > 0 then
      e.standing = math.max(0, e.standing - M.DECAY * days)
      e.day = day
    end
    if e.standing <= 0 then st[id] = nil end
  end
end

-- the brand to offer a sponsorship: the highest standing from OFFER_AT up that is not on cooldown (cooldown = { [brandId] = day it may offer again })
function M.best(st, day, cooldown)
  local best, bs
  local ids = {}
  for id in pairs(st) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local e = st[id]
    if e.standing >= M.OFFER_AT and (cooldown[id] or 0) <= day and (not bs or e.standing > bs) then best, bs = id, e.standing end
  end
  return best
end

-- the terms of a sponsorship at a standing and a kind ('maker' | 'aftermarket'): wins a week, a maker also wants one race a week in its cars; the retainer and the discount
function M.terms(standing, kind)
  return { wins = standing >= 300 and 3 or 2, car = kind == 'maker' or nil,
    retainer = math.min(1500, round10(150 + standing * 0.5)), discount = standing >= M.DISCOUNT.at and M.DISCOUNT.high or M.DISCOUNT.low }
end

-- the end of a sponsorship week: weekWins races won, madeCarRace = one of them (or any race) in the brand's car. sp.strikes is updated. Returns 'ok', 'warning', 'strike' or 'lost'
function M.review(sp, weekWins, carRaces)
  local met = weekWins >= sp.terms.wins and (not sp.terms.car or carRaces >= 1)
  if met then sp.strikes = 0 return 'ok' end
  sp.strikes = (sp.strikes or 0) + 1
  if sp.strikes >= M.STRIKES then return 'lost' end
  return sp.strikes == 1 and 'warning' or 'strike'
end

return M
