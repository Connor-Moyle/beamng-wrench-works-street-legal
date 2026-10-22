-- Street Legal: car mastery (career expansion #13). Kilometres and clean runs in one car earn small lasting perks for that car.
-- Pure, no game calls: tested by tools/luatest.js. The game side is sl/mastery.lua. The counters are car.mastery = { km, clean } (additive in the save).

local M = {}

local strings = require('sl/core/strings')

M.KM_PER_POINT = 5
M.CLEAN_POINTS = 20
M.THRESHOLDS = { 100, 300, 600, 1000, 1600 }     -- points for levels 1 to 5
M.MAX_LEVEL = #M.THRESHOLDS

-- the factor each level adds, per kind (a price or a payout multiplier)
M.PER_LEVEL = { insurance = -0.02, service = -0.02, tyres = -0.02, trade = 0.015 }

local function num(v) v = tonumber(v) return v and v == v and v > 0 and math.min(v, 1e7) or 0 end      -- (capped: no overflow on a hand-edited save)

function M.points(m)
  m = type(m) == 'table' and m or {}
  return math.floor(num(m.km) / M.KM_PER_POINT) + math.floor(num(m.clean)) * M.CLEAN_POINTS
end

function M.level(m)
  local p, lv = M.points(m), 0
  for i, t in ipairs(M.THRESHOLDS) do if p >= t then lv = i end end
  return lv
end

-- the points still needed for the next level, nil at the top
function M.toNext(m)
  local lv = M.level(m)
  local t = M.THRESHOLDS[lv + 1]
  return t and t - M.points(m) or nil
end

-- the multiplier for a kind at a level (1 for an unknown kind or level 0)
function M.factor(kind, level)
  local d = M.PER_LEVEL[kind]
  if not d then return 1 end
  return 1 + d * math.max(0, math.min(M.MAX_LEVEL, math.floor(num(level))))
end

-- the counters after a sync: the odometer reading since the car was bought (never goes back) and a clean run when asked
function M.bump(m, kmSince, clean)
  m = type(m) == 'table' and m or {}
  m.km, m.clean = math.max(num(m.km), num(kmSince)), num(m.clean) + (clean and 1 or 0)      -- (in place: the save keeps the table and anything else the game side stores in it)
  return m
end

-- for the car card: { level, points, toNext, perks = { text } } (perks of the level reached)
function M.view(m)
  local lv = M.level(m)
  local out = { level = lv, max = M.MAX_LEVEL, points = M.points(m), toNext = M.toNext(m), label = strings.t('mastery.level_' .. lv), perks = {} }
  if lv > 0 then
    out.perks = {
      strings.t('mastery.perk_insurance', math.floor(-M.PER_LEVEL.insurance * lv * 100 + 0.5)),
      strings.t('mastery.perk_trade', string.format('%.1f', M.PER_LEVEL.trade * lv * 100)),
      strings.t('mastery.perk_service', math.floor(-M.PER_LEVEL.service * lv * 100 + 0.5)),
      strings.t('mastery.perk_tyres', math.floor(-M.PER_LEVEL.tyres * lv * 100 + 0.5)),
    }
  end
  return out
end

return M
