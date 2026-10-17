-- Street Legal: the career save - money, reputation, cars, contacts, messages - and the
-- book-keeping on it. Pure (tested by tools/luatest.js); the career extension reads and
-- writes it to /settings/street_legal/career.json (slot 1; careerN.json for the other save slots).

local M = {}

local progression = require('sl/core/progression')
local roster = require('sl/core/roster')

M.VERSION = 1
local LEDGER_KEEP = 60
local MESSAGES_KEEP = 40      -- per contact

function M.new(seed, now)
  seed = math.floor(tonumber(seed) or 1)
  return {
    version = M.VERSION,
    seed = seed,
    started = now,
    day = 1,
    phase = 'day',          -- 'day' | 'night' (sl/core/phase)
    money = progression.START_MONEY,
    rep = 0,
    bankedRep = 0,          -- the reputation that is safe (D3): what the night earned since is lost in a bust
    garageLevel = 1,
    cars = {},              -- { id, model, config (parts tree as saved by the game), name, condition, faults, where = { kind, pos } }
    activeCar = nil,        -- id of the car the player drives
    nextCarId = 1,
    racers = roster.generate(seed, 36),
    known = {},             -- racer id -> true once their number is in the phone
    threads = {},           -- racer id (or 'system') -> { { from = 'me'|'them', text, at } }
    unread = {},            -- thread id -> number of unread messages
    calls = {},             -- recent calls { racer, at, outgoing, missed }
    challenges = {},        -- arranged races { id, racer, stake, bet, race, when, at }
    ledger = {},            -- { at, amount, label }
    stats = { races = 0, wins = 0, pinksWon = 0, pinksLost = 0, earned = 0 },
  }
end

-- an older save brought up to date (and anything missing put back)
function M.migrate(s)
  if type(s) ~= 'table' or not s.seed then return nil end
  if s.bankedRep == nil then s.bankedRep = s.rep or 0 end      -- (D3: an older save has nothing at risk)
  if s.phase == nil then s.phase = require('sl/core/phase').infer(s.hour) end      -- (D1: an older save is in the half its clock is in)
  local fresh = M.new(s.seed, s.started)
  for k, v in pairs(fresh) do
    if s[k] == nil then s[k] = v end
  end
  s.version = M.VERSION
  return s
end

function M.addMoney(s, amount, label, at)
  amount = math.floor((tonumber(amount) or 0) + 0.5)
  if amount < 0 and s.money + amount < 0 then return false end
  s.money = s.money + amount
  if amount > 0 then s.stats.earned = s.stats.earned + amount end
  table.insert(s.ledger, 1, { at = at, amount = amount, label = label })
  while #s.ledger > LEDGER_KEEP do table.remove(s.ledger) end
  return true
end

function M.addRep(s, amount)
  s.rep = math.max(0, s.rep + math.floor(tonumber(amount) or 0))
  return s.rep
end

function M.racer(s, id)
  for _, r in ipairs(s.racers) do
    if r.id == id then return r end
  end
end

-- a message in a thread; from = 'me' or 'them'
function M.addMessage(s, thread, from, text, at)
  local list = s.threads[thread]
  if not list then list = {}; s.threads[thread] = list end
  list[#list + 1] = { from = from, text = text, at = at }
  while #list > MESSAGES_KEEP do table.remove(list, 1) end
  if from ~= 'me' then s.unread[thread] = (s.unread[thread] or 0) + 1 end
end

function M.markRead(s, thread) s.unread[thread] = nil end

function M.unreadCount(s)
  local n = 0
  for _, c in pairs(s.unread) do n = n + c end
  return n
end

-- the racers whose number the player has: everybody of the bottom tier from the start, the
-- rest as the player gets known (one tier per title step, roughly)
function M.refreshContacts(s)
  local added = {}
  local _, _, titleRep = progression.titleFor(s.rep)
  for _, r in ipairs(s.racers) do
    if not s.known[r.id] and roster.TIERS[r.tier].rep[1] <= math.max(titleRep, s.rep) * 1.2 then
      s.known[r.id] = true
      added[#added + 1] = r
    end
  end
  return added
end

function M.addCar(s, car)
  car.id = s.nextCarId
  s.nextCarId = s.nextCarId + 1
  s.cars[#s.cars + 1] = car
  return car
end

function M.removeCar(s, id)
  for i, c in ipairs(s.cars) do
    if c.id == id then
      table.remove(s.cars, i)
      if s.activeCar == id then s.activeCar = nil end
      return c
    end
  end
end

-- a race result into the save: money, reputation, record against that racer
-- r = { racer (id), won, stake, bet, night, at }
function M.recordRace(s, r)
  local racer = r.racer and M.racer(s, r.racer)
  local repDelta, moneyDelta = progression.raceResult({
    won = r.won, stake = r.stake, bet = r.bet, night = r.night, opponentRep = racer and racer.rep or 300, playerRep = s.rep,
  })
  M.addRep(s, repDelta)
  if moneyDelta ~= 0 then
    if moneyDelta < 0 and s.money + moneyDelta < 0 then moneyDelta = -s.money end      -- you pay what you have
    M.addMoney(s, moneyDelta, (r.won and 'Won' or 'Lost') .. ' a race' .. (racer and (' against ' .. racer.name) or ''), r.at)
  end
  s.stats.races = s.stats.races + 1
  if r.won then s.stats.wins = s.stats.wins + 1 end
  if r.stake == 'pink' then
    if r.won then s.stats.pinksWon = s.stats.pinksWon + 1 else s.stats.pinksLost = s.stats.pinksLost + 1 end
  end
  if racer then
    if r.won then racer.losses = racer.losses + 1 else racer.wins = racer.wins + 1 end
    racer.rep = math.max(0, racer.rep + (r.won and -10 or 10))
  end
  return repDelta, moneyDelta
end

return M
