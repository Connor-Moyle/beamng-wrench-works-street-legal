-- Street Legal: clubs, leagues and the season calendar (BACKLOG X20 + X5; docs: DESIGN4_clubs.md). No game calls.
-- A car's class comes from its power to weight and is locked for the season; each club runs a night league
-- (head-to-heads on the street) and a day league (the strip, the oval, the valley venues); a season is a week
-- with one event per league a day and a double-points finale. The club's other racers race every event in
-- simulation (by skill, with luck), so the standings move whether or not the player turns up.

local M = {}

M.SEASON_DAYS = 7
M.POINTS = { 10, 6, 4, 3, 2, 1 }
M.FINISHED = 1                    -- for any place past the table
M.CLASSES = { 'D', 'C', 'B', 'A', 'S' }
local LIMITS = { 90, 130, 180, 250 }   -- PS per tonne at the top of D, C, B, A

M.CLUBS = {
  { name = 'Club 1', classes = { 'D', 'C' }, tiers = { 1, 2 }, purse = 300, seasonRep = 100 },
  { name = 'Club 2', classes = { 'C', 'B' }, tiers = { 2, 3 }, purse = 1500, seasonRep = 250 },
  { name = 'Club 3', classes = { 'B', 'A', 'S' }, tiers = { 4, 5 }, purse = 6000, seasonRep = 600 },
}

-- the class of a car: its peak power (PS) over its mass (kg)
function M.classOf(ps, massKg)
  local perTonne = (ps or 0) / math.max(300, massKg or 1000) * 1000
  for i, top in ipairs(LIMITS) do if perTonne < top then return M.CLASSES[i] end end
  return 'S'
end

function M.classIndex(c) for i, x in ipairs(M.CLASSES) do if x == c then return i end end return 1 end

-- the club's racers: the roster's racers of the club's tiers
function M.members(racers, club)
  local def, out = M.CLUBS[club] or M.CLUBS[1], {}
  for _, r in ipairs(racers or {}) do
    if r.tier >= def.tiers[1] and r.tier <= def.tiers[#def.tiers] then out[#out + 1] = r end
  end
  return out
end

-- a season's calendar: for each day a night event (a night race) and a day event (a drag, the oval or a venue),
-- spread over the races the map lists; races = listRaces-style { id, missionId, name, kind }
function M.calendar(races, rng)
  local night, day = {}, {}
  for _, r in ipairs(races or {}) do
    if r.kind == 'night' then night[#night + 1] = r
    elseif r.kind == 'drag' or r.kind == 'circuit' or r.kind == 'venue' then day[#day + 1] = r end
  end
  local function pick(list, used)
    if #list == 0 then return nil end
    for _ = 1, 20 do
      local r = list[rng:int(#list)]
      if not used[r.missionId or r.id] or #list <= M.SEASON_DAYS then used[r.missionId or r.id] = true return r end
    end
    return list[rng:int(#list)]
  end
  local cal, usedN, usedD = {}, {}, {}
  for d = 1, M.SEASON_DAYS do
    local n, dd = pick(night, usedN), pick(day, usedD)
    cal[d] = {
      night = n and { id = n.id, missionId = n.missionId, name = n.name, kind = n.kind } or nil,
      day = dd and { id = dd.id, missionId = dd.missionId, name = dd.name, kind = dd.kind } or nil,
      finale = d == M.SEASON_DAYS,
    }
  end
  return cal
end

function M.points(place, finale)
  if not place then return 0 end
  return (M.POINTS[place] or M.FINISHED) * (finale and 2 or 1)
end

-- how a racer goes in one event: their skill, with the day's luck (a better driver is faster on average)
function M.pace(skill, rng)
  return (skill or 0.5) + (rng:float() + rng:float() + rng:float() - 1.5) * 0.12
end

-- an event the club raced: the order of the given racers (ids), fastest first; the player may be among them
-- with a given place (then the others fill the rest around them)
function M.simulate(members, rng, playerPlace)
  local field = {}
  for _, r in ipairs(members) do field[#field + 1] = { id = r.id, pace = M.pace(r.skill, rng) } end
  table.sort(field, function(a, b) return a.pace > b.pace end)
  local order = {}
  for _, f in ipairs(field) do order[#order + 1] = f.id end
  if playerPlace then table.insert(order, math.max(1, math.min(#order + 1, playerPlace)), 'player') end
  return order
end

-- the season's standings after an event's order: { id -> points }
function M.score(standings, order, finale, fieldSize)
  for place, id in ipairs(order) do
    if not fieldSize or place <= fieldSize then standings[id] = (standings[id] or 0) + M.points(place, finale) end
  end
  return standings
end

-- the table, best first: { { id, points } ... } (ties: by id, so it is stable)
function M.table(standings)
  local t = {}
  for id, p in pairs(standings) do t[#t + 1] = { id = id, points = p } end
  table.sort(t, function(a, b) if a.points ~= b.points then return a.points > b.points end return tostring(a.id) < tostring(b.id) end)
  return t
end

function M.placeOf(standings, id)
  for i, row in ipairs(M.table(standings)) do if row.id == id then return i end end
end

-- what a season pays at its end: by the player's final place in the club
function M.seasonReward(club, place)
  local def = M.CLUBS[club] or M.CLUBS[1]
  if place == 1 then return def.purse * 2, def.seasonRep, true end
  if place and place <= 3 then return def.purse, math.floor(def.seasonRep / 2), true end
  return 0, 0, false
end

-- an event's purse by place (day league), and the night league's stake is the racers' own as now
function M.purse(club, place)
  local def = M.CLUBS[club] or M.CLUBS[1]
  local share = ({ 1, 0.5, 0.25 })[place or 99]
  return share and math.floor(def.purse * share / 10) * 10 or 0
end

return M
