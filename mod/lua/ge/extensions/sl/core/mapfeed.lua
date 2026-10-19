-- Street Legal: the Maps app's road data, the part that needs no game: road classes from a navgraph link and tiles of segments.
-- nodes = map.getMap().nodes: { [id] = { pos = {x, y, z}, radius, links = { [otherId] = { speedLimit, drivability, lanes, type, hiddenInNavi } } } }
-- A tile is TILE metres square; its key is "tx,ty". Each entry is { k = class, p = { x1, y1, x2, y2 } } (whole metres).

local M = {}

M.TILE = 256
-- class limits: the speed limit in m/s and the road width (node radius in m, lane count) each give a class; the higher one wins,
-- so a link without a speed limit (most of Valo City's) still reads by its width
M.SPEED = { highway = 25, arterial = 16, street = 9 }
M.RADIUS = { highway = 8, arterial = 4.5, street = 2.5 }
M.LANES = { highway = 5, arterial = 3 }
local RANK = { minor = 1, street = 2, arterial = 3, highway = 4 }
local NAME = { 'minor', 'street', 'arterial', 'highway' }

local function laneCount(lanes)
  if type(lanes) == 'string' then return #lanes end
  return tonumber(lanes) or 0
end

local function byLimit(v, limits)
  if v >= limits.highway then return 4 end
  if v >= limits.arterial then return 3 end
  if v >= limits.street then return 2 end
  return 1
end

-- 'minor' | 'street' | 'arterial' | 'highway' for the link between two nodes
function M.classify(link, a, b)
  link = link or {}
  if (link.drivability or 1) < 0.5 then return 'minor' end                  -- (a dirt track or a path is never a main road)
  local best = 1
  if link.speedLimit then best = math.max(best, byLimit(link.speedLimit, M.SPEED)) end
  local r = math.max(a and a.radius or 0, b and b.radius or 0)
  best = math.max(best, byLimit(r, M.RADIUS))
  local n = laneCount(link.lanes)
  if n >= M.LANES.highway then best = math.max(best, 4) elseif n >= M.LANES.arterial then best = math.max(best, 3) end
  return NAME[best]
end

function M.key(x, y) return math.floor(x / M.TILE) .. ',' .. math.floor(y / M.TILE) end

local function round(v) return math.floor(v + 0.5) end

-- x, y of anything with a position: a plain table or the game's vec3 (userdata, not a table); nil when it has none
local function xy(pos)
  local ok, x, y = pcall(function() return pos.x, pos.y end)
  if ok and type(x) == 'number' and type(y) == 'number' then return x, y end
end
M.xy = xy

-- a builder that walks the nodes a few at a time: b = M.builder(nodes); repeat until b:step(clock, seconds) is true; b.tiles is the result.
function M.builder(nodes)
  local self = { tiles = {}, count = 0, done = false }
  local seen, key = {}, nil
  function self:step(clock, budget)
    local t0 = clock()
    local n = 0
    while true do
      local id, a = next(nodes, key)
      if id == nil then self.done = true return true end
      key = id
      for other, link in pairs(type(a) == 'table' and type(a.links) == 'table' and a.links or {}) do
        local b = nodes[other]
        local ax, ay, bx, by
        if type(b) == 'table' and type(a) == 'table' then ax, ay = xy(a.pos) bx, by = xy(b.pos) end
        if not (ax and bx) then b = nil end      -- (a malformed node is skipped)
        local k = tostring(id) < tostring(other) and (tostring(id) .. '|' .. tostring(other)) or (tostring(other) .. '|' .. tostring(id))
        if b and not seen[k] then
          seen[k] = true
          local x1, y1, x2, y2 = round(ax), round(ay), round(bx), round(by)
          local tk = M.key((x1 + x2) / 2, (y1 + y2) / 2)
          local t = self.tiles[tk]
          if not t then t = {} self.tiles[tk] = t end
          t[#t + 1] = { k = M.classify(link, a, b), p = { x1, y1, x2, y2 } }
          self.count = self.count + 1
        end
      end
      n = n + 1
      if n % 50 == 0 and clock() - t0 > budget then return false end
    end
  end
  return self
end

-- the tile keys that cover a square around (x, y) with the given half size in metres
function M.tilesAround(x, y, half)
  local out = {}
  local x0, x1 = math.floor((x - half) / M.TILE), math.floor((x + half) / M.TILE)
  local y0, y1 = math.floor((y - half) / M.TILE), math.floor((y + half) / M.TILE)
  for tx = x0, x1 do for ty = y0, y1 do out[#out + 1] = tx .. ',' .. ty end end
  return out
end

-- a route (the game's path nodes, each with a pos) as a flat list of whole metres, thinned to points at least `gap` metres apart
function M.routePoints(path, gap)
  local out, lx, ly = {}, nil, nil
  gap = gap or 6
  for i, e in ipairs(path or {}) do
    local px, py = xy(type(e) == 'table' and e.pos or nil)
    if px then
      local x, y = round(px), round(py)
      if not lx or i == #path or (x - lx) ^ 2 + (y - ly) ^ 2 >= gap * gap then
        out[#out + 1], out[#out + 2] = x, y
        lx, ly = x, y
      end
    end
  end
  return out
end

-- who needs the feed: the HUD app and the phone's Map tab each say so by name; it runs while any of them does.
-- use(name, on) returns true when a consumer was ADDED (it has not seen the route and the places yet: send them again)
function M.consumers()
  local set = {}
  local self = {}
  function self.use(name, on)
    local had = set[name] == true
    set[name] = on and true or nil
    return on and not had or false
  end
  function self.any() return next(set) ~= nil end
  function self.clear() set = {} end
  return self
end

M.RANK = RANK
return M
