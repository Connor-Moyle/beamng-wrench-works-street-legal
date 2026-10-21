-- Street Legal: hunger, thirst and sleep (the Needs part; the control repo's docs/NEEDS_SYSTEM.md). Pure rules, no engine calls, tested by tools/luatest.js.
-- Three meters 0..100 (100 is full) drain per awake game hour; stages give a text, then a gentle handicap (a blur, a slower reaction, shaky hands);
-- never a death and never a game over. Eating, drinking and sleep put them back. All numbers are first guesses for the tester and the sim to tune.

local M = {}

local strings = require('sl/core/strings')

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

M.RATES = { food = 6, water = 11, rest = 5 }             -- per awake game hour: food empty in 16 h, water in 9 h, rest in 20 h
M.MULT = { foodBusy = 1.3, waterHot = 1.5, restHeat = 1.3 } -- racing or on a job eats more; hot clear weather; a night race with heat on
M.STAGES = { ok = 40, nudge = 20, handicap = 8 }         -- at or above: ok; below: a nudge (text), a handicap, a problem
M.WELL_FED_HOURS = 2                                     -- every meter over 70 this long: a small tip bonus on taxi and delivery jobs
M.WELL_FED_OVER = 70
M.TIP_BONUS = 0.04

-- what you can buy and what it does (the fuel station sells all four)
M.ITEMS = {
  drink  = { name = strings.t('needs.item_drink'), price = 2, water = 35 },
  snack  = { name = strings.t('needs.item_snack'), price = 3, food = 25 },
  coffee = { name = strings.t('needs.item_coffee'), price = 3, rest = 10, water = 5 },
  meal   = { name = strings.t('needs.item_meal'), price = 12, food = 60, water = 20 },
}
M.ITEM_ORDER = { 'drink', 'snack', 'coffee', 'meal' }
-- rest per hour of sleep: a bed, a couch (the first garage), the car seat (away from a garage), a nap in the garage
M.SLEEP = { bed = 27, couch = 18, car = 9, nap = 15 }
M.NIGHT_GAP_HOURS = 3                                    -- 04:00 to 07:00: the sleep the day half starts with

function M.newState()
  return { food = 100, water = 100, rest = 100, fedHours = 0, told = {} }
end

-- a save's needs table made whole (a missing or odd field is full / empty)
function M.repair(n)
  n = type(n) == 'table' and n or {}
  for _, k in ipairs({ 'food', 'water', 'rest' }) do n[k] = clamp(tonumber(n[k]) or 100, 0, 100) end
  n.fedHours = math.max(0, tonumber(n.fedHours) or 0)
  n.told = type(n.told) == 'table' and n.told or {}
  return n
end

-- `hours` of awake game time pass. ctx: { busy (racing or on a job), hot (clear and warm by day), nightHeat (night with heat on) }; scale: the Drain speed setting
function M.tick(n, hours, ctx, scale)
  hours = tonumber(hours) or 0
  if hours <= 0 then return n end
  ctx = ctx or {}
  scale = tonumber(scale) or 1
  n.food = clamp(n.food - M.RATES.food * (ctx.busy and M.MULT.foodBusy or 1) * hours * scale, 0, 100)
  n.water = clamp(n.water - M.RATES.water * (ctx.hot and M.MULT.waterHot or 1) * hours * scale, 0, 100)
  n.rest = clamp(n.rest - M.RATES.rest * (ctx.nightHeat and M.MULT.restHeat or 1) * hours * scale, 0, 100)
  if n.food > M.WELL_FED_OVER and n.water > M.WELL_FED_OVER and n.rest > M.WELL_FED_OVER then n.fedHours = n.fedHours + hours else n.fedHours = 0 end
  return n
end

function M.stage(v)
  v = tonumber(v) or 100
  if v >= M.STAGES.ok then return 'ok' end
  if v >= M.STAGES.nudge then return 'nudge' end
  if v >= M.STAGES.handicap then return 'handicap' end
  return 'problem'
end

local WORDS = {
  food = { ok = 'fed', nudge = 'peckish', handicap = 'hungry', problem = 'starving' },
  water = { ok = 'fine', nudge = 'thirsty', handicap = 'parched', problem = 'dehydrated' },
  rest = { ok = 'rested', nudge = 'yawning', handicap = 'tired', problem = 'exhausted' },
}
function M.word(meter, v) return WORDS[meter][M.stage(v)] end

-- the nudge texts (strings.t keys), once per stage per meter (told[meter] holds the stage already said)
M.TEXTS = {
  food = { nudge = 'needs.food_nudge', handicap = 'needs.food_handicap', problem = 'needs.food_problem' },
  water = { nudge = 'needs.water_nudge', handicap = 'needs.water_handicap', problem = 'needs.water_problem' },
  rest = { nudge = 'needs.rest_nudge', handicap = 'needs.rest_handicap', problem = 'needs.rest_problem' },
}
-- the key of the text to say now, if any: the stage got worse than the one said (a meter back over its stage resets what was said)
function M.nudge(n)
  local out
  for _, k in ipairs({ 'food', 'water', 'rest' }) do
    local st = M.stage(n[k])
    if st == 'ok' then n.told[k] = nil
    elseif n.told[k] ~= st then
      local order = { nudge = 1, handicap = 2, problem = 3 }
      if (order[n.told[k]] or 0) < order[st] then n.told[k] = st out = out or M.TEXTS[k][st] else n.told[k] = st end
    end
  end
  return out
end

-- the effects of the moment: blur 0..1 (screen edges), lag in seconds (steering and pedals follow the input with this time constant),
-- tremor 0..1 (a faint shake on the steering). opts: { strength 0..1, blur, lag, tremor (switches), night }. Capped so it is never unfair.
M.CAP = { blur = 0.6, lag = 0.12, tremor = 0.6 }
function M.effects(n, opts)
  opts = opts or {}
  local k = clamp(tonumber(opts.strength) or 1, 0, 1)
  local e = { blur = 0, lag = 0, tremor = 0, sleepy = false }
  local w, r, f = M.stage(n.water), M.stage(n.rest), M.stage(n.food)
  if w == 'handicap' then e.blur = 0.25 elseif w == 'problem' then e.blur = 0.45 end
  if r == 'handicap' then
    e.lag = 0.06 + 0.06 * clamp((M.STAGES.nudge - n.rest) / (M.STAGES.nudge - M.STAGES.handicap), 0, 1)      -- 60 ms at 20, 120 ms at 8
    e.blur = e.blur + 0.15
  elseif r == 'problem' then
    e.lag, e.blur, e.sleepy = 0.12, e.blur + 0.3, opts.night == true
  end
  if f == 'handicap' then e.tremor = 0.3 elseif f == 'problem' then e.tremor = 0.5 end
  if opts.blur == false then e.blur = 0 end
  if opts.lag == false then e.lag = 0 end
  if opts.tremor == false then e.tremor = 0 end
  e.blur, e.lag, e.tremor = clamp(e.blur * k, 0, M.CAP.blur), clamp(e.lag * k, 0, M.CAP.lag), clamp(e.tremor * k, 0, M.CAP.tremor)
  if e.lag == 0 then e.sleepy = false end
  return e
end

-- eating or drinking: returns ok, the price, and a line for the player
function M.eat(n, itemId)
  local it = M.ITEMS[itemId]
  if not it then return false, 0, strings.t('needs.nothing_of_that') end
  local parts = {}
  for _, k in ipairs({ 'food', 'water', 'rest' }) do
    if it[k] then n[k] = clamp(n[k] + it[k], 0, 100) parts[#parts + 1] = strings.t('needs.meter_' .. k) .. ' ' .. math.floor(n[k]) end
  end
  if it.food then n.lastMeal = true end
  return true, it.price, strings.t('needs.ate_1_2', it.name, table.concat(parts, ', '))
end

-- sleep: `hours` at `where` (bed, couch, car, nap). Returns the rest gained.
function M.sleep(n, hours, where)
  local rate = M.SLEEP[where] or M.SLEEP.car
  local before = n.rest
  n.rest = clamp(n.rest + rate * math.max(0, tonumber(hours) or 0), 0, 100)
  return n.rest - before
end

function M.wellFed(n) return (n.fedHours or 0) >= M.WELL_FED_HOURS end
-- the tip bonus on a job (0 unless well fed)
function M.tipBonus(n) return M.wellFed(n) and M.TIP_BONUS or 0 end

-- what the phone shows
function M.summary(n, effects, extra)
  local out = { meters = {}, wellFed = M.wellFed(n), effects = effects or M.effects(n) }
  for _, k in ipairs({ 'food', 'water', 'rest' }) do out.meters[#out.meters + 1] = { id = k, value = math.floor(n[k] + 0.5), stage = M.stage(n[k]), word = M.word(k, n[k]) } end
  out.items = {}
  for _, id in ipairs(M.ITEM_ORDER) do local it = M.ITEMS[id] out.items[#out.items + 1] = { id = id, name = it.name, price = it.price } end
  for k, v in pairs(extra or {}) do out[k] = v end
  return out
end

return M
