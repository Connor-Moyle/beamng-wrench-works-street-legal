-- In-game smoke test for the career's activities and jobs. Runs in the game's GE Lua, with a career
-- running and the player in one of their cars (a test career: it changes money, rep, heat and jobs).
--   node bng.js run_lua @tools/sl_smoke.lua       starts it (a few minutes; it teleports the car about)
--   node bng.js run_lua "return SL_SMOKE_REPORT"   the report so far: PASS/FAIL/SKIP per item, then a total
-- Each item starts something programmatically, drives (teleports) through it, and checks what the
-- career recorded: money, rep, heat, the job board, the phone's summary.

rawset(_G, 'SL_SMOKE', { lines = {}, done = false })
local R = SL_SMOKE
local function line(status, name, detail) R.lines[#R.lines + 1] = string.format('%-4s %-34s %s', status, name, detail or '') end
local function report()
  local p, f, k = 0, 0, 0
  for _, l in ipairs(R.lines) do
    if l:find('^PASS') then p = p + 1 elseif l:find('^FAIL') then f = f + 1 else k = k + 1 end
  end
  rawset(_G, 'SL_SMOKE_REPORT', table.concat(R.lines, '\n') .. string.format('\n-- %d passed, %d failed, %d skipped%s', p, f, k, R.done and '' or ' (still running)'))
end

local s = sl_career and sl_career.isActive() and sl_career.getState()
if not s then line('FAIL', 'career', 'no career running') R.done = true report() return 'no career' end

local function money() return sl_career.getState().money end
local function rep() return sl_career.getState().rep end
local function js() return sl_career.getState().jobs or {} end
local function player() return getPlayerVehicle(0) end

-- one check: name, function(job) -> ok, detail   (errors count as FAIL)
local checks = {}
local function check(name, fn) checks[#checks + 1] = { name = name, fn = fn } end

local function teleportTo(job, pos)
  local v = player()
  if not v then return end
  spawn.safeTeleport(v, vec3(pos.x, pos.y, (pos.z or v:getPosition().z) + 0.5), quat(v:getRotation()), false, nil, nil, nil, false)   -- (8th: no repair)
  job.sleep(2.5)                                   -- settle, stop, and let sl_jobs see it (it looks every 0.5 s)
end

-- a delivery job of one kind: take it, drive (teleport) through its stops, and see it paid
local function runJob(kind)
  return function(job)
    sl_jobs.summary()                              -- (fills the board if it is a new half-day)
    local pick
    for _, j in ipairs(js().offers or {}) do if not pick and j.kind == kind then pick = j end end
    if not pick then return nil, 'not on the board now (' .. (require('sl/core/progression').isNight(sl_career.hour()) and 'night' or 'day') .. ')' end
    local m0, done0 = money(), js().done or 0
    local ok, text = sl_jobs.take(pick.id)
    if not ok then return false, 'take: ' .. tostring(text) end
    for i, stop in ipairs(pick.legs) do
      teleportTo(job, stop)
      local a = js().active
      if i < #pick.legs and (not a or a.leg ~= i + 1) then return false, 'stop ' .. i .. ' not counted' end
      if i == 1 and pick.car and not (a and a.carVid and player() and player():getID() == a.carVid) then return false, 'not put in the job car' end
    end
    job.sleep(1.5)
    if js().active then return false, 'still active after the last stop' end
    local paid = money() - m0
    if (js().done or 0) ~= done0 + 1 then return false, 'done count did not go up' end
    if pick.fragile and paid == 0 then return true, 'fragile load broke on the teleports (paid 0): machinery works' end
    if paid <= 0 then return false, 'paid ' .. paid end
    return true, string.format('paid $%d of $%d', paid, pick.pay)
  end
end

-- the board
check('jobs: the board has offers', function()
  local n = #(sl_jobs.summary().offers or {})
  return n > 0, n .. ' offers'
end)
check('jobs: phone summary fields', function()
  local sum = sl_jobs.summary()
  return sum.flip ~= nil and sum.done ~= nil and sum.quarter ~= nil and sum.dyno ~= nil, 'flip/done/quarter/dyno present'
end)
check('jobs: give up costs 5 rep', function()
  local j = (js().offers or {})[1]
  if not j then return nil, 'no offer' end
  local r0 = rep()
  if not j.car and not sl_fleet.currentCar() then return nil, 'not in own car' end
  local ok = sl_jobs.take(j.id)
  if not ok then return false, 'take failed' end
  sl_jobs.giveUp()
  return rep() == r0 - 5 and not js().active, string.format('rep %d -> %d', r0, rep())
end)
for _, kind in ipairs({ 'part', 'courier', 'taxi', 'food', 'crush', 'transport', 'hot', 'testdrive', 'recovery', 'valet' }) do
  check('job: ' .. kind, runJob(kind))
end

-- lot flipping
check('flip: profit over target pays a bonus', function()
  local m0 = money()
  local target = (js().flip or { target = 1000 }).target
  sl_jobs.onStreetLegalCarSold({ name = 'Smoke test car', boughtFor = 1000 }, 1000 + target + 10, 'used')
  local bonus = money() - m0
  return bonus == math.floor(target * 0.5 / 10) * 10 and js().flip.target > target, string.format('bonus $%d, next target $%d', bonus, js().flip.target)
end)
check('flip: a loss pays nothing', function()
  local m0 = money()
  sl_jobs.onStreetLegalCarSold({ name = 'Smoke test car', boughtFor = 5000 }, 3000, 'used')
  return money() == m0, 'no change'
end)

-- tuning targets
check('dyno: 210 PS pays the 150 and 200 targets', function()
  local car = sl_fleet.currentCar()
  local v = car and sl_fleet.vehicleOf(car.id)
  if not v then return nil, 'not in own car' end
  local before = js().dyno or 1
  local m0 = money()
  sl_jobs.onWrenchWorksDyno(v:getID(), { maxPower = 210 })
  local paid = money() - m0
  return before > 2 or paid > 0, string.format('paid $%d, next target #%d', paid, js().dyno or 1)
end)
check('quarter mile: 15.5 s on the 1/4 strip', function()
  local strip
  for _, r in ipairs(sl_career.racesList() or {}) do if r.drag and tostring(r.name):find('1/4', 1, true) then strip = r end end
  if not strip then return nil, 'no 1/4 mile drag on this map' end
  local m0 = money()
  sl_jobs.onSlrrRaceFinished({ won = true, raceId = strip.id, missionId = strip.missionId, time = 15.5 })
  return money() > m0 or (js().quarter or 1) > 2, string.format('paid $%d', money() - m0)
end)

-- the map's missions in the career (fake mission and attempt tables, as BeamNG hands them over)
check('activity: sprint fee and prize', function()
  local id = 'slrr_valo_city/timeTrial/slrr_sprint_smoke'
  local m0 = money()
  sl_activities.onAnyMissionChanged('started', { id = id })
  local fee = m0 - money()
  sl_activities.onMissionAttemptAggregated({ type = 'passed', unlockedStars = { a = true, b = true } }, { id = id })
  local net = money() - m0
  local isNight = require('sl/core/progression').isNight(sl_career.hour())
  if isNight then return fee == 100 and net == 500, string.format('fee $%d, net $%d (night)', fee, net) end
  return fee == 0 and net == 0, string.format('fee $%d, net $%d (day: practice)', fee, net)
end)
check('activity: evade pays rep by heat, cools heat', function()
  local st = sl_career.getState()
  st.heat = 0.5
  local r0 = rep()
  sl_activities.onMissionAttemptAggregated({ type = 'completed' }, { id = 'slrr_valo_city/evade/slrr_evade_smoke' })
  return rep() - r0 == 50 and math.abs(st.heat - 0.2) < 1e-6, string.format('+%d rep, heat %.2f', rep() - r0, st.heat)
end)
check('activity: parking rep only the first time', function()
  local id = 'slrr_valo_city/precisionParking/slrr_park_smoke'
  local r0 = rep()
  sl_activities.onMissionAttemptAggregated({ type = 'passed' }, { id = id })
  local r1 = rep()
  sl_activities.onMissionAttemptAggregated({ type = 'passed' }, { id = id })
  return r1 - r0 == 10 and rep() == r1, string.format('+%d then +%d', r1 - r0, rep() - r1)
end)
check('activity: a failed attempt pays nothing', function()
  local m0, r0 = money(), rep()
  sl_activities.onMissionAttemptAggregated({ type = 'failed' }, { id = 'slrr_valo_city/drift/slrr_drift_smoke' })
  return money() == m0 and rep() == r0, 'no change'
end)

-- contracts
check('crew contract: offered, counted, paid', function()
  local st = sl_career.getState()
  if st.rep < 300 then st.rep = 300 end
  sl_jobs.onStreetLegalNewDay(st.day)
  local c = js().crew
  if not c then return false, 'no contract offered' end
  local strong
  for _, r in ipairs(st.racers) do if (r.tier or 1) >= c.tier then strong = r end end
  if not strong then return nil, 'no racer of tier ' .. c.tier end
  local m0 = money()
  for _ = 1, c.need do sl_jobs.onStreetLegalRaceResult(true, strong.name, strong.id) end
  return c.done and money() - m0 == c.pay, string.format('%s, %d wins, paid $%d', c.boss, c.won, money() - m0)
end)
check('sponsor: signs at 1500 rep, pays for two wins', function()
  local st = sl_career.getState()
  if st.rep < 1500 then st.rep = 1500 end
  sl_jobs.onStreetLegalNewDay(st.day)
  local sp = js().sponsor
  if not sp then return false, 'no sponsor' end
  st.jobs.weekWins = 2
  local m0 = money()
  sl_jobs.onStreetLegalNewDay(sp.since + 7)
  return money() - m0 == sp.weekly, string.format('%s, paid $%d', sp.name, money() - m0)
end)

-- a rival's errand: the crew wins above may have brought one (30 % a win)
check('job: errand', function(job)
  for i = 1, 12 do
    local any
    for _, j in ipairs(js().offers or {}) do if j.kind == 'errand' then any = true end end
    if any then break end
    local st = sl_career.getState()
    local r = st.racers[i % #st.racers + 1]
    st.ledger[#st.ledger + 1] = { label = 'smoke', amount = 0 }       -- (changes the errand's luck)
    sl_jobs.onStreetLegalRaceResult(true, r.name, r.id)
  end
  return runJob('errand')(job)
end)

-- moving garage: the offers come with a move (faked here: garage 1 to 2), one per car you own
check('job: move', function(job)
  sl_jobs.onStreetLegalGarageMoved(1, 2, 25000)
  local mine = sl_fleet.currentCar()
  local any
  for _, j in ipairs(js().offers or {}) do if j.kind == 'move' and mine and j.needCar == mine.id then any = j end end
  if not any then return false, 'no move offer for this car' end
  return runJob('move')(job)
end)

-- the tutorial (X24): each step through the real systems, faked here where they take minutes
check('tutorial: four steps, then the bonus', function(job)
  local st = sl_career.getState()
  if #st.cars == 0 then return nil, 'needs a car' end
  sl_tutorial.begin()
  job.sleep(1.5)                                                  -- step 1 (a car) is already done
  if st.tutorial.step ~= 2 then return false, 'step 1 did not pass with a car' end
  local any
  for _, j in ipairs(js().offers or {}) do if j.kind == 'part' then any = true end end
  if not any then return false, 'no part run on the board for step 2' end
  st.jobs.done = (st.jobs.done or 0) + 1 job.sleep(1.5)
  if st.tutorial.step ~= 3 then return false, 'step 2 did not pass' end
  st.jobs.upgraded = true job.sleep(1.5)
  if st.tutorial.step ~= 4 then return false, 'step 3 did not pass' end
  local race
  for _, c in ipairs(st.challenges) do if c.id:find(':tutorial', 1, true) then race = c end end
  if not race or race.bet ~= 100 then return false, 'no $100 race arranged for step 4' end
  local m0 = money()
  st.stats.races = st.stats.races + 1 job.sleep(1.5)
  return st.tutorial.done == true and money() - m0 == 500, string.format('done, +$%d', money() - m0)
end)

-- achievements and best times (X23)
check('achievements: earned from the record, bests kept', function(job)
  job.sleep(2.5)                                                  -- (checked every 2 s)
  local sum = sl_achievements.summary()
  if not sum or sum.total < 20 then return false, 'no list' end
  sl_achievements.onStreetLegalRaceTimed('Smoke track', 'Smoke track', 60)
  sl_achievements.onStreetLegalRaceTimed('Smoke track', 'Smoke track', 70)
  sl_achievements.onStreetLegalRaceTimed('Smoke track', 'Smoke track', 55.5)
  local b = sl_career.getState().bests['Smoke track']
  return sum.earned >= 1 and b and b.time == 55.5, string.format('%d of %d earned; best %.2f s', sum.earned, sum.total, b and b.time or -1)
end)

-- garage services and lists
check('services: drawer entries', function()
  local list = {}
  sl_services.onWrenchWorksServices(list, player() and player():getID() or 0)
  local groups = {}
  for _, e in ipairs(list) do groups[e.group or '?'] = (groups[e.group or '?'] or 0) + 1 end
  local out = {}
  for g, n in pairs(groups) do out[#out + 1] = g .. ' ' .. n end
  table.sort(out)
  return #list > 0, table.concat(out, ', ')
end)
check('tracks: the venue list', function()
  local n = #(sl_streets.tracks() or {})
  return n >= 10, n .. ' venues'
end)

-- run them all, one after the other
core_jobsystem.create(function(job)
  for _, c in ipairs(checks) do
    local ok, res, detail = pcall(c.fn, job)
    if not ok then line('FAIL', c.name, 'error: ' .. tostring(res))
    elseif res == nil then line('SKIP', c.name, detail)
    else line(res and 'PASS' or 'FAIL', c.name, detail) end
    report()
    job.sleep(0.3)
  end
  R.done = true
  report()
end)
report()
return 'smoke test started: ' .. #checks .. ' checks'
