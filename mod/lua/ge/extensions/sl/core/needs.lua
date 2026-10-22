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
  n.spentWeek = math.max(0, tonumber(n.spentWeek) or 0)      -- food and drink bought this week (the ledger line)
  n.plan = n.plan == true                                      -- the meal plan
  n.fridgeDay = tonumber(n.fridgeDay)                          -- the day the fridge was last used
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

-- ---- batch 2: the diner, the motel, the fridge and the bed, the meal plan, the ledger line, micro-sleeps
M.ITEMS.bigmeal = { name = strings.t('needs.item_bigmeal'), price = 25, food = 100, water = 40 }
M.DINER_ORDER = { 'drink', 'coffee', 'meal', 'bigmeal' }        -- what a diner sells (the fuel station sells ITEM_ORDER)
M.SIT_HOURS = 0.33                                              -- sitting down to eat: twenty minutes of the clock
M.MOTEL = { price = 40, hours = 6, where = 'bed' }              -- a room: six hours in a bed (27 an hour) is a full sleep
M.FRIDGE = { water = 100, food = 60 }                           -- the garage fridge, once a day: water full, food to 60
M.MEAL_PLAN = { weekly = 60, covers = { meal = true, bigmeal = true } }
M.MICRO = { minSpeed = 8, gapMin = 25, gapMax = 70, secMin = 0.5, secMax = 1.0, grace = 30 }      -- m/s, seconds between nods, how long a nod is, quiet seconds after a spawn or a switch

-- the price of an item at the counter: a meal on the plan is already paid
function M.price(itemId, plan)
  local it = M.ITEMS[itemId]
  if not it then return 0 end
  if plan and M.MEAL_PLAN.covers[itemId] then return 0 end
  return it.price
end

-- eating at a counter: like eat, but with the plan, and what is paid is added to the week's food and drink. Returns ok, price, text
function M.eatAt(n, itemId, plan)
  local price = M.price(itemId, plan)
  local ok, _, text = M.eat(n, itemId)
  if not ok then return false, 0, text end
  n.spentWeek = (n.spentWeek or 0) + price
  return true, price, text
end

-- the garage fridge: once a day. Returns true when it gave something
function M.fridge(n, day)
  if n.fridgeDay == day then return false end
  n.fridgeDay = day
  n.water = math.max(n.water, M.FRIDGE.water)
  n.food = math.max(n.food, M.FRIDGE.food)
  return true
end

-- where the night's sleep is: a bed (the garage has one), the couch (a garage), the car
function M.sleepPlace(atGarage, hasBed)
  if atGarage then return hasBed and 'bed' or 'couch' end
  return 'car'
end

-- a motel room: a full sleep. Returns the rest gained
function M.motel(n) return M.sleep(n, M.MOTEL.hours, M.MOTEL.where) end

-- the week's food and drink as a ledger line (an informational line: it was paid when bought), and the week starts again: { label key, amount } or nil
function M.takeWeek(n)
  local spent = math.floor((n.spentWeek or 0) + 0.5)
  n.spentWeek = 0
  if spent <= 0 then return nil end
  return { amount = spent }
end

-- the weekly bill of the meal plan: M.MEAL_PLAN.weekly while it is on
function M.planBill(n) return n.plan and M.MEAL_PLAN.weekly or 0 end

-- micro-sleeps (their own switch, off by default): a short nod at the wheel of a driver who is exhausted. st = { wait, quiet } kept by the caller; ctx = { on, rest, speed, blocked };
-- rnd() gives 0..1; dt in seconds. Returns the length of a nod in seconds, or nil. Never when the switch is off, rest is not in the problem stage, the car is slow, or blocked
-- (a race or a job, the first seconds after a spawn or a switch: ctx.blocked). The wait only runs down while a nod would be allowed.
function M.microStep(st, dt, ctx, rnd)
  st.wait = st.wait or (M.MICRO.gapMin + (M.MICRO.gapMax - M.MICRO.gapMin) * rnd())
  if not (ctx.on and M.stage(ctx.rest) == 'problem' and (ctx.speed or 0) >= M.MICRO.minSpeed and not ctx.blocked) then return nil end
  st.wait = st.wait - dt
  if st.wait > 0 then return nil end
  st.wait = M.MICRO.gapMin + (M.MICRO.gapMax - M.MICRO.gapMin) * rnd()
  return M.MICRO.secMin + (M.MICRO.secMax - M.MICRO.secMin) * rnd()
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
