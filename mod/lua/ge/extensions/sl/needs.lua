-- Street Legal: hunger, thirst and sleep (extension name: sl_needs; the Needs part, off by default: Mods > Street Legal > Parts of the game > Needs).
-- Rules in sl/core/needs. The meters drain with the career clock while the player is awake, sleep comes with Start the day (the 04:00 to 07:00 gap)
-- or a nap at the garage, food and drink are bought at a fuel station (the Health page of the phone). Effects: a blur at the screen edges (the
-- same screen blur the Driver Injuries add-on uses; the larger of the two shows), a reaction lag and a tremor in the player's car (slNeeds,
-- vehicle side). The state is s.needs in the career save; a save without it starts full.
-- Batch 2: a diner and a motel (shop kinds, sl_shops: sitting down to eat takes twenty minutes, a room is a full sleep), a fridge and a bed for the garage (upgrades), sleep that shortens the recovery of the
-- Driver Injuries driver (slrrInjury.healFor, when the add-on has it), the hospital resets the meters, a meal plan and the week's food and drink in the weekly ledger, and micro-sleeps (their own switch, off).

local M = {}

local rules = require('sl/core/needs')
local strings = require('sl/core/strings')
local features = require('sl/core/features')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function partOn() return features.on('needs') end
local function opt(key, default)
  if not (sl_options and sl_options.get) then return default end
  local v = sl_options.get(key)
  if v == nil then return default end
  return v
end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end
local provided, provide      -- (sl_shops gets the diner and the motel when it is there)

local function needsOf(s)
  s.needs = rules.repair(s.needs)
  return s.needs
end

-- ---- what is going on round the player
local function isNight() return sl_career and sl_career.isNight and sl_career.isNight() == true end
local function busy()
  local j = rawget(_G, 'sl_jobs')
  if j and j.active and j.active() then return true end
  local r = rawget(_G, 'sl_races')
  local st = r and r.getState and r.getState()
  return type(st) == 'table' and st.racing == true
end
local function hot()
  if isNight() then return false end
  local w = rawget(_G, 'sl_weather')
  return w ~= nil and w.state ~= nil and w.state() == 'clear'
end
local function nightHeat()
  local p = rawget(_G, 'sl_police')
  return isNight() and p ~= nil and p.level ~= nil and (p.level() or 0) > 0
end
local function nearPlace(kind, within)
  local v = getPlayerVehicle(0)
  local places = v and sl_career.getPlaces and sl_career.getPlaces()
  if not places then return nil end
  local p = v:getPosition()
  for _, place in pairs(places) do
    if place.kind == kind and place.pos and (place.pos - p):length() < within then return place end
  end
  return nil
end

-- what the player's garage has (sl_upgrades): a bed, a fridge
local function garageHas(what)
  local s = career()
  local f = s and sl_upgrades and sl_upgrades.features and sl_upgrades.features(s)
  return type(f) == 'table' and f[what] == true
end

-- sleep shortens the recovery of the Driver Injuries driver (slrrInjury.healFor, real seconds of recovery: an hour slept is two minutes); a long sleep (a bed or a room) that leaves the recovery at
-- nothing lets a broken limb heal (the career decides that, as the add-on asks). Guarded: the add-on may not have it yet.
local SECONDS_PER_HOUR = 120
local function healInjury(hours, full)
  local inj = rawget(_G, 'slrrInjury')
  if not (inj and inj.healFor) then return end
  pcall(inj.healFor, hours * SECONDS_PER_HOUR)
  if full and inj.getState and inj.heal then
    local ok, st = pcall(inj.getState)
    if ok and type(st) == 'table' and st.injured and (tonumber(st.recoverySeconds) or 0) <= 0 then pcall(inj.heal) end
  end
end

local function effectOpts()
  return { strength = (tonumber(opt('slNeedsStrength', 100)) or 100) / 100, blur = opt('slNeedsBlur', true) ~= false, lag = opt('slNeedsLag', true) ~= false,
           tremor = opt('slNeedsTremor', true) ~= false, night = isNight() }
end

-- ---- micro-sleeps (their own switch, off): a short nod at the wheel when exhausted. Never in a race or on a job, never in the first seconds after a spawn, a switch or a new phase
local micro, graceUntil = {}, 0
local function grace() graceUntil = os.clock() + rules.MICRO.grace end
local function blockedForNod()
  if busy() or os.clock() < graceUntil then return true end
  local st = rawget(_G, 'sl_streets')
  return st ~= nil and st.isRacing ~= nil and st.isRacing() == true
end
local function microSleep(n)
  if opt('slNeedsMicrosleep', false) ~= true then micro.wait = nil return end
  local v = getPlayerVehicle(0)
  if not v or v:getJBeamFilename() == 'unicycle' then return end
  local ok, speed = pcall(function() return v:getVelocity():length() end)
  local sec = rules.microStep(micro, 0.5, { on = true, rest = n.rest, speed = ok and speed or 0, blocked = blockedForNod() }, math.random)
  if not sec then return end
  v:queueLuaCommand(string.format('if not slNeeds then extensions.load("slNeeds") end if slNeeds then slNeeds.nod(%.2f) end', sec))
  toast(strings.t('needs.micro_nod'))
end

-- ---- the clock: awake game hours pass. The effects of the moment are worked out here, twice a second, and kept for the frames (onPreRender reads them)
local lastHour, tickT = nil, 0
local NONE = { blur = 0, lag = 0, tremor = 0, sleepy = false }
local current = NONE
local function tick(dtReal)
  tickT = tickT + dtReal
  if tickT < 0.5 then return end
  tickT = 0
  local s = career()
  if not s then lastHour = nil current = NONE return end
  current = rules.effects(needsOf(s), effectOpts())
  if not provided then provide() end
  microSleep(needsOf(s))
  local h = sl_career.hour()
  if lastHour == nil then lastHour = h return end
  local d = h - lastHour
  lastHour = h
  if d < 0 then d = d + 24 end
  if d <= 0 or d > 1 then return end         -- (a jump: a phase switch, a wait, a nap; those are handled where they happen)
  local n = needsOf(s)
  rules.tick(n, d, { busy = busy(), hot = hot(), nightHeat = nightHeat() }, tonumber(opt('slNeedsDrain', 1)) or 1)
  local key = rules.nudge(n)
  if key then
    if not n.toldOnce then n.toldOnce = true sl_career.sendText('benny', strings.t('needs.benny_rough'), 2) end
    toast(strings.t(key))
  end
end

-- ---- the effects
local sent = { lag = 0, tremor = 0, vid = nil }
local function pushCar(force)
  local s = career()
  local v = getPlayerVehicle(0)
  local vid = v and v:getID()
  local e = (s and partOn()) and rules.effects(needsOf(s), effectOpts()) or { lag = 0, tremor = 0 }      -- (the part off, or no career: the car is let go)
  if not v or v:getJBeamFilename() == 'unicycle' then e = { lag = 0, tremor = 0 } end
  local changed = force or vid ~= sent.vid or math.abs(e.lag - sent.lag) > 0.005 or math.abs(e.tremor - sent.tremor) > 0.02
  if not changed then return end
  if sent.vid and sent.vid ~= vid then      -- (always: a nod in progress goes too)
    local old = getObjectByID(sent.vid)
    if old then old:queueLuaCommand('if slNeeds then slNeeds.set(0, 0) slNeeds.release() end') end
  end
  sent.lag, sent.tremor, sent.vid = e.lag, e.tremor, vid
  if v and (e.lag > 0 or e.tremor > 0) then
    v:queueLuaCommand(string.format('if not slNeeds then extensions.load("slNeeds") end if slNeeds then slNeeds.set(%.3f, %.3f) end', e.lag, e.tremor))
  elseif v then
    v:queueLuaCommand('if slNeeds then slNeeds.set(0, 0) slNeeds.release() end')      -- (the part off, no career, a unicycle: the car, and a nod in progress, are let go)
  end
end
local pushT = 0

local function reduceMotion()
  if opt('slNeedsReduceMotion', false) == true then return true end
  local inj = rawget(_G, 'slrrInjury')
  return inj ~= nil and inj.getTune ~= nil and (inj.getTune('reduceMotion') or 0) ~= 0
end
local blurPhase, preRenderFailed = 0, false
local RECTS = { { 0, 0, 0.26, 1 }, { 0.74, 0, 1, 1 }, { 0.26, 0, 0.74, 0.22 }, { 0.26, 0.78, 0.74, 1 } }
local function preRender(dtReal)
  local e = current
  local a = e.blur
  if a <= 0 and not e.sleepy then return end
  if e.sleepy then blurPhase = blurPhase + dtReal a = math.min(rules.CAP.blur, a + 0.15 * math.max(0, math.sin(blurPhase * 0.7))) end      -- (eyelid dips at night: a slow pulse)
  if a <= 0 or reduceMotion() then return end
  local inj = rawget(_G, 'slrrInjury')
  local feel = inj and inj.getFeel and inj.getFeel()
  if type(feel) == 'table' and (tonumber(feel.amount) or 0) >= a then return end        -- (the injury blur is already stronger: one channel, the larger wins)
  if not (ColorF and scenetree and scenetree.ScreenBlurFX and scenetree.ScreenBlurFX.obj) then return end
  local o = scenetree.ScreenBlurFX.obj
  for _, r in ipairs(RECTS) do o:addFrameBlurRect(r[1], r[2], r[3], r[4], ColorF(1, 1, 1, a)) end
end
-- every frame: the blur of the moment, from the effects the tick keeps; an error is logged once and the blur stops until the next level
function M.onPreRender(dtReal)
  if preRenderFailed or current == NONE then return end
  local ok, err = pcall(preRender, dtReal)
  if not ok then preRenderFailed = true log('E', 'sl_needs', 'the blur is off after an error: ' .. tostring(err)) end
end

function M.onUpdate(dtReal)
  tick(dtReal)
  pushT = pushT + dtReal
  if pushT >= 1 then pushT = 0 pushCar(false) end
end

-- ---- sleep: Start the day is the night's sleep (04:00 to 07:00): a couch at a garage, the car seat anywhere else
function M.onStreetLegalPhase(phase)
  lastHour = nil
  local s = career()
  if not s or phase ~= 'day' then return end
  local n = needsOf(s)
  grace()
  local atGarage = nearPlace('garage', 40) ~= nil
  local where = rules.sleepPlace(atGarage, garageHas('bed'))
  local gained = rules.sleep(n, rules.NIGHT_GAP_HOURS, where)
  healInjury(rules.NIGHT_GAP_HOURS, where == 'bed')      -- (a night in your own bed is a long sleep: a limb that has nothing left to recover heals)
  if gained > 0 then toast(strings.t('needs.slept_1_2_rest_3', rules.NIGHT_GAP_HOURS, strings.t(where == 'bed' and 'needs.in_the_bed' or where == 'couch' and 'needs.on_the_couch' or 'needs.in_the_car'), math.floor(n.rest + 0.5))) end
  if atGarage and garageHas('fridge') and rules.fridge(n, s.day) then toast(strings.t('needs.fridge_used')) end      -- (breakfast from the fridge)
end
function M.onStreetLegalNewDay() lastHour = nil end

-- a nap at the garage: the Wait app's skip (1, 3 or 6 hours; refused in a race, on a job or with the police on you, by the career), then the rest
function M.nap(hours)
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  if not nearPlace('garage', 40) then return false, strings.t('needs.nap_at_garage') end
  local what = tostring(tonumber(hours) or 1)
  local ok, why = sl_career.skipTime(what)
  if not ok then return false, why end
  lastHour = nil
  rules.sleep(needsOf(s), tonumber(what) or 1, 'nap')
  healInjury(tonumber(what) or 1, false)
  local text = strings.t('needs.nap_1_rest_2', what, math.floor(s.needs.rest + 0.5))
  toast(text)
  extensions.hook('onStreetLegalChanged')
  return true, text
end

-- food and drink: at a fuel station, paid from the wallet
function M.eat(itemId)
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  if not nearPlace('gas', 40) then return false, strings.t('needs.eat_at_station') end
  local it = rules.ITEMS[itemId]
  local sold = false
  for _, id in ipairs(rules.ITEM_ORDER) do if id == itemId then sold = true end end
  if not it or not sold then return false, strings.t('needs.nothing_of_that') end
  if s.money < it.price then return false, strings.t('carcare.it_is_d_you_have', it.price, s.money) end
  local ok, price, text = rules.eat(needsOf(s), itemId)
  if ok and price > 0 then sl_career.addMoney(-price, strings.t('needs.food_and_drink')) end
  toast(text)
  extensions.hook('onStreetLegalChanged')
  return ok, text
end

-- ---- batch 2
-- the fridge of the garage (once a day): the phone's Health page may offer it
function M.useFridge()
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  if not garageHas('fridge') then return false, strings.t('needs.no_fridge') end
  if not nearPlace('garage', 40) then return false, strings.t('needs.nap_at_garage') end
  if not rules.fridge(needsOf(s), s.day) then return false, strings.t('needs.fridge_empty') end
  toast(strings.t('needs.fridge_used'))
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('needs.fridge_used')
end

-- the meal plan: on or off (the diner's menu offers it; the weekly ledger bills it)
function M.setMealPlan(on)
  local s = career()
  if not s then return false end
  needsOf(s).plan = on == true
  toast(on and strings.t('needs.plan_on', rules.MEAL_PLAN.weekly) or strings.t('needs.plan_off'))
  return true
end

-- the weekly ledger: the meal plan as a bill (nil without it), and what was bought as food and drink this week as an information line (the week starts again)
function M.weeklyBill()
  local s = career()
  local n = s and needsOf(s)
  local amount = n and rules.planBill(n) or 0
  if amount <= 0 then return nil end
  return { id = 'mealplan', label = strings.t('needs.ledger_plan'), amount = amount }
end
-- (called once per settlement, by sl_weekly when it closes the week: it takes the week's total, so the ledger preview does not call it)
function M.weeklyInfo()
  local s = career()
  local line = s and rules.takeWeek(needsOf(s))
  if not line then return nil end
  return { label = strings.t('needs.ledger_food'), amount = line.amount }
end

-- the diner (a shop kind): what it sells, and a sale: the food is eaten, then you sit for twenty minutes of the clock (refused in a race, on a job or with the police on you: you eat standing)
local function dinerStock()
  local s = career()
  if not s then return {}, strings.t('needs.no_career') end
  local n = needsOf(s)
  local out = {}
  for _, id in ipairs(rules.DINER_ORDER) do
    local it = rules.ITEMS[id]
    local specs = {}
    if it.food then specs[#specs + 1] = { label = strings.t('needs.meter_food'), text = '+' .. it.food, bar = it.food / 100 } end
    if it.water then specs[#specs + 1] = { label = strings.t('needs.meter_water'), text = '+' .. it.water, bar = it.water / 100 } end
    if it.rest then specs[#specs + 1] = { label = strings.t('needs.meter_rest'), text = '+' .. it.rest, bar = it.rest / 100 } end
    out[#out + 1] = { id = id, name = it.name, price = rules.price(id, n.plan), group = strings.t(it.food and 'needs.group_food' or 'needs.group_drink'), specs = specs }
  end
  out[#out + 1] = { id = 'mealplan', name = n.plan and strings.t('needs.plan_item_on') or strings.t('needs.plan_item_off', rules.MEAL_PLAN.weekly), price = 0, group = strings.t('needs.group_plan'),
    desc = strings.t('needs.plan_item_desc'), count = 1 }
  return out
end
function M.dinerStock()
  if not partOn() then return {}, strings.t('needs.off') end
  return dinerStock()
end
function M.dinerBuy(lines)
  local s = career()
  if not (s and partOn()) then return false end
  local n = needsOf(s)
  local ate = false
  for _, l in ipairs(lines or {}) do
    if l.id == 'mealplan' then
      M.setMealPlan(not n.plan)
    elseif rules.ITEMS[l.id] then
      for _ = 1, math.max(1, math.min(10, math.floor(tonumber(l.qty) or 1))) do rules.eatAt(n, l.id, n.plan) end      -- (the quantity comes from the screen: one to ten)
      ate = true
    end
  end
  if ate then
    local ok = sl_career.skipTime(tostring(rules.SIT_HOURS))      -- (refused: the food is still eaten and paid, you just do not sit; the note says so)
    lastHour = nil
    toast(ok and strings.t('needs.diner_ate', strings.t('needs.meter_food') .. ' ' .. math.floor(n.food + 0.5) .. ', ' .. strings.t('needs.meter_water') .. ' ' .. math.floor(n.water + 0.5)) or strings.t('needs.diner_no_time'))
  end
  extensions.hook('onStreetLegalChanged')
  return true
end

-- the motel (a shop kind): a room is a full sleep, away from home. The clock runs on (up to six hours, or the end of the phase); refused in a race, on a job or with the police on you
function M.motel()
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  if not partOn() then return false, strings.t('needs.off') end
  local ok, why = sl_career.skipTime(tostring(rules.MOTEL.hours))
  if not ok then return false, strings.t('needs.motel_no', tostring(why)) end
  lastHour = nil
  rules.motel(needsOf(s))
  healInjury(rules.MOTEL.hours, true)
  grace()
  toast(strings.t('needs.motel_slept', math.floor(s.needs.rest + 0.5)))
  extensions.hook('onStreetLegalChanged')
  return true
end

-- the shop kinds are registered with sl_shops when it is there (it may load after this part)
function provide()
  if provided or not (sl_shops and sl_shops.provide) then return end
  provided = true
  sl_shops.provide('diner', { stock = function() return M.dinerStock() end, buy = function(lines) return M.dinerBuy(lines) == true end })
  sl_shops.provide('motel', {
    services = function()
      if not partOn() then return {}, strings.t('needs.off') end
      return { { id = 'room', name = strings.t('shops.motel_room'), price = rules.MOTEL.price, desc = strings.t('shops.motel_room_desc') } }
    end,
    buy = function() return M.motel() == true end })
end

-- a hospital stay (sl_hospital may call this): fed, watered and rested to 70
function M.hospital()
  local s = career()
  if not s then return end
  local n = needsOf(s)
  for _, k in ipairs({ 'food', 'water', 'rest' }) do n[k] = math.max(n[k], 70) end
end

-- the tip bonus for a job well fed (0 otherwise): sl_jobs may add it to taxi and delivery tips
function M.tipBonus() local s = career() return s and rules.tipBonus(needsOf(s)) or 0 end

-- the phone's Health page
function M.summary()
  local s = career()
  if not s then return nil end
  local n = needsOf(s)
  return rules.summary(n, rules.effects(n, effectOpts()), { canEat = nearPlace('gas', 40) ~= nil, canNap = nearPlace('garage', 40) ~= nil, showMeters = opt('slNeedsShow', false) == true,
    plan = needsOf(s).plan, hasBed = garageHas('bed'), hasFridge = garageHas('fridge'), canFridge = garageHas('fridge') and needsOf(s).fridgeDay ~= s.day and nearPlace('garage', 40) ~= nil })
end

function M.status()
  local s = career()
  if not s then return 'no career' end
  local n = needsOf(s)
  local e = rules.effects(n, effectOpts())
  return string.format('food %.0f (%s) water %.0f (%s) rest %.0f (%s); blur %.2f lag %.0f ms tremor %.2f sleepy %s; well fed %s', n.food, rules.word('food', n.food), n.water, rules.word('water', n.water),
    n.rest, rules.word('rest', n.rest), e.blur, e.lag * 1000, e.tremor, tostring(e.sleepy), tostring(rules.wellFed(n)))
end
-- for the tester: set the meters
function M.debugSet(food, water, rest)
  local s = career()
  if not s then return 'no career' end
  local n = needsOf(s)
  n.food, n.water, n.rest = tonumber(food) or n.food, tonumber(water) or n.water, tonumber(rest) or n.rest
  pushCar(true)
  return M.status()
end

function M.onVehicleSwitched() pushT = 1 grace() end
function M.onVehicleResetted() grace() end
function M.onStreetLegalStarted() grace() provide() end
function M.onStreetLegalStopped() lastHour = nil pushCar(true) sent = { lag = 0, tremor = 0, vid = nil } end
function M.onClientEndMission() lastHour = nil sent = { lag = 0, tremor = 0, vid = nil } end

require('sl/core/features').gate('needs', M, nil, nil, { 'summary', 'eat', 'nap', 'tipBonus', 'hospital', 'useFridge', 'setMealPlan', 'weeklyBill', 'weeklyInfo', 'dinerStock', 'dinerBuy', 'motel' })      -- (the part off: nothing ticks, nothing shows, the car is let go by onStreetLegalStopped)

return M
