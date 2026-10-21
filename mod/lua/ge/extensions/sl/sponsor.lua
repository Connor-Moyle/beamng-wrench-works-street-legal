-- Street Legal: brand standing and sponsorships (extension name: sl_sponsor; docs/DESIGN_SPONSORSHIPS.md S1/S2). Rules in sl/core/brands; the brand of a car and of a part comes from Wrench Works'
-- slrr_brands (list, ofCar, ofPart, nameOf). Saved in the career as s.brands = { standing = { [brand] = { standing, day } }, cooldown = { [brand] = day }, offer = { brand, day }|nil } and
-- s.sponsorship = { brand, name, kind, since, nextReview, terms = { wins, car }, retainer, discount, weekWins, carRaces, strikes }|nil.
-- The discount reaches the shops through slrr_garage.setPriceFactor (Wrench Works' catalogue and shelf) and sl_shops.setPriceFactor('sponsor', fn) (the career's shop screens), each when present.

local M = {}

local strings = require('sl/core/strings')
local rules = require('sl/core/brands')
local stateLib = require('sl/core/state')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function api() local b = rawget(_G, 'slrr_brands') return b and type(b.ofCar) == 'function' and type(b.ofPart) == 'function' and b or nil end
local function brandName(id) local b = api() return b and b.nameOf and b.nameOf(id) or tostring(id) end
local kinds                       -- brand id -> 'maker' | 'aftermarket': slrr_brands.list() walks the game's whole model list and every pool, so it is read once a session
local function brandKind(id)
  if not kinds then
    local b = api()
    if not (b and b.list) then return nil end
    kinds = {}
    for _, x in ipairs(b.list() or {}) do kinds[x.id] = x.kind end
  end
  return kinds[id]
end

local function brandsState(s)
  s.brands = s.brands or {}
  s.brands.standing, s.brands.cooldown = s.brands.standing or {}, s.brands.cooldown or {}
  return s.brands
end

-- do the brand sponsorships work here: the part is on and Wrench Works' brand registry is there (without it nothing could be earned, and the fixed sponsors stay)
function M.active()
  return require('sl/core/features').on('sponsors') and api() ~= nil
end

-- the discount factor for a part name (1 = list price)
local function factorFor(partName)
  local s = career()
  local sp = s and s.sponsorship
  local b = api()
  if not (sp and b and partName) then return 1 end
  local ok, id = pcall(b.ofPart, partName)
  if ok and id == sp.brand then return 1 - (sp.discount or 0) end
  return 1
end
local function shopFactor(item)
  local s = career()
  local sp = s and s.sponsorship
  if sp and type(item) == 'table' and item.brand == sp.brand then return 1 - (sp.discount or 0) end
  return 1
end

-- hand the discount to the shops (or take it away): at the start, when a sponsorship begins or ends, at the end of the career
local registered = false          -- (nothing is touched in the shops unless this part has handed them a discount: free roam and a career with no sponsor leave them alone)
local function register(on)
  if not on and not registered then return end
  registered = on
  if rawget(_G, 'slrr_garage') and slrr_garage.setPriceFactor then pcall(slrr_garage.setPriceFactor, on and factorFor or nil) end
  if rawget(_G, 'sl_shops') and sl_shops.setPriceFactor then pcall(sl_shops.setPriceFactor, 'sponsor', on and shopFactor or nil) end
end

local function refreshShops()
  local s = career()
  register(s ~= nil and s.sponsorship ~= nil and require('sl/core/features').on('sponsors'))
end

-- the player's current car: { brand (maker id), counts (part brands) }
local function carBrands()
  local b = api()
  local car = sl_fleet and sl_fleet.currentCar and sl_fleet.currentCar()
  if not (b and car) then return nil end
  local ok, maker = pcall(b.ofCar, car.model)
  local names = rules.partNames(car.config and car.config.partsTree)
  local counts = rules.partCounts(names, function(n) local ok2, id = pcall(b.ofPart, n) return ok2 and id or nil end)
  return ok and maker or nil, counts
end

-- a race won: standing for the brand of the car and the brands of its parts; the week counts for a sponsorship
function M.onStreetLegalRaceResult(won)
  local s = career()
  if not s or not won or not api() then return end
  local maker, counts = carBrands()
  local st = brandsState(s)
  local day = s.day or 0
  for _, c in ipairs(rules.credits(maker, counts or {})) do rules.add(st.standing, c.brand, c.points, day) end
  local sp = s.sponsorship
  if sp then
    sp.weekWins = (sp.weekWins or 0) + 1
    if maker and maker == sp.brand then sp.carRaces = (sp.carRaces or 0) + 1 end
  end
end

local function text(s, line) sl_career.sendText('benny', line, 3) end

function M.onStreetLegalNewDay(day)
  local s = career()
  if not s or not api() then return end
  local st = brandsState(s)
  rules.decay(st.standing, day)
  local sp = s.sponsorship
  if sp then
    if day >= (sp.nextReview or day + 1) then
      sp.nextReview = day + 7
      local verdict = rules.review(sp, sp.weekWins or 0, sp.carRaces or 0)
      sp.weekWins, sp.carRaces = 0, 0
      if verdict == 'ok' then
        sl_career.payOut(sp.retainer, strings.t('sponsor.retainer', sp.name))
        extensions.hook('onStreetLegalChanged')
      elseif verdict == 'lost' then
        text(s, strings.t('sponsor.lost', sp.name))
        local e = st.standing[sp.brand]
        if e then e.standing = math.max(0, e.standing - rules.LOSS_STANDING) end
        st.cooldown[sp.brand] = day + rules.COOLDOWN
        s.sponsorship = nil
        refreshShops()
        extensions.hook('onStreetLegalChanged')
      else
        text(s, strings.t(verdict == 'warning' and 'sponsor.warning' or 'sponsor.strike', sp.name, sp.terms.wins))
      end
    end
    return
  end
  -- an offer stands a few days, then the brand waits before it offers again
  local offer = st.offer
  if offer and day - offer.day >= rules.IGNORE_DAYS then
    st.cooldown[offer.brand] = day + rules.COOLDOWN
    st.offer = nil
    offer = nil
  end
  if not offer then
    local id = rules.best(st.standing, day, st.cooldown)
    if id then
      st.offer = { brand = id, day = day }
      local terms = rules.terms(st.standing[id].standing, brandKind(id))
      text(s, strings.t('sponsor.offer', brandName(id), terms.retainer, math.floor(terms.discount * 100 + 0.5), terms.wins))
      extensions.hook('onStreetLegalChanged')
    end
  end
end

-- the phone's buttons: take the offer, turn it down, or end the sponsorship
function M.accept()
  local s = career()
  local st = s and brandsState(s)
  local offer = st and st.offer
  if not offer then return false, strings.t('sponsor.no_offer') end
  local e = st.standing[offer.brand]
  local kind = brandKind(offer.brand)
  local terms = rules.terms(e and e.standing or rules.OFFER_AT, kind)
  s.sponsorship = { brand = offer.brand, name = brandName(offer.brand), kind = kind, since = s.day, nextReview = s.day + 7, terms = { wins = terms.wins, car = terms.car },
    retainer = terms.retainer, discount = terms.discount, weekWins = 0, carRaces = 0, strikes = 0 }
  st.offer = nil
  if sl_jobs and sl_jobs.clearSponsor then sl_jobs.clearSponsor() end          -- (a fixed sponsor the career held is replaced)
  refreshShops()
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('sponsor.signed', s.sponsorship.name, math.floor(terms.discount * 100 + 0.5), terms.retainer)
end

function M.decline()
  local s = career()
  local st = s and brandsState(s)
  if not (st and st.offer) then return false, strings.t('sponsor.no_offer') end
  st.cooldown[st.offer.brand] = (s.day or 0) + rules.COOLDOWN
  st.offer = nil
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('sponsor.declined')
end

function M.quit()
  local s = career()
  local sp = s and s.sponsorship
  if not sp then return false, strings.t('sponsor.none') end
  local st = brandsState(s)
  st.cooldown[sp.brand] = (s.day or 0) + rules.COOLDOWN
  s.sponsorship = nil
  refreshShops()
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('sponsor.ended', sp.name)
end

-- for the billboards and the jobs summary: the current sponsor as { name, weekly, weekWins }, or nil
function M.current()
  local s = career()
  local sp = s and s.sponsorship
  return sp and { name = sp.name, weekly = sp.retainer, weekWins = sp.weekWins or 0 } or nil
end

-- for the phone: { current, offer, standing }
function M.summary()
  local s = career()
  if not s then return nil end
  local st = brandsState(s)
  local sp = s.sponsorship
  local out = { standing = {} }
  if sp then
    out.current = { brand = sp.brand, name = sp.name, kind = sp.kind, since = sp.since, retainer = sp.retainer, discount = sp.discount, terms = sp.terms, weekWins = sp.weekWins or 0,
      carRaces = sp.carRaces or 0, strikes = sp.strikes or 0, daysToReview = math.max(0, (sp.nextReview or 0) - (s.day or 0)) }
  end
  if st.offer then
    local e = st.standing[st.offer.brand]
    local t = rules.terms(e and e.standing or rules.OFFER_AT, brandKind(st.offer.brand))
    out.offer = { brand = st.offer.brand, name = brandName(st.offer.brand), retainer = t.retainer, discount = t.discount, terms = { wins = t.wins, car = t.car }, expiresIn = math.max(0, rules.IGNORE_DAYS - ((s.day or 0) - st.offer.day)) }
  end
  local ids = {}
  for id in pairs(st.standing) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b) return st.standing[a].standing > st.standing[b].standing end)
  for i = 1, math.min(8, #ids) do
    local id = ids[i]
    out.standing[#out.standing + 1] = { brand = id, name = brandName(id), kind = brandKind(id), standing = math.floor(st.standing[id].standing), nextAt = rules.OFFER_AT }
  end
  return out
end

function M.onStreetLegalStarted() refreshShops() end
function M.onStreetLegalOption(key) if key == 'slSponsors' then refreshShops() end end
function M.onStreetLegalStopped() register(false) kinds = nil end

require('sl/core/features').gate('sponsors', M, nil, { 'onStreetLegalStarted' }, { 'summary', 'current', 'accept', 'decline', 'quit' })

return M
