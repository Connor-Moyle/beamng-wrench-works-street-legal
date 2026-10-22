-- Street Legal: the grid race's rules (a race meeting on a closed layout against a field of AI cars in the player's class, run by sl_gridrace on
-- the game's own race object). Pure, no game calls: tested by tools/luatest.js. The weekend races of the calendar use it; the brand invitationals
-- and the home events of the series reuse it.

local M = {}

M.CLASSES = { 'D', 'C', 'B', 'A', 'S' }      -- the game's performance classes, slowest first (gameplay_vehiclePerformance)
M.MIN, M.MAX = 3, 7                           -- AI cars on the grid
M.BUILD_S = 12                                -- seconds of black the grid may take to build (shared with the other fade builders: job.slFadeT0)
M.CAM_INTRO_S, M.CAM_FINISH_S = 8, 5          -- the layout's camera paths, capped
M.MAX_RACE_S = 900                            -- a race that is not over by then is a DNF
M.SHARE = { 1, 0.5, 0.25 }                    -- of the purse by place
M.REP = { 40, 20, 10 }                        -- reputation by place; a finish below the podium
M.REP_FINISH = 5

-- how many AI cars: the setting, within MIN..MAX and the grid's slots less the player's
function M.gridSize(setting, slots)
  local n = math.floor(tonumber(setting) or M.MAX)
  n = math.max(M.MIN, math.min(M.MAX, n))
  return math.max(0, math.min(n, (tonumber(slots) or 0) - 1))
end

function M.classIndex(name) for i, c in ipairs(M.CLASSES) do if c == name then return i end end return nil end

-- the field: n cars from the candidates ({ model, config, class }), the player's class first, then the classes next to it (closer first),
-- distinct models before a second car of one model, in the rng's order within a class
function M.field(cands, class, n, rng)
  local want = M.classIndex(class) or 3
  local byDist = {}
  for _, c in ipairs(cands or {}) do
    local ci = M.classIndex(c.class)
    if ci then
      local d = math.abs(ci - want)
      byDist[d] = byDist[d] or {}
      table.insert(byDist[d], c)
    end
  end
  local out, models = {}, {}
  for d = 0, #M.CLASSES do
    local pool = byDist[d]
    if pool and #out < n then
      -- rng order
      local shuffled = {}
      while #pool > 0 do shuffled[#shuffled + 1] = table.remove(pool, rng:int(#pool)) end
      for pass = 1, 2 do          -- distinct models first, then any
        for _, c in ipairs(shuffled) do
          if #out >= n then break end
          if (pass == 2 or not models[c.model]) and not c.taken then c.taken = true models[c.model] = true out[#out + 1] = c end
        end
      end
    end
  end
  for _, c in ipairs(out) do c.taken = nil end
  return out
end

-- the fields of our own (a series round's `field`): off-road for the Johnson Valley loops (configs the game ships; the classes from their saved Performance Data)
M.ROSTERS = {
  offroad = {
    { model = 'pickup', config = 'd15_track_awd_M', class = 'A' }, { model = 'pickup', config = 'd15_4wd_offroad_M', class = 'B' },
    { model = 'hopper', config = 'race', class = 'B' }, { model = 'hopper', config = 'rock_racer', class = 'A' }, { model = 'hopper', config = 'offroad', class = 'B' },
    { model = 'utv', config = 'race', class = 'A' }, { model = 'utv', config = 'wild', class = 'B' },
    { model = 'rockbouncer', config = 'rock_racer', class = 'A' }, { model = 'burnside', config = 'banger', class = 'B' },
  },
}
-- the candidates of a race: a named roster of ours, else the AI pool with its classes (poolFn gives { model, config, class } entries)
function M.candidatesFor(field, poolFn)
  local roster = field and M.ROSTERS[field]
  if roster then
    local out = {}
    for i, c in ipairs(roster) do out[i] = { model = c.model, config = c.config, class = c.class } end
    return out
  end
  return poolFn and poolFn() or {}
end

-- a series round's track ('johnson_valley/timeTrial/006-ShortcourseA') as the folder of its files (the game's missions live under /gameplay/missions/)
function M.roundDir(track) return '/gameplay/missions/' .. tostring(track):gsub('^/', ''):gsub('/$', '') .. '/' end

-- the AI's aggression from the player's standing: a nobody meets a calm field, a name a hard one
function M.aggression(rep) return math.min(0.95, 0.55 + (tonumber(rep) or 0) / 5000) end

-- the purse share and the reputation of a place (nil place: a DNF, nothing)
function M.payout(place, purse)
  if not place then return 0, 0 end
  local money = math.floor((purse or 0) * (M.SHARE[place] or 0) / 10 + 0.5) * 10
  return money, M.REP[place] or M.REP_FINISH
end

-- a camera path's length in seconds (the last marker's time), capped
function M.camSeconds(path, cap)
  local m = type(path) == 'table' and path.markers
  local last = m and m[#m] and tonumber(m[#m].time) or 0
  return math.max(0, math.min(cap or last, last))
end

-- the layout's pathnodes in lap order as checkpoints for the flares: { pos, dir, half }
function M.cps(nodes)
  local out = {}
  for i, nd in ipairs(nodes or {}) do
    local nx = nodes[i % #nodes + 1]
    out[i] = { pos = nd.pos, dir = nd.normal or (nx and nx.pos and nd.pos and (nx.pos - nd.pos)) or nil, half = math.max(4, tonumber(nd.radius) or 6) }
  end
  return out
end

function M.placeWord(place) return place == 1 and '1st' or place == 2 and '2nd' or place == 3 and '3rd' or (tostring(place) .. 'th') end

return M
