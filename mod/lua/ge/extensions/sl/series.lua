-- Street Legal: the series of a visit (extension name: sl_series; docs/DESIGN_CAREER_TRAVEL.md section 11). Rules in sl/core/series. A round is run by a runner (the game's mission manager for
-- 'mission' rounds, sl_<runner> for the others) and reported here once; this module keeps the points, the standings, the prize and tells the screens. Saved in the career as
-- s.series[seriesId] = { entered, car, results = { [round] = { place, time, points, dnf, missed, racers } }, finished, paid }.

local M = {}

local strings = require('sl/core/strings')
local rules = require('sl/core/series')
local stateLib = require('sl/core/state')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) if ui_message then ui_message(text, 5, 'streetLegal') end end
local function store(s) s.series = s.series or {} return s.series end
local function mapName() return sl_career.mapName and sl_career.mapName() or '' end

-- the config of the game's rally field, and a stage's times, read once
local fieldCfg
local function rallyConfig()
  if fieldCfg == nil then
    local ok, d = pcall(jsonReadFile, '/gameplay/rally/aiCompetitorsConfig.json')
    fieldCfg = ok and type(d) == 'table' and d or false
  end
  return fieldCfg or nil
end
local stageCache = {}
local function stageInfo(missionId)
  if stageCache[missionId] == nil then
    local ok, d = pcall(jsonReadFile, '/gameplay/missions/' .. missionId .. '/info.json')
    local m = ok and type(d) == 'table' and d.missionTypeData or nil
    stageCache[missionId] = m and { goldTime = m.goldTime, bronzeTime = m.bronzeTime } or false
  end
  return stageCache[missionId] or { goldTime = 160, bronzeTime = 260 }
end

local function rosterNames(s)
  local out = {}
  for _, r in ipairs(s.racers or {}) do if r.name then out[#out + 1] = r.name end end
  return out
end

local function ctxFor(s, def, seriesId)
  return { roster = rosterNames(s), seed = tostring(s.seed) .. ':' .. seriesId, you = strings.t('series.you'),
    field = def.scoring == 'time' and function(round)
      local d = def.rounds[round]
      return rules.fieldTimes(rallyConfig(), stageInfo(d and d.mission or ''), tostring(s.seed) .. ':' .. seriesId, round)
    end or nil }
end

-- the series of the visit now, with its definition and state: seriesId, def, state; nil when not on a visit with a series
local function current()
  local s = career()
  local v = s and sl_career.visit and sl_career.visit()
  if not (v and v.series) then return nil end
  local def = rules.def(v.series)
  local st = def and store(s)[v.series]
  if not (def and st) then return nil end
  return v.series, def, st, s, v
end

-- a loaner: a car of the career that exists for the visit only (rules.loaner: the series' car, value 0, a deposit of a twentieth of its list price). Returns the car record.
function M.addLoaner(seriesId, listPrice)
  local s = career()
  local def = rules.def(seriesId)
  if not (s and def) then return nil end
  local rec = rules.loaner(def, listPrice)
  if (s.money or 0) < rec.deposit then return nil end
  if rec.deposit > 0 then stateLib.addMoney(s, -rec.deposit, strings.t('series.loaner_name', rec.model), os.time()) end
  rec.visit, rec.out = true, true
  return stateLib.addCar(s, rec)
end

-- the visit is over: a loaner that comes back undamaged gives its deposit back
function M.onStreetLegalVisitEnded(visit, how, loaners)
  M.running = nil
  local s = career()
  if not s then return end
  for _, car in ipairs(loaners or {}) do
    if (car.deposit or 0) > 0 then
      local dented = type(car.damage) == 'table' and type(car.damage.nodes) == 'table' and next(car.damage.nodes) ~= nil
      if dented then toast(strings.t('series.loaner_damaged'))
      else sl_career.addMoney(car.deposit, strings.t('series.loaner_back', car.deposit)) toast(strings.t('series.loaner_back', car.deposit)) end
    end
  end
end

-- the trip planned from a calendar event (the phone's pick-cars screen): { eventId, name, place, fee, perCar, hours, max, refuse, cars = { { id, name, fits, why, report } }, loaner = { name, deposit } }
local function eventOf(eventId)
  local ev = sl_calendar and sl_calendar.event and sl_calendar.event(eventId)
  local def = ev and ev.series and rules.def(ev.series.id)
  return ev, def
end
local function reportLine(car)
  local ok, r = pcall(function() return sl_carcare and sl_carcare.reportOf and sl_carcare.reportOf(car) end)
  if ok and type(r) == 'table' then return string.format('%s, %d fault(s)', tostring(r.label or ''), #(r.faults or {})) end
  return nil
end
function M.options(eventId)
  local s = career()
  if not s then return nil, strings.t('bank.no_career_running') end
  local ev, def = eventOf(tostring(eventId))
  if not (ev and def) then return nil, strings.t('series.no_event') end
  local visits = require('sl/core/visit')
  local out = { eventId = ev.id, name = ev.title, place = ev.place, fee = (ev.travel and ev.travel.fee) or 0, perCar = visits.FEE_PER_CAR, hours = (ev.travel and ev.travel.hours) or visits.TRAVEL_HOURS,
    max = visits.MAX_CARS, cars = {} }
  local anyFits = false
  for _, car in ipairs(s.cars or {}) do
    if not car.loaner then
      local fits, why = rules.fits(def, car)
      if car.impounded then fits, why = false, strings.t('visit.car_impounded', car.name or '?') end
      anyFits = anyFits or fits
      out.cars[#out.cars + 1] = { id = car.id, name = car.name, fits = fits == true, why = why, report = reportLine(car) }
    end
  end
  local prices = rules.loaner(def, 0)
  out.loaner = (not anyFits) and { name = prices.name, deposit = rules.loaner(def, M.listPrice and M.listPrice(def) or 20000).deposit } or nil
  if ev.series.round ~= 1 then out.refuse = strings.t('series.enter_at_start')
  elseif store(s)[ev.series.id] then out.refuse = strings.t('series.already_entered')
  elseif sl_career.visit and sl_career.visit() then out.refuse = strings.t('visit.already') end
  return out
end

-- the trip confirmed: the cars chosen (or a loaner), the entry paid (entry plus a fee a car), the series entered, the career sent to the map. Returns ok, text.
function M.confirm(eventId, carIds, useLoaner)
  local s = career()
  if not s then return false, strings.t('bank.no_career_running') end
  local ev, def = eventOf(tostring(eventId))
  if not (ev and def) then return false, strings.t('series.no_event') end
  local o = M.options(ev.id)
  if o.refuse then return false, o.refuse end
  local ids, loanerId = {}, nil
  for _, id in ipairs(carIds or {}) do ids[#ids + 1] = id end
  if useLoaner then
    if not o.loaner then return false, strings.t('series.no_loaner_needed') end
    local car = M.addLoaner(ev.series.id, M.listPrice and M.listPrice(def) or 20000)
    if not car then return false, strings.t('visit.cannot_afford', o.loaner.deposit) end
    loanerId = car.id
    ids = { car.id }
  end
  if #ids == 0 then return false, strings.t('series.bring_a_car') end
  M.enter(ev.series.id, ids[1])
  local ok, text = sl_career.depart({ level = def.map, cars = ids, event = ev.id, series = ev.series.id, entry = o.fee, rounds = #def.rounds,
    firstDay = ev.day - (ev.series.round - 1), untilDay = ev.day - (ev.series.round - 1) + #def.rounds, fits = function(car) return rules.fits(def, car) end })
  if not ok then
    store(s)[ev.series.id] = nil                                            -- (nothing was entered)
    if loanerId then
      local st = require('sl/core/state')
      local car = st.removeCar(s, loanerId)
      if car and (car.deposit or 0) > 0 then st.addMoney(s, car.deposit, strings.t('series.loaner_back', car.deposit), os.time()) end
    end
  end
  return ok, text
end

-- the entry: a series state for the cycle, with the car that goes (called when the trip is confirmed)
function M.enter(seriesId, carId)
  local s = career()
  if not s or not rules.def(seriesId) then return false end
  local st = store(s)
  if not st[seriesId] then st[seriesId] = rules.newState(carId) end
  return true
end

function M.standings(seriesId)
  local cur, def, st, s = current()
  if seriesId and seriesId ~= cur then return nil end
  if not cur then return nil end
  return rules.standings(st, def, ctxFor(s, def, cur))
end

function M.nextRound(seriesId)
  local cur, def, st = current()
  if not cur or (seriesId and seriesId ~= cur) then return nil end
  return rules.nextRound(st, def)
end

-- a round is over (the runner or the mission hook): points, the table, the hooks, and at the end of the last round the prize
local function finishRound(rec, round)
  local cur, def, st, s, v = current()
  if not cur then return end
  local list = rules.standings(st, def, ctxFor(s, def, cur))
  local mine
  for _, e in ipairs(list) do if e.you then mine = e end end
  extensions.hook('onStreetLegalRoundResult', { series = def.id, seriesId = cur, name = strings.t('series.title_' .. def.id), round = round, rounds = #def.rounds, place = rec.place, points = rec.points, prize = 0, you = true, dnf = rec.dnf, missed = rec.missed })
  if not rules.finished(st, def) or st.paid then return end
  st.finished, st.paid = true, true
  local purse = def.purse or 0
  local prize = rules.prize(def, mine and mine.pos or 99, purse)
  if sl_seasons and sl_seasons.purse then prize.money = math.floor(prize.money * (sl_seasons.purse(def.class == 'rally' and 'rally' or 'series') or 1) + 0.5) end          -- (Seasons)
  if prize.money > 0 then sl_career.payOut(prize.money, strings.t('series.prize_label', def.id)) end
  if prize.rep > 0 then stateLib.addRep(s, prize.rep) end
  if mine and mine.pos == 1 then s.trophies = require('sl/core/trophies').add(s.trophies, strings.t('series.title_' .. def.id), 'series', s.day, 1) end
  local podium = {}
  for i = 1, math.min(3, #list) do podium[i] = { name = list[i].name, points = list[i].points, you = list[i].you } end
  toast(strings.t('series.finished', mine and mine.pos or '-', prize.money))
  extensions.hook('onStreetLegalSeriesFinished', { series = def.id, seriesId = cur, name = strings.t('series.title_' .. def.id), pos = mine and mine.pos, position = mine and mine.pos, points = mine and mine.points or 0, prize = prize.money, champion = mine ~= nil and mine.pos == 1, podium = podium })
  extensions.hook('onStreetLegalChanged')
end

-- a runner (or the mission hook below) reports a finished round: result = { place, time, dnf, racers }
function M.report(seriesId, round, result)
  local cur, def, st, s = current()
  if not cur or cur ~= seriesId or not def.rounds[round] or st.results[round] then return false end
  local rec = rules.record(st, def, round, result, ctxFor(s, def, cur))
  M.running = nil
  toast(rec.dnf and strings.t('series.round_dnf', round) or strings.t('series.round_done', round, rec.place or '-', rec.points))
  finishRound(rec, round)
  return true
end

-- a round called off (the player left, a restart): it counts as missed, the series goes on
function M.abort(seriesId, round, why)
  local cur, def, st, s = current()
  if not cur or cur ~= seriesId or not def.rounds[round] or st.results[round] then return false end
  local rec = rules.record(st, def, round, { missed = true }, ctxFor(s, def, cur))
  M.running = nil
  toast(strings.t('series.round_missed', round))
  finishRound(rec, round)
  return true
end

-- the visit is ending (the player goes home, or the days ran out): every round without a result counts as missed, and the series is closed (the last one pays the prize)
function M.closeVisit()
  local cur, def, st = current()
  if not cur then return 0 end
  local n = 0
  for r = 1, #def.rounds do
    if not st.results[r] then M.abort(cur, r, 'closed') n = n + 1 end
  end
  return n
end

-- the day a round may be run: round 1 on the visit's first day, one a day after that
local function roundDay(v, round) return (v.firstDay or v.fromDay or 0) + round - 1 end

-- can the next round start now, and if not, why
local function canStart()
  local cur, def, st, s, v = current()
  if not cur then return false, strings.t('series.no_series') end
  if M.running then return false, strings.t('series.round_running') end
  local r = rules.nextRound(st, def)
  if not r then return false, strings.t('series.all_done') end
  if (s.day or 0) < roundDay(v, r) then return false, strings.t('series.round_on_day', r, roundDay(v, r)) end
  local busy = sl_career.isBusy and sl_career.isBusy()
  if busy then return false, strings.t('visit.not_now') end
  return true
end

-- start the next round with the runner its definition names
function M.startNext()
  local ok, why = canStart()
  if not ok then return false, why end
  local cur, def, st, s, v = current()
  local r = rules.nextRound(st, def)
  local round = def.rounds[r]
  local car = sl_fleet and sl_fleet.currentCar and sl_fleet.currentCar()
  local veh = getPlayerVehicle and getPlayerVehicle(0)
  if not (car and car.visit and veh) then return false, strings.t('series.get_in_car') end
  if round.runner == 'mission' then
    local mission = gameplay_missions_missions and gameplay_missions_missions.getMissionById(round.mission)
    if not (mission and gameplay_missions_missionManager) then return false, strings.t('series.mission_missing') end
    local setup = mission.setupModules and mission.setupModules.vehicles
    local idx = (setup and setup.vehicles and #setup.vehicles or 0) + 1                  -- (the option after the mission's own cars is the player's)
    M.running = { series = cur, round = r, mission = round.mission }
    gameplay_missions_missionManager.startWithFade(mission, { setupModuleVehicles = idx })
    return true, strings.t('series.round_starting', r, round.title)
  end
  local runner = rawget(_G, 'sl_' .. tostring(round.runner))
  if not (runner and runner.startRound) then return false, strings.t('series.runner_missing') end
  M.running = { series = cur, round = r }
  local okr, why2 = runner.startRound({ series = cur, round = r, def = round, vehId = veh:getID(), seed = tostring(s.seed), rivals = 3 })
  if not okr then M.running = nil return false, why2 or strings.t('series.runner_missing') end
  return true, strings.t('series.round_starting', r, round.title)
end

-- the game's missions: a finished attempt of the mission we started is the round's result
function M.onMissionAttemptAggregated(attempt, mission)
  local run = M.running
  if not (run and run.mission and mission and mission.id == run.mission and type(attempt) == 'table') then return end
  local dnf = attempt.type == 'failed' or (attempt.time == nil and attempt.place == nil)
  M.report(run.series, run.round, { place = attempt.place, time = tonumber(attempt.time), dnf = dnf, racers = nil })
end

-- the mission ended without a result (abandoned, the player left): the round is missed
function M.onAnyMissionChanged(state, mission)
  local run = M.running
  if state == 'stopped' and run and run.mission and mission and mission.id == run.mission then
    core_jobsystem.create(function(job)
      job.sleep(1)                                     -- (the aggregated attempt comes first when there is one)
      if M.running and M.running.mission == run.mission then M.abort(run.series, run.round, 'stopped') end
    end)
  end
end

-- for the screens (9e's hub): the event, the standings, the schedule, the cars at the paddock, whether the next round can start
function M.hub()
  local cur, def, st, s, v = current()
  if not cur then return nil end
  local list = rules.standings(st, def, ctxFor(s, def, cur))
  local top = {}
  for _, e in ipairs(list) do if e.pos <= 8 or e.you then top[#top + 1] = { pos = e.pos, name = e.name, points = e.points, you = e.you, time = e.time } end end
  local r = rules.nextRound(st, def)
  local schedule = {}
  for i, round in ipairs(def.rounds) do
    local rec = st.results[i]
    schedule[i] = { day = roundDay(v, i), hour = 10, title = round.title, status = rec and (rec.missed and 'missed' or 'done') or (i == r and 'next' or 'later') }
  end
  local ok, why = canStart()
  local cars = {}
  for _, id in ipairs(v.cars or {}) do
    for _, c in ipairs(s.cars) do if c.id == id then cars[#cars + 1] = { id = c.id, name = c.name } end end
  end
  return { event = { id = v.event, title = strings.t('series.title_' .. def.id), mapName = mapName(), series = def.id, round = r or #def.rounds, rounds = #def.rounds,
      rules = { strings.t('series.rules_' .. def.scoring) }, startHour = 10, status = st.finished and 'done' or (M.running and 'running' or 'ready') },
    standings = top, schedule = schedule, cars = cars, canStart = ok == true, startWhy = not ok and why or nil, leaveNote = strings.t('series.leave_note') }
end

-- a new day on a visit whose days have run out: the career goes home by itself (the rounds left count as missed)
local leaving
function M.onStreetLegalNewDay(day)
  local s = career()
  local v = s and sl_career.visit and sl_career.visit()
  if not (v and v.untilDay and (tonumber(day) or 0) > v.untilDay) or leaving then return end
  leaving = true
  -- not from inside the hook: returnHome stops the career and loads the home map while the other listeners of this hook are still being called; a moment later, retried while the clock is busy
  core_jobsystem.create(function(job)
    job.sleep(1)
    local rounds = M.closeVisit()                      -- (once: the rounds are closed as missed by the first pass, a second pass would find none and say 'done')
    for _ = 1, 8 do
      if sl_career.returnHome(rounds > 0 and 'missed' or 'done') then break end
      job.sleep(1)
    end
    leaving = false
  end)
end

function M.onClientEndMission() M.running = nil end

require('sl/core/features').gate('travel', M, nil, nil, { 'enter', 'standings', 'nextRound', 'report', 'abort', 'startNext', 'hub' })

return M
