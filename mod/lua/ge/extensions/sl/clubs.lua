-- Wrench Works: Street Legal: clubs and leagues (extension name: sl_clubs; X20 + X5; docs: DESIGN4_clubs.md)
-- Rules in sl/core/clubs. The player's club is their garage's; a season is a week with a night event (a
-- head-to-head against the club racer just ahead of you in the standings) and a day event (the drag strip
-- for now; the oval and the valley venues once the map's races take a field) every day, through the map's
-- own races. Missed events cost only their points; the club's other racers race them in simulation.

local M = {}

local clubs = require('sl/core/clubs')
local rngLib = require('sl/core/rng')
local roster = require('sl/core/roster')
local stateLib = require('sl/core/state')
local activityRules = require('sl/core/activityrules')

-- nothing runs, is sent or is shown on a map that cannot host it (progression.MAPS has); the code and the save stay
local function career() return sl_career and sl_career.isActive() and sl_career.has('clubs') and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end

----------------------------------------------------------------------------------------------
-- a car's class: measured in the car's own Lua (peak power, mass), kept on the car, re-measured only when it
-- leaves the garage (so it can't change mid-race), and locked into the season at its start

function M.onCarMeasured(vid, ps, kg)
  local s = career()
  local carId = s and sl_fleet and sl_fleet.carOfVehicle and sl_fleet.carOfVehicle(vid)
  if not carId then return end
  for _, car in ipairs(s.cars) do
    if car.id == carId then car.class, car.ps, car.kg = clubs.classOf(ps, kg), math.floor(ps or 0), math.floor(kg or 0) end
  end
  extensions.hook('onStreetLegalChanged')
end

local MEASURE = [[
local ps, kg = 0, 0
for _, d in pairs(powertrain.getDevices() or {}) do
  local ok, td = pcall(function() return d.getTorqueData and d:getTorqueData() or d.torqueData end)
  if ok and type(td) == 'table' and (td.maxPower or 0) > ps then ps = td.maxPower end
end
for _, n in pairs(v.data.nodes or {}) do kg = kg + (n.nodeWeight or 0) end
obj:queueGameEngineLua(string.format('if sl_clubs then sl_clubs.onCarMeasured(%d, %f, %f) end', obj:getId(), ps, kg))
]]
local function measure(veh) if veh then veh:queueLuaCommand(MEASURE) end end

-- a car that has not been measured yet is, the first time it is out
function M.onUpdate(dt)
  local s = career()
  if not s then return end
  M._t = (M._t or 0) + dt
  if M._t < 3 then return end
  M._t = 0
  local car = sl_fleet and sl_fleet.currentCar()
  if car and not car.class then measure(sl_fleet.vehicleOf(car.id)) end
  M.ensureSeason(s)
end

function M.onWrenchWorksDriveOut(vid) if sl_fleet and sl_fleet.carOfVehicle(vid) then measure(getObjectByID(vid)) end end

----------------------------------------------------------------------------------------------
-- the season

local function clubState(s) return s.club end
local function members(s) return clubs.members(s.racers, s.garageLevel or 1) end

function M.ensureSeason(s)
  local c = s.club
  if c and c.club == (s.garageLevel or 1) and s.day < c.start + clubs.SEASON_DAYS then return c end
  if c and c.club == (s.garageLevel or 1) then M.endSeason(s) end
  local car = sl_fleet and sl_fleet.currentCar()
  local rng = rngLib.new(rngLib.hash('season:' .. s.day .. ':' .. tostring(s.seed)))
  s.club = { club = s.garageLevel or 1, start = s.day, class = car and car.class or nil, standings = {}, raced = {},
    calendar = clubs.calendar(sl_career.racesList and M.listed() or {}, rng), season = ((c and c.season) or 0) + 1 }
  for _, r in ipairs(members(s)) do s.club.standings[r.id] = 0 end
  s.club.standings.player = 0
  M.morningText(s)
  return s.club
end

-- the races the map lists (night, drag, circuit, venue), as the calendar wants them
function M.listed()
  local out = {}
  for _, r in ipairs(sl_career.racesList() or {}) do out[#out + 1] = { id = r.id, missionId = r.missionId, name = r.name, kind = r.drag and 'drag' or (r.kind or 'night') } end
  for _, t in ipairs(sl_career.has('clubDays') and sl_career.tracksList and sl_career.tracksList() or {}) do out[#out + 1] = { id = t.id, missionId = t.missionId, name = t.name, kind = t.kind } end
  if sl_career.has('stockEvents') then            -- (#41) West Coast USA: the day league is the map's stock track events
    local all = gameplay_missions_missions and gameplay_missions_missions.getAllMissions and gameplay_missions_missions.getAllMissions() or {}
    local nameOf = function(m)
      local ok, text = pcall(function() return translateLanguage and translateLanguage(m.name, tostring(m.name or m.id), true) end)
      return ok and type(text) == 'string' and text or tostring(m.name or m.id)
    end
    for _, e in ipairs(clubs.stockEvents(all, function(id) return activityRules.ruleFor(sl_career.LEVEL, id) end, nameOf)) do out[#out + 1] = e end
  end
  return out
end

-- a stock day event is open by day only (the career's phase; D2)
local function dayOpen(e)
  if e.stock then return not (sl_career.isNight and sl_career.isNight()) end
  return e.kind == 'drag' or (sl_career.has('clubDays') and slrrValoRaces and slrrValoRaces.circuitOpponents) == true
end

local function today(s) local c = s.club return c and c.calendar[s.day - c.start + 1], s.day - c.start + 1 end

function M.morningText(s)
  local ev, n = today(s)
  if not ev then return end
  local parts = {}
  if ev.night then parts[#parts + 1] = 'tonight ' .. ev.night.name end
  if ev.day then parts[#parts + 1] = 'today ' .. ev.day.name end
  sl_career.sendText('benny', string.format('%s, season %d, day %d%s: %s. Class %s. It is on the Club app; skip it if you are busy.',
    clubs.CLUBS[s.club.club].name, s.club.season, n, ev.finale and ' (the finale, double points)' or '', table.concat(parts, ', '), s.club.class or '?'), 2)
end

-- a day gone: the events the player did not race are raced without them
function M.onStreetLegalNewDay(day)
  local s = career()
  local c = s and s.club
  if not c then return end
  local d = day - 1 - c.start + 1
  local ev = c.calendar[d]
  if ev then
    for _, kind in ipairs({ 'night', 'day' }) do
      if ev[kind] and not c.raced[d .. kind] then
        c.raced[d .. kind] = 'skipped'
        clubs.score(c.standings, clubs.simulate(members(s), rngLib.new(rngLib.hash(kind .. d .. ':' .. c.start .. tostring(s.seed)))), ev.finale)
      end
    end
  end
  if day < c.start + clubs.SEASON_DAYS then M.morningText(s) end
end

function M.endSeason(s)
  local c = s.club
  local place = clubs.placeOf(c.standings, 'player')
  local money, rep, invited = clubs.seasonReward(c.club, place)
  if money > 0 then sl_career.payOut(money, clubs.CLUBS[c.club].name .. ' season ' .. c.season) end
  if rep > 0 then stateLib.addRep(s, rep) end
  local text = string.format('%s season %d is over: you finished %s.', clubs.CLUBS[c.club].name, c.season, place and ('#' .. place) or 'unplaced')
  if invited and clubs.CLUBS[c.club + 1] then text = text .. ' ' .. clubs.CLUBS[c.club + 1].name .. ' has sent you an invitation: move up when you can (phone, Street cred).' end
  sl_career.sendText('benny', text, 1)
end

----------------------------------------------------------------------------------------------
-- entering an event: a real race through the career's arranged races (and so through the map's launch)

-- the racer just ahead of you in the standings (or the leader, if you lead), the night league's rival
function M.rival(s)
  local tbl = clubs.table(s.club.standings)
  local me = clubs.placeOf(s.club.standings, 'player') or #tbl
  for i = me - 1, 1, -1 do if tbl[i].id ~= 'player' then return stateLib.racer(s, tbl[i].id) end end
  for i = me + 1, #tbl do if tbl[i].id ~= 'player' then return stateLib.racer(s, tbl[i].id) end end
end

function M.enter(kind)
  local s = career()
  if not s then return false, 'No career running.' end
  local c = M.ensureSeason(s)
  local ev, d = today(s)
  local race = ev and ev[kind]
  if not race then return false, 'Nothing on in that league today.' end
  if c.raced[d .. kind] then return false, 'You have done that one today.' end
  if kind == 'night' and sl_career.isNight and not sl_career.isNight() then return false, 'The night league races after dark.' end
  if kind == 'day' and not dayOpen(race) then
    return false, race.stock and 'The day league runs by day.' or 'The track events open soon. The drags run today.'
  end
  if race.stock then            -- (#41) a stock track event: nothing to arrange, the player runs it from its marker and the game's stars score it
    return true, string.format('Day league: %s today. Run it from its marker on the map; the stars you earn score your points.', race.name)
  end
  local car = sl_fleet and sl_fleet.currentCar()
  if not car then return false, 'Bring one of your cars.' end
  if c.class and car.class and clubs.classIndex(car.class) > clubs.classIndex(c.class) then
    return false, string.format('This season you are class %s; the %s is class %s.', c.class, car.name, car.class)
  end
  local rival = M.rival(s)
  if not rival then return false, 'Nobody to race.' end
  s.known[rival.id] = true
  for i = #s.challenges, 1, -1 do if s.challenges[i].racer == rival.id then table.remove(s.challenges, i) end end
  local bet = math.floor(((rival.betMin or 100) + (rival.betMax or 300)) / 2 / 50) * 50
  s.challenges[#s.challenges + 1] = { id = rival.id .. ':league:' .. d .. kind, racer = rival.id, stake = 'money', bet = bet, race = race.id,
    raceName = race.name, missionId = race.missionId, at = os.time(), league = { day = d, kind = kind } }
  extensions.hook('onStreetLegalChanged')
  return true, string.format('%s: %s against %s for $%d. It is in your Races app.', kind == 'night' and 'Night league' or 'Day league', race.name, roster.displayName(rival), bet)
end

-- the result: the head-to-head places you first or second against your rival; the rest of the club in simulation
function M.onSlrrRaceFinished(r)
  local s = career()
  local c = s and s.club
  if not c or type(r) ~= 'table' then return end
  local ch
  for _, x in ipairs(s.challenges) do if (x.race == r.raceId or (r.missionId and x.missionId == r.missionId)) and x.league then ch = x end end
  ch = ch or M._lastLeague
  if not ch or not ch.league then return end
  M._lastLeague = nil
  local key = ch.league.day .. ch.league.kind
  if c.raced[key] then return end
  c.raced[key] = 'raced'
  local ev = c.calendar[ch.league.day] or {}
  local others = {}
  for _, m in ipairs(members(s)) do if m.id ~= ch.racer then others[#others + 1] = m end end
  local order = clubs.simulate(others, rngLib.new(rngLib.hash('league' .. key .. tostring(s.seed))))
  -- the head-to-head decides who of the two is ahead; the pair slots in by the winner's pace
  local pair = r.won and { 'player', ch.racer } or { ch.racer, 'player' }
  local at = math.max(1, math.floor(#order / 3))
  table.insert(order, at, pair[2]) table.insert(order, at, pair[1])
  clubs.score(c.standings, order, ev.finale)
  local purse = ch.league.kind == 'day' and clubs.purse(c.club, r.won and 1 or 2) or 0
  if purse > 0 then sl_career.payOut(purse, 'Day league purse') end
  toast(string.format('League: %s. You are #%d in the %s standings.', r.won and 'won' or 'lost', clubs.placeOf(c.standings, 'player') or 0, clubs.CLUBS[c.club].name))
  extensions.hook('onStreetLegalChanged')
end
-- (#41) a stock day event run from its marker: the game's stars decide the place, the rest of the club in simulation
function M.onMissionAttemptAggregated(attempt, mission)
  local s = career()
  local c = s and s.club
  if not c or not mission or type(attempt) ~= 'table' then return end
  if attempt.type ~= 'passed' and attempt.type ~= 'completed' then return end
  local ev, d = today(s)
  local race = ev and ev.day
  if not (race and race.stock and race.missionId == mission.id) or c.raced[d .. 'day'] then return end
  local stars = 0
  for _, on in pairs(type(attempt.unlockedStars) == 'table' and attempt.unlockedStars or {}) do if on then stars = stars + 1 end end
  local place = clubs.placeFromStars(stars)
  if not place then return end
  c.raced[d .. 'day'] = 'raced'
  clubs.score(c.standings, clubs.simulate(members(s), rngLib.new(rngLib.hash('stock' .. d .. ':' .. c.start .. tostring(s.seed))), place), ev.finale)
  local purse = clubs.purse(c.club, place)
  if purse > 0 then sl_career.payOut(purse, 'Day league purse') end
  toast(string.format('League: %s (%d star%s). You are #%d in the %s standings.', race.name, stars, stars == 1 and '' or 's', clubs.placeOf(c.standings, 'player') or 0, clubs.CLUBS[c.club].name))
  extensions.hook('onStreetLegalChanged')
end

-- (the career removes the challenge when it settles the race; keep it for us if it goes first)
local function rememberLeague() local s = career() for _, x in ipairs(s and s.challenges or {}) do if x.league then M._lastLeague = x end end end
M.onStreetLegalRaceStarted = rememberLeague
M.onSlrrRaceStarted = rememberLeague

----------------------------------------------------------------------------------------------
-- for the phone's Club app

function M.summary()
  local s = career()
  if not s then return nil end
  local c = M.ensureSeason(s)
  local ev, d = today(s)
  local tbl = {}
  for i, row in ipairs(clubs.table(c.standings)) do
    local r = row.id ~= 'player' and stateLib.racer(s, row.id)
    tbl[#tbl + 1] = { place = i, name = row.id == 'player' and 'You' or (r and roster.displayName(r) or row.id), points = row.points, you = row.id == 'player' }
  end
  local car = sl_fleet and sl_fleet.currentCar()
  return {
    club = clubs.CLUBS[c.club].name, season = c.season, day = d, days = clubs.SEASON_DAYS, class = c.class, carClass = car and car.class,
    today = ev and {
      night = ev.night and { name = ev.night.name, done = c.raced[d .. 'night'] ~= nil } or nil,
      day = ev.day and { name = ev.day.name, done = c.raced[d .. 'day'] ~= nil, open = dayOpen(ev.day) } or nil,
      finale = ev.finale,
    } or nil,
    standings = tbl,
  }
end

return M
