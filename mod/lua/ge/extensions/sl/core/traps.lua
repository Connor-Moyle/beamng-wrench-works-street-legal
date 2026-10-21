-- Street Legal: speed traps and speed zones (campaign idea #1). A trap is a gate across a long straight road: your speed as you cross it counts. A zone is two gates on a long road: your
-- average speed between them counts. Each has a target (a first time over it pays) and a personal best. The roads are chosen from the navgraph with a seeded roll, so the same career gets the
-- same traps on the same map. Pure, no game calls (nodes = map.getMap().nodes): tested by tools/luatest.js.

local M = {}

local strings = require('sl/core/strings')

M.TRAP_MIN = 180            -- m: the shortest road link a trap is put on
M.ZONE_MIN = 350            -- m: the shortest link a zone is put on
M.APART = 600               -- m between two traps / zones
M.HALF = 8                  -- m: half the width of a gate
M.TRAPS, M.ZONES = 6, 2     -- how many
M.PAY = { trap = 250, zone = 400 }
M.REP = 5
M.ZONE_MAX_TIME = 120       -- s from the first gate to the second

local function round10(x) return math.floor(x / 10 + 0.5) * 10 end

-- the road links that can hold one: public, drivable, visible, long enough, with a speed limit that is a real road's (above 15 m/s)
local function candidates(nodes)
  local out, seen = {}, {}
  for id, a in pairs(nodes or {}) do
    for oid, e in pairs(a.links or {}) do
      local key = id < oid and (id .. '|' .. oid) or (oid .. '|' .. id)
      local b = nodes[oid]
      if not seen[key] and b and (e.drivability or 1) >= 0.9 and not e.hiddenInNavi and (e.type == nil or e.type == 'public') and (e.speedLimit == nil or e.speedLimit > 15) then
        seen[key] = true
        local dx, dy = b.pos.x - a.pos.x, b.pos.y - a.pos.y
        local len = math.sqrt(dx * dx + dy * dy)
        if len >= M.TRAP_MIN then
          out[#out + 1] = { key = key, a = a.pos, b = b.pos, dx = dx / len, dy = dy / len, len = len, limit = e.speedLimit or 25 }
        end
      end
    end
  end
  table.sort(out, function(p, q) return p.key < q.key end)      -- (the same order every time, whatever the order of pairs)
  return out
end

local function far(list, x, y)
  for _, t in ipairs(list) do if (t.x - x) ^ 2 + (t.y - y) ^ 2 < M.APART ^ 2 then return false end end
  return true
end

-- the traps and zones of a map: { { id, kind = 'trap' | 'zone', name, x, y, z, dx, dy, limit, target, len, g1 = { x, y }, g2 = { x, y } } }; rng is sl/core/rng
function M.select(nodes, rng)
  local cands = candidates(nodes)
  -- a seeded shuffle
  for i = #cands, 2, -1 do local j = rng:int(i) cands[i], cands[j] = cands[j], cands[i] end
  local out, nTrap, nZone = {}, 0, 0
  -- the long links first for the zones, then the rest for the traps
  for _, c in ipairs(cands) do
    if nZone < M.ZONES and c.len >= M.ZONE_MIN then
      local mx, my = (c.a.x + c.b.x) / 2, (c.a.y + c.b.y) / 2
      if far(out, mx, my) then
        nZone = nZone + 1
        out[#out + 1] = { id = 'z' .. nZone, kind = 'zone', name = strings.t('traps.zone', nZone), x = mx, y = my, z = (c.a.z + c.b.z) / 2, dx = c.dx, dy = c.dy, limit = c.limit,
          len = c.len * 0.7, target = round10(c.limit * 1.1 * 3.6), g1 = { x = c.a.x + c.dx * c.len * 0.15, y = c.a.y + c.dy * c.len * 0.15 }, g2 = { x = c.a.x + c.dx * c.len * 0.85, y = c.a.y + c.dy * c.len * 0.85 } }
      end
    end
  end
  for _, c in ipairs(cands) do
    if nTrap >= M.TRAPS then break end
    local mx, my = (c.a.x + c.b.x) / 2, (c.a.y + c.b.y) / 2
    if far(out, mx, my) then
      nTrap = nTrap + 1
      out[#out + 1] = { id = 't' .. nTrap, kind = 'trap', name = strings.t('traps.trap', nTrap), x = mx, y = my, z = (c.a.z + c.b.z) / 2, dx = c.dx, dy = c.dy, limit = c.limit, len = 0,
        target = math.max(110, round10(c.limit * 1.5 * 3.6)), g1 = { x = mx, y = my } }
    end
  end
  return out
end

-- did the move p0 -> p1 cross the gate at g (across the road, M.HALF each side, the road runs d)? 
function M.crossed(p0, p1, g, d)
  local nx, ny = -d.dy, d.dx
  local ax, ay, bx, by = g.x - nx * M.HALF, g.y - ny * M.HALF, g.x + nx * M.HALF, g.y + ny * M.HALF
  local function cross(ox, oy, px, py, qx, qy) return (px - ox) * (qy - oy) - (py - oy) * (qx - ox) end
  local d1, d2 = cross(ax, ay, bx, by, p0.x, p0.y), cross(ax, ay, bx, by, p1.x, p1.y)
  local d3, d4 = cross(p0.x, p0.y, p1.x, p1.y, ax, ay), cross(p0.x, p0.y, p1.x, p1.y, bx, by)
  return (d1 > 0) ~= (d2 > 0) and (d3 > 0) ~= (d4 > 0)
end

-- a result for a trap or a zone (km/h as a whole number) against its record { best, count, paid }: returns the new record and { first = it reached the target for the first time, best = a personal best }
function M.score(rec, t, kmh)
  rec = rec or { best = 0, count = 0, paid = false }
  kmh = math.floor(kmh)
  local out = { first = false, best = kmh > rec.best }
  local new = { best = math.max(rec.best, kmh), count = rec.count + 1, paid = rec.paid }
  if not rec.paid and kmh >= t.target then new.paid, out.first = true, true end
  return new, out
end

return M
