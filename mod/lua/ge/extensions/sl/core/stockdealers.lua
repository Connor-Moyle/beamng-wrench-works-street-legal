-- Street Legal: the game's own dealerships and garages as career places (T12). Pure: sl/career reads the
-- level's facilities (freeroam_facilities, as data: no career module is loaded) and hands them in as plain
-- tables; this makes the places (the same shape as the map's /street_legal/places json), merges them with the
-- map's own, and picks each dealer's stock from the dealer's filter. Tested by tools/luatest.js.

local progression = require('sl/core/progression')

local M = {}

M.USED_MILEAGE = 50000000     -- the game's Mileage is in metres: a dealer whose cars start at 50,000 km sells used ones
M.MIN_POOL = 4                -- a filter that leaves fewer cars than this is not used (every car is)
M.SAME_GARAGE = 30            -- metres: a stock garage this close to a Wrench Works garage site is that garage
M.BAY_RADIUS = 38             -- m: the painted bays used are within this of the lot's first spot
M.BAY_DZ = 1                  -- m: and on its ground level
M.BAY_APART = 1.8             -- m: no bay on top of a spot already kept
M.BAY_MIN = 3                 -- spots in all, or the lot keeps its own
M.BAY_CAP = 6                 -- cars on a lot
M.SAME_PLACE = 80             -- metres: a map place this close to a stock dealer is the same dealer

-- the dealer's filter says new or used by the mileage its cars start at
function M.offerKind(filter)
  local m = type(filter) == 'table' and type(filter.whiteList) == 'table' and filter.whiteList.Mileage
  return (type(m) == 'table' and (tonumber(m.min) or 0) >= M.USED_MILEAGE) and 'used' or 'dealer'
end

-- the translated name, or the id read as words ("belascoAuto" -> "Belasco Auto")
function M.nameOf(fac, tr)
  local t = tr and fac.name and tr(fac.name)
  if type(t) == 'string' and t ~= '' and t ~= fac.name then return t end
  local words = tostring(fac.id):gsub('(%l)(%u)', '%1 %2')
  return (words:gsub('^%l', string.upper))
end

local function arr3(a) return { a.x, a.y, a.z } end

-- More cars on a lot (T37): the lot's own parking spots first (the stock parkingSpotNames), then the map's painted parking bays
-- around it (the level's city parking sites: the spots parked traffic uses), nearest first. candidates: { { x, y, z, dx, dy,
-- occupied } } (every bay near the lot), roads: { { x1, y1, x2, y2, half } } (the public roads near it). A bay is kept if it is
-- within BAY_RADIUS of the first spot, on its ground level (BAY_DZ), not taken by a parked car, not on a road, not across a
-- road from the lot (the straight line to it crosses no road), and not on top of a spot already kept (BAY_APART). Capped at
-- BAY_CAP. Fewer than BAY_MIN spots in all: the lot's own spots, as they were. A spot made up from a door (synthetic): as it is.
local roadspot = require('sl/core/roadspot')
function M.withBays(spots, candidates, roads)
  local own = {}
  for _, sp in ipairs(spots or {}) do own[#own + 1] = sp end
  local a = own[1]
  if not a or a.synthetic or type(candidates) ~= 'table' then return own end
  local function flat(p, q) return math.sqrt((p.x - q.x) ^ 2 + (p.y - q.y) ^ 2) end
  local function onRoad(c)
    for _, r in ipairs(roads or {}) do
      if roadspot.segDist(c.x, c.y, c.x, c.y, r.x1, r.y1, r.x2, r.y2) < r.half then return true end
    end
    return false
  end
  local function acrossRoad(c)
    for _, r in ipairs(roads or {}) do
      if roadspot.segDist(a.x, a.y, c.x, c.y, r.x1, r.y1, r.x2, r.y2) < r.half then return true end
    end
    return false
  end
  local list = {}
  for _, c in ipairs(candidates) do
    if not c.occupied and flat(a, c) <= M.BAY_RADIUS and math.abs((c.z or a.z) - a.z) <= M.BAY_DZ
        and (c.dx ~= 0 or c.dy ~= 0) and not onRoad(c) and not acrossRoad(c) then
      list[#list + 1] = c
    end
  end
  table.sort(list, function(u, v) return flat(a, u) < flat(a, v) end)
  local out = {}
  for _, sp in ipairs(own) do if #out < M.BAY_CAP then out[#out + 1] = sp end end
  for _, c in ipairs(list) do
    if #out >= M.BAY_CAP then break end
    local free = true
    for _, k in ipairs(out) do if flat(k, c) < M.BAY_APART then free = false break end end
    if free then out[#out + 1] = { x = c.x, y = c.y, z = c.z, dx = c.dx, dy = c.dy } end
  end
  return #out >= M.BAY_MIN and out or own
end

-- spots: { { x, y, z, dx, dy } } the facility's parking spots (position and the way a car stands). A dealer
-- without a spot has no lot to put cars on, so no place.
function M.dealer(fac, spots, tr, bays)
  if not (spots and spots[1]) then return nil end
  if bays and not spots[1].synthetic then
    local candidates, roads = bays(spots[1])
    spots = M.withBays(spots, candidates, roads)
  end
  local a = spots[1]
  local p = { id = 'stock_' .. tostring(fac.id):lower(), stockId = fac.id, kind = 'dealer', name = M.nameOf(fac, tr), pos = arr3(a), display = arr3(a),
    displayDir = { a.dx, a.dy }, displays = {}, stock = { kind = M.offerKind(fac.filter), filter = fac.filter } }
  for _, s in ipairs(spots) do p.displays[#p.displays + 1] = { pos = arr3(s), dir = { s.dx, s.dy } } end
  return p
end

-- a garage: where its first parking spot is, or its door
function M.garage(fac, spots, door, tr)
  local a = spots and spots[1] or door
  if not a then return nil end
  return { id = 'stock_' .. tostring(fac.id):lower(), kind = 'garage', name = M.nameOf(fac, tr), pos = arr3(a), dir = a.dx and { a.dx, a.dy } or { 0, 1 } }
end

local function apart(a, b) return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) end

-- the stock places win over the map's own where they are the same dealer (the same name, or close): the stock
-- place then takes the map place's id, so what points at it ("dealer") still finds it. Others are kept.
function M.merge(stock, mine)
  local out, taken = {}, {}
  for _, p in ipairs(stock) do out[#out + 1] = p end
  for _, m in ipairs(mine) do
    local best, bs
    if m.kind == 'dealer' and type(m.pos) == 'table' then
      for _, p in ipairs(stock) do
        if p.stock and not taken[p] then
          local same = tostring(m.name):lower() == p.name:lower()
          local d = apart(m.pos, p.pos)
          local score = same and -1 or d
          if (same or d < M.SAME_PLACE) and (not bs or score < bs) then best, bs = p, score end
        end
      end
    end
    if best then taken[best], best.id = true, m.id else out[#out + 1] = m end
  end
  return out
end

-- Never on a dealer's lot, whatever its filter or fallback: the police, service (ambulance, fire...), race, rally, drift and
-- show cars (the game's "Config Type"), and one-offs (a Population of 1). c.raw is the game's own entry.
local NOT_FOR_SALE = { Police = true, Service = true, Race = true, Rally = true, Drift = true, Powerglow = true }
function M.forSale(c)
  local r = type(c) == 'table' and c.raw
  if type(r) ~= 'table' then return true end
  -- the game's tutorial and scenario configs (covet_tutorial, apmTutorial_sunburst...) are props of its own missions, never stock
  local ident = (tostring(r.key or '') .. ' ' .. tostring(r.pcFilename or '') .. ' ' .. tostring(r.Name or '')):lower()
  if ident:find('tutorial', 1, true) or ident:find('scenario', 1, true) then return false end
  if type(r['Config Type']) == 'string' and NOT_FOR_SALE[r['Config Type']] then return false end
  local ag = type(r.aggregates) == 'table' and r.aggregates['Config Type']
  for k in pairs(type(ag) == 'table' and ag or {}) do if NOT_FOR_SALE[k] then return false end end
  local pop = tonumber(r.Population)
  return not (pop and pop <= 1)
end

-- configs: the cars the game has ({ model, config, raw, ... }); passes(config, filter) -> bool is the game's own filter
-- test. The dealer's cars are the ones for sale that pass its filter. Too few (under MIN_POOL): the filter is widened a
-- key at a time, the narrowest key (the one that lets the fewest cars through alone) dropped first, until there are
-- enough; the blackList is never dropped. With nothing left to drop, every car for sale. shortcut: only the dealer's
-- main filter, not its subFilters (the age bands); upgrade if the stock should follow them.
function M.pool(configs, filter, passes)
  local base = {}
  for _, c in ipairs(configs or {}) do if M.forSale(c) then base[#base + 1] = c end end
  if type(filter) ~= 'table' or not passes then return base end
  local function count(f)
    local out = {}
    for _, c in ipairs(base) do
      local ok, yes = pcall(passes, c, f)
      if ok and yes then out[#out + 1] = c end
    end
    return out
  end
  local white = type(filter.whiteList) == 'table' and filter.whiteList or {}
  local keys = {}
  for k in pairs(white) do
    local alone = count({ whiteList = { [k] = white[k] }, blackList = filter.blackList })
    keys[#keys + 1] = { key = k, n = #alone }
  end
  table.sort(keys, function(a, b) if a.n ~= b.n then return a.n < b.n end return tostring(a.key) < tostring(b.key) end)
  local kept = {}
  for k, v in pairs(white) do kept[k] = v end
  local i = 0
  repeat
    local out = count({ whiteList = kept, blackList = filter.blackList })
    if #out >= M.MIN_POOL then return out end
    i = i + 1
    if keys[i] then kept[keys[i].key] = nil end
  until i > #keys
  return base
end

-- the places of a level's stock facilities. api (the game's freeroam_facilities, read as data):
--   api.list(type, level) -> the facilities of that type ('dealership', 'garage')
--   api.bays(firstSpot) -> candidates, roads for M.withBays (nil: the lot's own spots only)
--   api.ownSpots() -> { { x, y } } where Wrench Works' garage sites are
--   api.spots(f) -> { { x, y, z, dx, dy } }   api.door(f) -> { x, y, z, dx, dy } or nil (dx, dy: the way it faces, if known)
-- A map without stockFacilities gets none. A garage that is already one of the map's career garages (Wrench Works'
-- sites) is not added again; the tutorial's seller (remotePurchaseOnly) has no lot.
function M.fromFacilities(api, level, tr)
  if not api or not progression.has(level, 'stockFacilities') then return {} end
  local own = {}
  for _, g in ipairs((progression.MAPS[level] or {}).garages or {}) do own[g.id] = true end
  local out = {}
  -- a dealer with no parking spot stands on its door (api.door: x, y, z and, if known, the way it faces dx, dy)
  local function spotsOrDoor(f)
    local spots = api.spots(f)
    if spots and #spots > 0 then return spots end
    local d = api.door(f)
    return d and { { x = d.x, y = d.y, z = d.z, dx = d.dx or 0, dy = d.dy or 1, synthetic = true } } or {}
  end
  for _, f in ipairs(api.list('dealership', level) or {}) do
    local p = not f.remotePurchaseOnly and M.dealer(f, spotsOrDoor(f), tr, api.bays)
    if p then out[#out + 1] = p end
  end
  -- Wrench Works' garages have their own ids on the stock facilities' (the same building): a stock garage next to
  -- one of its sites is that garage
  local sites = api.ownSpots and api.ownSpots() or {}
  for _, f in ipairs(api.list('garage', level) or {}) do
    local p = not own[f.id] and M.garage(f, api.spots(f), api.door(f), tr)
    for _, q in ipairs(p and sites or {}) do
      if apart(p.pos, { q.x, q.y }) < M.SAME_GARAGE then p = nil break end
    end
    if p then out[#out + 1] = p end
  end
  return out
end

-- The places, and whether to ask again: a career can start before the level has loaded its facilities, and a map with
-- stock facilities that gave none yet is tried again (state.retry) up to MAX_TRIES times. makeApi() -> api, tr
-- (nil when the game's facilities are not there).
M.MAX_TRIES = 20
function M.load(state, level, makeApi)
  local api, tr = makeApi()
  local list = M.fromFacilities(api, level, tr)
  state.tries = (state.tries or 0) + 1
  state.retry = progression.has(level, 'stockFacilities') and #list == 0 and state.tries < M.MAX_TRIES
  return list
end

return M
