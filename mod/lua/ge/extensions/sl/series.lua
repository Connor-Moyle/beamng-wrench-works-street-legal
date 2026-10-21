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
  if prize.money > 0 then sl_career.payOut(prize.money, strings.t('series.prize_label', def.id)) end
  if prize.rep > 0 then stateLib.addRep(s, prize.rep) end
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
function M.onStreetLegalNewDay(day)
  local s = career()
  local v = s and sl_career.visit and sl_career.visit()
  if v and v.untilDay and (tonumber(day) or 0) > v.untilDay then sl_career.returnHome(M.closeVisit() > 0 and 'missed' or 'done') end
end

function M.onStreetLegalVisitEnded()
  M.running = nil
end
function M.onClientEndMission() M.running = nil end

require('sl/core/features').gate('travel', M, nil, nil, { 'enter', 'standings', 'nextRound', 'report', 'abort', 'startNext', 'hub' })

return M
