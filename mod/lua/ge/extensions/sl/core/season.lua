-- Street Legal: the home championship season's rules (CAREER_EXPANSION #5). Pure, no game calls: tested by tools/luatest.js.
-- One season at a time: the next five weekend dockyards races on the calendar plus a hill duel round on the Saturday night of its second
-- week, six rounds over three ledger weeks. Points by place as the series pay them (the duel: won = first, lost = second); a missed round is
-- nought points, never money. The table, the position and the prize come from sl/core/series (the same rules the travel series use).

local M = {}

local series = require('sl/core/series')
local weekly = require('sl/core/weekly')
local strings = require('sl/core/strings')

M.RACES = 5                       -- weekend races in a season
M.DUEL_WEEK = 2                   -- the duel round: the Saturday night of this week of the season
M.DUEL_HOUR = 21
M.PURSE = 2000
M.PRIZE = { money = { 1.0, 0.55, 0.3, 0.15 }, rep = { 30, 20, 10, 5 } }
M.TITLE = 'Belasco season champion'

function M.newStore() return { n = 0, titles = 0, trophies = {}, current = nil } end
function M.repair(st)
  st = type(st) == 'table' and st or M.newStore()
  st.n, st.titles, st.trophies = st.n or 0, st.titles or 0, type(st.trophies) == 'table' and st.trophies or {}
  return st
end

-- the definition the series rules read: place-scored, six rounds, the season's prize
function M.def(season)
  local rounds = {}
  for i = 1, #season.rounds do rounds[i] = { title = season.rounds[i].title } end
  return { id = season.id, scoring = 'place', points = series.RACE_POINTS, rounds = rounds, prize = M.PRIZE }
end

-- the plan from the calendar's weekend events ({ id, day, title }, any order), from `day`: the next RACES races and the duel night; nil with too few
function M.plan(n, day, seed, weekendEvents)
  local list = {}
  for _, ev in ipairs(weekendEvents or {}) do if ev.day and ev.day >= day then list[#list + 1] = ev end end
  table.sort(list, function(a, b) return a.day < b.day end)
  if #list < M.RACES then return nil end
  local rounds = {}
  for i = 1, M.RACES do rounds[#rounds + 1] = { kind = 'race', eventId = list[i].id, day = list[i].day, title = list[i].title } end
  -- the duel: the Saturday (day 6 of the week) of the season's second week, counted from the first race's week
  local firstWeek = weekly.week(rounds[1].day)
  local duelDay = (firstWeek + M.DUEL_WEEK - 2) * weekly.DAYS + 6
  rounds[#rounds + 1] = { kind = 'duel', day = duelDay, hour = M.DUEL_HOUR, title = strings.t('season.hill_duel_night') }
  table.sort(rounds, function(a, b) if a.day ~= b.day then return a.day < b.day end return a.kind < b.kind end)
  return { id = 'season:' .. n, n = n, from = rounds[1].day, to = rounds[#rounds].day, rounds = rounds, results = {}, entered = false, done = false }
end

-- entry is open until the first round's day has passed
function M.canEnter(season, day) return season ~= nil and not season.entered and not season.done and day <= season.rounds[1].day end

-- which round an event (a race by its id, the duel by its day) is
function M.roundFor(season, kind, key)
  for i, r in ipairs(season.rounds or {}) do
    if r.kind == kind and ((kind == 'race' and r.eventId == key) or (kind == 'duel' and r.day == key)) then return i, r end
  end
  return nil
end

-- a result: place (1.. or nil for a DNF), or missed; nothing after the first record of a round
function M.record(season, round, place, missed)
  if not season or not round or season.results[round] then return nil end
  return series.record(season, M.def(season), round, { place = place, dnf = place == nil and not missed, missed = missed == true, racers = series.RACERS })
end
function M.recordDuel(season, round, won) return M.record(season, round, won and 1 or 2, false) end

-- the rounds whose day has passed with no result: missed
function M.sweep(season, day)
  local out = {}
  for i, r in ipairs(season.rounds or {}) do
    if not season.results[i] and r.day < day then M.record(season, i, nil, true) out[#out + 1] = i end
  end
  return out
end

function M.standings(season, ctx) return series.standings(season, M.def(season), ctx) end
function M.position(list) return series.position(list) end
function M.nextRound(season) return series.nextRound(season, M.def(season)) end
function M.over(season) return series.finished(season, M.def(season)) end
function M.prize(position) return series.prize({ prize = M.PRIZE }, position, M.PURSE) end
function M.trophy(season, day) return { title = M.TITLE, season = season.id, day = day } end

return M
