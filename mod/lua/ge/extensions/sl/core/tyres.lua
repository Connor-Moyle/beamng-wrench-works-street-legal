-- Street Legal: the tyres of the career (design with Car Surface FX's tyre rules, tyre-research): which compounds exist for sale, where they are sold, what a set
-- or an axle costs, what the tread says about a tyre, and the quote of a tyre change. Pure, tested by tools/luatest.js. The physics (wear, temperature, grip) is
-- Car Surface FX's; this is the shop side. Compound ids are the ids of carSurfaceFx's tyrerules.COMPOUNDS.

local strings = require('sl/core/strings')

local M = {}

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

-- id -> { family, set = the price of four tyres, shop = the range it is sold in ('torres' Torres Tires, 'race' Fast Automotive) }
M.COMPOUNDS = {
  road         = { family = 'road',    set = 360,  shop = 'torres' },
  performance  = { family = 'road',    set = 640,  shop = 'torres' },
  winter       = { family = 'weather', set = 480,  shop = 'torres' },
  intermediate = { family = 'weather', set = 700,  shop = 'torres' },
  fullwet      = { family = 'weather', set = 700,  shop = 'torres' },
  offroad      = { family = 'offroad', set = 520,  shop = 'torres' },
  mud          = { family = 'offroad', set = 600,  shop = 'torres' },
  rally        = { family = 'offroad', set = 780,  shop = 'torres' },
  semislick    = { family = 'track',   set = 900,  shop = 'race' },
  slick        = { family = 'track',   set = 1100, shop = 'race' },
  slicksoft    = { family = 'track',   set = 1250, shop = 'race' },
  drag         = { family = 'track',   set = 800,  shop = 'race' },
}
M.ORDER = { 'road', 'performance', 'winter', 'intermediate', 'fullwet', 'offroad', 'mud', 'rally', 'semislick', 'slick', 'slicksoft', 'drag' }
M.SHOP_IDS = { torres = 'torresTires', race = 'fastAutomotive' }      -- the Wrench Works shop ids that stock each range
M.TRACK_FEE = 1.3             -- a change at a track or a meet costs this much (the crew comes to you)
M.TRADE_IN = 0.15             -- of the old set's price, times what is left of its tread
M.AXLES = { 'front', 'rear' }

function M.known(id) return M.COMPOUNDS[id] ~= nil end

function M.name(id) return strings.t('tyres.name_' .. tostring(id)) end

-- the compounds a shop stocks (a Wrench Works shop id), in display order; nil shop = all
function M.stocked(shopId)
  local out = {}
  for _, id in ipairs(M.ORDER) do
    local c = M.COMPOUNDS[id]
    if shopId == nil or M.SHOP_IDS[c.shop] == shopId then out[#out + 1] = id end
  end
  return out
end

-- what a change costs: compound id, axle 'front' | 'rear' | nil (all four), where 'shop' | 'garage' | 'track', the old fit { compound, frac } for the trade-in
-- -> price (whole dollars, never below 0) and the line items { gross, fee, credit }
function M.quote(compound, axle, where, old)
  local c = M.COMPOUNDS[compound]
  if not c then return nil, 'unknown compound' end
  local share = axle and 0.5 or 1
  local gross = c.set * share
  local credit = 0
  local o = old and M.COMPOUNDS[old.compound]
  if o then credit = o.set * share * M.TRADE_IN * clamp(old.frac or 0, 0, 1) end
  local fee = (where == 'track') and (M.TRACK_FEE - 1) * gross or 0
  local price = math.max(0, math.floor(gross + fee - credit + 0.5))
  return price, { gross = gross, fee = math.floor(fee + 0.5), credit = math.floor(credit + 0.5) }
end

-- the tread of a tyre as a word: frac 0..1 of the usable tread (0 = down to the belts)
M.STAGES = { { 0.75, 'new' }, { 0.45, 'good' }, { 0.2, 'worn' }, { 0.05, 'low' }, { -1, 'bald' } }
function M.stage(frac, blown)
  if blown then return 'blown' end
  frac = tonumber(frac) or 1
  for _, s in ipairs(M.STAGES) do if frac >= s[1] then return s[2] end end
  return 'bald'
end
M.FLAT_SPOT = 0.4             -- mm: a flat spot this deep is felt as a shake

-- getTyres() of Car Surface FX -> what the phone and the garage show per axle:
-- { { axle, compound, frac (the worst tyre of the axle), stage, flat (a flat spot you feel), blown, replace (bald or blown) } }
function M.summary(info)
  local out = {}
  if type(info) ~= 'table' then return out end
  for _, axle in ipairs(M.AXLES) do
    local row
    for _, w in ipairs(info.wheels or {}) do
      if w.axle == axle then
        row = row or { axle = axle, compound = w.compound or info.compound, frac = 1, blown = false, flat = false }
        row.frac = math.min(row.frac, clamp(tonumber(w.frac) or 1, 0, 1))
        row.blown = row.blown or w.blown == true
        row.flat = row.flat or (tonumber(w.flat) or 0) >= M.FLAT_SPOT
      end
    end
    if row then
      row.stage = M.stage(row.frac, row.blown)
      row.replace = row.blown or row.stage == 'bald' or row.stage == 'low'
      out[#out + 1] = row
    end
  end
  return out
end

-- the game's stage of a tyre (carSurfaceFx tyre rules: 0 fresh .. 5 worn to the belts) as a tread fraction, for a tyre module that does not give one
M.STAGE_FRAC = { [0] = 1, 0.8, 0.6, 0.4, 0.15, 0 }

-- one wheel of carSurfaceFx_tyres.getTyres: { idx, frac or stage, flat, blown } -> { idx, frac, stage (word), flat (felt), blown, replace }
function M.wheelRow(w)
  local frac = tonumber(w.frac)
  if frac == nil and tonumber(w.stage) then frac = M.STAGE_FRAC[math.max(0, math.min(5, math.floor(w.stage)))] end
  frac = clamp(frac or 1, 0, 1)
  local blown = w.blown == true
  local word = M.stage(frac, blown)
  return { idx = w.idx, frac = frac, stage = word, flat = (tonumber(w.flat) or 0) >= M.FLAT_SPOT, blown = blown, replace = blown or word == 'bald' or word == 'low',
    axle = w.axle, side = w.side, compound = w.compound, mm = tonumber(w.tread) }
end

-- the car's tyres for the garage and the phone: { compound, rows = { wheelRow... }, worst = the row with the least tread, replace = any tyre to replace }; nil without tyre data
function M.carRows(info)
  if type(info) ~= 'table' or type(info.wheels) ~= 'table' or #info.wheels == 0 then return nil end
  local rows, worst, replace = {}, nil, false
  for _, w in ipairs(info.wheels) do
    local r = M.wheelRow(w)
    rows[#rows + 1] = r
    if not worst or r.frac < worst.frac or r.blown then worst = r end
    replace = replace or r.replace
  end
  return { compound = info.compound or (worst and worst.compound), rows = rows, worst = worst, replace = replace, axles = M.summary(info) }
end

-- why a change cannot go ahead (nil: it can)
function M.refusal(price, money, carMoving)
  if carMoving then return strings.t('tyres.stop_the_car_first') end
  if (money or 0) < (price or 0) then return strings.t('tyres.you_cannot_afford_that') end
  return nil
end

-- a change of the whole car's tyres: compound id, where ('garage' | 'track'), the set now on { compound, frac } (frac = the worst tyre's tread), money, whether the car is moving
-- -> { ok, price, parts = { gross, fee, credit } } or { ok = false, why = text }
function M.plan(compound, where, current, money, moving)
  local price, parts = M.quote(compound, nil, where, current)
  if not price then return { ok = false, why = strings.t('tyres.not_here') } end
  local why = M.refusal(price, money, moving)
  if why then return { ok = false, why = why, price = price, parts = parts } end
  return { ok = true, price = price, parts = parts }
end

return M
