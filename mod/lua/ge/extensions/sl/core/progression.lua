-- Street Legal: money, reputation and the climb from the first garage to the ROC.
-- Pure rules, no game calls: everything here is tested outside the game (tools/luatest.js).
--
-- You start with a little money and a name nobody knows. Racing builds reputation - more at
-- night, more against racers better known than you - and reputation opens doors: better
-- garages (which also cost money to move into), racers who would not have talked to you, and
-- in the end the ROC.

local M = {}

local strings = require('sl/core/strings')

M.START_MONEY = 5000
M.START_HOUR = 10            -- a daytime start (Connor, 2026-10-16); the races are still at night

-- the maps a career is played on (W1). garages: Wrench Works' site ids for the garage ladder below, in order (none:
-- the ladder as written); races: the extension that runs its street races (the map's own, or the career's sl_races).
-- has: what the map can host. The ROC needs its track and spawn_roc, tracks the multibot_tracks.json circuits, testdrive
-- racelines/tt_oval.json, clubDays the map's circuitOpponents, swapMeet the Tuning shop lot; clubs, crews and classifieds
-- (the phone's Club, Turf, Revline, Classifieds and Swap & Bid apps) are release 2 and Valo City's for now. A feature a map lacks is hidden, not half-run.
local ALL = { roc = true, tracks = true, testdrive = true, clubDays = true, swapMeet = true, clubs = true, crews = true, classifieds = true }
M.MAPS = {
  slrr_valo_city = { name = strings.t('progression.valo_city'), races = 'slrrValoRaces', has = ALL },
  -- stockFacilities: the map's own dealerships and garages (game data) become places; Valo City has its own
  -- clubs (#41): the night league races the map's sprints; the day league is the stock track events (stockEvents, scored by the game's stars)
  west_coast_usa = { name = strings.t('progression.west_coast_usa'), races = 'sl_races', has = { stockFacilities = true, classifieds = true, clubs = true, stockEvents = true, swapMeet = true, nightMeet = true, crews = true }, garages = {
    { id = 'alderDragwayGarage', name = strings.t('progression.alder_dragway_garage') }, { id = 'commercialGarage', name = strings.t('progression.industrial_garage') },
    { id = 'belascoCityGarage', name = strings.t('progression.belasco_city_garage') } } },
}
-- the maps a career travels to (docs/DESIGN_CAREER_TRAVEL.md): not maps to play a career on (they are not in MAP_ORDER), no feature of the home world exists there
M.MAPS.johnson_valley = { name = strings.t('progression.johnson_valley'), visit = true, races = 'sl_races', has = {} }
M.MAPS.utah = { name = strings.t('progression.utah'), visit = true, races = 'sl_races', has = {} }
M.MAPS.hirochi_raceway = { name = strings.t('progression.hirochi_raceway'), visit = true, races = 'sl_races', has = {} }
function M.isVisit(level) return M.MAPS[level] ~= nil and M.MAPS[level].visit == true end
M.MAP_ORDER = { 'west_coast_usa', 'slrr_valo_city' }      -- (West Coast USA is the game; Valo City is parked: its code stays, it is only not the default)
M.DEFAULT_MAP = 'west_coast_usa'
-- A save from before the maps were chosen has no level field, and before West Coast USA was the default every career was a Valo City one: a save with no level IS Valo City.
-- Only a new career takes the default map.
M.LEGACY_MAP = 'slrr_valo_city'
-- the map of a saved career (nil / no save: the default for a new one)
function M.levelOf(save)
  if type(save) ~= 'table' then return M.DEFAULT_MAP end
  if save.level == nil then return M.LEGACY_MAP end
  if M.MAPS[save.level] then return save.level end
  return M.DEFAULT_MAP
end

function M.has(level, feature) return ((M.MAPS[level] or M.MAPS[M.DEFAULT_MAP]).has or {})[feature] == true end

-- Valo-named text on another map says that map's name
function M.mapText(text, level)
  local map = M.MAPS[level] or M.MAPS[M.DEFAULT_MAP]
  if map == M.MAPS.slrr_valo_city then return text end
  local n = map.name:gsub('%%', '%%%%')
  return (text:gsub('Valo City', n):gsub('%f[%w]Valo%f[%W]', n))
end

-- Waiting (the phone's Wait app): 'morning' = the next 06:00 (a few minutes past it, so the day change is counted once), or 1, 3 or
-- 6 hours. h0 = the hour now (0..24). Returns { hours, to (the hour it will be), days (06:00s passed: the day counter goes up by that) } or nil.
M.WAIT_CHOICES = { morning = true, ['1'] = true, ['3'] = true, ['6'] = true, ['0.33'] = true }
function M.skipPlan(h0, what)
  what = tostring(what)
  if not M.WAIT_CHOICES[what] then return nil end
  local hours = what == 'morning' and (6.05 - h0) % 24 or tonumber(what)
  if hours < 0.05 then hours = 24 end
  local days = math.floor((h0 - 6 + hours) / 24) - math.floor((h0 - 6) / 24)
  return { hours = hours, to = (h0 + hours) % 24, days = days }
end

-- no waiting in a race, on a job or with the police on you (state = { racing, job, heat })
function M.skipRefusal(state)
  if state.racing then return strings.t('jobs.not_in_the_middle_of') end
  if state.job then return strings.t('classifieds.finish_the_job_you_are') end
  if (state.heat or 0) > 0.3 then return strings.t('phase.the_police_are_after_you') end
  return nil
end

-- how hard the street gets, 0 (nobody) to 1 (the ROC crowd): from reputation
function M.difficulty(rep) return math.max(0, math.min(1, (rep or 0) / 6000)) end

-- what people call you
M.titles = {
  { rep = 0, title = 'Nobody' },
  { rep = 100, title = strings.t('progression.street_kid') },
  { rep = 300, title = 'Regular' },
  { rep = 700, title = strings.t('progression.known_face') },
  { rep = 1500, title = 'Contender' },
  { rep = 3000, title = strings.t('progression.local_legend') },
  { rep = 6000, title = strings.t('achievements.king_of_valo_city') },
}

-- the garages, in order. Moving up needs the reputation and the money. (site and name are Valo City's; the career
-- sets them per map from MAPS, so every module reads one ladder)
M.garages = {
  { level = 1, site = 'slrrGarage1', name = strings.t('progression.club_garage_1'), rep = 0, cost = 0 },
  { level = 2, site = 'slrrGarage2', name = strings.t('progression.club_garage_2'), rep = 175, cost = 6000 },
  { level = 3, site = 'slrrGarage3', name = strings.t('progression.club_garage_3'), rep = 1000, cost = 25000 },
}

-- garage upgrades (X58, Design 7): what a garage has is bought, and kept with that garage. The club garages (2, 3)
-- come with the lift and the workbench. Off a career Wrench Works has everything.
M.UPGRADES = {
  { id = 'lift', name = strings.t('progression.two_post_lift'), price = 2000, desc = strings.t('progression.gearbox_suspension_driveline_and_exhaust') },
  { id = 'crane', name = strings.t('progression.engine_crane'), price = 3500, desc = strings.t('progression.the_engine_comes_out_and') },
  { id = 'workbench', name = strings.t('progression.workbench_and_tools'), price = 1500, desc = strings.t('progression.repairs_at_the_normal_price') },
  { id = 'dyno', name = 'Dyno', price = 6000, desc = strings.t('progression.power_curves_before_and_after') },
  { id = 'paint', name = strings.t('progression.paint_booth'), price = 5000, desc = strings.t('progression.paint_liveries_and_tint_at') },
  { id = 'shelves', name = strings.t('progression.parts_shelves'), price = 1000, desc = strings.t('progression.three_times_the_shelf_space') },
  { id = 'photo', name = strings.t('progression.photo_corner'), price = 800, desc = strings.t('progression.photo_mode_in_the_garage') },
  { id = 'fridge', needs = true, name = strings.t('progression.fridge'), price = 400, desc = strings.t('progression.fridge_desc') },      -- (the Needs part: shown only while it is on)
  { id = 'bed', needs = true, name = strings.t('progression.bed'), price = 1200, desc = strings.t('progression.bed_desc') },
}
M.GARAGE_COMES_WITH = { [2] = { lift = true, workbench = true, crane = true }, [3] = { lift = true, workbench = true, crane = true } }
M.SHELF = { base = 12, shelves = 40 }       -- parts per model on the shelf
M.MOBILE_MECHANIC = 1.5                    -- repairs without the workbench cost this much more

function M.upgrade(id) for _, u in ipairs(M.UPGRADES) do if u.id == id then return u end end end

-- what Wrench Works may do in this garage: bought ones and what the garage came with
function M.garageFeatures(bought, level)
  local has = {}
  for k, v in pairs(M.GARAGE_COMES_WITH[level or 1] or {}) do has[k] = v end
  for k, v in pairs(bought or {}) do if v then has[k] = true end end
  return { lift = has.lift == true, crane = has.crane == true, workbench = has.workbench == true, dyno = has.dyno == true, paint = has.paint == true, photo = has.photo == true, fridge = has.fridge == true, bed = has.bed == true,
    shelfSize = has.shelves and M.SHELF.shelves or M.SHELF.base, repairFactor = has.workbench and 1 or M.MOBILE_MECHANIC }
end

-- the Race of Champions: the last garage and the top title
M.ROC = { garageLevel = 3, rep = 6000, entry = 50000 }

function M.titleFor(rep, level)
  local current, nextOne = M.titles[1], nil
  for i, t in ipairs(M.titles) do
    if rep >= t.rep then
      current, nextOne = t, M.titles[i + 1]
    end
  end
  return level and M.mapText(current.title, level) or current.title, nextOne and nextOne.rep or nil, current.rep
end

-- the next garage up from where the player is: { garage, canMove, why } (nil at the top)
function M.nextGarage(state)
  local nextOne = M.garages[(state.garageLevel or 1) + 1]
  if not nextOne then return nil end
  if (state.rep or 0) < nextOne.rep then
    return { garage = nextOne, canMove = false, why = string.format(strings.t('progression.needs_d_reputation'), nextOne.rep) }
  end
  if (state.money or 0) < nextOne.cost then
    return { garage = nextOne, canMove = false, why = string.format(strings.t('progression.costs_d'), nextOne.cost) }
  end
  return { garage = nextOne, canMove = true }
end

-- the garage ladder: a garage above your level is not available (no marker, no way in). A site that is not on the ladder is free.
-- -> true, or false and what to tell the player
function M.garageAccess(state, siteId)
  for _, g in ipairs(M.garages) do
    if g.site == siteId then
      if g.level <= (state.garageLevel or 1) then return true end
      if (state.rep or 0) < g.rep then return false, string.format(strings.t('progression.you_need_d_reputation_to'), g.rep, g.name) end
      return false, string.format(strings.t('progression.move_up_to_s_first'), g.name)
    end
  end
  return true
end

function M.rocOpen(state)
  return (state.garageLevel or 1) >= M.ROC.garageLevel and (state.rep or 0) >= M.ROC.rep
end

-- What a race was worth. r = { won, stake = 'money'|'pink', bet, night, opponentRep, playerRep }
-- Returns rep change (whole number) and money change.
function M.raceResult(r)
  local rep
  local ratio = ((r.opponentRep or 0) + 200) / ((r.playerRep or 0) + 200)
  local against = math.max(0.5, math.min(2, ratio))          -- beating somebody better known counts for more
  if r.won then
    rep = 35 + math.min(80, (r.bet or 0) / 100)                -- (35: balance pass, tools/economy_sim.py)
    if r.stake == 'pink' then rep = rep + 60 end
    rep = rep * against
    if r.night then rep = rep * 1.5 end
  else
    rep = r.stake == 'pink' and -30 or -5
    rep = rep / against                                      -- losing to a big name costs less
  end
  local money = 0
  if r.stake ~= 'pink' then money = (r.won and 1 or -1) * (r.bet or 0) end
  return math.floor(rep + (rep >= 0 and 0.5 or -0.5)), money
end

-- what it costs to have a car towed: a call-out charge and the distance
function M.towFee(distanceMetres)
  return 150 + math.floor((distanceMetres or 0) / 1000 * 40 + 0.5)
end

-- the reset key in the career: pulled back onto the nearest road as it is (no repairs), by how far off it you are
function M.roadFee(distanceMetres)
  return 50 + math.floor((distanceMetres or 0) * 2 + 0.5)
end

-- a taxi across town (on foot)
function M.taxiFee(distanceMetres)
  return 20 + math.floor((distanceMetres or 0) / 1000 * 12 + 0.5)
end

-- the police: caught, you pay for every offence (more if you were racing) and lose face;
-- getting away is worth a little on the street
M.EVADE_REP = 15
M.ARREST_REP = -25

function M.policeFine(offences, racing)
  return 250 + 150 * math.max(1, offences or 0) + (racing and 500 or 0)      -- (balance pass: bites, doesn't bankrupt)
end

-- is it night? (hour of day, 0-24) Races at night pay better in reputation.
function M.isNight(hour)
  return hour >= 20 or hour < 5
end

return M
