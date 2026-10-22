-- Street Legal: the home championship season (extension name: sl_season; the Championship season part: Mods > Street Legal > Parts of the game >
-- Championship season). Rules in sl/core/season. On the first day of a ledger week with no season running the next one is planned from the
-- calendar's weekend races (five races and a hill duel night, six rounds over three weeks); Benny texts; the player enters once on the phone;
-- the weekend races and the duel report through hooks (sl_calendar: onStreetLegalCalendarRace / onStreetLegalCalendarMissed; sl_hillduel:
-- onStreetLegalHillDuelResult); the end pays the prize by position, the champion gets the title achievement and a trophy entry.
-- The save keeps s.season = { n, titles, trophies, current }.

local M = {}

local rules = require('sl/core/season')
local strings = require('sl/core/strings')
local features = require('sl/core/features')
local stateLib = require('sl/core/state')
local weekly = require('sl/core/weekly')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end
local function store(s) s.season = rules.repair(s.season) return s.season end
local function ctx(s)
  local names = {}
  for _, r in ipairs(s.racers or {}) do names[#names + 1] = r.name end
  return { roster = names, seed = tostring(s.seed) .. ':' .. ((store(s).current or {}).id or ''), you = strings.t('series.you') }
end
local function weekendEvents(s)
  local out = {}
  if not (sl_calendar and sl_calendar.summary) then return out end
  local sum = sl_calendar.summary()
  for _, ev in ipairs(sum and sum.events or {}) do
    if ev.kind == 'weekend' and ev.id:find('^weekend:') then out[#out + 1] = { id = ev.id, day = ev.day, title = ev.title } end
  end
  return out
end

-- the end of a season: the prize by position, the title, the trophy
local function finish(s, season)
  local st = store(s)
  if season.done or st.current ~= season then return end        -- (once: a throw below never pays twice)
  season.done = true
  st.current = nil
  st.last = { id = season.id, day = s.day }
  if not season.entered then extensions.hook('onStreetLegalChanged') return end
  local list = rules.standings(season, ctx(s))
  local pos = rules.position(list) or #list
  local prize = rules.prize(pos)
  if prize.money > 0 then sl_career.payOut(prize.money, strings.t('season.prize')) end
  if prize.rep > 0 then stateLib.addRep(s, prize.rep) end
  if pos == 1 then
    st.titles = st.titles + 1
    st.trophies[#st.trophies + 1] = rules.trophy(season, s.day)
    pcall(function() s.trophies = require('sl/core/trophies').add(s.trophies, rules.TITLE, 'series', s.day, 1) end)      -- (the shared trophy shelf and the Street cred card)
    pcall(sl_career.sendText, 'benny', strings.t('season.benny_champion'), 2)
  end
  pcall(toast, strings.t('season.over_1_2_3', require('sl/core/gridrace').placeWord(pos), prize.money, prize.rep))
  local mine = 0
  for _, e in ipairs(list) do if e.you then mine = e.points end end
  pcall(extensions.hook, 'onStreetLegalSeasonFinished', { id = season.id, position = pos, points = mine, title = strings.t('season.title_1', season.n), money = prize.money, rep = prize.rep, table = list })      -- (9e's banner reads position, points, title)
  extensions.hook('onStreetLegalChanged')
end

local function plan(s)
  local st = store(s)
  if st.current then return end
  local season = rules.plan(st.n + 1, s.day, s.seed, weekendEvents(s))
  if not season then return end
  st.n = st.n + 1
  st.current = season
  sl_career.sendText('benny', strings.t('season.benny_opens_1', season.from), 2)
  extensions.hook('onStreetLegalChanged')
end

function M.onStreetLegalNewDay(day)
  local s = career()
  if not s then return end
  local st = store(s)
  local season = st.current
  if season then
    local missed = rules.sweep(season, day or s.day)
    if #missed > 0 and season.entered then toast(strings.t('season.missed_1', #missed)) end
    if rules.over(season) or (day or s.day) > season.to then finish(s, season) end
  elseif weekly.dayOfWeek(day or s.day) == 1 then
    plan(s)
  end
end
function M.onStreetLegalStarted() local s = career() if s and not store(s).current then plan(s) end end

-- the phone
function M.enter()
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  local season = store(s).current
  if not season then return false, strings.t('season.none_planned') end
  if season.entered then return false, strings.t('season.already_entered') end
  if not rules.canEnter(season, s.day) then return false, strings.t('season.too_late') end
  season.entered = true
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('season.entered_1', season.from)
end

-- the rounds report (each under a guard: a throw here must not reach the calendar's or the duel's own finish)
local function raceResult(eventId, place)
  local s = career()
  local season = s and store(s).current
  if not season or not season.entered then return end
  local i = rules.roundFor(season, 'race', eventId)
  if not i then return end
  local rec = rules.record(season, i, place, false)
  if rec then toast(strings.t('season.round_1_2_points', i, rec.points)) extensions.hook('onStreetLegalChanged') end
  if rules.over(season) then finish(s, season) end
end
local function raceMissed(eventId)
  local s = career()
  local season = s and store(s).current
  if not season or not season.entered then return end
  local i = rules.roundFor(season, 'race', eventId)
  if i and rules.record(season, i, nil, true) then toast(strings.t('season.round_1_missed', i)) extensions.hook('onStreetLegalChanged') end
end
local function duelResult(roadId, won)
  local s = career()
  local season = s and store(s).current
  if not season or not season.entered then return end
  local i = rules.roundFor(season, 'duel', s.day)
  if not i then return end
  local rec = rules.recordDuel(season, i, won == true)
  if rec then toast(strings.t('season.round_1_2_points', i, rec.points)) extensions.hook('onStreetLegalChanged') end
  if rules.over(season) then finish(s, season) end
end

local function guarded(fn, ...) local ok, err = pcall(fn, ...) if not ok then log('E', 'sl_season', tostring(err)) end end
function M.onStreetLegalCalendarRace(eventId, place) guarded(raceResult, eventId, place) end
function M.onStreetLegalCalendarMissed(eventId) guarded(raceMissed, eventId) end
function M.onStreetLegalHillDuelResult(roadId, won) guarded(duelResult, roadId, won) end

function M.summary()
  local s = career()
  if not s then return nil end
  local st = store(s)
  local season = st.current
  local out = { titles = st.titles, trophies = st.trophies, purse = rules.PURSE }
  if not season then return out end
  local list = rules.standings(season, ctx(s))
  local top = {}
  for _, e in ipairs(list) do if e.pos <= 8 or e.you then top[#top + 1] = { pos = e.pos, name = e.name, points = e.points, you = e.you } end end
  local nextI = rules.nextRound(season)
  local rounds = {}
  for i, r in ipairs(season.rounds) do
    local rec = season.results[i]
    rounds[i] = { kind = r.kind, title = r.title, day = r.day, eventId = r.eventId, done = rec ~= nil, missed = rec and rec.missed or false, place = rec and rec.place or nil, points = rec and rec.points or nil }
  end
  out.season = { id = season.id, n = season.n, from = season.from, to = season.to, entered = season.entered, canEnter = rules.canEnter(season, s.day), rounds = rounds,
    next = nextI and rounds[nextI] or nil, round = nextI, table = top, position = rules.position(list) }
  return out
end
function M.trophies() local s = career() return s and store(s).trophies or {} end
function M.status()
  local s = career()
  if not s then return 'no career' end
  local sum = M.summary()
  if not sum.season then return string.format('no season planned; titles %d', sum.titles) end
  local sea = sum.season
  return string.format('%s days %d-%d, entered %s, next round %s, position %s, titles %d', sea.id, sea.from, sea.to, tostring(sea.entered), tostring(sea.round), tostring(sea.position), sum.titles)
end
-- for the tester: the next round scored now (a place), or the season planned now
function M.debugRound(place)
  local s = career()
  local season = s and store(s).current
  if not season then plan(s) return M.status() end
  local i = rules.nextRound(season)
  if not i then return 'over' end
  if not season.entered then season.entered = true end
  rules.record(season, i, tonumber(place) or 1, false)
  if rules.over(season) then finish(s, season) end
  return M.status()
end

features.gate('season', M, nil, nil, { 'summary', 'enter', 'trophies' })      -- (the part off: nothing is planned, no app)

return M
