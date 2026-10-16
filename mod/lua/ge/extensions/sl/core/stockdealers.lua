-- Street Legal: the game's own dealerships and garages as career places (T12). Pure: sl/career reads the
-- level's facilities (freeroam_facilities, as data: no career module is loaded) and hands them in as plain
-- tables; this makes the places (the same shape as the map's /street_legal/places json), merges them with the
-- map's own, and picks each dealer's stock from the dealer's filter. Tested by tools/luatest.js.

local progression = require('sl/core/progression')

local M = {}

M.USED_MILEAGE = 50000000     -- the game's Mileage is in metres: a dealer whose cars start at 50,000 km sells used ones
M.MIN_POOL = 4                -- a filter that leaves fewer cars than this is not used (every car is)
M.SAME_GARAGE = 30            -- metres: a stock garage this close to a Wrench Works garage site is that garage
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

-- spots: { { x, y, z, dx, dy } } the facility's parking spots (position and the way a car stands). A dealer
-- without a spot has no lot to put cars on, so no place.
function M.dealer(fac, spots, tr)
  local a = spots and spots[1]
  if not a then return nil end
  local p = { id = 'stock_' .. tostring(fac.id):lower(), kind = 'dealer', name = M.nameOf(fac, tr), pos = arr3(a), display = arr3(a),
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

-- configs: the cars the game has ({ model, config, ... }); passes(config, filter) -> bool is the game's own
-- filter test. shortcut: only the dealer's main filter, not its subFilters (the age bands); upgrade if the
-- stock should follow them.
function M.pool(configs, filter, passes)
  if type(filter) ~= 'table' or not passes then return configs end
  local out = {}
  for _, c in ipairs(configs or {}) do
    local ok, yes = pcall(passes, c, filter)
    if ok and yes then out[#out + 1] = c end
  end
  return #out >= M.MIN_POOL and out or configs
end

-- the places of a level's stock facilities. api (the game's freeroam_facilities, read as data):
--   api.list(type, level) -> the facilities of that type ('dealership', 'garage')
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
    return d and { { x = d.x, y = d.y, z = d.z, dx = d.dx or 0, dy = d.dy or 1 } } or {}
  end
  for _, f in ipairs(api.list('dealership', level) or {}) do
    local p = not f.remotePurchaseOnly and M.dealer(f, spotsOrDoor(f), tr)
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
