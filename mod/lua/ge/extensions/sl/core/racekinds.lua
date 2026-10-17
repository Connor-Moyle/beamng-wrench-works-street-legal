-- Street Legal: kinds of night street race (#17, variety), picked from the road graph. Pure rules over a plain navgraph, no game calls:
-- tested outside the game (tools/luatest.js).
--
-- nodes[name] = { pos = { x, y, z }, radius = m, links = { [other] = { drivability = 0..1, speedLimit = m/s } } } (the game's map.getMap().nodes).
-- A route is a list of node names. Every kind is data: how long, what the road must be like, how it pays. The kinds:
--   city     a run through the streets with turns in it (the checkpoints are its turns)
--   highway  fast, wide road end to end: the freeway on-ramp to off-ramp
--   hill     a climb on a narrow road: height gained decides
--   rolling  a highway pull from a rolling start (60 to 130 mph), only against a rolling opponent

local M = {}

M.FAST_MS = 22            -- m/s: an edge with this speed limit (or wider than FAST_RADIUS) is "fast road"
M.FAST_RADIUS = 5.5       -- m: half-width of a freeway
M.TARMAC = 0.9            -- an edge with this drivability counts as tarmac
M.TURN_DEG = 40           -- a heading change over this is a turn

M.KINDS = {
  city    = { id = 'city',    minLen = 900,  maxLen = 1800, weight = 4, pay = 1.0, ok = function(m) return m.turns >= 4 and m.tarmac >= 0.95 and m.fast < 0.5 end },
  highway = { id = 'highway', minLen = 2000, maxLen = 3800, weight = 2, pay = 1.25, ok = function(m) return m.fast >= 0.75 and m.tarmac >= 0.98 and m.turns <= 3 end },
  hill    = { id = 'hill',    minLen = 700,  maxLen = 2200, weight = 2, pay = 1.2, ok = function(m) return m.gain >= 40 and m.tarmac >= 0.95 and m.fast < 0.5 end },
  rolling = { id = 'rolling', minLen = 2000, maxLen = 4000, weight = 1, pay = 1.4, rolling = true, ok = function(m) return m.fast >= 0.75 and m.tarmac >= 0.98 and m.turns <= 2 end },
}
M.ORDER = { 'city', 'highway', 'hill', 'rolling' }

local COS_TURN = math.cos(math.rad(M.TURN_DEG))
local function d2(a, b) local dx, dy = a.x - b.x, a.y - b.y return math.sqrt(dx * dx + dy * dy) end

-- what a route is like. dead = the route doubles back on itself or ends on a dead end (it must not)
function M.measure(nodes, path)
  local m = { len = 0, gain = 0, fastLen = 0, tarmacLen = 0, turns = 0, dead = false, nodes = #path }
  local seen, prev = {}, nil
  for i = 1, #path do
    local n = nodes[path[i]]
    if not n then m.dead = true return m end
    if seen[path[i]] then m.dead = true end
    seen[path[i]] = true
    local p = nodes[path[i - 1] or '']
    if i > 1 and p then
      local len = d2(p.pos, n.pos)
      local link = (p.links or {})[path[i]] or {}
      m.len = m.len + len
      if n.pos.z > p.pos.z then m.gain = m.gain + (n.pos.z - p.pos.z) end
      if (link.speedLimit or 0) >= M.FAST_MS or math.min(p.radius or 0, n.radius or 0) >= M.FAST_RADIUS then m.fastLen = m.fastLen + len end
      if (link.drivability or 1) >= M.TARMAC then m.tarmacLen = m.tarmacLen + len end
      if len > 1 then
        local vx, vy = (n.pos.x - p.pos.x) / len, (n.pos.y - p.pos.y) / len
        if prev and prev.x * vx + prev.y * vy < COS_TURN then m.turns = m.turns + 1 end     -- (no atan2: LuaJIT and Lua 5.3 differ)
        prev = { x = vx, y = vy }
      end
    end
  end
  local last = nodes[path[#path]]
  if last then
    local deg = 0
    for _ in pairs(last.links or {}) do deg = deg + 1 end
    if deg < 2 then m.dead = true end
  end
  m.fast = m.len > 0 and m.fastLen / m.len or 0
  m.tarmac = m.len > 0 and m.tarmacLen / m.len or 0
  return m
end

-- is this route right for the kind (length, road, no dead end)
function M.valid(kind, m)
  local k = M.KINDS[kind]
  return k ~= nil and m ~= nil and not m.dead and m.len >= k.minLen and m.len <= k.maxLen and k.ok(m) == true
end

-- the kind of tonight's race: weights, rolling only for a rolling start, highway kinds need the map to have one (have[kind] == false removes it)
function M.choose(rng, opts)
  opts = opts or {}
  local total, list = 0, {}
  for _, id in ipairs(M.ORDER) do
    local k = M.KINDS[id]
    local fine = (opts.have == nil or opts.have[id] ~= false) and ((not k.rolling) or opts.rolling == true)
    if fine then list[#list + 1] = k total = total + k.weight end
  end
  if #list == 0 then return 'city' end
  local roll = rng:float() * total
  for _, k in ipairs(list) do
    roll = roll - k.weight
    if roll <= 0 then return k.id end
  end
  return list[#list].id
end

-- a goal for the kind: up to `tries` random nodes of the right distance, the first whose route fits. pathFn(startName, goalName) -> names.
-- Returns goalName, path, measure; or nil when the map has none near here.
function M.pick(nodes, startName, pathFn, kind, rng, tries)
  local k = M.KINDS[kind]
  local from = nodes[startName]
  if not (k and from) then return nil end
  local names = {}
  for name, n in pairs(nodes) do
    local d = d2(from.pos, n.pos)
    if name ~= startName and d >= k.minLen * 0.45 and d <= k.maxLen * 0.95 then names[#names + 1] = name end
  end
  table.sort(names)
  for _ = 1, tries or 40 do
    if #names == 0 then return nil end
    local goal = table.remove(names, rng:int(#names))
    local path = pathFn(startName, goal) or {}
    if #path >= 2 then
      local m = M.measure(nodes, path)
      if M.valid(kind, m) then return goal, path, m end
    end
  end
  return nil
end

-- the extra a win pays on top of the bet: the kind's multiplier, a fifth of its extra again per heat level (0..5)
function M.bonus(kind, bet, heatLevel)
  local k = M.KINDS[kind]
  if not k or (bet or 0) <= 0 then return 0 end
  local mul = 1 + (k.pay - 1) * (1 + 0.2 * math.max(0, math.min(5, heatLevel or 0)))
  return math.floor(bet * (mul - 1) / 10 + 0.5) * 10
end

return M
