-- Street Legal: the markers of the career's places (T33). Pure: which places have a marker and a big-map entry, and what
-- they are called there (tested by tools/luatest.js). sl/pois draws them with the game's own marker code.
-- A place is a lot (dealer, used lot, scrap yard); the stock dealerships keep their stock markers (stockId).

local M = {}

local strings = require('sl/core/strings')

-- kind of place -> what the game's lists call it (type: dealership shows under the big map's Dealerships; icons are the big map's)
M.KINDS = {
  dealer = { type = 'dealership', cardIcon = 'carDealer', pin = 'poi_dealer_1_rect', what = strings.t('pois.new_cars') },
  junkyard = { type = 'other', cardIcon = 'carsChange', pin = 'poi_dealer_1_rect', what = strings.t('pois.used_cars') },
  scrapyard = { type = 'other', cardIcon = 'trashBin1', pin = 'poi_dealer_1_rect', what = strings.t('pois.scrap_yard') },
}

-- places: id -> { id, kind, name, at = {x, y, z}, stockId }.  Returns a list sorted by id, one record per place with a marker.
function M.records(places)
  local ids = {}
  for id, p in pairs(places or {}) do
    local k = M.KINDS[p.kind]
    if k and p.at then ids[#ids + 1] = id end
  end
  table.sort(ids)
  local out = {}
  for _, id in ipairs(ids) do
    local p, k = places[id], M.KINDS[places[id].kind]
    out[#out + 1] = { poiId = 'sl_place_' .. id, placeId = id, type = k.type, cardIcon = k.cardIcon, pin = k.pin, name = p.name, what = k.what,
      pos = { p.at.x, p.at.y, p.at.z }, stockId = p.stockId,
      marker = p.stockId and 'walking' or 'mission' }       -- (one marker a place: a stock dealership has the game's walking marker at its door)
  end
  return out
end

return M
