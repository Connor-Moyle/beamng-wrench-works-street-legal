-- Street Legal: the rival story beats (extension name: sl_rivalbeats; the part Rival story beats, on by default: Mods > Street Legal > Parts of the game).
-- Rules in sl/core/rivalbeats (Graph docs/RIVAL_BEATS.md). Two arcs on what the rivals (sl_rivals), the crews (sl_crews) and the career's arranged
-- races already do: the HUNT (a pink-slip car you won off a rival: days later they want it back, an offer on the Rivals card for the car itself,
-- a sweetener when you make them wait, then they give up or get it back) and the beaten CREW'S THREE NIGHTS (a crew whose home district you took
-- calls three races on three nights; two wins and they respect you: a truce). The texts are in the rival's persona (core/rivals.text).
-- The save (additive, inside s.rivals): hunts = { [rivalId] = hunt }, crewSeries, truce = { [crewId] = day }, seriesDone = { [crewId] = true }.

local M = {}

local rules = require('sl/core/rivalbeats')
local rivalRules = require('sl/core/rivals')
local stateLib = require('sl/core/state')
local rngLib = require('sl/core/rng')
local strings = require('sl/core/strings')
local features = require('sl/core/features')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end
local function changed() extensions.hook('onStreetLegalChanged') end
local function store(s)
  s.rivals = type(s.rivals) == 'table' and s.rivals or {}
  local m = s.rivals
  m.hunts, m.truce, m.seriesDone = m.hunts or {}, m.truce or {}, m.seriesDone or {}
  return m
end
local function rivalOf(s, racerId) return rivalRules.byId(store(s).list, racerId) end
local function carById(s, id) for _, c in ipairs(s.cars or {}) do if c.id == id then return c end end return nil end
local function nameOfRacer(s, id) local r = stateLib.racer(s, id) return r and require('sl/core/roster').displayName(r) or tostring(id) end
-- a text in the racer's persona (a crew leader who is no rival speaks cool)
local function say(s, racerId, kind, delay, ...)
  local rival = rivalOf(s, racerId) or { persona = 'cool', id = racerId }
  local rng = rngLib.new(rngLib.hash(racerId .. ':' .. kind .. ':' .. tostring(s.day) .. ':' .. tostring(s.seed)))
  s.known[racerId] = true
  sl_career.sendText(racerId, rivalRules.text(rival, kind, rng, ...), delay or 4)
end

-- ---- the hunt
local pendingWin = nil      -- { racerId, at }: a pink win over a rival; the fleet's next car is the one
function M.onStreetLegalRaceResult(won, opponent, racerId, stake)
  local s = career()
  if not s or type(racerId) ~= 'string' then return end
  local m = store(s)
  -- the crew series' night
  local sr = m.crewSeries
  if sr and rules.seriesRacer(sr) == racerId and sr.sentDay then
    rules.seriesRecord(sr, won)
    M.finishSeries(s, m)
  end
  local h = m.hunts[racerId]
  if h and h.racing and stake == 'pink' then      -- the hunt's race
    h.racing, h.done = nil, true
    if won then
      local sweet = rules.sweetener(h)
      if sweet > 0 then sl_career.payOut(sweet, strings.t('rivalbeats.sweetener')) end
      stateLib.addRep(s, rules.HUNT_REP)
      say(s, racerId, 'hunt_won', 20)
    else
      say(s, racerId, 'hunt_lost', 20)
    end
    changed()
    return
  end
  if won and stake == 'pink' and rivalOf(s, racerId) and not h then pendingWin = { racerId = racerId, at = os.clock() } end
end
function M.onStreetLegalCarAdded(car)
  local s = career()
  if not s or not pendingWin or os.clock() - pendingWin.at > 60 then pendingWin = nil return end
  local m = store(s)
  car.wonFrom = pendingWin.racerId
  local rng = rngLib.new(rngLib.hash('hunt:' .. pendingWin.racerId .. ':' .. tostring(s.day) .. ':' .. tostring(s.seed)))
  m.hunts[pendingWin.racerId] = rules.newHunt(pendingWin.racerId, car.id, s.day, car.value, rng)
  pendingWin = nil
  changed()
end
local function huntOver(s, m, h, kind, meter)
  h.done, h.offered, h.racing = true, nil, nil
  if sl_rivals and sl_rivals.dropOffer then sl_rivals.dropOffer(h.rival) end
  local rival = rivalOf(s, h.rival)
  if rival and meter then rival.meter = math.max(rivalRules.METER[1], (rival.meter or 0) + meter) end
  say(s, h.rival, kind, 4)
end
-- the player sold the car: the rival hears of it
function M.onStreetLegalCarSold(car)
  local s = career()
  local m = s and store(s)
  local h = m and car and car.wonFrom and m.hunts[car.wonFrom]
  if h and not h.done and h.carId == car.id then huntOver(s, m, h, 'hunt_gone', rules.METER_SOLD) changed() end
end
-- the Rivals card's offer taken (sl_rivals.accept) or walked away from (sl_rivals.decline)
function M.huntAccepted(rivalId) local s = career() local h = s and store(s).hunts[rivalId] if h then h.offered, h.racing = nil, true end end
function M.huntLapsed(rivalId) local s = career() local h = s and store(s).hunts[rivalId] if h and not h.done then rules.lapse(h, s.day) end end
-- the accept guard: the hunted car has to be the one you sit in
function M.canAcceptHunt(rivalId, currentCarId)
  local s = career()
  local h = s and store(s).hunts[rivalId]
  if not h then return true end
  if rules.canAccept(h, currentCarId) then return true end
  local car = carById(s, h.carId)
  return false, strings.t('rivalbeats.wrong_car_1', car and car.name or '?')
end
local function huntTick(s, m, day)
  for rivalId, h in pairs(m.hunts) do
    if not h.done then
      local rival = rivalOf(s, rivalId)
      if not carById(s, h.carId) then huntOver(s, m, h, 'hunt_gone', nil)      -- (the car is gone another way: lost, scrapped)
      elseif not rival then h.done = true
      else
        if h.racing then rules.lapse(h, day) end                                  -- (the race did not happen)
        if h.offered and not (sl_rivals and sl_rivals.hasOffer and sl_rivals.hasOffer(rivalId)) then rules.lapse(h, day) end      -- (the offer lapsed on the card)
        local kind, stage = rules.huntDue(h, day)
        if kind == 'hunt_gone' then h.stage = stage huntOver(s, m, h, kind, rules.METER_GONE)
        elseif kind then
          h.stage, h.offered = stage, true
          local sweet = rules.sweetener(h)
          say(s, rivalId, kind, 4, sweet)
          if sl_rivals and sl_rivals.offerHunt then sl_rivals.offerHunt(rivalId, h.carId, sweet) end
        end
      end
    end
  end
end

-- ---- the beaten crew's three nights
local function crewState(s) return sl_crews and sl_crews.ensure and sl_crews.ensure(s) or nil end
function M.onStreetLegalDistrictTaken(districtId, crewId)
  local s = career()
  local m = s and store(s)
  local c = m and crewState(s)
  if not c or m.crewSeries or m.seriesDone[crewId] then return end
  local t = c.territory and c.territory[districtId]
  if not (t and t.home == crewId) then return end
  local members = {}
  for _, r in ipairs(s.racers or {}) do if c.member and c.member[r.id] == crewId then members[#members + 1] = r end end
  local leader = c.leader and c.leader[crewId]
  local racers = rules.seriesRacers(members, leader)
  if #racers < 2 then return end
  m.crewSeries = rules.newSeries(crewId, districtId, racers, s.day)
  m.seriesDone[crewId] = true
  say(s, racers[#racers], 'crewcall', 6, #racers, #racers)      -- (the lines: nights, racers)
  changed()
end
-- the night's race: an arranged race through the career (the racer answers as always; a refusal is tried again the next night)
local function sendNight(s, m, day)
  local sr = m.crewSeries
  if not sr or sr.sentDay == day then return end
  local racerId = rules.seriesRacer(sr)
  if not racerId then return end
  local racer = stateLib.racer(s, racerId)
  if not racer then rules.seriesRecord(sr, true) M.finishSeries(s, m) return end      -- (a racer gone from the roster: that night is yours)
  s.known[racerId] = true
  local answer = sl_career.challenge(racerId, 'race')
  if answer and answer.accept and answer.challenge then
    answer.challenge.bet = rules.seriesBet(racer)
    answer.challenge.nightOnly = true
    answer.challenge.series = sr.crew
    sr.sentDay = day
    toast(strings.t('rivalbeats.night_1_2_3', sr.night, nameOfRacer(s, racerId), answer.challenge.bet))
    changed()
  end
end
function M.finishSeries(s, m)
  local sr = m.crewSeries
  if not sr or not rules.seriesOver(sr) then return end
  local respect, wins = rules.seriesVerdict(sr)
  local leader = sr.racers[#sr.racers]
  m.crewSeries = nil
  if respect then
    m.truce[sr.crew] = rules.truceUntil(s.day)
    local c = crewState(s)
    if c then
      if c.angry then c.angry[sr.crew] = nil end
      for i = #(c.callouts or {}), 1, -1 do if c.callouts[i].crew == sr.crew then table.remove(c.callouts, i) end end
    end
    stateLib.addRep(s, rules.SERIES_REP)
    say(s, leader, 'crew_respect', 8, wins)
    toast(strings.t('rivalbeats.respect_1', rules.TRUCE_DAYS))
  else
    local rival = rivalOf(s, leader)
    if rival then rival.meter = math.max(rivalRules.METER[1], (rival.meter or 0) - 10) end
    say(s, leader, 'crew_mock', 8, wins)
  end
  changed()
end
-- for sl_crews: a crew under truce sends no call-outs and plans no raids
function M.truce(crewId) local s = career() return s ~= nil and rules.inTruce(store(s).truce, crewId, s.day) end

-- ---- the day
function M.onStreetLegalNewDay(day)
  local s = career()
  if not s then return end
  local m = store(s)
  local ok, err = pcall(function()
    huntTick(s, m, day)
    local sr = m.crewSeries
    if sr and rules.seriesMissed(sr, day) then rules.seriesRecord(sr, false) say(s, rules.seriesRacer({ racers = sr.racers, night = sr.night - 1 }) or sr.racers[#sr.racers], 'crew_mock', 6, 0) M.finishSeries(s, m) end
    if m.crewSeries then sendNight(s, m, day) end
  end)
  if not ok then log('E', 'sl_rivalbeats', tostring(err)) end
end

function M.summary()
  local s = career()
  if not s then return nil end
  local m = store(s)
  local hunts = {}
  for rivalId, h in pairs(m.hunts) do
    if not h.done then local car = carById(s, h.carId) hunts[#hunts + 1] = { rival = nameOfRacer(s, rivalId), car = car and car.name or '?', stage = h.stage, offered = h.offered == true, sweetener = rules.sweetener(h) } end
  end
  table.sort(hunts, function(a, b) return a.rival < b.rival end)
  local sr = m.crewSeries
  return { hunts = hunts, series = sr and { crew = sr.crew, night = sr.night, of = #sr.racers, wins = select(2, rules.seriesVerdict(sr)), racer = nameOfRacer(s, rules.seriesRacer(sr) or '') } or nil, truces = m.truce }
end
function M.status()
  local sum = M.summary()
  if not sum then return 'no career' end
  return string.format('hunts %d, series %s', #sum.hunts, sum.series and (sum.series.crew .. ' night ' .. sum.series.night) or 'none')
end
function M.onStreetLegalStopped() pendingWin = nil end

features.gate('rivalbeats', M, nil, nil, { 'summary', 'canAcceptHunt' })      -- (the part off: no beats; the card's guard answers nil = no guard)

return M
