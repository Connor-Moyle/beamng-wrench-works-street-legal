-- Street Legal: money, reputation and the climb from the first garage to the ROC.
-- Pure rules, no game calls: everything here is tested outside the game (tools/luatest.js).
--
-- You start with a little money and a name nobody knows. Racing builds reputation - more at
-- night, more against racers better known than you - and reputation opens doors: better
-- garages (which also cost money to move into), racers who would not have talked to you, and
-- in the end the ROC.

local M = {}

M.START_MONEY = 3500
M.START_HOUR = 20.5          -- the first evening

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

-- the garages, in order. Moving up needs the reputation and the money.
M.garages = {
  { level = 1, site = 'slrrGarage1', name = 'Club Garage 1', rep = 0, cost = 0 },
  { level = 2, site = 'slrrGarage2', name = 'Club Garage 2', rep = 1500, cost = 25000 },
  { level = 3, site = 'slrrGarage3', name = 'Club Garage 3', rep = 3000, cost = 75000 },
}

-- the Race of Champions: the last garage and the top title
M.ROC = { garageLevel = 3, rep = 6000, entry = 50000 }

function M.titleFor(rep)
  local current, nextOne = M.titles[1], nil
  for i, t in ipairs(M.titles) do
    if rep >= t.rep then
      current, nextOne = t, M.titles[i + 1]
    end
  end
  return current.title, nextOne and nextOne.rep or nil, current.rep
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
    rep = 20 + math.min(80, (r.bet or 0) / 100)
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

-- a taxi across town (on foot)
function M.taxiFee(distanceMetres)
  return 20 + math.floor((distanceMetres or 0) / 1000 * 12 + 0.5)
end

-- the police: caught, you pay for every offence (more if you were racing) and lose face;
-- getting away is worth a little on the street
M.EVADE_REP = 15
M.ARREST_REP = -25

function M.policeFine(offences, racing)
  return 400 + 300 * math.max(1, offences or 0) + (racing and 1000 or 0)
end

-- is it night? (hour of day, 0-24) Races at night pay better in reputation.
function M.isNight(hour)
  return hour >= 20 or hour < 5
end

return M
