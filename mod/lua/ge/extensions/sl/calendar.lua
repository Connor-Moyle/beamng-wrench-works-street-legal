-- Street Legal: the calendar (extension name: sl_calendar; the Calendar part: Mods > Street Legal > Parts of the game > Calendar).
-- Rules in sl/core/calendar. The schedule comes from the day, the seed and the reputation; the save keeps only s.calendar (entered, declined,
-- reminders, done). Weekend home races run on the dockyards layouts the map brings through the grid runner (sl_gridrace: the layout's barriers,
-- a standing grid of AI cars in the player's class, three laps); the monthly series are listed and answer "not yet" until the travel part (T3).
-- The phone (sl_phone) reads summary() and calls the actions.

local M = {}

local rules = require('sl/core/calendar')
local strings = require('sl/core/strings')
local features = require('sl/core/features')
local stateLib = require('sl/core/state')

local function opt(key, default) local v = sl_options and sl_options.get and tonumber((sl_options.get(key))) return v or default end
local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function store(s) s.calendar = rules.repair(s.calendar) return s.calendar end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end
local function homeOn() return sl_career.LEVEL == 'west_coast_usa' end         -- (the dockyards layouts are West Coast's)
local function opts() return { home = homeOn(), swap = sl_career.has('swapMeet'), extra = homeOn() and sl_invite and sl_invite.events and sl_invite.events() or nil } end

-- the settings (Mods menu): weekend fees, purses and laps, the trip fees. One function for the events and the phone's summary of them, so the card shows what is charged and paid.
local function scaleEvent(ev)
  local fee, purse, trip = opt('slCalFee', 100) / 100, opt('slCalPurse', 100) / 100, opt('slTravelFee', 100) / 100
  if ev.kind == 'weekend' and tostring(ev.id):sub(1, 8) == 'weekend:' then
    if ev.fee then ev.fee = math.floor(ev.fee * fee + 0.5) end
    if ev.reward then ev.reward = math.floor(ev.reward * purse + 0.5) end
    if ev.laps then ev.laps = opt('slCalLaps', rules.HOME_LAPS) end
  elseif ev.travel and ev.travel.needed then
    ev.travel = { needed = true, fee = math.floor((ev.travel.fee or 0) * trip + 0.5), hours = ev.travel.hours }
  end
end
local function schedule(s)
  local list = rules.schedule(s.day, sl_career.hour(), s.seed, s.rep, store(s), opts())
  require('sl/core/visit').FEE_PER_CAR = math.floor(200 * opt('slTravelFee', 100) / 100 + 0.5)
  for _, ev in ipairs(list) do scaleEvent(ev) end
  return list
end

-- the purse of an event with the season's few per cent (Seasons on); nothing for an event without a purse
local function seasonal(ev, reward)
  if not (reward and sl_seasons and sl_seasons.purse) then return reward end
  local f = sl_seasons.purse(tostring(ev.id):sub(1, 5) == 'swap:' and 'meet' or 'sprint') or 1          -- (the part off: the gate answers nothing)
  return math.floor(reward * f + 0.5)
end

-- ---- the phone
function M.summary()
  local s = career()
  if not s then return nil end
  local sum = rules.summary(s.day, sl_career.hour(), s.seed, s.rep, store(s), opts())
  for _, ev in ipairs(sum.events) do          -- (the card shows what will be charged and paid: the settings, then Seasons)
    if ev.status ~= 'done' then scaleEvent(ev) ev.reward = seasonal(ev, ev.reward) end
  end
  return sum
end

function M.enter(eventId, carIds)
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  local ev = rules.find(schedule(s), tostring(eventId))
  local st = store(s)
  local ok, text, fee = rules.enter(st, ev, s.money, s.day, sl_career.hour())
  if ok and (fee or 0) > 0 and not sl_career.addMoney(-fee, strings.t('calendar.entry_fee')) then      -- (the charge failed: the entry comes off the books)
    st.entered[ev.id], st.remind[ev.id] = nil, nil
    return false, strings.t('carcare.it_is_d_you_have', fee, s.money)
  end
  if ok then extensions.hook('onStreetLegalChanged') end
  return ok, text
end
function M.decline(eventId)
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  local ok, text = rules.decline(store(s), rules.find(schedule(s), tostring(eventId)))
  if ok then extensions.hook('onStreetLegalChanged') end
  return ok, text
end
function M.remind(eventId, on)
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  local ok, text = rules.remind(store(s), rules.find(schedule(s), tostring(eventId)), on == true)
  if ok then extensions.hook('onStreetLegalChanged') end
  return ok, text
end
function M.travel(eventId)
  if not career() then return false, strings.t('needs.no_career') end
  return false, strings.t('calendar.travel_not_yet')
end
-- one event with the rules' own fields (fee, laps, layer, travel, requires): sl_series reads it for the travel screen
function M.event(eventId)
  local s = career()
  return s and rules.find(schedule(s), tostring(eventId)) or nil
end

-- an invitational is over (sl_invite pays it): the event is done with the place
function M.complete(eventId, place, reward)
  local s = career()
  local ev = s and rules.find(schedule(s), tostring(eventId))
  if not ev then return end
  local st = store(s)
  st.done[ev.id] = { won = place == 1, place = place, day = ev.day, reward = reward or 0 }
  st.entered[ev.id] = nil
  extensions.hook('onStreetLegalChanged')
end

-- a series round is over (sl_series: it pays the series prize at the end, so the round's calendar event is only marked, never paid here)
function M.onStreetLegalRoundResult(r)
  local s = career()
  if not s or type(r) ~= 'table' or not r.seriesId or not r.round then return end
  local id = tostring(r.seriesId) .. ':r' .. tostring(r.round)
  local st = store(s)
  if st.done[id] then return end
  local ev = rules.find(schedule(s), id)
  if r.missed then st.done[id] = { won = nil, day = ev and ev.day or s.day, reward = 0 }      -- (nil won: the calendar shows it missed)
  else st.done[id] = { won = r.place == 1, place = r.place, day = ev and ev.day or s.day, reward = 0 } end
  st.entered[id] = nil
  extensions.hook('onStreetLegalChanged')
end

-- ---- the weekend race on a dockyards layout: the grid spot, read once per layer (the race itself is sl_gridrace's)
local tracks = {}
local function trackFor(ev)
  if not ev.layer then return nil end
  if tracks[ev.layer] == nil then
    local data = jsonReadFile('/levels/' .. sl_career.LEVEL .. '/gameplay/trackLayers/dockyards/' .. ev.layer .. '/race.race.json')
    tracks[ev.layer] = rules.trackFromLayer(data, ev.title, vec3) or false
  end
  return tracks[ev.layer] or nil
end
local function distToGrid(ev)
  local v = getPlayerVehicle(0)
  local t = v and trackFor(ev)
  if not t then return 1e9 end
  local g = t.start and t.start.pos or t.cps[1].pos
  return (v:getPosition() - g):length()
end
local running = nil
local function finished(eventId, res)
  local s = career()
  running = nil
  if not s or res.aborted then return end
  local ev = rules.find(schedule(s), eventId)
  if not ev then return end
  ev.reward = seasonal(ev, ev.reward)          -- (Seasons: a few per cent by season, as the card showed)
  local money, rep = rules.result(store(s), ev, res.place)
  if res.place == 1 then s.trophies = require('sl/core/trophies').add(s.trophies, ev.title, 'sprint', s.day, 1) end
  if money > 0 then sl_career.payOut(money, strings.t('calendar.purse_1', ev.title)) end
  if rep > 0 then stateLib.addRep(s, rep) end
  extensions.hook('onStreetLegalCalendarRace', eventId, res.place, res.grid)      -- (the season counts the round)
  toast(res.place and strings.t('calendar.you_finished_1_in_2_3_4_rep', require('sl/core/gridrace').placeWord(res.place), ev.title, money, rep) or strings.t('calendar.you_did_not_finish_1', ev.title))
  extensions.hook('onStreetLegalChanged')
end
local function startRace(ev)
  running = ev.id
  if ev.invite then          -- (the brand lends the car: sl_invite spawns it and runs the race)
    local ok = sl_invite and sl_invite.start(ev, function() running = nil end)
    if not ok then running = nil end
    return ok
  end
  local ok = sl_gridrace.start({ layer = ev.layer, name = ev.title, laps = ev.laps or rules.HOME_LAPS, purse = ev.reward }, function(res) finished(ev.id, res) end)
  if not ok then running = nil end
  return ok
end

local tickT, fails = 0, 0
local function tickBody()
  local s = career()
  if not s then running = nil return end
  local list = schedule(s)
  local st = store(s)
  for _, r in ipairs(rules.reminders(list, st, s.day, sl_career.hour())) do
    toast(strings.t('calendar.reminder_1_in_2_h', r.event.title, r.hoursLeft))
    extensions.hook('onStreetLegalCalendarReminder', r.event, r.hoursLeft)
  end
  for _, ev in ipairs(rules.missed(list, st, s.day, sl_career.hour())) do
    sl_career.sendText('benny', strings.t('calendar.you_missed_1', ev.title), 1)
    extensions.hook('onStreetLegalCalendarMissed', ev.id)
    extensions.hook('onStreetLegalChanged')
  end
  if running or not (sl_gridrace and sl_gridrace.start) or sl_gridrace.running() then return end
  if sl_career.freeToStart and sl_career.freeToStart() then return end          -- (a race, a job, a chase, a fade, a scene, an open lot: the next tick tries again)
  local ev = rules.due(list, st, s.day, sl_career.hour(), distToGrid)
  if ev then startRace(ev) end
end
-- every 2 s, under a guard: an error is logged and five in a row switch the calendar's tick off for the session (the app and the actions stay)
local function tick(dtReal)
  tickT = tickT + dtReal
  if tickT < 2 or fails >= 5 then return end
  tickT = 0
  local ok, err = pcall(tickBody)
  if ok then fails = 0 else
    fails = fails + 1
    log('E', 'sl_calendar', tostring(err) .. (fails >= 5 and ' (the calendar tick is off for this session)' or ''))
  end
end
function M.onUpdate(dtReal) tick(dtReal) end

function M.onStreetLegalNewDay(day) local s = career() if s then rules.sweep(store(s), day or s.day) end end
function M.onStreetLegalStopped() running = nil tracks = {} require('sl/core/visit').FEE_PER_CAR = 200 end          -- (the trip fee setting does not outlive the career)
function M.onClientEndMission() running = nil tracks = {} end

function M.status()
  local s = career()
  if not s then return 'no career' end
  local out = {}
  for _, ev in ipairs(schedule(s)) do out[#out + 1] = string.format('%s day %d %s %s', ev.id, ev.day, rules.clock(ev.hour), ev.status) end
  return #out > 0 and table.concat(out, '\n') or 'nothing planned'
end
-- for the tester: enter the next open home race for free and start it now, wherever the car is (the grid runner moves it to the grid)
function M.debugDue()
  local s = career()
  if not s then return 'no career' end
  for _, ev in ipairs(schedule(s)) do
    if ev.kind == 'weekend' and ev.layer and ev.status == 'open' then
      store(s).entered[ev.id] = { day = ev.day, hour = ev.hour, fee = 0 }
      return startRace(ev) and ('started ' .. ev.id) or 'not started'
    end
  end
  return 'no open home race in the window'
end

features.gate('calendar', M, nil, nil, { 'summary', 'enter', 'decline', 'remind', 'travel', 'event' })      -- (the part off: nothing ticks, no app, the actions answer nothing)

return M
