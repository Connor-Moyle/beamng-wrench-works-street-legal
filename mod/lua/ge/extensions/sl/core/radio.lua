-- Street Legal: the car radio's DJ (campaign idea #15). Text lines about the career, built from its events: a race won or lost, a pink slip, the weather, the heat, a bust, a district
-- taken, the king of the city. A line is picked from a pool of written lines with a short memory so the same one does not come twice running; a quiet day gets a filler line. The
-- names are invented. No voices, no music (WW's car radio plays music). Pure, no game calls: tested by tools/luatest.js.

local M = {}

local strings = require('sl/core/strings')

M.STATION_ID, M.STATION_NAME = 'sl_fm', 'Street Legal FM'
M.GAP = 60              -- s between two lines at the least
M.IDLE_GAP = 150        -- s of nothing to say before a filler line
M.QUEUE_MAX = 6         -- news waiting for a quiet moment; the oldest goes first when more come
M.MAX_AGE = 1           -- days: news older than this is not read
M.MEMORY = 3            -- lines of a pool not to repeat

-- the pools: strings radio.<kind>_<n>, n = 1..COUNTS[kind]; {1}.. are the arguments of the event. Priority: higher is read first.
M.COUNTS = { race_win = 4, race_loss = 4, pink_won = 3, pink_lost = 3, clear = 2, cloudy = 2, rain = 3, fog = 2, heat = 3, busted = 3, district = 3, king = 2, filler = 12 }
M.PRIORITY = { king = 6, pink_won = 5, pink_lost = 5, busted = 4, district = 4, heat = 3, race_win = 3, race_loss = 3, rain = 2, fog = 2, clear = 1, cloudy = 1, filler = 0 }

function M.new() return { queue = {}, memory = {}, lastAt = 0, spoke = 0 } end

-- news: kind, its arguments, the day it happened
function M.push(r, kind, args, day)
  if not M.COUNTS[kind] or kind == 'filler' then return false end
  for i, n in ipairs(r.queue) do            -- (the same kind twice in a row is one item: the newest wins)
    if n.kind == kind then table.remove(r.queue, i) break end
  end
  r.queue[#r.queue + 1] = { kind = kind, args = args or {}, day = day or 0 }
  if #r.queue > M.QUEUE_MAX then table.remove(r.queue, 1) end
  return true
end

-- the events of the game as news (the game side calls these)
function M.fromRace(won, opponent, stake)
  if stake == 'pink' then return won and 'pink_won' or 'pink_lost', { opponent or '?' } end
  return won and 'race_win' or 'race_loss', { opponent or '?' }
end
M.WEATHER = { clear = 'clear', cloudy = 'cloudy', rain = 'rain', fog = 'fog', light = 'rain', medium = 'rain', heavy = 'rain' }
function M.fromWeather(id) return M.WEATHER[id] end

-- a line of a pool: not one of the last MEMORY of that pool
local function pick(r, kind, rng)
  local n = M.COUNTS[kind]
  local mem = r.memory[kind] or {}
  r.memory[kind] = mem
  local free = {}
  for i = 1, n do
    local seen = false
    for _, m in ipairs(mem) do if m == i then seen = true end end
    if not seen then free[#free + 1] = i end
  end
  if #free == 0 then free = {} for i = 1, n do free[i] = i end end
  local i = free[rng and rng:int(#free) or 1]
  mem[#mem + 1] = i
  while #mem > math.min(M.MEMORY, n - 1) do table.remove(mem, 1) end
  return i
end

-- the next line at time `now` (seconds), on `day`: nil when it is not time or nothing to say. quiet: a race or a chase is on (nothing is said, the news waits)
function M.next(r, now, day, quiet, rng)
  if quiet or now - r.lastAt < M.GAP then return nil end
  for i = #r.queue, 1, -1 do               -- (news from before yesterday is stale)
    if day - r.queue[i].day > M.MAX_AGE then table.remove(r.queue, i) end
  end
  local best
  for i, n in ipairs(r.queue) do
    if not best or M.PRIORITY[n.kind] > M.PRIORITY[r.queue[best].kind] then best = i end
  end
  local kind, args
  if best then
    local n = table.remove(r.queue, best)
    kind, args = n.kind, n.args
  elseif now - r.lastAt >= M.IDLE_GAP then
    kind, args = 'filler', {}
  else
    return nil
  end
  local i = pick(r, kind, rng)
  r.lastAt, r.spoke = now, r.spoke + 1
  return strings.t('radio.' .. kind .. '_' .. i, table.unpack(args)), kind
end

return M
