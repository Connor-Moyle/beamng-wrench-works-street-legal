-- Street Legal: the calendar (extension name: sl_calendar; the Calendar part: Mods > Street Legal > Parts of the game > Calendar).
-- Rules in sl/core/calendar. The schedule comes from the day, the seed and the reputation; the save keeps only s.calendar (entered, declined,
-- reminders, done). Weekend home races run on the dockyards layouts the map brings, through sl_streets' circuit race against a rival; the
-- monthly series are listed and answer "not yet" until the travel part (T3). The phone (sl_phone) reads summary() and calls the actions.

local M = {}

local rules = require('sl/core/calendar')
local strings = require('sl/core/strings')
local features = require('sl/core/features')
local stateLib = require('sl/core/state')
local rngLib = require('sl/core/rng')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function store(s) s.calendar = rules.repair(s.calendar) return s.calendar end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end
local function homeOn() return sl_career.LEVEL == 'west_coast_usa' end         -- (the dockyards layouts are West Coast's)
local function opts() return { home = homeOn(), swap = sl_career.has('swapMeet') } end

local function schedule(s) return rules.schedule(s.day, sl_career.hour(), s.seed, s.rep, store(s), opts()) end

-- ---- the phone
function M.summary()
  local s = career()
  if not s then return nil end
  return rules.summary(s.day, sl_career.hour(), s.seed, s.rep, store(s), opts())
end

function M.enter(eventId, carIds)
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  local ev = rules.find(schedule(s), tostring(eventId))
  local ok, text, fee = rules.enter(store(s), ev, s.money, s.day, sl_career.hour())
  if ok and (fee or 0) > 0 then sl_career.addMoney(-fee, strings.t('calendar.entry_fee')) end
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

-- ---- the weekend race on a dockyards layout: the layout's circuit, read once per layer
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
-- a rival of the player's standing, who is not out on the road
local function rival(s, ev)
  local rng = rngLib.new(rngLib.hash(ev.id .. ':' .. s.seed))
  local fit = {}
  for _, r in ipairs(s.racers or {}) do if math.abs((r.rep or 0) - s.rep) < 1500 + s.rep * 0.5 then fit[#fit + 1] = r end end
  if #fit == 0 then fit = s.racers or {} end
  return fit[rng:int(#fit)]
end

local tickT, running = 0, nil
local function tick(dtReal)
  tickT = tickT + dtReal
  if tickT < 2 then return end
  tickT = 0
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
    extensions.hook('onStreetLegalChanged')
  end
  if running or not (sl_streets and sl_streets.startCalendarRace) or sl_streets.isRacing() then return end
  local ev = rules.due(list, st, s.day, sl_career.hour(), distToGrid)
  if not ev then return end
  local track = trackFor(ev)
  local r = rival(s, ev)
  if not track or not r then return end
  running = ev.id
  local ok = sl_streets.startCalendarRace(ev.id, track, ev.laps or rules.HOME_LAPS, r.id)
  if not ok then running = nil end
end
function M.onUpdate(dtReal) tick(dtReal) end

-- the race is over (sl_streets): the purse on a win
function M.onStreetLegalCalendarRace(eventId, won)
  local s = career()
  if not s or running ~= eventId then running = nil return end
  running = nil
  local ev = rules.find(schedule(s), eventId)
  local reward = rules.result(store(s), ev, won)
  if reward > 0 then sl_career.payOut(reward, strings.t('calendar.purse_1', ev.title)) end
  toast(won and strings.t('calendar.you_won_1_purse_2', ev.title, reward) or strings.t('calendar.you_lost_1', ev.title))
  extensions.hook('onStreetLegalChanged')
end

function M.onStreetLegalNewDay(day) local s = career() if s then rules.sweep(store(s), day or s.day) end end
function M.onStreetLegalStopped() running = nil tracks = {} end
function M.onClientEndMission() running = nil tracks = {} end

function M.status()
  local s = career()
  if not s then return 'no career' end
  local out = {}
  for _, ev in ipairs(schedule(s)) do out[#out + 1] = string.format('%s day %d %s %s', ev.id, ev.day, rules.clock(ev.hour), ev.status) end
  return #out > 0 and table.concat(out, '\n') or 'nothing planned'
end
-- for the tester: enter the next home race and jump the clock to it is done by hand (sl_career.skipTime); this moves the race to now
function M.debugDue()
  local s = career()
  if not s then return 'no career' end
  for _, ev in ipairs(schedule(s)) do
    if ev.kind == 'weekend' and ev.layer and ev.status == 'open' then
      local st = store(s)
      st.entered[ev.id] = { day = ev.day, hour = ev.hour, fee = 0 }
      ev.status = 'entered'
      local track = trackFor(ev)
      local r = rival(s, ev)
      if not track or not r then return 'no track or rival' end
      running = ev.id
      return sl_streets.startCalendarRace(ev.id, track, ev.laps or rules.HOME_LAPS, r.id) and ('started ' .. ev.id) or 'not started'
    end
  end
  return 'no open home race in the window'
end

features.gate('calendar', M, nil, nil, { 'summary', 'enter', 'decline', 'remind', 'travel' })      -- (the part off: nothing ticks, no app, the actions answer nothing)

return M
