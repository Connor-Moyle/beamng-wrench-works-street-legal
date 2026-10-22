-- Street Legal: fast travel from the big map to the career's places (#20). Pure, tested by tools/luatest.js.
-- Every dealer, used lot, scrap yard, garage and Wrench Works shop is a point on the big map. Where you arrive: a lot's car park (in front
-- of its cars, as the cab drops you), a garage in front of its door, a shop on its forecourt marker. A garage above your level is shown
-- greyed with the reputation it needs. Travel is refused while a race, a job, a chase or a cab ride is on.

local cabplan = require('sl/core/cabplan')
local progression = require('sl/core/progression')
local tiers = require('sl/core/tiers')

local M = {}

local strings = require('sl/core/strings')

-- cardIcon: the card's icon (the game's bngIcons names); pin: the map sprite of the pin (nil: the usual triangle)
-- the lots (dealer, junkyard, scrapyard) have theirs in sl/core/pois, the gas stations the game's own
M.SAME_SPOT = 8          -- m: two places of one kind this close are one pin
M.KINDS = {
  garage = { cardIcon = 'garage01', pin = 'poi_garage_2', what = 'Garage' },
  shop = { cardIcon = 'houseWrench', pin = 'poi_point_1_round', what = strings.t('fasttravel.parts_shop') },
  -- the other places of the map (their own pin and a trip there, never locked): car wash, meet, hospital, valet, parts store
  carwash = { cardIcon = 'droplet', pin = 'poi_point_1_round', what = strings.t('fasttravel.car_wash') },
  meet = { cardIcon = 'cars', pin = 'poi_parking_round', what = strings.t('fasttravel.car_meet') },
  hospital = { cardIcon = 'shieldHandPlus', pin = 'poi_exclamationmark_round', what = strings.t('fasttravel.hospital') },
  impound = { cardIcon = 'shieldHandPlus', pin = 'poi_exclamationmark_round', what = strings.t('fasttravel.police_impound') },
  valet = { cardIcon = 'keys1', pin = 'poi_parking_round', what = strings.t('fasttravel.valet') },
  parts = { cardIcon = 'wrench', pin = 'poi_point_1_round', what = strings.t('fasttravel.parts_store') },
  auction = { cardIcon = 'carCoins', pin = 'poi_point_1_round', what = strings.t('fasttravel.live_auction') },     -- (the junkyard on auction day)
  job = { cardIcon = 'boxPickUp01', pin = 'poi_pickup_round', what = strings.t('fasttravel.job_pickup') },         -- (a job on the board that starts off the map's places, or the stop you are heading for)
}

-- The places that are not in the career's lists, added to `out` (id -> place): a shop with the name of another place is told apart (the stock dealer
-- 'Belasco Auto' and Wrench Works' trim shop), the weekly live auction stands at the junkyard, and the job stops: the one you are heading for always, the
-- start of a job on the board where no place is within JOB_APART metres already. jobPins: { { id, name, x, y, z, active } } (sl_jobs.pins)
M.JOB_APART = 15
function M.derive(out, jobPins)
  local names = {}
  for _, p in pairs(out) do if p.kind ~= 'shop' and p.name then names[tostring(p.name):lower()] = true end end
  for _, p in pairs(out) do
    if p.kind == 'shop' and names[tostring(p.name):lower()] then p.name = string.format(strings.t('career.s_parts_shop'), p.name) end
  end
  local ids = {}
  for id, p in pairs(out) do if p.kind == 'junkyard' and p.pos then ids[#ids + 1] = id end end
  table.sort(ids)
  local jy = ids[1] and out[ids[1]]
  if jy then out.auction = { id = 'auction', kind = 'auction', name = strings.t('career.junkyard_auction'), pos = jy.pos, at = jy.at or jy.pos, dir = jy.dir } end
  for _, j in ipairs(jobPins or {}) do
    local free = true
    if not j.active then
      for _, p in pairs(out) do
        local q = p.at or p.pos
        if q and (q.x - j.x) ^ 2 + (q.y - j.y) ^ 2 < M.JOB_APART ^ 2 then free = false break end
      end
    end
    if free then
      local at = { x = j.x, y = j.y, z = j.z or 0 }
      out[j.id] = { id = j.id, kind = 'job', name = j.name, pos = at, at = at, dir = { x = 0, y = 1 } }
    end
  end
  return out
end

-- the text that refuses a trip, or nil. ctx: { racing, job, chase, cab } booleans
function M.refusal(ctx)
  ctx = ctx or {}
  if ctx.racing then return strings.t('fasttravel.no_fast_travel_during_a') end
  if ctx.chase then return strings.t('fasttravel.no_fast_travel_with_the') end
  if ctx.cab then return strings.t('fasttravel.you_are_in_a_cab') end
  if ctx.job then return strings.t('fasttravel.finish_or_cancel_your_job') end
  return nil
end

-- where the player arrives at a place: { x, y, z, dx, dy }, the way to face; nil without a position
function M.arrival(place)
  if type(place) ~= 'table' then return nil end
  local drop = cabplan.dropAt(place)                 -- a lot: in front of its cars
  if drop then return drop end
  local p = place.at or place.pos
  if not p then return nil end
  local d = place.dir or { x = 0, y = 1 }
  return { x = p.x, y = p.y, z = p.z, dx = d.x, dy = d.y }
end

-- the bigmap-only entries for the garages, shops and other places: { poiId, kind, placeId, name, cardIcon, pin, what, pos = { x, y, z }, arrive, locked, why }
-- places: id -> place (sl_career.allPlaces: the garages have kind 'garage', the parts shops 'shop'); state: { rep, garageLevel } for the garage ladder
function M.extras(places, state)
  local out = {}
  local ids = {}
  for id, p in pairs(places or {}) do if M.KINDS[p.kind] and (p.at or p.pos) then ids[#ids + 1] = id end end
  table.sort(ids)
  local seen = {}
  for _, id in ipairs(ids) do
    local p = places[id]
    local k = M.KINDS[p.kind]
    local ok, why = true, nil
    local at = p.at or p.pos
    local twin
    for _, q in ipairs(seen) do
      if q.kind == p.kind and (q.x - at.x) ^ 2 + (q.y - at.y) ^ 2 < M.SAME_SPOT ^ 2 then twin = true break end
    end
    if not twin then
      seen[#seen + 1] = { kind = p.kind, x = at.x, y = at.y }
      if p.kind == 'garage' then ok, why = progression.garageAccess(state or {}, id) end
      local a = M.arrival(p)
      out[#out + 1] = { poiId = 'sl_place_' .. id, kind = p.kind, placeId = id, name = p.name or id, cardIcon = k.cardIcon, pin = k.pin,
        what = (ok and k.what or (k.what .. '. ' .. tostring(why))) .. (p.trade and (' · ' .. p.trade) or ''), pos = { x = a.x, y = a.y, z = a.z }, arrive = a, locked = not ok, why = why }
    end
  end
  return out
end

-- what a lot's card says: its kind and its tier
function M.lotDescription(what, tierLabel)
  return tierLabel and (what .. ' · ' .. tierLabel) or what
end

return M
