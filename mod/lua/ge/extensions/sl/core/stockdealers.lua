-- Street Legal: the game's own dealerships and garages as career places (T12). Pure: sl/career reads the
-- level's facilities (freeroam_facilities, as data: no career module is loaded) and hands them in as plain
-- tables; this makes the places (the same shape as the map's /street_legal/places json), merges them with the
-- map's own, and picks each dealer's stock from the dealer's filter. Tested by tools/luatest.js.

local progression = require('sl/core/progression')

local M = {}

M.USED_MILEAGE = 50000000     -- the game's Mileage is in metres: a dealer whose cars start at 50,000 km sells used ones
M.MIN_POOL = 4                -- a filter that leaves fewer cars than this is not used (every car is)
M.SAME_GARAGE = 30            -- metres: a stock garage this close to a Wrench Works garage site is that garage
M.SLOT_GAP = 3                -- m: neighbour slots stand this far apart, along the spot's sideways axis
M.SLOT_MIN = 2.5              -- m: no slot closer than this to another
M.SLOT_REACH = 2.5            -- m: a slot needs this much clear space towards the next slot and the arrival point
M.SLOT_RINGS = 3              -- slots out from a spot, each side
M.SLOT_CAP = 6                -- cars on a lot
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

-- More cars on a lot (T22): the parking spots first, then neighbour slots out from each spot along its sideways axis, both
-- sides, SLOT_GAP apart, each kept only if the ground there is the spot's (rays.ground(x, y, z) -> the ground z, or nil, from
-- 1.5 m above; within 0.25 m of the spot's z), there is room (rays.free(x, y, z, dx, dy, dist) -> true when nothing is
-- hit within dist at 0.8 m height) towards the next slot outward and towards the arrival point, and it is SLOT_MIN from
-- every kept slot. A side stops at its first slot that fails. Capped at SLOT_CAP. No rays, or a spot made up from a door
-- (spot.synthetic): the spots as they are.
function M.slots(spots, rays)
  local kept = {}
  for _, sp in ipairs(spots or {}) do if #kept < M.SLOT_CAP then kept[#kept + 1] = sp end end
  local a = spots and spots[1]
  if not rays or not a or a.synthetic then return kept end
  local alen = math.sqrt(a.dx ^ 2 + a.dy ^ 2)
  if alen < 1e-6 then return kept end
  local arrival = { x = a.x + a.dx / alen * 8, y = a.y + a.dy / alen * 8 }      -- (where sl/career puts the player: 8 m in front)
  local blocked = {}
  for k = 1, M.SLOT_RINGS do
    for i, sp in ipairs(spots) do
      local len = math.sqrt(sp.dx ^ 2 + sp.dy ^ 2)
      for _, sign in ipairs({ 1, -1 }) do
        if len > 1e-6 and #kept < M.SLOT_CAP and not blocked[i * sign] then
          local sx, sy = sp.dy / len * sign, -sp.dx / len * sign
          local x, y = sp.x + sx * M.SLOT_GAP * k, sp.y + sy * M.SLOT_GAP * k
          local gz = rays.ground(x, y, sp.z)
          local ok = gz ~= nil and math.abs(gz - sp.z) <= 0.25 and rays.free(x, y, gz, sx, sy, M.SLOT_REACH)
          if ok then
            local ax, ay = arrival.x - x, arrival.y - y
            local d = math.sqrt(ax * ax + ay * ay)
            ok = d < 0.5 or rays.free(x, y, gz, ax / d, ay / d, math.min(M.SLOT_REACH, d))
          end
          for _, o in ipairs(ok and kept or {}) do
            if math.sqrt((o.x - x) ^ 2 + (o.y - y) ^ 2) < M.SLOT_MIN then ok = false break end
          end
          if ok then kept[#kept + 1] = { x = x, y = y, z = gz, dx = sp.dx, dy = sp.dy } else blocked[i * sign] = true end
        end
      end
    end
  end
  return kept
end

-- spots: { { x, y, z, dx, dy } } the facility's parking spots (position and the way a car stands). A dealer
-- without a spot has no lot to put cars on, so no place.
function M.dealer(fac, spots, tr, rays)
  if not (spots and spots[1]) then return nil end
  spots = M.slots(spots, rays)
  local a = spots[1]
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

-- Never on a dealer's lot, whatever its filter or fallback: the police, service (ambulance, fire...), race, rally, drift and
-- show cars (the game's "Config Type"), and one-offs (a Population of 1). c.raw is the game's own entry.
local NOT_FOR_SALE = { Police = true, Service = true, Race = true, Rally = true, Drift = true, Powerglow = true }
function M.forSale(c)
  local r = type(c) == 'table' and c.raw
  if type(r) ~= 'table' then return true end
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
--   api.rays -> { ground, free } for M.slots (nil: no extra slots)
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
    local p = not f.remotePurchaseOnly and M.dealer(f, spotsOrDoor(f), tr, api.rays)
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
