-- Street Legal: fast travel from the big map to the career's places (#20). Pure, tested by tools/luatest.js.
-- Every dealer, used lot, scrap yard, garage and Wrench Works shop is a point on the big map. Where you arrive: a lot's car park (in front
-- of its cars, as the cab drops you), a garage in front of its door, a shop on its forecourt marker. A garage above your level is shown
-- greyed with the reputation it needs. Travel is refused while a race, a job, a chase or a cab ride is on.

local cabplan = require('sl/core/cabplan')
local progression = require('sl/core/progression')
local tiers = require('sl/core/tiers')

local M = {}

local strings = require('sl/core/strings')

M.KINDS = {
  garage = { cardIcon = 'garage01', what = 'Garage' },
  shop = { cardIcon = 'wrench', what = strings.t('fasttravel.parts_shop') },
}

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

-- the bigmap-only entries for the garages and shops: { poiId, kind, placeId, name, cardIcon, what, pos = { x, y, z }, arrive, locked, why }
-- places: id -> place (the garages have kind 'garage'); shops: { { id, name, trade, pos } }; state: { rep, garageLevel } for the garage ladder
function M.extras(places, shops, state)
  local out = {}
  local ids = {}
  for id, p in pairs(places or {}) do if p.kind == 'garage' and (p.at or p.pos) then ids[#ids + 1] = id end end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local p = places[id]
    local ok, why = progression.garageAccess(state or {}, id)
    local a = M.arrival(p)
    out[#out + 1] = { poiId = 'sl_place_' .. id, kind = 'garage', placeId = id, name = p.name, cardIcon = M.KINDS.garage.cardIcon,
      what = ok and M.KINDS.garage.what or (M.KINDS.garage.what .. '. ' .. tostring(why)), pos = { x = a.x, y = a.y, z = a.z }, arrive = a, locked = not ok, why = why }
  end
  local sorted = {}
  for _, s in ipairs(shops or {}) do if s.id and s.pos then sorted[#sorted + 1] = s end end
  table.sort(sorted, function(a, b) return tostring(a.id) < tostring(b.id) end)
  for _, s in ipairs(sorted) do
    out[#out + 1] = { poiId = 'sl_shop_' .. s.id, kind = 'shop', placeId = s.id, name = s.name or s.id, cardIcon = M.KINDS.shop.cardIcon,
      what = M.KINDS.shop.what .. (s.trade and (' · ' .. s.trade) or ''), pos = { x = s.pos.x, y = s.pos.y, z = s.pos.z },
      arrive = { x = s.pos.x, y = s.pos.y, z = s.pos.z, dx = 0, dy = 1 }, locked = false }
  end
  return out
end

-- what a lot's card says: its kind and its tier
function M.lotDescription(what, tierLabel)
  return tierLabel and (what .. ' · ' .. tierLabel) or what
end

return M
