-- Street Legal: rival crews and their districts (X21; docs: DESIGN6_crews.md). No game calls.
-- Every street racer belongs to one of four crews; each crew holds districts of the city; a race won in a district
-- against a member of the crew that holds it takes control from them, and at 0 the district is yours. Crews fight
-- back (call-outs), shift districts among themselves at night, and a player holding enough meets the leaders in a
-- turf war. Positions are anything with x, y.

local M = {}

M.CREWS = {
  { id = 'southside', name = 'the Southside Kings' },
  { id = 'riverbed', name = 'Riverbed Runners' },
  { id = 'northend', name = 'the North End crew' },
  { id = 'ringroad', name = 'Ring Road Ghosts' },
}
M.START_CONTROL = 60
M.TAKEN_CONTROL = 50          -- a district changing hands starts with this much for its new owner
M.GAIN = { member = 25, leader = 40 }
M.LOSS = 15                   -- a race lost in their district: they gain this much back
M.DEFEND = { won = 10, lost = 25 }
M.PERKS = { rep = 1.2, heat = 0.5, pay = 1.1, shop = 0.9 }
M.TURF_WAR_AT = 4             -- districts held to be called to the turf war

function M.crew(id) for _, c in ipairs(M.CREWS) do if c.id == id then return c end end end

-- every racer into a crew, the tiers spread evenly (so no crew is all beginners); the leader is each crew's best
function M.assign(racers, rng)
  local list = {}
  for _, r in ipairs(racers or {}) do list[#list + 1] = r end
  table.sort(list, function(a, b) if (a.tier or 1) ~= (b.tier or 1) then return (a.tier or 1) > (b.tier or 1) end return tostring(a.id) < tostring(b.id) end)
  local offset = rng:int(#M.CREWS) - 1
  local member, leader, best = {}, {}, {}
  for i, r in ipairs(list) do
    local c = M.CREWS[(i + offset - 1) % #M.CREWS + 1].id
    member[r.id] = c
    if not best[c] or (r.skill or 0) > best[c] then best[c], leader[c] = r.skill or 0, r.id end
  end
  return member, leader
end

----------------------------------------------------------------------------------------------
-- districts: from the map's file (polygons) or, without one, the career's places clustered by position

local function inside(poly, x, y)
  local hit, j = false, #poly
  for i = 1, #poly do
    local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
    if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then hit = not hit end
    j = i
  end
  return hit
end
M.inside = inside

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end     -- (LuaJIT in the game; Lua 5.4 in the tests)

local COMPASS = { 'East Side', 'North-East', 'Northside', 'North-West', 'West End', 'South-West', 'Southside', 'South-East' }

-- k districts from points ({ x, y }): a few rounds of k-means from evenly spread seeds; named by where they lie
-- from the middle of town (the one nearest the middle is Downtown)
function M.cluster(points, k)
  if #points == 0 then return {} end
  k = math.min(k or 6, #points)
  local sorted = {}
  for _, p in ipairs(points) do sorted[#sorted + 1] = p end
  table.sort(sorted, function(a, b) return atan2(a.y, a.x) < atan2(b.y, b.x) end)
  local centres = {}
  for i = 1, k do local p = sorted[math.floor((i - 1) * #sorted / k) + 1] centres[i] = { x = p.x, y = p.y } end
  for _ = 1, 12 do
    local sum = {}
    for i = 1, k do sum[i] = { x = 0, y = 0, n = 0 } end
    for _, p in ipairs(points) do
      local bi, bd = 1, math.huge
      for i, c in ipairs(centres) do local d = (p.x - c.x) ^ 2 + (p.y - c.y) ^ 2 if d < bd then bi, bd = i, d end end
      sum[bi].x, sum[bi].y, sum[bi].n = sum[bi].x + p.x, sum[bi].y + p.y, sum[bi].n + 1
    end
    for i = 1, k do if sum[i].n > 0 then centres[i] = { x = sum[i].x / sum[i].n, y = sum[i].y / sum[i].n } end end
  end
  local mx, my = 0, 0
  for _, c in ipairs(centres) do mx, my = mx + c.x / k, my + c.y / k end
  local middle, md = 1, math.huge
  for i, c in ipairs(centres) do local d = (c.x - mx) ^ 2 + (c.y - my) ^ 2 if d < md then middle, md = i, d end end
  local out, used = {}, {}
  for i, c in ipairs(centres) do
    local name = 'Downtown'
    if i ~= middle then
      name = COMPASS[math.floor(((atan2(c.y - my, c.x - mx) / (2 * math.pi)) * 8 + 0.5) % 8) + 1]
      if used[name] then name = name .. ' ' .. (used[name] + 1) end
    end
    used[name] = (used[name] or 0) + 1
    out[i] = { id = 'd' .. i, name = name, centre = c }
  end
  return out
end

-- (#42) a place's name as an area's: 'Alder Dragway Garage' -> 'Alder Dragway', 'Quarryside Auto Sales' -> 'Quarryside'
local TRAILING = { 'garage', 'autos', 'auto', 'sales', 'motors', 'motor', 'dealership', 'dealer', 'cars', 'car', 'used', 'shop', 'yard', 'junkyard', 'scrapyard' }
function M.areaName(name)
  local words = {}
  for w in tostring(name or ''):gmatch('%S+') do words[#words + 1] = w end
  if words[1] and words[1]:lower() == 'the' then table.remove(words, 1) end
  local function trailing(w) w = w:lower() for _, t in ipairs(TRAILING) do if w == t then return true end end end
  while #words > 1 and trailing(words[#words]) do words[#words] = nil end
  return table.concat(words, ' ')
end

-- districts (with a centre) named after the nearest named place, so the turf map reads like the map: places = { { name, x, y } }.
-- Two districts with the same place: the second gets a number. With no places the compass names stay.
function M.nameByPlaces(districts, places)
  local used = {}
  for _, d in ipairs(districts) do
    local best, bd
    for _, p in ipairs(places or {}) do
      if p.name and p.x and p.y and d.centre then
        local dist = (p.x - d.centre.x) ^ 2 + (p.y - d.centre.y) ^ 2
        if not bd or dist < bd then best, bd = p, dist end
      end
    end
    if best then
      local name = M.areaName(best.name)
      if name ~= '' then
        used[name] = (used[name] or 0) + 1
        d.name = used[name] > 1 and (name .. ' ' .. used[name]) or name
      end
    end
  end
  return districts
end

-- the district a position is in: inside its polygon, else the nearest centre
function M.districtOf(districts, x, y)
  local best, bd
  for _, d in ipairs(districts) do
    if d.polygon and #d.polygon >= 3 and inside(d.polygon, x, y) then return d end
    local c = d.centre or d.label
    if c then
      local cx, cy = c.x or c[1], c.y or c[2]
      local dist = (x - cx) ^ 2 + (y - cy) ^ 2
      if not bd or dist < bd then best, bd = d, dist end
    end
  end
  return best
end

-- who holds what at the start: every crew its home (the file's, or one each in turn), the rest dealt round
function M.newTerritory(districts, rng)
  local t, homes, free = {}, {}, {}
  for _, d in ipairs(districts) do
    if d.home and M.crew(d.home) and not homes[d.home] then homes[d.home] = d.id else free[#free + 1] = d end
  end
  for _, c in ipairs(M.CREWS) do
    if not homes[c.id] and #free > 0 then homes[c.id] = table.remove(free, rng:int(#free)).id end
  end
  for crewId, id in pairs(homes) do t[id] = { owner = crewId, control = M.START_CONTROL, home = crewId } end
  local i = rng:int(#M.CREWS)
  for _, d in ipairs(free) do
    t[d.id] = { owner = M.CREWS[i].id, control = M.START_CONTROL }
    i = i % #M.CREWS + 1
  end
  return t
end

-- a street race in a district against a racer of crewId: what changes. Returns the district's entry and an event:
-- 'taken' (yours now), 'lost' (theirs again), or nil
function M.raceResult(t, districtId, crewId, isLeader, won, pink, friendly)
  local d = t[districtId]
  if not d or not crewId or crewId == friendly then return d, nil end
  if d.owner == 'player' then
    if won then d.control = math.min(100, d.control + M.DEFEND.won) return d, nil end
    d.control = d.control - M.DEFEND.lost * (pink and 2 or 1)
    if d.control <= 0 then d.owner, d.control = crewId, M.TAKEN_CONTROL return d, 'lost' end
    return d, nil
  end
  if d.owner ~= crewId then return d, nil end            -- (not their turf: nothing to win here)
  if won then
    d.control = d.control - (isLeader and M.GAIN.leader or M.GAIN.member) * (pink and 2 or 1)
    if d.control <= 0 then d.owner, d.control = 'player', M.TAKEN_CONTROL return d, 'taken' end
  else
    d.control = math.min(100, d.control + M.LOSS)
  end
  return d, nil
end

-- overnight the crews race each other: one district a night may change hands between them (never yours, never a home)
function M.nightly(t, rng)
  local open = {}
  for id, d in pairs(t) do if d.owner ~= 'player' and not d.home then open[#open + 1] = id end end
  table.sort(open)
  if #open == 0 then return nil end
  local id = open[rng:int(#open)]
  local d = t[id]
  local attacker = M.CREWS[rng:int(#M.CREWS)].id
  if attacker == d.owner then return nil end
  d.control = d.control - rng:int(5, 25)
  if d.control <= 0 then d.owner, d.control = attacker, M.TAKEN_CONTROL return id, attacker end
  return nil
end

function M.held(t)
  local n = 0
  for _, d in pairs(t) do if d.owner == 'player' then n = n + 1 end end
  return n
end

-- the perks in a district for the player: theirs when they hold it
function M.perks(t, districtId)
  local d = t[districtId]
  if d and d.owner == 'player' then return M.PERKS end
  return { rep = 1, heat = 1, pay = 1, shop = 1 }
end

-- the leaders come for you: enough districts held (or every crew but one has lost its home)
function M.turfWarReady(t)
  if M.held(t) >= M.TURF_WAR_AT then return true end
  local homesKept = 0
  for _, d in pairs(t) do if d.home and d.owner ~= 'player' then homesKept = homesKept + 1 end end
  return homesKept <= 1
end

return M
