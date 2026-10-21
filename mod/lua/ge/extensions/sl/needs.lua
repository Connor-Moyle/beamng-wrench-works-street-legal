-- Street Legal: hunger, thirst and sleep (extension name: sl_needs; the Needs part, off by default: Mods > Street Legal > Parts of the game > Needs).
-- Rules in sl/core/needs. The meters drain with the career clock while the player is awake, sleep comes with Start the day (the 04:00 to 07:00 gap)
-- or a nap at the garage, food and drink are bought at a fuel station (the Health page of the phone). Effects: a blur at the screen edges (the
-- same screen blur the Driver Injuries add-on uses; the larger of the two shows), a reaction lag and a tremor in the player's car (slNeeds,
-- vehicle side). The state is s.needs in the career save; a save without it starts full.

local M = {}

local rules = require('sl/core/needs')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function opt(key, default)
  if not (sl_options and sl_options.get) then return default end
  local v = sl_options.get(key)
  if v == nil then return default end
  return v
end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end

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

local function effectOpts()
  return { strength = (tonumber(opt('slNeedsStrength', 100)) or 100) / 100, blur = opt('slNeedsBlur', true) ~= false, lag = opt('slNeedsLag', true) ~= false,
           tremor = opt('slNeedsTremor', true) ~= false, night = isNight() }
end

-- ---- the clock: awake game hours pass
local lastHour, tickT = nil, 0
local function tick(dtReal)
  tickT = tickT + dtReal
  if tickT < 0.5 then return end
  tickT = 0
  local s = career()
  if not s then lastHour = nil return end
  local h = sl_career.hour()
  if lastHour == nil then lastHour = h return end
  local d = h - lastHour
  lastHour = h
  if d < 0 then d = d + 24 end
  if d <= 0 or d > 1 then return end         -- (a jump: a phase switch, a wait, a nap; those are handled where they happen)
  local n = needsOf(s)
  rules.tick(n, d, { busy = busy(), hot = hot(), nightHeat = nightHeat() }, tonumber(opt('slNeedsDrain', 1)) or 1)
  local text = rules.nudge(n)
  if text then
    if not n.toldOnce then n.toldOnce = true sl_career.sendText('benny', 'You look rough. Grab a bite and a drink at a fuel station, and sleep when the day starts.', 2) end
    toast(text)
  end
end

-- ---- the effects
local sent = { lag = 0, tremor = 0, vid = nil }
local function pushCar(force)
  local s = career()
  local v = getPlayerVehicle(0)
  local vid = v and v:getID()
  local e = s and rules.effects(needsOf(s), effectOpts()) or { lag = 0, tremor = 0 }
  if not v or v:getJBeamFilename() == 'unicycle' then e = { lag = 0, tremor = 0 } end
  local changed = force or vid ~= sent.vid or math.abs(e.lag - sent.lag) > 0.005 or math.abs(e.tremor - sent.tremor) > 0.02
  if not changed then return end
  if sent.vid and sent.vid ~= vid and (sent.lag > 0 or sent.tremor > 0) then
    local old = getObjectByID(sent.vid)
    if old then old:queueLuaCommand('if slNeeds then slNeeds.set(0, 0) end') end
  end
  sent.lag, sent.tremor, sent.vid = e.lag, e.tremor, vid
  if v and (e.lag > 0 or e.tremor > 0) then
    v:queueLuaCommand(string.format('if not slNeeds then extensions.load("slNeeds") end if slNeeds then slNeeds.set(%.3f, %.3f) end', e.lag, e.tremor))
  elseif v then
    v:queueLuaCommand('if slNeeds then slNeeds.set(0, 0) end')
  end
end
local pushT = 0

local function reduceMotion()
  if opt('slNeedsReduceMotion', false) == true then return true end
  local inj = rawget(_G, 'slrrInjury')
  return inj ~= nil and inj.getTune ~= nil and (inj.getTune('reduceMotion') or 0) ~= 0
end
local blurPhase = 0
function M.onPreRender(dtReal)
  local s = career()
  if not s then return end
  local e = rules.effects(needsOf(s), effectOpts())
  local a = e.blur
  if e.sleepy then blurPhase = blurPhase + dtReal a = math.min(rules.CAP.blur, a + 0.15 * math.max(0, math.sin(blurPhase * 0.7))) end      -- (eyelid dips at night: a slow pulse)
  if a <= 0 or reduceMotion() then return end
  local inj = rawget(_G, 'slrrInjury')
  local feel = inj and inj.getFeel and inj.getFeel()
  if type(feel) == 'table' and (tonumber(feel.amount) or 0) >= a then return end        -- (the injury blur is already stronger: one channel, the larger wins)
  if not (ColorF and scenetree and scenetree.ScreenBlurFX and scenetree.ScreenBlurFX.obj) then return end
  local o = scenetree.ScreenBlurFX.obj
  for _, r in ipairs({ { 0, 0, 0.26, 1 }, { 0.74, 0, 1, 1 }, { 0.26, 0, 0.74, 0.22 }, { 0.26, 0.78, 0.74, 1 } }) do
    pcall(o.addFrameBlurRect, o, r[1], r[2], r[3], r[4], ColorF(1, 1, 1, a))
  end
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
  local where = nearPlace('garage', 40) and 'couch' or 'car'
  local gained = rules.sleep(n, rules.NIGHT_GAP_HOURS, where)
  if gained > 0 then toast(string.format('You slept %d hours %s: rest %d.', rules.NIGHT_GAP_HOURS, where == 'couch' and 'on the garage couch' or 'in the car', math.floor(n.rest + 0.5))) end
end
function M.onStreetLegalNewDay() lastHour = nil end

-- a nap at the garage: the Wait app's skip (1, 3 or 6 hours; refused in a race, on a job or with the police on you, by the career), then the rest
function M.nap(hours)
  local s = career()
  if not s then return false, 'No career.' end
  if not nearPlace('garage', 40) then return false, 'You can only nap at a garage.' end
  local what = tostring(tonumber(hours) or 1)
  local ok, why = sl_career.skipTime(what)
  if not ok then return false, why end
  lastHour = nil
  local gained = rules.sleep(needsOf(s), tonumber(what) or 1, 'nap')
  toast(string.format('A %s hour nap: rest %d.', what, math.floor(s.needs.rest + 0.5)))
  extensions.hook('onStreetLegalChanged')
  return true
end

-- food and drink: at a fuel station, paid from the wallet
function M.eat(itemId)
  local s = career()
  if not s then return false, 'No career.' end
  if not nearPlace('gas', 40) then return false, 'Food and drink are sold at fuel stations.' end
  local it = rules.ITEMS[itemId]
  if not it then return false, 'Nothing of that here.' end
  if s.money < it.price then return false, string.format('It is $%d, you have $%d.', it.price, s.money) end
  local ok, price, text = rules.eat(needsOf(s), itemId)
  if ok and price > 0 then sl_career.addMoney(-price, 'Food and drink') end
  toast(text)
  extensions.hook('onStreetLegalChanged')
  return ok, text
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
  return rules.summary(n, rules.effects(n, effectOpts()), { canEat = nearPlace('gas', 40) ~= nil, canNap = nearPlace('garage', 40) ~= nil, showMeters = opt('slNeedsShow', false) == true })
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

function M.onVehicleSwitched() pushT = 1 end
function M.onStreetLegalStopped() lastHour = nil pushCar(true) sent = { lag = 0, tremor = 0, vid = nil } end
function M.onClientEndMission() lastHour = nil sent = { lag = 0, tremor = 0, vid = nil } end

require('sl/core/features').gate('needs', M, nil, nil, { 'summary', 'eat', 'nap', 'tipBonus', 'hospital' })      -- (the part off: nothing ticks, nothing shows, the car is let go by onStreetLegalStopped)

return M
