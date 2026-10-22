-- Street Legal: crew mates (campaign idea #8; design: Graph docs/CREW_MATES_DESIGN.md). Take a district from a rival crew and one of its people joins you: a mechanic who makes parts and labour
-- cheaper, a tipster who texts where the money is, or a scout who rides along and calls the route and the police. A mate is a person: never a car, never in a race.
-- Pure, no game calls: tested by tools/luatest.lua. The game side is sl/mates.lua (sl_mates; the switch 'mates', off by default).
--   state: { [crewId] = { role = 'mechanic'|'tipster'|'scout', name = '...', day = n } }     (saved as the career's additive key s.mates)

local M = {}

local strings = require('sl/core/strings')

-- the crew decides the role: fixed, the same in every save (one place to change it)
M.ROLES = { riverbed = 'mechanic', southside = 'tipster', northend = 'scout', ringroad = 'scout' }

-- first names by crew; a mate takes one at random (never the same name twice in one roster)
M.NAMES = {
  riverbed = { 'Dex', 'Marlo', 'Ines', 'Tobias', 'Wren' },
  southside = { 'Rico', 'Jonah', 'Lucia', 'Kade', 'Mara' },
  northend = { 'Skye', 'Bram', 'Noor', 'Cole', 'Ivy' },
  ringroad = { 'Nico', 'Tess', 'Arlo', 'Dani', 'Hugo' },
}

M.PARTS_FACTOR = 0.95      -- the mechanic's cut off parts in the shops
M.LABOUR_FACTOR = 0.90     -- and off the service's labour
M.TIP_GAP_DAYS = 1         -- the tipster texts at most once a game day
M.WARN_GAP = 60            -- seconds between two police warnings from a scout
M.WARN_RANGE = 400         -- metres ahead a patrol must be to be called
M.WARN_AHEAD = 0.3         -- cosine of the angle off the heading: a patrol roughly in front

function M.new() return {} end

local function clone(t) local o = {} for k, v in pairs(t or {}) do o[k] = v end return o end

local function nameTaken(state, name)
  for _, m in pairs(state) do if m.name == name then return true end end
  return false
end

-- a crew's mate joins (once per crew: a district lost and retaken recruits nobody twice). Returns the mate, or nil when the crew is unknown or already has one in the roster.
function M.recruit(state, crewId, day, rng)
  local role = M.ROLES[crewId]
  if not role or state[crewId] then return nil end
  local pool = M.NAMES[crewId]
  local name
  for _ = 1, 8 do
    local pick = pool[rng and rng:int(#pool) or 1]
    if not nameTaken(state, pick) then name = pick break end
  end
  name = name or pool[1]
  state[crewId] = { role = role, name = name, day = tonumber(day) or 0 }
  return state[crewId]
end

-- the mates as a list, in the order of the crews
function M.roster(state)
  local out = {}
  for _, id in ipairs({ 'southside', 'riverbed', 'northend', 'ringroad' }) do
    local m = state[id]
    if m then out[#out + 1] = { crew = id, role = m.role, name = m.name, day = m.day } end
  end
  return out
end

function M.has(state, role)
  for _, m in pairs(state) do if m.role == role then return true end end
  return false
end

function M.scouts(state)
  local n = 0
  for _, m in pairs(state) do if m.role == 'scout' then n = n + 1 end end
  return n
end

function M.partsFactor(state) return M.has(state, 'mechanic') and M.PARTS_FACTOR or 1 end
function M.labourFactor(state) return M.has(state, 'mechanic') and M.LABOUR_FACTOR or 1 end

-- the first scout, whom the passenger seat shows (the Drivers skin is chosen by the game side from the name)
function M.rider(state)
  for _, id in ipairs({ 'northend', 'ringroad' }) do if state[id] and state[id].role == 'scout' then return state[id], id end end
  return nil
end

local function mateWith(state, role)
  for _, id in ipairs({ 'southside', 'riverbed', 'northend', 'ringroad' }) do
    if state[id] and state[id].role == role then return state[id], id end
  end
  return nil
end

-- what a recruited mate says
function M.welcome(mate, crewName)
  return { from = mate.name, text = strings.t('mates.recruited_' .. mate.role, mate.name, crewName or '') }
end

-- the tipster's text: once a game day at most (lastDay = the day of his last text), none with the switch's rate at 0, and only when the world has something to tell.
-- world = { race = { name, hours } or nil, job = { name, pay } or nil }. Returns { from, text } or nil.
function M.tip(state, world, today, lastDay, rate, rng)
  local mate = mateWith(state, 'tipster')
  if not mate or (rate or 1) <= 0 then return nil end
  if lastDay and today - lastDay < M.TIP_GAP_DAYS / math.max(rate, 0.01) then return nil end
  local w = world or {}
  local options = {}
  if w.race then options[#options + 1] = strings.t('mates.tip_race', w.race.name, w.race.hours) end
  if w.job then options[#options + 1] = strings.t('mates.tip_job', w.job.name, w.job.pay) end
  if #options == 0 then return nil end
  return { from = mate.name, text = options[rng and rng:int(#options) or 1] }
end

-- the scout's line when a route starts: where the first turn is. route = { dist = metres to the first turn, turn = 'left'|'right'|'straight', place = '...' }
function M.scoutRoute(state, route)
  local mate = mateWith(state, 'scout')
  if not mate or not route or type(route.dist) ~= 'number' then return nil end
  local dist = math.floor(route.dist / 10 + 0.5) * 10
  local turn = route.turn == 'left' and strings.t('mates.left') or route.turn == 'right' and strings.t('mates.right') or strings.t('mates.straight')
  return { from = mate.name, text = strings.t('mates.scout_route', dist, turn, route.place or '') }
end

-- the scout's police warning: patrols = { { x, y } ... } in metres; me = { x, y } with a heading (hx, hy: a vector). The nearest patrol in front and within WARN_RANGE is called, at most
-- every WARN_GAP seconds (lastAt = when he last called). Returns { from, text, at } or nil.
function M.policeWarning(state, now, lastAt, patrols, me)
  local mate = mateWith(state, 'scout')
  if not mate or not patrols or not me then return nil end
  if lastAt and now - lastAt < M.WARN_GAP then return nil end
  local hl = math.sqrt((me.hx or 0) ^ 2 + (me.hy or 0) ^ 2)
  if hl < 1e-6 then return nil end
  local best, bestD
  for _, p in ipairs(patrols) do
    local dx, dy = p.x - me.x, p.y - me.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d > 1 and d <= M.WARN_RANGE then
      local cos = (dx * me.hx + dy * me.hy) / (d * hl)
      if cos >= M.WARN_AHEAD and (not bestD or d < bestD) then best, bestD = p, d end
    end
  end
  if not best then return nil end
  return { from = mate.name, text = strings.t('mates.police_ahead', math.floor(bestD / 50 + 0.5) * 50), at = now }
end

-- the save: only what is understood. A damaged blob gives an empty roster and never an error.
function M.save(state) local out = {} for id, m in pairs(state) do out[id] = clone(m) end return out end
function M.load(blob)
  local state = {}
  if type(blob) ~= 'table' then return state end
  for id, m in pairs(blob) do
    local role = M.ROLES[id]
    if role and type(m) == 'table' and m.role == role and type(m.name) == 'string' and m.name ~= '' then
      state[id] = { role = role, name = m.name, day = tonumber(m.day) or 0 }
    end
  end
  return state
end

return M
