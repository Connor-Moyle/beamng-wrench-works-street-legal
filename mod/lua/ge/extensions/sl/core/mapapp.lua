-- Street Legal: the phone's Map app, the parts that need no game: the places grouped by kind with their distance from the player, and the arrival test.
-- Places are { id, name, kind, x, y }; from is { x, y } (nil: no distances).

local M = {}

M.ARRIVED = 15          -- metres from the route's end: it is there
-- the order of the groups on the screen; a kind that is not listed comes after them
M.ORDER = { 'garage', 'dealer', 'junkyard', 'scrapyard', 'auction', 'shop', 'parts', 'carwash', 'gas', 'meet', 'hospital', 'valet', 'job' }

local function rank(kind)
  for i, k in ipairs(M.ORDER) do if k == kind then return i end end
  return #M.ORDER + 1
end

function M.distance(from, p)
  if not from then return nil end
  return math.floor(math.sqrt((p.x - from.x) ^ 2 + (p.y - from.y) ^ 2) + 0.5)
end

-- { { kind, places = { { id, name, dist } nearest first } } } in group order
function M.groups(places, from)
  local by, kinds = {}, {}
  for _, p in ipairs(places) do
    local g = by[p.kind]
    if not g then g = { kind = p.kind, places = {} } by[p.kind] = g kinds[#kinds + 1] = g end
    g.places[#g.places + 1] = { id = p.id, name = p.name, dist = M.distance(from, p), info = p.info }
  end
  for _, g in ipairs(kinds) do
    table.sort(g.places, function(a, b)
      if a.dist and b.dist and a.dist ~= b.dist then return a.dist < b.dist end
      return tostring(a.name) < tostring(b.name)
    end)
  end
  table.sort(kinds, function(a, b)
    local ra, rb = rank(a.kind), rank(b.kind)
    if ra ~= rb then return ra < rb end
    return tostring(a.kind) < tostring(b.kind)
  end)
  return kinds
end

-- the game's ground markers keep the end of the route they show (core_groundMarkers.endWP, a list of positions or nil): the Map's route is still the one
-- on the road only while that list is one point at the place the Map sent it to. A job (or anything else) that sets its own path replaces it.
function M.stillActive(endWP, p)
  if type(endWP) ~= 'table' or #endWP ~= 1 or not endWP[1] or not p then return false end
  return math.abs(endWP[1].x - p.x) < 1 and math.abs(endWP[1].y - p.y) < 1
end

-- the people you have met for the Contacts app: { id, name, kind = 'rival' | 'crew' | 'dealer', line, placeId (may be nil) }; rivals first, then crew leaders, then
-- dealers; an id comes once (a rival who is also a crew leader is a rival)
function M.people(rivals, crews, dealers)
  local out, seen = {}, {}
  for _, list in ipairs({ rivals or {}, crews or {}, dealers or {} }) do
    for _, p in ipairs(list) do
      if p.id and not seen[p.id] then seen[p.id] = true out[#out + 1] = p end
    end
  end
  return out
end

function M.arrived(from, p) return from ~= nil and p ~= nil and M.distance(from, p) <= M.ARRIVED end

-- A rumour pin marks an AREA, not the spot (finding a barn stays a search): the circle's centre is the true spot moved a fixed, id-seeded distance and direction, so the
-- centre is never the spot, the spot is always inside the circle, and the same rumour always draws the same circle. Returns { x, y, r } (metres).
M.RUMOUR_RADIUS = 220
function M.rumourArea(id, x, y)
  local h = 0
  for i = 1, #tostring(id) do h = (h * 31 + tostring(id):byte(i)) % 1000003 end
  local angle = (h % 360) * math.pi / 180
  local dist = M.RUMOUR_RADIUS * (0.35 + 0.35 * ((math.floor(h / 360) % 100) / 100))      -- 35 % to 70 % of the radius away from the spot
  return { x = math.floor(x + math.cos(angle) * dist + 0.5), y = math.floor(y + math.sin(angle) * dist + 0.5), r = M.RUMOUR_RADIUS }
end

return M
