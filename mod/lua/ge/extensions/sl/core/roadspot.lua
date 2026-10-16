-- Street Legal: where a car bought at a lot leaves from: the nearest city lane (playtest: the yards' display
-- spots are boxed in). From the game's navgraph (map.getMap().nodes): a link of a public, drivable, visible,
-- city-speed road between two plain road nodes (no junction), at its middle, in the right-hand lane's centre,
-- facing along that lane. No game calls: positions are anything with x, y, z.

local M = {}

M.MAX_SPEED = 22          -- m/s: above this it is a freeway
M.LOT_REACH = 60          -- m: a lot's nearest city lane is at most this far (the car leaves by it)
M.LOT_TARGET = 45         -- m: a lot further than that is moved to this distance from its lane
M.MIN_RADIUS = 1.5        -- m: a lane, not a path (Valo City's navgraph is one node per lane, radius 1.75)

local function degree(node) local n = 0 for _ in pairs(node.links or {}) do n = n + 1 end return n end

local function cityLink(e)
  return (e.drivability or 1) >= 0.9 and not e.hiddenInNavi and (e.type == nil or e.type == 'public')
    and (e.speedLimit == nil or e.speedLimit <= M.MAX_SPEED)
end

-- candidate spots, nearest first: { x, y, z, dx, dy, dist } (dx, dy: unit heading); rightHand = traffic keeps right
function M.candidates(nodes, from, rightHand, maxDist)
  local out, seen = {}, {}
  maxDist = maxDist or 400
  for id, a in pairs(nodes or {}) do
    for oid, e in pairs(a.links or {}) do
      local key = id < oid and (id .. '|' .. oid) or (oid .. '|' .. id)
      local b = nodes[oid]
      if not seen[key] and b and cityLink(e) and degree(a) <= 2 and degree(b) <= 2 then     -- (no junction; a lane end is fine: Valo City's one-way lanes are mostly two-node links)
        seen[key] = true
        local p, q = nodes[e.inNode or id].pos, nodes[e.outNode or oid].pos
        local r = math.min(a.radius or 0, b.radius or 0)
        local dx, dy = q.x - p.x, q.y - p.y
        local len = math.sqrt(dx * dx + dy * dy)
        if r >= M.MIN_RADIUS and len > 6 then
          dx, dy = dx / len, dy / len
          local lanes = e.lanes and #e.lanes or (e.oneWay and 1 or 2)
          local side = r - r / math.max(1, lanes)           -- the outermost lane's centre, from the middle
          local rx, ry = dy, -dx                            -- right of the heading
          if not rightHand then rx, ry = -rx, -ry end
          local x, y, z = (p.x + q.x) / 2 + rx * side, (p.y + q.y) / 2 + ry * side, (p.z + q.z) / 2
          local d = math.sqrt((x - from.x) ^ 2 + (y - from.y) ^ 2)
          if d <= maxDist then out[#out + 1] = { x = x, y = y, z = z, dx = dx, dy = dy, dist = d } end
        end
      end
    end
  end
  table.sort(out, function(u, v) return u.dist < v.dist end)
  return out
end

-- the first candidate with no car within `clear` metres (others = list of positions)
function M.pick(cands, others, clear)
  clear = clear or 6
  for _, c in ipairs(cands) do
    local free = true
    for _, o in ipairs(others or {}) do
      if (o.x - c.x) ^ 2 + (o.y - c.y) ^ 2 < clear * clear then free = false break end
    end
    if free then return c end
  end
end

-- A lot whose nearest city lane c (a candidate, with .dist) is further than `limit` metres: where to stand so that it
-- is `target` metres away, on the line to the lane. nil when it is near enough. (T15: West Coast USA's lots)
function M.towards(from, c, limit, target)
  if not c or c.dist <= limit then return nil end
  local k = (c.dist - target) / c.dist
  return { x = from.x + (c.x - from.x) * k, y = from.y + (c.y - from.y) * k, z = from.z + ((c.z or from.z) - from.z) * k }
end

-- The public roads near (cx, cy), as flat segments { x1, y1, x2, y2, half } with half the road's width (the narrower node radius),
-- from the navgraph: any public, drivable, visible link, freeways too (a lot's bays are not on a road and not across one: T37).
-- Links with an end within `reach` metres of the point.
function M.roadSegments(nodes, cx, cy, reach)
  local out, seen = {}, {}
  for id, a in pairs(nodes or {}) do
    for oid, e in pairs(a.links or {}) do
      local key = id < oid and (id .. '|' .. oid) or (oid .. '|' .. id)
      local b = nodes[oid]
      if not seen[key] and b and (e.drivability or 1) >= 0.9 and not e.hiddenInNavi and (e.type == nil or e.type == 'public') then
        seen[key] = true
        local near = math.min((a.pos.x - cx) ^ 2 + (a.pos.y - cy) ^ 2, (b.pos.x - cx) ^ 2 + (b.pos.y - cy) ^ 2)
        if near <= reach * reach then
          out[#out + 1] = { x1 = a.pos.x, y1 = a.pos.y, x2 = b.pos.x, y2 = b.pos.y, half = math.min(a.radius or 2, b.radius or 2) }
        end
      end
    end
  end
  return out
end

-- distance between two flat segments (0 when they cross)
local function pointSeg(px, py, x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  local l2 = dx * dx + dy * dy
  local t = l2 > 0 and math.max(0, math.min(1, ((px - x1) * dx + (py - y1) * dy) / l2)) or 0
  return math.sqrt((px - x1 - t * dx) ^ 2 + (py - y1 - t * dy) ^ 2)
end
function M.segDist(ax, ay, bx, by, cx, cy, dx, dy)
  local function side(px, py, qx, qy, rx, ry) return (qx - px) * (ry - py) - (qy - py) * (rx - px) end
  local d1, d2 = side(ax, ay, bx, by, cx, cy), side(ax, ay, bx, by, dx, dy)
  local d3, d4 = side(cx, cy, dx, dy, ax, ay), side(cx, cy, dx, dy, bx, by)
  if ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0)) then return 0 end
  return math.min(pointSeg(ax, ay, cx, cy, dx, dy), pointSeg(bx, by, cx, cy, dx, dy), pointSeg(cx, cy, ax, ay, bx, by), pointSeg(dx, dy, ax, ay, bx, by))
end

return M
