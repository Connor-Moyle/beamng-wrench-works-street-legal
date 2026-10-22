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
local function within(v, d, lo, hi) v = tonumber(v) if not v or v ~= v then return d end return math.max(lo, math.min(hi, v)) end

-- the settings (the Mods menu rows, all optional): { kmPerPoint, cleanPoints, thresholdScale, insurance, trade, service, tyres (the percent each level gives) } -> the numbers used
function M.config(c)
  c = type(c) == 'table' and c or {}
  return { km = within(c.kmPerPoint, M.KM_PER_POINT, 1, 100), clean = within(c.cleanPoints, M.CLEAN_POINTS, 0, 200), scale = within(c.thresholdScale, 1, 0.25, 4),
    per = { insurance = -within(c.insurance, -M.PER_LEVEL.insurance * 100, 0, 5) / 100, service = -within(c.service, -M.PER_LEVEL.service * 100, 0, 5) / 100,
      tyres = -within(c.tyres, -M.PER_LEVEL.tyres * 100, 0, 5) / 100, trade = within(c.trade, M.PER_LEVEL.trade * 100, 0, 5) / 100 } }
end

function M.points(m, cfg)
  m = type(m) == 'table' and m or {}
  cfg = M.config(cfg)
  return math.floor(num(m.km) / cfg.km) + math.floor(num(m.clean)) * cfg.clean
end

function M.level(m, cfg)
  cfg = M.config(cfg)
  local p, lv = M.points(m, cfg), 0
  for i, t in ipairs(M.THRESHOLDS) do if p >= math.floor(t * cfg.scale + 0.5) then lv = i end end
  return lv
end

-- the points still needed for the next level, nil at the top
function M.toNext(m, cfg)
  cfg = M.config(cfg)
  local lv = M.level(m, cfg)
  local t = M.THRESHOLDS[lv + 1]
  return t and math.floor(t * cfg.scale + 0.5) - M.points(m, cfg) or nil
end

-- the multiplier for a kind at a level (1 for an unknown kind or level 0)
function M.factor(kind, level, cfg)
  local d = M.config(cfg).per[kind]
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
function M.view(m, cfg)
  cfg = M.config(cfg)
  local lv = M.level(m, cfg)
  local out = { level = lv, max = M.MAX_LEVEL, points = M.points(m, cfg), toNext = M.toNext(m, cfg), label = strings.t('mastery.level_' .. lv), perks = {} }
  if lv > 0 then
    out.perks = {
      strings.t('mastery.perk_insurance', string.format('%.4g', -cfg.per.insurance * lv * 100)),
      strings.t('mastery.perk_trade', string.format('%.4g', cfg.per.trade * lv * 100)),
      strings.t('mastery.perk_service', string.format('%.4g', -cfg.per.service * lv * 100)),
      strings.t('mastery.perk_tyres', string.format('%.4g', -cfg.per.tyres * lv * 100)),
    }
  end
  return out
end

return M
