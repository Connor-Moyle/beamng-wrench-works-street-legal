-- Street Legal: rally stages on West Coast USA (#24). Pure, tested by tools/luatest.js. A stage is a line of points along a dirt or gravel road
-- (mod/street_legal/rally/west_coast_usa.json, tools/make_rally.py). From the line's curvature this gives the pacenotes (corner calls with a severity, 1 the
-- tightest to 6 nearly flat), follows a car along it, and works out the par time, the prize and who may enter (a class rule).

local M = {}

M.DS = 5                    -- m between the line's points (as the file is made)
M.TURN_PER_STEP = 0.035     -- rad of turn in one step that makes it a corner (a radius under about 140 m)
M.MIN_CALL = 6              -- m: a corner shorter than this is not called

-- how tight a corner is by its tightest radius (m): 6 flat out ... 1 hairpin
function M.severity(minR)
  if minR < 18 then return 1 end
  if minR < 30 then return 2 end
  if minR < 50 then return 3 end
  if minR < 80 then return 4 end
  if minR < 120 then return 5 end
  return 6
end

local atan2 = math.atan2 or math.atan                 -- (LuaJIT in the game has atan2; Lua 5.3 in the tests only atan)
local function heading(a, b) return atan2(b[2] - a[2], b[1] - a[1]) end
local function wrap(x)
  while x > math.pi do x = x - 2 * math.pi end
  while x < -math.pi do x = x + 2 * math.pi end
  return x
end

-- cumulative distance along the points
function M.cumulative(points)
  local out = { 0 }
  for i = 2, #points do
    out[i] = out[i - 1] + math.sqrt((points[i][1] - points[i - 1][1]) ^ 2 + (points[i][2] - points[i - 1][2]) ^ 2)
  end
  return out
end

-- the corners: { at (m along the line to its start), len, dir = 'left' | 'right', sev = 1..6, angle (rad), minR }
function M.corners(points)
  local cum = M.cumulative(points)
  local turns = {}
  for i = 2, #points - 1 do
    local d1, d2 = heading(points[i - 1], points[i]), heading(points[i], points[i + 1])
    local ds = (cum[i + 1] - cum[i - 1]) / 2
    turns[i] = { d = wrap(d2 - d1), ds = math.max(ds, 1e-3) }
  end
  local out, cur = {}, nil
  local function close()
    if cur and cur.len >= M.MIN_CALL then
      cur.sev = M.severity(cur.minR)
      out[#out + 1] = cur
    end
    cur = nil
  end
  for i = 2, #points - 1 do
    local t = turns[i]
    local rate = math.abs(t.d) / t.ds * M.DS             -- turn per DS metres
    local dir = t.d > 0 and 'left' or 'right'
    if rate > M.TURN_PER_STEP then
      local r = t.ds / math.max(math.abs(t.d), 1e-6)
      if cur and cur.dir ~= dir then close() end
      if not cur then cur = { at = cum[i], len = 0, dir = dir, angle = 0, minR = r } end
      cur.len, cur.angle, cur.minR = cum[i] - cur.at + t.ds, cur.angle + math.abs(t.d), math.min(cur.minR, r)
    else
      close()
    end
  end
  close()
  return out
end

local SEV_WORD = { [1] = 'hairpin', [2] = '2', [3] = '3', [4] = '4', [5] = '5', [6] = '6' }

-- the call for a corner: 'Left 4', 'Hairpin right', 'Right 3 long' (a long one over 60 m)
function M.callText(c)
  local side = c.dir == 'left' and 'Left' or 'Right'
  if c.sev == 1 then return 'Hairpin ' .. c.dir end
  return side .. ' ' .. SEV_WORD[c.sev] .. (c.len > 60 and ' long' or '')
end

-- the pacenotes: { at, text, dist (m to the next call, nil at the last) }; corners closer than 30 m are one call 'Left 4 into Right 3'
function M.pacenotes(points)
  local cs = M.corners(points)
  local notes = {}
  local i = 1
  while i <= #cs do
    local c = cs[i]
    local text = M.callText(c)
    local j = i
    while cs[j + 1] and cs[j + 1].at - (cs[j].at + cs[j].len) < 30 and j - i < 2 do
      j = j + 1
      text = text .. ' into ' .. M.callText(cs[j])
    end
    notes[#notes + 1] = { at = c.at, text = text, sev = c.sev }
    i = j + 1
  end
  for k = 1, #notes - 1 do notes[k].dist = math.floor((notes[k + 1].at - notes[k].at) / 10 + 0.5) * 10 end
  return notes
end

-- the call to show now: the first note that starts ahead of `along` within `look` metres; nil when none is near. Returns the note and its index.
function M.nextCall(notes, along, look)
  for i, n in ipairs(notes) do
    if n.at > along then
      if n.at - along <= look then return n, i end
      return nil
    end
  end
end

-- how far along the line a car at (x, y) is, looking only a little way ahead of where it was (so a loop that comes back near its start is not mistaken):
-- returns the index of the nearest point in [from, from + window] and its distance (m)
function M.progress(points, x, y, from, window)
  local best, bd = from, math.huge
  for i = math.max(1, from), math.min(#points, from + (window or 20)) do
    local d = math.sqrt((points[i][1] - x) ^ 2 + (points[i][2] - y) ^ 2)
    if d < bd then best, bd = i, d end
  end
  return best, bd
end

M.PAR_SPEED = 20            -- m/s average a good time on dirt is
function M.parTime(length) return length / M.PAR_SPEED end

M.ENTRY_FEE = 50
M.MAX_PRIZE = 600
M.MIN_PRIZE = 100
-- the prize for a finish: at or under the par time the most, at 1.35 x par or slower the least; a time that is not valid (off the stage) pays nothing
function M.prize(par, time)
  if not time or time <= 0 or not par or par <= 0 then return 0 end
  local x = math.max(0, math.min(1, (par * 1.35 - time) / (par * 0.35)))
  return math.floor((M.MIN_PRIZE + (M.MAX_PRIZE - M.MIN_PRIZE) * x) / 10 + 0.5) * 10
end

-- the class rule: a rally class car makes at most 300 PS and weighs at least 900 kg (no rocket and no featherweight); car: { power, weight } from the config
M.CLASS = { maxPower = 300, minWeight = 900 }
function M.classOk(car)
  if type(car) ~= 'table' then return false, 'Bring a car.' end
  local p, w = tonumber(car.power), tonumber(car.weight)
  if p and p > M.CLASS.maxPower then return false, string.format('Rally class is %d PS at most; this car has %d.', M.CLASS.maxPower, math.floor(p)) end
  if w and w < M.CLASS.minWeight then return false, string.format('Rally class cars weigh at least %d kg.', M.CLASS.minWeight) end
  return true
end

return M
