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

-- raising the stake on an arranged race (playtest #6): 10 % of the agreed bet a step, up to what their car
-- makes them sure of: twice the bet in a beater, four times in a supercar
function M.stakeStep(base) return math.max(50, round50((base or 0) * 0.1)) end
function M.maxStake(racer, base)
  local class = 1
  for i, c in ipairs(M.CLASSES) do if c == racer.class then class = i end end
  return round50((base or 0) * math.min(4, 1.5 + 0.5 * class))
end

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
  notTonight = {
    easy = "Pinks? Not tonight. Ask me another night, I might be in the mood.",
    trash = "My car stays mine tonight. Money race, or wait for a night I'm feeling lucky.",
    roller = "Not tonight. When I put the car up, you'll hear about it.",
    careful = "Not tonight. I only race for cars when I've decided to.",
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
  beaten = {
    easy = "You had me last time. Give me a while, I'll text you when I want another go.",
    trash = "I'm not racing you again until I've sorted the car. You'll hear from me.",
    roller = "No. When I want a rematch, you'll get a text.",
    careful = "Not yet. I'll let you know when I'm ready to race you again.",
  },
}

local function line(kind, style, ...)
  local text = LINES[kind][style] or LINES[kind].easy
  if select('#', ...) > 0 and text:find('%%') then return string.format(text, ...) end
  return text
end

-- After a race (W3 rematch rule). A racer you beat will not race you again until they text for a rematch some
-- game hours later (racer.beaten; roughly half do, likelier after a narrow loss); a racer who beat you races you
-- again at once. Now and then one of them texts: a sore loser, or a winner's mockery.
M.TAUNT_CHANCE, M.REMATCH_CHANCE, M.REMATCH_NARROW = 0.4, 0.5, 0.75
M.NARROW_SECONDS = 3
local TAUNTS = {
  sore = {   -- they lost
    "You cut that corner. Everyone saw it.",
    "My tyres were gone. Wait till I've got new ones on.",
    "That wasn't a race, that was a traffic jam. Doesn't count.",
    "Cheater. I don't know how, but you cheated.",
    "I lifted for a cop. You didn't. Says it all.",
    "Missed a shift at the start. Won't happen twice.",
    "Nice car. Shame about the driver. Lucky driver.",
    "Nobody's going to hear about this. Nobody.",
    "You got the inside line because I let you. Enjoy it.",
    "Engine's down on power. Doesn't count, that.",
    "Your car's quicker. Mine's better. Big difference.",
    "I'll have that money back, don't you worry.",
  },
  mock = {   -- they won
    "Was that your race pace, or were you looking for a parking space?",
    "Thanks for the money. Petrol's not cheap.",
    "Next time bring a car.",
    "I had the radio on. Did you even start?",
    "Easy money. Call me again when you've found the throttle.",
    "You drive like my gran. She's faster, mind.",
    "Everyone's asking who the slow one was. I told them.",
    "Did you stop for a coffee halfway?",
    "Nice try. No, actually, it wasn't.",
    "Keep practising. I could use the money.",
    "You should see your face in my mirror. All race long.",
    "Lost by that much? Ouch. Same stakes next time?",
  },
}
local REMATCH = {
  "You got lucky. Rematch - same stakes or more. Text me when you're ready.",
  "That wasn't a real race. Again. Name the night.",
  "Everybody's talking about you beating me. I want that back. Rematch?",
  "Car's sorted. Fancy losing that money back to me?",
  "Right. I've had time to think about it. You and me, again.",
  "I want a rematch. Properly this time, no excuses.",
}
--   won: the player won; margin: seconds between the two cars (nil: not known); rng: an rng from sl/core/rng
-- Returns { taunt = text or nil, rematchIn = game hours or nil }
function M.afterRace(racer, won, margin, rng)
  local out = {}
  rng:next() rng:next()      -- (the first draw of a Park-Miller rng barely differs between neighbouring seeds)
  if rng:chance(M.TAUNT_CHANCE) then out.taunt = rng:pick(won and TAUNTS.sore or TAUNTS.mock) end
  if won then
    racer.beaten = true
    local narrow = tonumber(margin) ~= nil and math.abs(margin) < M.NARROW_SECONDS
    if rng:chance(narrow and M.REMATCH_NARROW or M.REMATCH_CHANCE) then out.rematchIn = rng:range(1, 6) end
  else
    racer.beaten = nil
  end
  return out
end
-- the rematch text: from then on they race you again
function M.rematchText(racer, rng)
  racer.beaten = nil
  return rng:pick(REMATCH)
end
M._TAUNTS, M._REMATCH = TAUNTS, REMATCH   -- (for the tests)

-- Pink slips are special: on any one night only a few of the racers who would ever bet their car
-- are up for it (a different few each night, the same all night). day: the career's day number.
M.PINK_NIGHT_CHANCE = 0.12
function M.pinkTonight(racer, day, seed)
  if not racer or not racer.pinkOK then return false end
  return rngLib.hash(racer.id .. ':pinks:' .. tostring(day) .. ':' .. tostring(seed or 0)) % 1000 < M.PINK_NIGHT_CHANCE * 1000
end

-- How a racer answers a challenge.
--   kind: 'race' (their usual stake) | 'high' (three times that) | 'pink' (cars)
--   player: { rep, money, hasCar, pinkTonight (this racer is up for pinks tonight: M.pinkTonight) }
--   rng: an rng from sl/core/rng (decides the stake within their range)
-- Returns { accept, stake = 'money'|'pink', bet, text, when }
function M.respond(racer, kind, player, rng)
  local when = racer.nightOnly and 'tonight' or 'any time'
  local floor = TIERS[racer.tier].rep[1] * 0.5           -- below this they will not take you seriously
  if (player.rep or 0) < floor then return { accept = false, text = line('nobody', racer.style) } end
  if not player.hasCar then return { accept = false, text = line('noCar', racer.style) } end
  if racer.beaten then return { accept = false, text = line('beaten', racer.style) } end   -- (until they text for a rematch)
  if kind == 'pink' then
    if not racer.pinkOK or (player.rep or 0) < TIERS[racer.tier].rep[1] then
      return { accept = false, text = line('noPink', racer.style) }
    end
    if not player.pinkTonight then return { accept = false, text = line('notTonight', racer.style) } end
    return { accept = true, stake = 'pink', bet = 0, when = 'tonight', text = line('yesPink', racer.style, 'tonight') }
  end
  local bet = round50(rng:range(racer.betMin, racer.betMax))
  if kind == 'high' then bet = bet * 3 end
  if (player.money or 0) < bet then return { accept = false, text = line('broke', racer.style, bet) } end
  return { accept = true, stake = 'money', bet = bet, when = when, text = line('yes', racer.style, bet, when) }
end

return M
