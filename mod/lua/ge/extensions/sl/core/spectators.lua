-- Street Legal: where the spectators stand (#40). Pure, tested by tools/luatest.js. Crowds for the drag strip, the race track and the meets of a map whose level
-- has none of its own: spots in rows beside a stretch of track (both sides, facing it) or in a ring round a meet. The SLRR Drivers mod
-- (slrrPedestrians.addSpectatorZones) fills them near the camera, within its frame-time budget, and has them cheer when a race ends.

local M = {}

M.SPACING = 1.4          -- m along the track between two spectators
M.ROW_GAP = 1.4
M.ROWS = 2
M.MAX_SPOTS = 60         -- per zone (the mod shows far fewer: its budget decides)

local function unit(dx, dy)
  local l = math.sqrt(dx * dx + dy * dy)
  if l < 1e-9 then return nil end
  return dx / l, dy / l
end

-- spots beside the segment a -> b (points { x, y, z }), both sides, `half` metres from its middle line to the near row's start plus `gap`, facing the track
function M.stand(a, b, half, gap)
  local tx, ty = unit(b.x - a.x, b.y - a.y)
  if not tx then return {} end
  local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
  local nx, ny = ty, -tx
  local out = {}
  local d = 0
  while d <= len and #out < M.MAX_SPOTS do
    local t = d / len
    local cx, cy, cz = a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + ((b.z or a.z) - a.z) * t
    for side = -1, 1, 2 do
      for row = 0, M.ROWS - 1 do
        if #out < M.MAX_SPOTS then
          local off = side * (half + (gap or 3) + row * M.ROW_GAP)
          out[#out + 1] = { cx + nx * off, cy + ny * off, cz, -nx * side, -ny * side }
        end
      end
    end
    d = d + M.SPACING
  end
  return out
end

-- spots in a ring round a meet, between r1 and r2 metres, facing the middle
function M.ring(c, r1, r2, n)
  local out = {}
  for k = 0, n - 1 do
    local a = (k / n) * math.pi * 2
    local r = (k % 2 == 0) and r1 or r2
    local x, y = c.x + math.cos(a) * r, c.y + math.sin(a) * r
    local fx, fy = unit(c.x - x, c.y - y)
    out[#out + 1] = { x, y, c.z, fx, fy }
  end
  return out
end

-- the zone table slrrPedestrians.addSpectatorZones takes
function M.zone(id, kind, spots)
  if #spots == 0 then return nil end
  local cx, cy, cz = 0, 0, 0
  for _, s in ipairs(spots) do cx, cy, cz = cx + s[1], cy + s[2], cz + s[3] end
  cx, cy, cz = cx / #spots, cy / #spots, cz / #spots
  local r = 0
  for _, s in ipairs(spots) do r = math.max(r, math.sqrt((s[1] - cx) ^ 2 + (s[2] - cy) ^ 2)) end
  return { id = id, kind = kind, c = { cx, cy, cz }, r = r + 15, spots = spots, ground = true }
end

-- the stands of a drag strip: lanes = { { from = {x,y,z}, to = {x,y,z} } } (a lane's stage line and its end line); the crowd stands beside the outer lanes
function M.dragStrip(lanes)
  if #lanes == 0 then return {} end
  local a, b, n = { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, #lanes
  for _, l in ipairs(lanes) do
    a.x, a.y, a.z = a.x + l.from.x / n, a.y + l.from.y / n, a.z + l.from.z / n
    b.x, b.y, b.z = b.x + l.to.x / n, b.y + l.to.y / n, b.z + l.to.z / n
  end
  local half = 2.5                                 -- one lane's width, to start with
  if n >= 2 then
    local l1, l2 = lanes[1], lanes[2]
    half = math.sqrt((l1.from.x - l2.from.x) ^ 2 + (l1.from.y - l2.from.y) ^ 2) * 0.5 * (n - 1) + 2
  end
  return M.stand(a, b, half, 4)
end

-- stands round a circuit: nodes = { { pos = {x,y,z}, radius } } in driving order; a stand on the first stretch (the start and finish) and three more
function M.circuitStands(nodes)
  local out = {}
  local n = #nodes
  if n < 4 then return out end
  for _, k in ipairs({ 1, math.floor(n / 4) + 1, math.floor(n / 2) + 1, math.floor(3 * n / 4) + 1 }) do
    local a, b = nodes[k], nodes[k % n + 1]
    out[#out + 1] = M.stand({ x = a.pos[1], y = a.pos[2], z = a.pos[3] }, { x = b.pos[1], y = b.pos[2], z = b.pos[3] },
      math.max(a.radius or 6, b.radius or 6) + 0.5, 3)
  end
  return out
end

return M
