-- Street Legal: money, reputation and the climb from the first garage to the ROC.
-- Pure rules, no game calls: everything here is tested outside the game (tools/luatest.js).
--
-- You start with a little money and a name nobody knows. Racing builds reputation - more at
-- night, more against racers better known than you - and reputation opens doors: better
-- garages (which also cost money to move into), racers who would not have talked to you, and
-- in the end the ROC.

local M = {}

M.START_MONEY = 5000
M.START_HOUR = 10            -- a daytime start (Connor, 2026-10-16); the races are still at night

-- the maps a career is played on (W1). garages: Wrench Works' site ids for the garage ladder below, in order (none:
-- the ladder as written); races: the extension that runs its street races (the map's own, or the career's sl_races).
-- has: what the map can host. The ROC needs its track and spawn_roc, tracks the multibot_tracks.json circuits, testdrive
-- racelines/tt_oval.json, clubDays the map's circuitOpponents, swapMeet the Tuning shop lot. A feature a map lacks is hidden, not half-run.
local ALL = { roc = true, tracks = true, testdrive = true, clubDays = true, swapMeet = true }
M.MAPS = {
  slrr_valo_city = { name = 'Valo City', races = 'slrrValoRaces', has = ALL },
  -- stockFacilities: the map's own dealerships and garages (game data) become places; Valo City has its own
  west_coast_usa = { name = 'West Coast USA', races = 'sl_races', has = { stockFacilities = true }, garages = {
    { id = 'alderDragwayGarage', name = 'Alder Dragway Garage' }, { id = 'commercialGarage', name = 'Industrial Garage' },
    { id = 'belascoCityGarage', name = 'Belasco City Garage' } } },
}
M.MAP_ORDER = { 'slrr_valo_city', 'west_coast_usa' }
M.DEFAULT_MAP = 'slrr_valo_city'

function M.has(level, feature) return ((M.MAPS[level] or M.MAPS[M.DEFAULT_MAP]).has or {})[feature] == true end

-- Valo-named text on another map says that map's name
function M.mapText(text, level)
  local map = M.MAPS[level] or M.MAPS[M.DEFAULT_MAP]
  if map == M.MAPS.slrr_valo_city then return text end
  local n = map.name:gsub('%%', '%%%%')
  return (text:gsub('Valo City', n):gsub('%f[%w]Valo%f[%W]', n))
end

-- how hard the street gets, 0 (nobody) to 1 (the ROC crowd): from reputation
function M.difficulty(rep) return math.max(0, math.min(1, (rep or 0) / 6000)) end

-- what people call you
M.titles = {
  { rep = 0, title = 'Nobody' },
  { rep = 100, title = 'Street kid' },
  { rep = 300, title = 'Regular' },
  { rep = 700, title = 'Known face' },
  { rep = 1500, title = 'Contender' },
  { rep = 3000, title = 'Local legend' },
  { rep = 6000, title = 'King of Valo City' },
}

-- the garages, in order. Moving up needs the reputation and the money. (site and name are Valo City's; the career
-- sets them per map from MAPS, so every module reads one ladder)
M.garages = {
  { level = 1, site = 'slrrGarage1', name = 'Club Garage 1', rep = 0, cost = 0 },
  { level = 2, site = 'slrrGarage2', name = 'Club Garage 2', rep = 1500, cost = 25000 },
  { level = 3, site = 'slrrGarage3', name = 'Club Garage 3', rep = 3000, cost = 75000 },
}

-- garage upgrades (X58, Design 7): what a garage has is bought, and kept with that garage. The club garages (2, 3)
-- come with the lift and the workbench. Off a career Wrench Works has everything.
M.UPGRADES = {
  { id = 'lift', name = 'Two-post lift', price = 2000, desc = 'Engine, gearbox, suspension and exhaust work at home.' },
  { id = 'workbench', name = 'Workbench and tools', price = 1500, desc = 'Repairs at the normal price; engine rebuilds.' },
  { id = 'dyno', name = 'Dyno', price = 6000, desc = 'Power curves, before and after.' },
  { id = 'paint', name = 'Paint booth', price = 5000, desc = 'Paint, liveries and tint at home.' },
  { id = 'shelves', name = 'Parts shelves', price = 1000, desc = 'Three times the shelf space.' },
  { id = 'photo', name = 'Photo corner', price = 800, desc = 'Photo mode in the garage, and a showcase shot for the meets.' },
}
M.GARAGE_COMES_WITH = { [2] = { lift = true, workbench = true }, [3] = { lift = true, workbench = true } }
M.SHELF = { base = 12, shelves = 40 }       -- parts per model on the shelf
M.MOBILE_MECHANIC = 1.5                    -- repairs without the workbench cost this much more

function M.upgrade(id) for _, u in ipairs(M.UPGRADES) do if u.id == id then return u end end end

-- what Wrench Works may do in this garage: bought ones and what the garage came with
function M.garageFeatures(bought, level)
  local has = {}
  for k, v in pairs(M.GARAGE_COMES_WITH[level or 1] or {}) do has[k] = v end
  for k, v in pairs(bought or {}) do if v then has[k] = true end end
  return { lift = has.lift == true, workbench = has.workbench == true, dyno = has.dyno == true, paint = has.paint == true, photo = has.photo == true,
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
    return { garage = nextOne, canMove = false, why = string.format('needs %d reputation', nextOne.rep) }
  end
  if (state.money or 0) < nextOne.cost then
    return { garage = nextOne, canMove = false, why = string.format('costs $%d', nextOne.cost) }
  end
  return { garage = nextOne, canMove = true }
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
