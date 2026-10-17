-- Street Legal: the street racers of Valo City.
-- Made up from a seed when a career starts, so every career has its own crowd. Each racer is
-- a contact in the phone: a name, a number, how good they are, what they drive, how they talk
-- and what they will race for. Pure: no game calls (tested by tools/luatest.js).

local M = {}

local strings = require('sl/core/strings')

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
    easy = strings.t('roster.sorry_i_don_t_race'),
    trash = strings.t('roster.who_is_this_call_me'),
    roller = strings.t('roster.i_race_for_real_money'),
    careful = strings.t('roster.i_don_t_know_you'),
  },
  broke = {
    easy = strings.t('roster.that_s_more_than_you'),
    trash = strings.t('roster.with_what_money_come_back'),
    roller = strings.t('roster.can_t_cover_the_stake'),
    careful = strings.t('roster.you_d_need_d_up'),
  },
  noPink = {
    easy = strings.t('roster.pink_slips_nah_i_like'),
    trash = strings.t('roster.my_car_for_yours_have'),
    roller = strings.t('roster.not_this_week_money_race'),
    careful = strings.t('roster.i_don_t_race_for'),
  },
  notTonight = {
    easy = strings.t('roster.pinks_not_tonight_ask_me'),
    trash = strings.t('roster.my_car_stays_mine_tonight'),
    roller = strings.t('roster.not_tonight_when_i_put'),
    careful = strings.t('roster.not_tonight_i_only_race'),
  },
  noCar = {
    easy = strings.t('roster.you_haven_t_even_got'),
    trash = strings.t('roster.race_you_in_what_a'),
    roller = strings.t('roster.get_yourself_a_car_then'),
    careful = strings.t('roster.you_need_a_car_for'),
  },
  yes = {
    easy = strings.t('roster.you_re_on_d_s'),
    trash = strings.t('roster.easy_money_d_s_don'),
    roller = strings.t('roster.d_on_the_line_s'),
    careful = strings.t('roster.alright_d_s_clean_race'),
  },
  yesPink = {
    easy = strings.t('roster.pink_slips_it_is_s'),
    trash = strings.t('roster.your_car_s_going_to'),
    roller = strings.t('roster.now_we_re_talking_pinks'),
    careful = strings.t('roster.fine_pink_slips_s_don'),
  },
  beaten = {
    easy = strings.t('roster.you_had_me_last_time'),
    trash = strings.t('roster.i_m_not_racing_you'),
    roller = strings.t('roster.no_when_i_want_a'),
    careful = strings.t('roster.not_yet_i_ll_let'),
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
    strings.t('roster.you_cut_that_corner_everyone'),
    strings.t('roster.my_tyres_were_gone_wait'),
    strings.t('roster.that_wasn_t_a_race'),
    strings.t('roster.cheater_i_don_t_know'),
    strings.t('roster.i_lifted_for_a_cop'),
    strings.t('roster.missed_a_shift_at_the'),
    strings.t('roster.nice_car_shame_about_the'),
    strings.t('roster.nobody_s_going_to_hear'),
    strings.t('roster.you_got_the_inside_line'),
    strings.t('roster.engine_s_down_on_power'),
    strings.t('roster.your_car_s_quicker_mine'),
    strings.t('roster.i_ll_have_that_money'),
  },
  mock = {   -- they won
    strings.t('roster.was_that_your_race_pace'),
    strings.t('roster.thanks_for_the_money_petrol'),
    strings.t('roster.next_time_bring_a_car'),
    strings.t('roster.i_had_the_radio_on'),
    strings.t('roster.easy_money_call_me_again'),
    strings.t('roster.you_drive_like_my_gran'),
    strings.t('roster.everyone_s_asking_who_the'),
    strings.t('roster.did_you_stop_for_a'),
    strings.t('roster.nice_try_no_actually_it'),
    strings.t('roster.keep_practising_i_could_use'),
    strings.t('roster.you_should_see_your_face'),
    strings.t('roster.lost_by_that_much_ouch'),
  },
}
local REMATCH = {
  strings.t('roster.you_got_lucky_rematch_same'),
  strings.t('roster.that_wasn_t_a_real'),
  strings.t('roster.everybody_s_talking_about_you'),
  strings.t('roster.car_s_sorted_fancy_losing'),
  strings.t('roster.right_i_ve_had_time'),
  strings.t('roster.i_want_a_rematch_properly'),
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
-- sl_rivals: racers who have a pink slip offer open with the player are always up for it (a rival who offers must not then say 'not tonight')
M.pinkForced = {}
function M.pinkTonight(racer, day, seed)
  if racer and M.pinkForced[racer.id] then return true end
  if not racer or not racer.pinkOK then return false end
  return rngLib.hash(racer.id .. ':pinks:' .. tostring(day) .. ':' .. tostring(seed or 0)) % 1000 < M.PINK_NIGHT_CHANCE * 1000
end

-- How a racer answers a challenge.
--   kind: 'race' (their usual stake) | 'high' (three times that) | 'pink' (cars)
--   player: { rep, money, hasCar, pinkTonight (this racer is up for pinks tonight: M.pinkTonight) }
--   rng: an rng from sl/core/rng (decides the stake within their range)
-- Returns { accept, stake = 'money'|'pink', bet, text, when }
-- sl_rivals sets this: a function(racer) -> a text when the racer will not race you yet (the boss in front of their tier has not been beaten), else nil
M.gateHook = nil

function M.respond(racer, kind, player, rng)
  if M.gateHook then
    local gate = M.gateHook(racer)
    if gate then return { accept = false, text = gate } end
  end
  local when = racer.nightOnly and 'tonight' or strings.t('roster.any_time')
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
