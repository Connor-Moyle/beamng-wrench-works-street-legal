-- Street Legal: the rules of a race series on a visited map (docs/DESIGN_CAREER_TRAVEL.md section 11). A series is a list of rounds; a runner runs a round and reports a place (race rounds) or a
-- time (rally stages). Here: the definitions, the points, the simulated opponents (the named field of the game's rally config for stage times, the career's racers for race places),
-- the standings, the prize and the loaner. Pure, no game calls: tested by tools/luatest.js.

local M = {}

local strings = require('sl/core/strings')
local rngLib = require('sl/core/rng')

M.RACE_POINTS = { 10, 7, 5, 3, 2, 1 }
M.RALLY_POINTS = { 25, 18, 15, 12, 10, 8, 6, 4, 2, 1 }
M.RACERS = 4                            -- a race round without a count: the player and three rivals

-- one entry per calendar series id (the id without the cycle). prize: shares of the calendar series' purse and reputation by final position
M.DEFS = {
  ['hirochi-cup'] = { id = 'hirochi-cup', map = 'hirochi_raceway', purse = 2000, scoring = 'place', points = M.RACE_POINTS, class = 'road',
    prize = { money = { 1.0, 0.55, 0.3, 0.15 }, rep = { 30, 20, 10, 5 } }, loaner = { model = 'covet', config = 'race' },
    rounds = {
      { runner = 'mission', mission = 'hirochi_raceway/aiRace/001-Short', title = 'Short circuit' },
      { runner = 'mission', mission = 'hirochi_raceway/aiRace/002-Medium', title = 'Medium circuit' },
      { runner = 'mission', mission = 'hirochi_raceway/aiRace/003-Long', title = 'Long circuit' },
      { runner = 'mission', mission = 'hirochi_raceway/aiRace/004-derby', title = 'Banger derby', finale = true },
    } },
  ['utah-rally'] = { id = 'utah-rally', map = 'utah', purse = 3000, scoring = 'time', points = M.RALLY_POINTS, class = 'rally',
    prize = { money = { 1.0, 0.55, 0.3, 0.15 }, rep = { 40, 25, 15, 8 } }, loaner = { model = 'sunburst2', config = 'rally_am_gravel' },
    rounds = {
      { runner = 'mission', mission = 'utah/rallyStage/ngrc26-ss1-river', title = 'SS1 River' },
      { runner = 'mission', mission = 'utah/rallyStage/ngrc26-ss2-canyon', title = 'SS2 Canyon' },
      { runner = 'mission', mission = 'utah/rallyStage/ngrc26-ss3-river-reverse', title = 'SS3 River reverse' },
      { runner = 'mission', mission = 'utah/rallyStage/ngrc26-ss4-canyon-reverse', title = 'SS4 Canyon reverse' },
    } },
  ['jv-offroad'] = { id = 'jv-offroad', map = 'johnson_valley', purse = 1200, scoring = 'place', points = M.RACE_POINTS, class = 'offroad',
    prize = { money = { 1.0, 0.55, 0.3, 0.15 }, rep = { 30, 20, 10, 5 } }, loaner = { model = 'pickup', config = 'd15_track_awd_M' },
    rounds = {
      { runner = 'mission', mission = 'johnson_valley/aiRace/005-outbackbangers', title = 'Outback bangers' },
      { runner = 'gridrace', track = 'johnson_valley/timeTrial/006-ShortcourseA', laps = 3, field = 'offroad', title = 'Short course A' },
      { runner = 'gridrace', track = 'johnson_valley/timeTrial/007-ShortcourseB', laps = 3, field = 'offroad', title = 'Short course B' },
      { runner = 'gridrace', track = 'johnson_valley/timeTrial/008-ShortcourseC', laps = 3, field = 'offroad', title = 'Short course C' },
      { runner = 'gridrace', track = 'johnson_valley/timeTrial/005-dunerace', laps = 2, field = 'offroad', title = 'Dune race' },
    } },
}

-- 'utah-rally:3' (a cycle of the series) -> the definition, the cycle
function M.def(seriesId)
  local base, cycle = tostring(seriesId):match('^(.-):(%d+)$')
  base = base or tostring(seriesId)
  return M.DEFS[base], tonumber(cycle)
end

function M.pointsFor(def, place)
  if not place or place < 1 then return 0 end
  return def.points[place] or 0
end

-- the named opponents of a stage: stage times from the competitors of the game's rally config (name, skill, consistency, risk), drawn deterministically. A competitor is as fast as the
-- stage's gold time at skill 1 and as slow as 10% past the bronze time at skill 0, with noise from the consistency, and may not finish (a retirement) at a rate from the risk.
-- cfg = the parsed aiCompetitorsConfig.json ({ competitors = { { name, skill, consistency, risk } } }); stage = { goldTime, bronzeTime }; returns { { name, time|nil } } (nil = retired)
function M.fieldTimes(cfg, stage, seed, round)
  local out = {}
  local fast, slow = (stage.goldTime or 150) * 0.97, (stage.bronzeTime or 260) * 1.1
  for i, c in ipairs(cfg and cfg.competitors or {}) do
    local rng = rngLib.new(rngLib.hash(tostring(seed) .. ':' .. tostring(round) .. ':' .. tostring(c.name) .. ':' .. i))
    local base = slow + (fast - slow) * (c.skill or 0.5)
    local noise = (rng:float() + rng:float() + rng:float() - 1.5) / 1.5          -- roughly -1..1, bell-shaped
    local sd = (stage.goldTime or 150) * (0.02 + 0.06 * (1 - (c.consistency or 0.5)))
    local t = math.max(fast, base + noise * sd * 2)
    if rng:float() < (c.risk or 0) * 0.04 then out[#out + 1] = { name = c.name }
    else out[#out + 1] = { name = c.name, time = t } end
  end
  return out
end

-- the player's place among a field for a time (a retirement of the player is dnf): 1 + the competitors who finished faster
function M.placeInField(field, time)
  if not time then return #field + 1 end
  local place = 1
  for _, f in ipairs(field) do if f.time and f.time < time then place = place + 1 end end
  return place
end

function M.newState(carId) return { entered = true, car = carId, results = {} } end

-- a round's result into the state. result = { place, time, dnf, racers, missed }. Returns the round's record { place, time, points, dnf, missed, racers }.
-- For time scoring `place` is worked out from the field of that stage (ctx.field(round) -> { { name, time } }).
function M.record(state, def, round, result, ctx)
  result = result or {}
  local rec = { place = result.place, time = result.time, dnf = result.dnf == true, missed = result.missed == true, racers = result.racers or M.RACERS }
  if def.scoring == 'time' and not rec.missed then
    local field = ctx and ctx.field and ctx.field(round) or {}
    rec.racers = #field + 1
    if rec.dnf then rec.place = nil else rec.place = M.placeInField(field, rec.time) end          -- (not `dnf and nil or ...`: that is always the right-hand side)
  end
  rec.points = (rec.dnf or rec.missed or not rec.place) and 0 or M.pointsFor(def, rec.place)
  state.results[round] = rec
  return rec
end

local function shuffled(list, rng)
  local out = {}
  for _, v in ipairs(list) do out[#out + 1] = v end
  for i = #out, 2, -1 do local j = rng:int(i) out[i], out[j] = out[j], out[i] end
  return out
end

-- the table after the rounds so far: { { pos, name, points, you = bool, time = seconds|nil } }, best first. Place-scored rounds give the AI places the player did not take, to rivals of
-- the roster in a seeded order; time-scored rounds use the stage fields. ctx = { roster = { names }, field = function(round), seed, you = name }; the player's total stage time is `time`.
function M.standings(state, def, ctx)
  local pts, total, order = {}, 0, {}
  local you = ctx.you or 'You'
  local function bump(name, p, t)
    if not pts[name] then pts[name] = { name = name, points = 0, time = t and 0 or nil, you = name == you } order[#order + 1] = name end
    pts[name].points = pts[name].points + p
    if t and pts[name].time then pts[name].time = pts[name].time + t end
  end
  bump(you, 0, def.scoring == 'time' and 0 or nil)
  local rounds = 0
  for r = 1, #def.rounds do
    local rec = state.results[r]
    if rec then
      rounds = rounds + 1
      bump(you, rec.points or 0, def.scoring == 'time' and rec.time or nil)
      if def.scoring == 'time' then
        local field = ctx.field and ctx.field(r) or {}
        for _, f in ipairs(field) do
          if f.time then
            local place = M.placeInField(field, f.time) + ((rec.time and not rec.dnf and rec.time < f.time) and 1 or 0)         -- (the player ahead of it takes a place)
            bump(f.name, M.pointsFor(def, place), f.time)
          else
            bump(f.name, 0, nil)
          end
        end
      else
        local rng = rngLib.new(rngLib.hash(tostring(ctx.seed) .. ':round:' .. r))
        local names = shuffled(ctx.roster or {}, rng)
        local n = math.max(2, rec.racers or M.RACERS)
        local k = 0
        for place = 1, n do
          if place ~= rec.place then
            k = k + 1
            local nm = names[k] or ('Racer ' .. k)
            bump(nm, M.pointsFor(def, place))
          end
        end
      end
    end
  end
  local list = {}
  for _, name in ipairs(order) do list[#list + 1] = pts[name] end
  table.sort(list, function(a, b)
    if a.points ~= b.points then return a.points > b.points end
    if a.time and b.time and a.time ~= b.time then return a.time < b.time end
    return a.name < b.name
  end)
  for i, e in ipairs(list) do e.pos = i end
  return list
end

-- the player's final position in the table
function M.position(list)
  for _, e in ipairs(list) do if e.you then return e.pos end end
end

function M.finished(state, def)
  for r = 1, #def.rounds do if not state.results[r] then return false end end
  return true
end

-- the prize for a final position: money (a share of the series' purse) and reputation; none past the places the table pays
function M.prize(def, position, purse)
  local share = def.prize.money[position] or 0
  return { money = math.floor((purse or 0) * share / 10 + 0.5) * 10, rep = def.prize.rep[position] or 0 }
end

-- the next round to run: the first without a result, or nil when all are in
function M.nextRound(state, def)
  for r = 1, #def.rounds do if not state.results[r] then return r end end
end

-- the loaner for a series: a stock record that exists only for the visit; deposit = list price / 20 (the player's money back when it returns undamaged)
function M.loaner(def, listPrice)
  local l = def.loaner
  return { model = l.model, config = l.config, pcPath = 'vehicles/' .. l.model .. '/' .. l.config .. '.pc', name = strings.t('series.loaner_name', l.model), loaner = true, value = 0, condition = 1, faults = {}, mileage = 0, deposit = math.floor((listPrice or 0) / 20 / 10 + 0.5) * 10 }
end

return M
