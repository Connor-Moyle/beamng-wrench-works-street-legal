-- Street Legal: the street racers of Valo City.
-- Made up from a seed when a career starts, so every career has its own crowd. Each racer is
-- a contact in the phone: a name, a number, how good they are, what they drive, how they talk
-- and what they will race for. Pure: no game calls (tested by tools/luatest.js).

local M = {}

local rngLib = require('sl/core/rng')

local FIRST = { 'Viktor', 'Dora', 'Mick', 'Rusty', 'Lena', 'Tomi', 'Andre', 'Kenji', 'Sal', 'Jade', 'Fritz', 'Carla',
  'Zoltan', 'Danny', 'Marek', 'Rosa', 'Ivo', 'Nadia', 'Brett', 'Yusuf', 'Petra', 'Leon', 'Gina', 'Oskar', 'Mira',
  'Tariq', 'Elsa', 'Dmitri', 'Kat', 'Bruno', 'Sofia', 'Gus', 'Hana', 'Rafael', 'Tess', 'Viggo' }
local LAST = { 'Halasz', 'Kovacs', 'Santana', 'Ferreira', 'Weiss', 'Szabo', 'Dupuis', 'Mori', 'Monroe', 'Bauer', 'Reyes',
  'Nagy', 'Kim', 'Novak', 'Lindqvist', 'Varga', 'Okafor', 'Brandt', 'Costa', 'Petrov', 'Holm', 'Rossi', 'Vidal',
  'Kral', 'Doyle', 'Moreau', 'Sato', 'Horvat', 'Jansen', 'Pike' }
local NICKS = { 'Nitro', 'Two-Step', 'Clutch', 'Redline', 'Ghost', 'Sparky', 'Lowboy', 'Tank', 'Slick', 'Boost', 'Rook',
  'Smokey', 'Diesel', 'Gears', 'Flash', 'Vandal', 'Torque', 'Mouse', 'Blitz', 'Chrome' }

-- what they like to drive, cheapest first; the market and race code turn a class into real cars
M.CLASSES = { 'beater', 'compact', 'muscle', 'tuner', 'sport', 'super' }

-- tier 1 races for pocket money, tier 5 are the names everybody knows
local TIERS = {
  { rep = { 0, 150 }, skill = { 0.15, 0.4 }, bet = { 100, 400 }, classes = { 1, 2 } },
  { rep = { 150, 600 }, skill = { 0.3, 0.55 }, bet = { 300, 1000 }, classes = { 2, 3 } },
  { rep = { 600, 1800 }, skill = { 0.45, 0.7 }, bet = { 800, 3000 }, classes = { 3, 4 } },
  { rep = { 1800, 4000 }, skill = { 0.6, 0.85 }, bet = { 2500, 8000 }, classes = { 4, 5 } },
  { rep = { 4000, 9000 }, skill = { 0.75, 0.97 }, bet = { 6000, 20000 }, classes = { 5, 6 } },
}
M.TIERS = TIERS

-- how they come across, in calls and messages
local STYLES = { 'easy', 'trash', 'roller', 'careful' }

local function round50(x) return math.floor(x / 50 + 0.5) * 50 end

-- count racers: more at the bottom of the ladder than at the top
function M.generate(seed, count)
  count = count or 36
  local rng = rngLib.new(seed)
  local list, usedNames, usedNicks = {}, {}, {}
  for i = 1, count do
    local tier = math.min(5, 1 + math.floor(((i - 1) / count) ^ 1.4 * 5))
    local t = TIERS[tier]
    local name
    repeat name = rng:pick(FIRST) .. ' ' .. rng:pick(LAST) until not usedNames[name]
    usedNames[name] = true
    local nick
    if rng:chance(0.45) then
      for _ = 1, 10 do
        local n = rng:pick(NICKS)
        if not usedNicks[n] then nick = n break end
      end
      if nick then usedNicks[nick] = true end
    end
    local style = rng:pick(STYLES)
    local betLo, betHi = t.bet[1], t.bet[2]
    if style == 'roller' then betLo, betHi = betLo * 1.5, betHi * 1.5 end
    list[i] = {
      id = string.format('r%02d', i),
      name = name, nick = nick,
      phone = string.format('555-%04d', 1000 + (i * 137 + seed) % 9000),
      tier = tier,
      rep = rng:int(t.rep[1], t.rep[2]),
      skill = math.floor(rng:range(t.skill[1], t.skill[2]) * 100 + 0.5) / 100,
      class = M.CLASSES[rng:int(t.classes[1], t.classes[2])],
      style = style,
      pinkOK = rng:chance(style == 'roller' and 0.7 or (style == 'careful' and 0.15 or 0.4)),
      nightOnly = rng:chance(0.35),
      betMin = round50(betLo), betMax = round50(betHi),
      wins = 0, losses = 0,          -- against the player
    }
  end
  return list
end

function M.displayName(r)
  if r.nick then
    local first, last = r.name:match('^(%S+)%s+(.+)$')
    return string.format('%s "%s" %s', first, r.nick, last)
  end
  return r.name
end

-- What they say. Kept per style so a contact sounds like the same person every time.
local LINES = {
  nobody = {
    easy = "Sorry, I don't race people I don't know. Make a name first.",
    trash = "Who is this? Call me when somebody's heard of you.",
    roller = "I race for real money with real names. You're neither yet.",
    careful = "I don't know you. Win a few races and we'll talk.",
  },
  broke = {
    easy = "That's more than you've got, mate. Bring the cash.",
    trash = "With what money? Come back when your wallet's bigger than your mouth.",
    roller = "Can't cover the stake? Then don't waste my time.",
    careful = "You'd need $%d up front. Call me when you have it.",
  },
  noPink = {
    easy = "Pink slips? Nah, I like my car too much.",
    trash = "My car? For yours? Have you seen yours?",
    roller = "Not this week. Money race, or nothing.",
    careful = "I don't race for cars. Money only.",
  },
  noCar = {
    easy = "You haven't even got a car. Sort that out first.",
    trash = "Race you in what, a shopping trolley?",
    roller = "Get yourself a car. Then we talk.",
    careful = "You need a car for that.",
  },
  yes = {
    easy = "You're on. $%d, %s.",
    trash = "Easy money. $%d, %s. Don't be late.",
    roller = "$%d on the line, %s. Bring it.",
    careful = "Alright. $%d, %s. Clean race, no funny stuff.",
  },
  yesPink = {
    easy = "Pink slips it is. %s. Winner drives home in both.",
    trash = "Your car's going to look great in my garage. %s.",
    roller = "Now we're talking. Pinks, %s.",
    careful = "Fine. Pink slips, %s. Don't back out.",
  },
}

local function line(kind, style, ...)
  local text = LINES[kind][style] or LINES[kind].easy
  if select('#', ...) > 0 and text:find('%%') then return string.format(text, ...) end
  return text
end

-- How a racer answers a challenge.
--   kind: 'race' (their usual stake) | 'high' (three times that) | 'pink' (cars)
--   player: { rep, money, hasCar }
--   rng: an rng from sl/core/rng (decides the stake within their range)
-- Returns { accept, stake = 'money'|'pink', bet, text, when }
function M.respond(racer, kind, player, rng)
  local when = racer.nightOnly and 'tonight' or 'any time'
  local floor = TIERS[racer.tier].rep[1] * 0.5           -- below this they will not take you seriously
  if (player.rep or 0) < floor then return { accept = false, text = line('nobody', racer.style) } end
  if not player.hasCar then return { accept = false, text = line('noCar', racer.style) } end
  if kind == 'pink' then
    if not racer.pinkOK or (player.rep or 0) < TIERS[racer.tier].rep[1] then
      return { accept = false, text = line('noPink', racer.style) }
    end
    return { accept = true, stake = 'pink', bet = 0, when = when, text = line('yesPink', racer.style, when) }
  end
  local bet = round50(rng:range(racer.betMin, racer.betMax))
  if kind == 'high' then bet = bet * 3 end
  if (player.money or 0) < bet then return { accept = false, text = line('broke', racer.style, bet) } end
  return { accept = true, stake = 'money', bet = bet, when = when, text = line('yes', racer.style, bet, when) }
end

return M
