-- Street Legal Racing: the phone (extension name: sl_phone)
-- The Lua side of the phone in ui/modModules/slPhone: it hands the screen everything it shows
-- (contacts, messages, calls, the bank, the cab) and does what its buttons ask. All the
-- career's state lives in sl_career; this only translates.

local M = {}

local progression = require('sl/core/progression')
local roster = require('sl/core/roster')
local rngLib = require('sl/core/rng')

local BENNY = { id = 'benny', name = 'Benny (garage)', phone = '555-0100', system = true }

local sendTimer, wantSend = 0, true

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

----------------------------------------------------------------------------------------------
-- what the screen shows

local function snapshot()
  local s = career()
  if not s then return { active = false } end
  local title, nextRep, titleRep = progression.titleFor(s.rep)
  local h = sl_career.hour()
  local contacts = { { id = BENNY.id, name = BENNY.name, phone = BENNY.phone, system = true } }
  for _, r in ipairs(s.racers) do
    if s.known[r.id] then
      contacts[#contacts + 1] = {
        id = r.id, name = roster.displayName(r), short = r.name, phone = r.phone, tier = r.tier, class = r.class,
        nightOnly = r.nightOnly, wins = r.wins, losses = r.losses, pinkTonight = roster.pinkTonight(r, s.day, s.seed),
      }
    end
  end
  table.sort(contacts, function(a, b)
    if a.system ~= b.system then return a.system == true end
    return a.short and b.short and a.short < b.short or false
  end)
  local challenges = {}
  for _, c in ipairs(s.challenges) do
    local r
    for _, x in ipairs(s.racers) do if x.id == c.racer then r = x end end
    challenges[#challenges + 1] = { id = c.id, racer = c.racer, name = r and roster.displayName(r) or '?', stake = c.stake, bet = c.bet,
      raceName = c.raceName, nightOnly = c.nightOnly }
  end
  local placesOut = {}
  for id, p in pairs(sl_career.getPlaces() or {}) do placesOut[#placesOut + 1] = { id = id, name = p.name, kind = p.kind } end
  table.sort(placesOut, function(a, b) return a.name < b.name end)
  local ledger = {}
  for i = 1, math.min(30, #s.ledger) do ledger[i] = s.ledger[i] end
  local nextGarage = progression.nextGarage(s)
  return {
    active = true,
    money = s.money, rep = s.rep, title = title, nextRep = nextRep, titleRep = titleRep,
    day = s.day, hour = math.floor(h), minute = math.floor((h % 1) * 60), night = progression.isNight(h),
    garage = (progression.garages[s.garageLevel] or {}).name,
    nextGarage = nextGarage and { name = nextGarage.garage.name, canMove = nextGarage.canMove, why = nextGarage.why } or nil,
    roc = progression.rocOpen(s),
    contacts = contacts, threads = s.threads, unread = s.unread,
    challenges = challenges, ledger = ledger, places = placesOut,
    cars = #s.cars, stats = s.stats,
    fleet = sl_fleet and sl_fleet.list() or {},
    hud = sl_hud and sl_hud.getSettings and sl_hud.getSettings() or nil,
    rocRound = (s.roc or {}).round or 0, rocChampion = (s.roc or {}).champion == true,
    rocEntry = progression.ROC.entry,
    jobs = sl_jobs and sl_jobs.summary and sl_jobs.summary() or nil,
    tutorial = sl_tutorial and sl_tutorial.summary and sl_tutorial.summary() or nil,
    achievements = sl_achievements and sl_achievements.summary and sl_achievements.summary() or nil,
    bank = sl_bank and sl_bank.summary and sl_bank.summary() or nil,
  }
end

local function send() guihooks.trigger('slPhoneData', snapshot()) end

----------------------------------------------------------------------------------------------
-- calls

-- the first thing they say when they pick up
local GREETINGS = {
  easy = 'Yeah? Who is this?',
  trash = "Make it quick, I've got better things to do.",
  roller = 'Talk. Time is money.',
  careful = 'Hello?',
}

local function bennyAdvice(s)
  if #s.cars == 0 then return "You still haven't got a car. Get a cab to the junkyard and see what's on the lot. Don't buy the shiniest one, buy one you can fix." end
  local n = progression.nextGarage(s)
  if n and n.canMove then return 'You could move up to ' .. n.garage.name .. ' now. Bigger place, better crowd.' end
  if not progression.isNight(sl_career.hour()) then return 'Nothing much happens in the daytime. Tune the car, and race when it gets dark.' end
  return 'Call a few of the racers in your phone and set something up. Night races are where the name gets made.'
end

function M.call(id)
  local s = career()
  if not s then return end
  if id == BENNY.id then
    guihooks.trigger('slPhoneCall', { id = id, answered = true, greeting = 'Benny here.', text = bennyAdvice(s), options = {} })
    return
  end
  local racer
  for _, r in ipairs(s.racers) do if r.id == id and s.known[id] then racer = r end end
  if not racer then
    guihooks.trigger('slPhoneCall', { id = id, answered = false, text = 'The number you have dialled is not available.' })
    return
  end
  -- most pick up; the same hour gives the same answer
  local rng = rngLib.new(rngLib.hash(id .. ':' .. s.day .. ':' .. math.floor(sl_career.hour())))
  local answered = rng:chance(racer.nightOnly and progression.isNight(sl_career.hour()) and 0.95 or 0.8)
  s.calls[#s.calls + 1] = { racer = id, at = os.time(), outgoing = true, missed = not answered }
  while #s.calls > 30 do table.remove(s.calls, 1) end
  guihooks.trigger('slPhoneCall', {
    id = id, answered = answered,
    greeting = answered and (GREETINGS[racer.style] or GREETINGS.easy) or nil,
    text = not answered and 'No answer.' or nil,
    options = answered and (roster.pinkTonight(racer, s.day, s.seed) and { 'race', 'high', 'drag', 'pink' } or { 'race', 'high', 'drag' }) or {},
  })
end

-- on a call: race for money, high stakes or pink slips
function M.challenge(id, kind)
  if not career() then return end
  local answer = sl_career.challenge(id, kind)
  guihooks.trigger('slPhoneCallReply', { id = id, accept = answer.accept, text = answer.text, challenge = answer.challenge })
  wantSend = true
end

-- the same by text message: they write back after a moment
local ASK = {
  race = 'Up for a race?',
  high = 'Race me. High stakes.',
  pink = 'Pink slips. You and me.',
  drag = 'Drag race at the test track?',
}

function M.text(id, kind)
  if not career() or not ASK[kind] then return end
  sl_career.logMessage(id, ASK[kind])
  local answer = sl_career.challenge(id, kind)
  sl_career.sendText(id, answer.text, 3 + math.random() * 5)
  wantSend = true
end

----------------------------------------------------------------------------------------------
-- the rest of the buttons

function M.request() wantSend = true end
function M.markRead(thread) if career() then sl_career.markRead(thread) end end
function M.waypoint(id) if career() then sl_career.waypoint(id) end end
function M.cancel(challengeId) if career() then sl_career.cancelChallenge(challengeId) end end

local function answer(ok, text)
  guihooks.trigger('slPhoneToast', { text = text })
  wantSend = true
end

function M.tow(carId) if career() then answer(sl_fleet.tow(tonumber(carId))) end end
function M.release(carId) if career() then answer(sl_career.releaseCar(tonumber(carId))) end end
function M.useItem(carId, itemId) if career() and sl_carcare then answer(sl_carcare.useItem(tonumber(carId), tostring(itemId))) end end
function M.useCar(carId) if career() then answer(sl_fleet.setActive(tonumber(carId))) end end
function M.moveGarage() if career() then answer(sl_career.moveGarage()) end end
function M.enterRoc() if career() then answer(sl_streets.enterRoc()) end end
function M.borrow(amount) if career() and sl_bank then answer(sl_bank.borrow(tonumber(amount))) end end
function M.repay(amount) if career() and sl_bank then answer(sl_bank.repay(tonumber(amount))) end end
function M.insure(on) if career() and sl_bank then answer(sl_bank.insure(on == true or on == 'true')) end end
function M.takeJob(id) if career() and sl_jobs then answer(sl_jobs.take(tostring(id))) end end
function M.giveUpJob() if career() and sl_jobs then answer(sl_jobs.giveUp()) end end
function M.jobWay() if career() and sl_jobs then sl_jobs.showWay() end end

function M.taxi(placeId)
  if not career() then return end
  local ok, why = sl_career.taxi(placeId)
  guihooks.trigger('slPhoneToast', { text = ok and 'Your cab is on its way.' or why })
end

-- the K key (rebindable in Options > Controls)
function M.toggle()
  if not career() then return end
  guihooks.trigger('slPhoneToggle', {})
  wantSend = true
end

----------------------------------------------------------------------------------------------
-- hooks

M.onStreetLegalChanged = function() wantSend = true end
M.onStreetLegalStarted = function() wantSend = true end
M.onStreetLegalStopped = function() guihooks.trigger('slPhoneData', { active = false }) end

M.onStreetLegalText = function(thread, text)
  local s = career()
  if not s then return end
  local name = BENNY.name
  for _, r in ipairs(s.racers) do if r.id == thread then name = roster.displayName(r) end end
  guihooks.trigger('slPhoneNotify', { thread = thread, name = name, text = text })
end

M.onUpdate = function(dtReal)
  sendTimer = sendTimer + dtReal
  -- the clock on the screen moves too: a refresh every few seconds, sooner when something changed
  if (wantSend and sendTimer > 0.25) or (sendTimer > 5 and career()) then
    sendTimer, wantSend = 0, false
    send()
  end
end

return M
