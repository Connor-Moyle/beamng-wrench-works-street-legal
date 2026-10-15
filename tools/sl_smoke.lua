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

-- every lot has a city lane to leave by (playtest: boxed-in display spots)
for _, kind in ipairs({ 'junkyard', 'dealer', 'scrapyard' }) do
  check('lot ' .. kind .. ': a clear city lane nearby to drive away from', function()
    local rs = require('sl/core/roadspot')
    for _, p in pairs(sl_career.getPlaces() or {}) do
      if p.kind == kind then
        local c = rs.pick(rs.candidates(map.getMap().nodes, p.pos, not map.getRoadRules().rightHandDrive), {})
        return c ~= nil and c.dist < 250, c and string.format('%.0f m from the lot', c.dist) or 'none within 400 m'
      end
    end
    return false, 'no ' .. kind .. ' on this map'
  end)
end

check('cab: a city lane near the garage door for a cab to pull up on', function()
  local rs = require('sl/core/roadspot')
  local pos = sl_fleet.forecourt(sl_career.getState(), 0)
  local c = pos and rs.pick(rs.candidates(map.getMap().nodes, pos, not map.getRoadRules().rightHandDrive, 300), {})
  return c ~= nil, c and string.format('%.0f m', c.dist) or 'none'
end)

check('tow: a city lane near the garage for the truck to drop the car at', function()
  local rs = require('sl/core/roadspot')
  local pos = sl_fleet.forecourt(sl_career.getState(), 0)
  local c = pos and rs.pick(rs.candidates(map.getMap().nodes, pos, not map.getRoadRules().rightHandDrive, 200), {})
  return c ~= nil and sl_tow ~= nil, c and string.format('%.0f m', c.dist) or 'none'
end)

check('slots: the career being played is one of the saved ones', function()
  local n, found = sl_career.getSlot(), false
  for _, c in ipairs(sl_career.listSlots()) do if c.slot == n then found = true end end
  return found, 'slot ' .. tostring(n)
end)

-- the settings group (X53): every setting has a value, the career's own go in the save, and Pay scales earnings
check('options: Street Legal settings read and write, per career where they change the balance', function()
  local before = sl_options.get('slEconomy')
  local defs = {}
  sl_options.onWrenchWorksSettingsDefs(defs)
  sl_options.onWrenchWorksSetting('slEconomy', 2)
  local inSave = (sl_career.getState().options or {}).slEconomy == 2
  local m0 = sl_career.getState().money
  sl_career.payOut(100, 'Smoke pay')
  local paid = sl_career.getState().money - m0
  sl_career.addMoney(-paid, 'Smoke pay back')
  sl_options.onWrenchWorksSetting('slEconomy', before)
  return #defs >= 7 and inSave and paid == 200, string.format('%d settings shown, x2 paid $%d', #defs, paid)
end)

-- rival crews (X21): districts on this map, every racer in a crew, a win on a crew's own streets takes control
check('crews: districts, crews, and a win on their streets takes control', function()
  local s = sl_career.getState()
  local c = sl_crews.ensure(s)
  local d = c.districts[1]
  local t = c.territory[d.id]
  local member
  for _, r in ipairs(s.racers) do if c.member[r.id] == t.owner and c.leader[t.owner] ~= r.id then member = r.id end end
  local before, owner = t.control, t.owner
  local saved = { owner = t.owner, control = t.control }
  local v = getPlayerVehicle(0)
  sl_crews.onStreetLegalRaceStarted()
  local here = sl_crews.districtAt(v and v:getPosition() or vec3(0, 0, 0))
  local ok = here ~= nil
  if here and here.id == d.id then
    sl_crews.onStreetLegalRaceResult(true, 'smoke', member, 'money')
    ok = c.territory[d.id].control < before
  end
  c.territory[d.id].owner, c.territory[d.id].control = saved.owner, saved.control
  local all = true
  for _, r in ipairs(s.racers) do if not c.member[r.id] then all = false end end
  return #c.districts >= 4 and all and ok, string.format('%d districts (%s), %s holds %s', #c.districts, c.sig, owner, d.name)
end)

-- hurt and killed at the wheel (sl_hospital, with Drivers & Pedestrians' slrrInjury)
check('death, normal career: the hospital, its bill, the car towed home as it is', function(job)
  local s = sl_career.getState()
  local v = getPlayerVehicle(0)
  local carId = v and sl_fleet.carOfVehicle(v:getID())
  local hc = sl_options.get('slHardcore')
  sl_options.set('slHardcore', false)
  local m0 = s.money
  sl_hospital.onSlrrDriverDied(v and v:getID() or -1, 'crash', { player = true })
  job.sleep(4)
  sl_options.set('slHardcore', hc)
  local me = getPlayerVehicle(0)
  local hosp
  for _, p in pairs(sl_career.getPlaces()) do if p.kind == 'hospital' then hosp = p end end
  local there = me and hosp and (me:getPosition() - hosp.pos):length() < 15
  local car = carId and sl_fleet.vehicleOf(carId)
  local atGarage = car and sl_fleet.atGarage(car:getPosition(), s)
  return me and me:getJBeamFilename() == 'unicycle' and s.money <= m0 and (not carId or atGarage), string.format('billed $%d, %s, car %s',
    m0 - s.money, hosp and (there and 'at the hospital' or 'NOT at the hospital') or 'no hospital place (home instead)', carId and (atGarage and 'at the garage' or 'not at the garage') or 'none')
end)
check('death, Hardcore: the career ends, with what it came to', function()
  local s = sl_career.getState()
  local hc, orig, ended, shown = sl_options.get('slHardcore'), sl_career.endCareer, false, nil
  sl_options.set('slHardcore', true)
  sl_career.endCareer = function() ended = true end           -- (not really: the smoke run goes on)
  local data = sl_hospital.gameOverData(s, 'crash')
  sl_hospital.onSlrrDriverDied(-1, 'crash', { player = true })
  sl_career.endCareer = orig
  sl_options.set('slHardcore', hc)
  local marked = s.ended ~= nil
  s.ended = nil
  guihooks.trigger('slGameOver', nil)
  return ended and marked and data.day and data.achievementsTotal, 'day ' .. tostring(data.day)
end)

check('crews: a crew that lost a district calls you out to a race there', function()
  local s = sl_career.getState()
  local c = sl_crews.ensure(s)
  local target, crewId
  for _, r in ipairs(sl_career.racesList()) do
    local d = r.start and not r.drag and sl_crews.districtAt(r.start)
    if d and not target then target, crewId = d.id, c.territory[d.id].owner end
  end
  if not target then return false, 'no race starts in any district' end
  if crewId == 'player' then crewId = 'southside' end
  c.callouts = { { crew = crewId, district = target, day = s.day } }
  sl_crews.onUpdate(6)
  local found
  for i = #s.challenges, 1, -1 do if s.challenges[i].callout == target then found = s.challenges[i] table.remove(s.challenges, i) end end
  c.callouts = {}
  return found ~= nil, found and (found.raceName .. ', ' .. found.stake) or 'no challenge'
end)

-- vehicle budget: nothing of ours left standing about (cabs, tow trucks, lot rows, patrols)
check('budget: no stray spawned vehicles', function()
  local keep = {}
  local p = getPlayerVehicle(0)
  if p then keep[p:getID()] = true end
  for _, id in ipairs(gameplay_traffic and gameplay_traffic.getTrafficList and gameplay_traffic.getTrafficList() or {}) do keep[id] = true end
  for _, c in ipairs(sl_career.getState().cars or {}) do local v = sl_fleet.vehicleOf(c.id) if v then keep[v:getID()] = true end end
  local extra = {}
  for _, v in ipairs(getAllVehicles()) do if not keep[v:getID()] then extra[#extra + 1] = v:getJBeamFilename() end end
  return #extra <= 3, #extra .. ' extra: ' .. table.concat(extra, ', ')
end)

-- no freeroam shortcuts in the career (playtest #2, #3)
check('lockdown: editor, vehicle menus, rewind and teleports blocked; the pause menu has its own mode', function()
  local af = core_input_actionFilter
  local blocked = true
  for _, a in ipairs({ 'editorToggle', 'vehicle_selector', 'parts_selector', 'recover_vehicle', 'dropPlayerAtCamera', 'loadHome', 'reload_vehicle', 'toggleRadialMenuSandbox' }) do
    if not af.isActionBlocked(a) then blocked = false end
  end
  local mode = require('ge/extensions/ui/router/services/navigationContext').getContext().mode
  return sl_lockdown.isLocked() and blocked and not af.isActionBlocked('reset_physics') and mode ~= 'freeroam', 'pause mode ' .. tostring(mode)
end)

-- the bank (X22)
check('bank: borrow within the limit, repay', function()
  local st = sl_career.getState()
  if st.bank and st.bank.loan then sl_bank.repay(st.bank.loan.owed) end
  local limit = sl_bank.summary().limit
  local tooMuch = sl_bank.borrow(limit + 100)
  local m0 = money()
  local ok = sl_bank.borrow(1000)
  local got = money() - m0
  local ok2 = sl_bank.repay(1000)
  return not tooMuch and ok and got == 1000 and ok2 and not (st.bank and st.bank.loan), string.format('limit $%d, borrowed and repaid $1000', limit)
end)
check('bank: insurance waits a day, then pays half over the deductible', function()
  local st = sl_career.getState()
  sl_bank.insure(false)
  local ok = sl_bank.insure(true)
  if not ok then return nil, 'could not afford the premium' end
  local m0 = money()
  sl_bank.onStreetLegalSpent(2200, 'Repaired the car')                -- the same day: nothing
  local sameDay = money() - m0
  st.bank.policy.from = st.day                                          -- (as if a day had passed)
  sl_bank.onStreetLegalSpent(2200, 'Repaired the car')
  local next = money() - m0 - sameDay
  sl_bank.insure(false)
  return sameDay == 0 and next == 1000, string.format('same day $%d, after $%d', sameDay, next)
end)

-- clubs and leagues (X20/X5)
check('club: a season, a night-league entry, a scored result', function(job)
  local sum = sl_clubs.summary()
  if not sum or not sum.today then return false, 'no season or no calendar' end
  if not sum.today.night or sum.today.night.done then return nil, 'no open night event today' end
  local ok, text = sl_clubs.enter('night')
  if not ok then return false, 'enter: ' .. tostring(text) end
  local st = sl_career.getState()
  local ch
  for _, x in ipairs(st.challenges) do if x.league then ch = x end end
  if not ch then return false, 'no league race arranged' end
  local p0 = st.club.standings.player or 0
  sl_clubs.onSlrrRaceFinished({ won = true, raceId = ch.race, missionId = ch.missionId, time = 60 })
  local gained = (st.club.standings.player or 0) - p0
  local again = sl_clubs.enter('night')
  return gained > 0 and not again, string.format('+%d points, #%d; a second entry refused', gained, sl_clubs.summary().standings[1] and (function() for _, r in ipairs(sl_clubs.summary().standings) do if r.you then return r.place end end end)() or 0)
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
