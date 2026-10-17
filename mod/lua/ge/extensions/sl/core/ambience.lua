-- Street Legal: ambient sound zones (#46). Pure, tested by tools/luatest.js. Where there is something to hear near the player: the water's edge (harbour), a wide
-- road (the freeway), a crowd in town (several shops, dealers and the like close together), a meet with music. This module decides, from what the
-- world says about the player's surroundings, which emitters should exist, where, and how loud; sl/ambience.lua plays them and drops them when far.

local M = {}

M.RANGE = { harbour = 160, freeway = 130, crowd = 90, music = 110 }
M.BASE = { harbour = 0.55, freeway = 0.45, crowd = 0.5, music = 0.7 }
M.FILES = { harbour = 'harbour.wav', freeway = 'freeway.wav', crowd = 'crowd.wav' }
-- the game's own FMOD ambience events to try for each kind, best first (the game's banks cannot be listed offline: sl_ambience.probe() logs which of
-- these make a source in the running game; sl_ambience.USE_STOCK stays off until one is confirmed to be heard)
M.STOCK = {
  harbour = { 'event:>Ambient>Water>Waves_Shore', 'event:>Ambient>Water>Harbor' },
  freeway = { 'event:>Ambient>Traffic>Highway', 'event:>Ambient>Traffic>Traffic_Loop' },
  crowd = { 'event:>Ambient>Crowds>Crowd_Murmur', 'event:>Ambient>Urban>City' },
}
M.WIDE_ROAD = 5            -- road node half-width (m) of a freeway-sized road
M.CROWD_MIN = 2            -- places within CROWD_R of each other that make a crowd
M.CROWD_R = 60
M.CROWD_KINDS = { shop = true, dealer = true, junkyard = true, scrapyard = true, garage = true, hospital = true, carwash = true, parts = true, station = true }

local function dist2(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

-- loudness at a distance: full close in, falling smoothly to nothing at the range
function M.volume(kind, d)
  local range = M.RANGE[kind]
  if not range or d >= range then return 0 end
  local x = 1 - d / range
  return (M.BASE[kind] or 0.5) * x * x
end

-- the nearest point of water around p: height(x, y) -> ground height there, waterZ the water's surface. Rings of 8 directions out to maxD.
function M.waterEdge(height, waterZ, p, maxD)
  if type(height) ~= 'function' or not waterZ then return nil end
  for ring = 1, math.floor((maxD or 160) / 40) do
    local r = ring * 40
    for k = 0, 7 do
      local a = k * math.pi / 4
      local x, y = p.x + math.cos(a) * r, p.y + math.sin(a) * r
      local h = height(x, y)
      if h and h < waterZ + 0.3 then return { x = x, y = y, z = waterZ } end
    end
  end
  return nil
end

-- the nearest node of a wide road within maxD. nodes: name -> { pos = {x, y, z}, radius }
function M.freewayNode(nodes, p, maxD)
  local best, bd = nil, maxD or M.RANGE.freeway
  local scanned = 0
  for _, n in pairs(nodes or {}) do
    scanned = scanned + 1
    if scanned > 30000 then break end
    if (n.radius or 0) >= M.WIDE_ROAD then
      local d = dist2(n.pos.x, n.pos.y, p.x, p.y)
      if d < bd then best, bd = n, d end
    end
  end
  return best and { x = best.pos.x, y = best.pos.y, z = best.pos.z }, best and bd or nil
end

-- the middle of the crowd-making places within maxD of p, and how many: places = id -> { kind, pos = {x, y, z} }
function M.crowd(places, p, maxD)
  local near = {}
  for _, pl in pairs(places or {}) do
    if M.CROWD_KINDS[pl.kind] and pl.pos and dist2(pl.pos.x, pl.pos.y, p.x, p.y) < (maxD or M.RANGE.crowd) + M.CROWD_R then near[#near + 1] = pl.pos end
  end
  local best, bestN = nil, 0
  for _, a in ipairs(near) do
    local n, cx, cy, cz = 0, 0, 0, 0
    for _, b in ipairs(near) do
      if dist2(a.x, a.y, b.x, b.y) <= M.CROWD_R then n, cx, cy, cz = n + 1, cx + b.x, cy + b.y, cz + (b.z or 0) end
    end
    if n >= M.CROWD_MIN and n > bestN then best, bestN = { x = cx / n, y = cy / n, z = cz / n }, n end
  end
  return best, bestN
end

-- which emitters there should be now. ctx: { player = {x,y,z}, height = fn, waterZ, nodes, places, phase, meet = { pos } or nil, raining = bool }
-- returns a list of { id, kind, file (nil for the music), pos, volume }, loudest first; nothing at all out of range
function M.plan(ctx)
  local out = {}
  local p = ctx.player
  if not p then return out end
  local function add(id, kind, pos)
    local v = M.volume(kind, dist2(pos.x, pos.y, p.x, p.y))
    if v > 0.01 then out[#out + 1] = { id = id, kind = kind, file = M.FILES[kind], pos = pos, volume = v } end
  end
  local water = M.waterEdge(ctx.height, ctx.waterZ, p, M.RANGE.harbour)
  if water then add('harbour', 'harbour', water) end
  local road = M.freewayNode(ctx.nodes, p, M.RANGE.freeway)
  if road then add('freeway', 'freeway', road) end
  if ctx.phase ~= 'night' and not ctx.raining then
    local centre = M.crowd(ctx.places, p, M.RANGE.crowd)
    if centre then add('crowd', 'crowd', centre) end
  end
  if ctx.meet and ctx.meet.pos then
    add('music', 'music', ctx.meet.speaker or ctx.meet.pos)         -- from one car's speakers
    if ctx.phase == 'night' then add('crowd_meet', 'crowd', ctx.meet.pos) end         -- people stand about at a meet
  end
  table.sort(out, function(a, b) return a.volume > b.volume end)
  return out
end

return M
