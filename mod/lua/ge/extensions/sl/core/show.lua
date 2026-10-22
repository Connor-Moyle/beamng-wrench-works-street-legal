-- Street Legal: the Style show (campaign idea #9, docs/STYLE_SHOW.md). Pure, no game calls: tested by tools/luatest.lua. Judges score a car by six criteria (paint and finish, wheels, aftermarket
-- parts, cleanliness, body, wear); each is a number 0..1 or nil when its source is missing (a mod that is absent drops its criterion and the rest renormalise, so nothing ever errors). A field
-- of rival cars with seeded scores, the place, the prize and the reputation, a judge's line per criterion and the one thing to improve first. The extension (sl/show.lua) gathers the inputs.

local M = {}

local strings = require('sl/core/strings')
local rngLib = require('sl/core/rng')
local roster = require('sl/core/roster')
local weekly = require('sl/core/weekly')

local function clamp(x, lo, hi) return x < lo and lo or (x > hi and hi or x) end
M.clamp = clamp

M.ORDER = { 'paint', 'wheels', 'parts', 'clean', 'body', 'wear' }
M.WEIGHTS = { paint = 25, wheels = 15, parts = 20, clean = 15, body = 15, wear = 10 }

M.FEE = 60                       -- the entry fee
M.DOW = 6                        -- Saturday (core/weekly: day 6 of the week)
M.HOUR = 21                      -- the show starts at nine in the evening
M.START_REACH = 80               -- metres from the marker to be on time (as the weekend race)
M.LATE_H = 1.5
M.PURSE = { 300, 500, 800, 1100, 1500 }              -- by tier of the player's reputation (core/roster tiers)
M.SHARE = { 1, 0.5, 0.25 }                           -- of the purse for the places 1, 2, 3
M.REP_BASE, M.REP_TIER = 12, 8                       -- reputation for a win: 12 + 8 x tier; half and a quarter for 2nd and 3rd
M.FIELD_MIN, M.FIELD_MAX = 7, 11
M.TIER_MEAN = { 0.40, 0.50, 0.60, 0.70, 0.80 }       -- the mean score of the rival cars by tier
M.PARTS_FULL = 10                                    -- aftermarket parts for the full parts score
M.WEAR_PARTS = 12                                    -- fully worn parts that make the wear score zero

function M.tierOf(rep)
  rep = tonumber(rep) or 0
  for i = #roster.TIERS, 1, -1 do if rep >= roster.TIERS[i].rep[1] then return i end end
  return 1
end

-- ---- the six criteria. Every function answers nil when its input is nil or not a table (the source is missing)

-- paint: the car's paint slots (Wrench Works: slrr_garageParts.getPaints(): { { baseColor = { r, g, b, a }, metallic, roughness, clearcoat, clearcoatRoughness } .. }), the Part Wear paint
-- condition (1 when Part Wear is off) and whether the colour differs from the factory one (a respray counts)
function M.paintScore(paints, condition, changed)
  if type(paints) ~= 'table' or type(paints[1]) ~= 'table' then return nil end
  local p = paints[1]
  local function num(x, d) x = tonumber(x) if x == nil or x ~= x then return d end return clamp(x, 0, 1) end
  local gloss = 0.5 * num(p.clearcoat, 0.5) + 0.5 * (1 - num(p.clearcoatRoughness, 0.5))
  local metallic = num(p.metallic, 0)
  local c = type(p.baseColor) == 'table' and p.baseColor or { 0.5, 0.5, 0.5 }
  local r, g, b = num(c[1], 0.5), num(c[2], 0.5), num(c[3], 0.5)
  local hi, lo = math.max(r, g, b), math.min(r, g, b)
  local sat = hi > 0.02 and (hi - lo) / hi or 0
  local colour = 0.6 * sat + 0.4 * (changed and 1 or 0)
  local finish = 0.45 * gloss + 0.25 * metallic + 0.30 * colour
  return clamp(finish * (0.4 + 0.6 * clamp(tonumber(condition) or 1, 0, 1)), 0, 1)
end

-- wheels: { aftermarket = rims of an aftermarket brand, tread = the tread left 0..1 (nil: not known) }
function M.wheelsScore(w)
  if type(w) ~= 'table' then return nil end
  local tread = tonumber(w.tread)
  return clamp(0.45 + (w.aftermarket and 0.40 or 0) + 0.15 * (tread ~= nil and clamp(tread, 0, 1) or 0.7), 0, 1)
end

-- aftermarket parts: counts = { [brandId] = parts of that aftermarket brand fitted }; a full kit of one brand beats a pile of mixed ones
function M.partsScore(counts)
  if type(counts) ~= 'table' then return nil end
  local n, most = 0, 0
  for _, k in pairs(counts) do
    k = tonumber(k) or 0
    n, most = n + k, math.max(most, k)
  end
  local cohesion = n >= 3 and (most / n) * clamp(n / 6, 0, 1) or 0
  return clamp(0.6 * clamp(n / M.PARTS_FULL, 0, 1) + 0.4 * cohesion, 0, 1)
end

-- cleanliness: Car Surface FX: { dirt = 0..1, scratches = 0..1 }
function M.cleanScore(level)
  if type(level) ~= 'table' or tonumber(level.dirt) == nil then return nil end
  return clamp(1 - clamp(level.dirt, 0, 1) ^ 0.7 - 0.25 * clamp(tonumber(level.scratches) or 0, 0, 1), 0, 1)
end

-- body: the car's damage 0..1 (the car report)
function M.bodyScore(damage)
  damage = tonumber(damage)
  if damage == nil or damage ~= damage then return nil end
  return clamp(1 - 1.4 * clamp(damage, 0, 1), 0, 1)
end

-- wear: the conditions (1 = new) of the parts Part Wear lists below new; a part that is not listed is new
function M.wearScore(conditions)
  if type(conditions) ~= 'table' then return nil end
  local lost = 0
  for _, c in ipairs(conditions) do lost = lost + (1 - clamp(tonumber(c) or 1, 0, 1)) end
  return clamp(1 - lost / M.WEAR_PARTS, 0, 1)
end

-- ---- the total. inp = { paint = { paints, condition, changed }, wheels = {..}, parts = counts, clean = {..}, body = damage, wear = { conditions } }, every part may be nil.
-- Returns { criteria = { id = 0..1 }, used = { id = weight (renormalised to 100) }, missing = { id }, total = 0..100 | nil }
function M.score(inp)
  inp = type(inp) == 'table' and inp or {}
  local c = {
    paint = inp.paint and M.paintScore(inp.paint.paints, inp.paint.condition, inp.paint.changed) or nil,
    wheels = M.wheelsScore(inp.wheels), parts = M.partsScore(inp.parts), clean = M.cleanScore(inp.clean), body = M.bodyScore(inp.body), wear = M.wearScore(inp.wear),
  }
  local sum, missing = 0, {}
  for _, id in ipairs(M.ORDER) do
    if c[id] ~= nil then sum = sum + M.WEIGHTS[id] else missing[#missing + 1] = id end
  end
  local used, total = {}, nil
  if sum > 0 then
    total = 0
    for _, id in ipairs(M.ORDER) do
      if c[id] ~= nil then
        used[id] = M.WEIGHTS[id] * 100 / sum
        total = total + used[id] * c[id]
      end
    end
    total = math.floor(total * 10 + 0.5) / 10
  end
  return { criteria = c, used = used, missing = missing, total = total }
end

-- the settings (the Mods rows, all optional): { fee, hour, prize (a multiplier of the purse), tipAt (the points a criterion must lose before the judges name it), stand (seconds to stand at the marker) }
local function within(v, d, lo, hi) v = tonumber(v) if not v or v ~= v then return d end return math.max(lo, math.min(hi, v)) end
function M.config(c)
  c = type(c) == 'table' and c or {}
  return { fee = math.floor(within(c.fee, M.FEE, 0, 1000) + 0.5), hour = math.floor(within(c.hour, M.HOUR, 18, 23) + 0.5), prize = within(c.prize, 1, 0.25, 3), tipAt = within(c.tipAt, 3, 0, 20), stand = within(c.stand, 1.2, 0.2, 10) }
end

-- ---- the judges' words: a band 1 (poor) to 4 (excellent) per criterion and the one thing to put right first (the criterion that loses the most weighted points)
function M.band(x) return x < 0.35 and 1 or (x < 0.55 and 2 or (x < 0.75 and 3 or 4)) end
function M.lines(result, cfg)
  local tipAt = M.config(cfg).tipAt
  local out, worst, wd = {}, nil, 0
  for _, id in ipairs(M.ORDER) do
    local s = result.criteria[id]
    if s ~= nil then
      out[#out + 1] = { id = id, score = s, weight = result.used[id], text = strings.t('show.' .. id .. '_' .. M.band(s)) }
      local deficit = result.used[id] * (1 - s)
      if deficit > wd + 1e-9 then worst, wd = id, deficit end
    end
  end
  local tip = (worst and wd >= tipAt) and strings.t('show.' .. worst .. '_tip') or nil
  return out, tip, worst
end

-- ---- the field of rival cars: the same for the same seed and week, better with the tier
local FIRST = { 'Viktor', 'Dora', 'Mick', 'Lena', 'Tomi', 'Andre', 'Kenji', 'Jade', 'Carla', 'Marek', 'Rosa', 'Nadia', 'Brett', 'Petra', 'Leon', 'Gina', 'Oskar', 'Mira', 'Tess', 'Hana' }
local LAST = { 'Halasz', 'Santana', 'Weiss', 'Mori', 'Bauer', 'Reyes', 'Kim', 'Novak', 'Varga', 'Brandt', 'Costa', 'Holm', 'Rossi', 'Vidal', 'Doyle', 'Sato', 'Jansen', 'Pike', 'Okafor', 'Kral' }
local CARS = { 'low coupe', 'hot hatch', 'wide-body sedan', 'old roadster', 'muscle car', 'tuned wagon', 'rally replica', 'show truck', 'drift sedan', 'retro sports car', 'fastback' }

function M.fieldSize(tier) return clamp(M.FIELD_MIN + (tier or 1) - 1, M.FIELD_MIN, M.FIELD_MAX) end
function M.field(seed, week, tier, n)
  tier = clamp(math.floor(tonumber(tier) or 1), 1, #M.TIER_MEAN)
  n = n or M.fieldSize(tier)
  local rng = rngLib.new(rngLib.hash('show:' .. tostring(seed) .. ':' .. tostring(week)))
  local list, used = {}, {}
  for i = 1, n do
    local name
    repeat name = rng:pick(FIRST) .. ' ' .. rng:pick(LAST) until not used[name]
    used[name] = true
    local skill = clamp(M.TIER_MEAN[tier] + rng:range(-0.18, 0.18), 0.05, 0.97)
    local scores = {}
    for _, id in ipairs(M.ORDER) do scores[id] = clamp(skill + rng:range(-0.22, 0.22), 0, 1) end
    list[i] = { name = name, car = rng:pick(CARS), scores = scores }
  end
  return list
end
-- a rival's total on the criteria the player was judged on (the same weights, so a missing source does not tilt the placing)
function M.rivalTotal(rival, used)
  local t = 0
  for id, w in pairs(used) do t = t + w * (rival.scores[id] or 0) end
  return math.floor(t * 10 + 0.5) / 10
end
-- the placing of a total in a field: ties go to the rival. Returns the place (1 = first), and the top three { { name, total, you } }
function M.rank(total, used, field, playerName)
  local all = { { name = playerName or 'You', total = total, you = true } }
  for _, r in ipairs(field) do all[#all + 1] = { name = r.name, car = r.car, total = M.rivalTotal(r, used) } end
  table.sort(all, function(a, b)
    if a.total ~= b.total then return a.total > b.total end
    if a.you ~= b.you then return not a.you end                  -- (a tie goes to the rival)
    return a.name < b.name
  end)
  local place
  for i, e in ipairs(all) do if e.you then place = i end end
  return place, { all[1], all[2], all[3] }, all
end

-- ---- the prize: money and reputation by tier and place (nothing past the third)
local function round10(x) return math.floor(x / 10 + 0.5) * 10 end
function M.prize(tier, place, cfg)
  local scale = M.config(cfg).prize
  tier = clamp(math.floor(tonumber(tier) or 1), 1, #M.PURSE)
  local share = M.SHARE[place]
  if not share then return 0, 0 end
  return round10(M.PURSE[tier] * share * scale), math.floor((M.REP_BASE + M.REP_TIER * tier) * share + 0.5)
end

-- ---- the calendar event of a Saturday night (nil on other days): spots = a list of meet spot names (the career's), seed = the career's seed
function M.event(day, seed, spots, rep, cfg)
  cfg = M.config(cfg)
  if weekly.dayOfWeek(day) ~= M.DOW then return nil end
  local week = weekly.week(day)
  local list = (type(spots) == 'table' and #spots > 0) and spots or { strings.t('show.default_spot') }
  local i = ((week + (tonumber(seed) or 0)) % #list) + 1
  local spot = list[i]
  local tier = M.tierOf(rep)
  return { id = 'show:' .. i .. ':' .. week, title = strings.t('show.title', spot), kind = 'show', day = day, hour = cfg.hour, place = spot, map = nil,
    travel = { needed = false, fee = 0, hours = 0 }, series = nil, reward = strings.t('show.reward', round10(M.PURSE[tier] * cfg.prize)), fee = cfg.fee, week = week, spot = spot,
    requires = nil }
end

return M
