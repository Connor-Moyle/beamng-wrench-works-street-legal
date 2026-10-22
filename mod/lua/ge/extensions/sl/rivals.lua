-- Wrench Works: Street Legal: named rivals (extension name: sl_rivals; rules in sl/core/rivals, design note to connor-62 2026-10-18)
-- Six of the career's racers are recurring characters: a boss for each tier and a nemesis. They text you in their own voice, challenge you at stakes that
-- climb with the races between you, remember how it went (the rivalry meter), get better cars, and the bosses stand between you and the next tier.
-- Their state is in the save (s.rivals); the racers themselves are the roster's (s.racers), so every existing race, call and pink-slip rule applies.

local M = {}

local strings = require('sl/core/strings')
local rules = require('sl/core/rivals')
local roster = require('sl/core/roster')
local stateLib = require('sl/core/state')
local crewsLib = require('sl/core/crews')
local rngLib = require('sl/core/rng')
local builds = require('sl/core/builds')
local tuning = require('sl/tuning')

local PERSONA_OF_STYLE = { easy = 'friendly', trash = 'cocky', roller = 'ruthless', careful = 'respectful' }
local STEP_KIND = { 'race', 'race', 'high', 'pink' }      -- the career's challenge kind for each step of the ladder
-- (the chances and day counts below are tuning: Mods menu > Street Legal: story and markets > Rivals; defaults are these)
local function tune(name, default) return tuning.get('rivals.' .. name, default) end
local function applyTuning()
  rules.BOSS_WINS = tune('bossWins', 3)
  rules.BOSS_COOLDOWN = tune('bossCooldown', 3)
  rules.STEP_RACES = tune('stepRaces', 3)
  rules.UPGRADE_DAYS = tune('upgradeDays', 5)
end
local function on() return tune('enabled', true) end

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end
local function night() return sl_career and sl_career.isNight and sl_career.isNight() end

local function state(s)
  local m = s.rivals
  if not m or not m.list or #m.list == 0 then
    m = { list = rules.generate(s.seed, s.racers or {}, crewsLib.CREWS), tierWins = {}, lastTextDay = -1 }
    for _, r in ipairs(m.list) do
      local racer = stateLib.racer(s, r.id)
      r.baseSkill = racer and racer.skill or 0.5
    end
    s.rivals = m
    rules.grandfather(m.list, s.rep)      -- (a save from before the rivals keeps the tiers its rep has reached)
  end
  return m
end

local function racerOf(s, id) return stateLib.racer(s, id) end
local function nameOf(s, rival) local r = racerOf(s, rival.id) return r and roster.displayName(r) or rival.id end
local function crewName(id) for _, c in ipairs(crewsLib.CREWS) do if c.id == id then return c.name end end end

-- where you are: the career place nearest to the player (a rival is 'met' where their first text or first race found you)
local function nearestPlace()
  local v = getPlayerVehicle and getPlayerVehicle(0)
  if not v then return nil end
  local here, best, bd = v:getPosition(), nil, 1e12
  for id, p in pairs(sl_career.getPlaces and sl_career.getPlaces() or {}) do
    if p.pos then
      local d = (vec3(p.pos.x, p.pos.y, p.pos.z) - here):squaredLength()
      if d < bd then best, bd = id, d end
    end
  end
  return best
end
local function markMet(rival) if not rival.metAt then rival.metAt = nearestPlace() end end

-- a text from a rival in their voice, a little after the event
local function say(s, rival, kind, delay, ...)
  local rng = rngLib.new(rngLib.hash(rival.id .. ':' .. kind .. ':' .. tostring(s.day) .. ':' .. tostring(rival.races or 0)))
  sl_career.sendText(rival.id, rules.text(rival, kind, rng, ...), delay or 4)
end

-- ---- the tier gate: a racer more than one tier above your rank sends you to the boss in front of them
local function gate(racer)
  local s = career()
  if not s or not racer or not on() then return nil end
  local m = state(s)
  local boss = rules.gatekeeper(m.list, racer.tier)
  if not boss then return nil end
  local rival = rules.byId(m.list, racer.id)
  local persona = rival and rival.persona or PERSONA_OF_STYLE[racer.style] or 'cool'
  local rng = rngLib.new(rngLib.hash(racer.id .. ':gate'))
  return rules.text({ persona = persona }, 'gate', rng, nameOf(s, boss))
end

-- ---- their cars: the stage follows the defeats and the days; applied to the racer's own car once it exists
local function applyStages(s, m)
  for _, rival in ipairs(m.list) do
    local racer = racerOf(s, rival.id)
    if racer then
      local st = rules.stageNow(rival, s.day)
      if st > (rival.stage or 0) then
        rival.stage = st
        racer.skill = rules.skillNow(rival.baseSkill, st)
        rival.upgradeToTell = true
      end
      if racer.car and not racer.car.setup then
        local want = math.max(builds.stageFor(racer.tier), rival.stage or 0)
        if (racer.car.stage or 0) < want then racer.car.stage = want end
      end
    end
  end
end

-- ---- a race against a racer is over
local pending
function M.onSlrrRaceFinished(r) pending = { margin = tonumber(r and r.margin), t = os.clock() } end

function M.onStreetLegalRaceResult(won, opponent, racerId, stake)
  local s = career()
  if not s or not on() then return end
  applyTuning()
  local m = state(s)
  local racer = racerOf(s, racerId)
  if not racer then return end
  if won then m.tierWins[racer.tier] = (m.tierWins[racer.tier] or 0) + 1 end
  local rival = rules.byId(m.list, racerId)
  if not rival then return end
  markMet(rival)
  local margin = pending and os.clock() - pending.t < 5 and pending.margin or nil
  pending = nil
  rules.recordRace(rival, won, margin, stake, s.day)
  if m.bossActive == rival.id then
    m.bossActive = nil
    if won then
      rival.bossBeaten = true
      stateLib.addRep(s, 25 * rival.tier)
      say(s, rival, 'bossw', 20)
      toast(string.format(strings.t('rivals.rank_up'), nameOf(s, rival), rules.rank(m.list)))
      if rules.rank(m.list) > 5 and not m.finale then      -- the last boss: the campaign's end (no ROC on every map); the street goes on
        m.finale = true
        sl_career.sendText('benny', strings.t('rivals.finale'), 40)
      end
    else
      rival.cooldown = s.day + rules.BOSS_COOLDOWN
      say(s, rival, 'bossl', 20)
    end
  elseif math.random() < tune('reactionChance', 0.7) then
    say(s, rival, won and 'won' or 'lost', 25)
  end
  local word = rules.meterWord(rival.meter)
  if (word == 'respect' or word == 'friends') and rules.firstTime(rival, 'respect') then say(s, rival, 'respect', 60) end
  applyStages(s, m)
  extensions.hook('onStreetLegalChanged')
end

-- ---- the night: at most one rival text a night (a boss calling you out, a first hello, a new exhaust, a bigger bet, a taunt or a word of respect)
local function activeChallenge(s, id)
  for _, c in ipairs(s.challenges or {}) do if c.racer == id then return c end end
end

local function challenge(s, rival, kind)
  s.known[rival.id] = true
  local answer = sl_career.challenge(rival.id, kind)
  return answer and answer.accept and answer.challenge or nil, answer
end

-- A pink slip race is never arranged by a rival on his own: it is an OFFER on the Rivals card, naming your car and his; you accept it, race for money instead, or walk away
-- (the meter drops a little, nothing else). The offer lapses after OFFER_DAYS.
local function offerDays() return tune('offerDays', 3) end
local function makeOffer(s, m, rival, isBoss)
  m.offers = m.offers or {}
  m.offers[rival.id] = { stake = 'pink', boss = isBoss or nil, day = s.day }
  roster.pinkForced[rival.id] = true
  local racer = racerOf(s, rival.id)
  if racer then racer.pinkOK = true end      -- (a rival who offers is up for it)
  say(s, rival, isBoss and 'bosscall' or 'escalate', 3)
end

local function offerView(s, m, rival)
  local o = m.offers and m.offers[rival.id]
  if not o then return nil end
  local mine = sl_fleet and sl_fleet.currentCar and sl_fleet.currentCar()
  local racer = racerOf(s, rival.id)
  local hunted
  if o.hunt then for _, c in ipairs(s.cars or {}) do if c.id == o.hunt then hunted = c.name end end end
  return { stake = o.stake, boss = o.boss, myCar = mine and mine.name or nil, theirCar = racer and racer.car and racer.car.name or nil, hunt = hunted, sweetener = o.sweetener }
end
-- the hunt (sl_rivalbeats): the rival wants the car you took back: an offer for that car, maybe with money on top for you
function M.offerHunt(rivalId, carId, sweetener)
  local s = career()
  local m = s and state(s)
  local rival = m and rules.byId(m.list, tostring(rivalId))
  if not rival then return false end
  m.offers = m.offers or {}
  m.offers[rival.id] = { stake = 'pink', hunt = carId, sweetener = sweetener, day = s.day }
  roster.pinkForced[rival.id] = true
  local racer = racerOf(s, rival.id)
  if racer then racer.pinkOK = true end
  extensions.hook('onStreetLegalChanged')
  return true
end
function M.hasOffer(rivalId) local s = career() local m = s and state(s) return m ~= nil and m.offers ~= nil and m.offers[tostring(rivalId)] ~= nil end
function M.dropOffer(rivalId) local s = career() local m = s and state(s) if m and m.offers then m.offers[tostring(rivalId)] = nil roster.pinkForced[tostring(rivalId)] = nil end end

local function proactive(s, m)
  local rng = rngLib.new(rngLib.hash('rivalnight:' .. tostring(s.day) .. ':' .. tostring(s.seed)))
  -- 1. a boss asks for you
  -- the wins that count are those over racers of the boss's tier or above (a player who races the tier above has earned the call just as well)
  local wins = 0
  for t = rules.rank(m.list), 5 do wins = wins + (m.tierWins[t] or 0) end
  local boss = not m.bossActive and rules.bossReady(m.list, s.rep, wins, s.day)
  if boss and not activeChallenge(s, boss.id) then
    local racer = racerOf(s, boss.id)
    local sd = rules.showdown(boss, racer)
    if sd.stake == 'pink' then
      if not (m.offers and m.offers[boss.id]) then makeOffer(s, m, boss, true) return true end
    elseif (s.money or 0) >= sd.bet then
      local c = challenge(s, boss, 'race')      -- (the showdown's bet is set below)
      if c then
        if sd.stake == 'money' then c.bet = sd.bet end
        c.boss = true
        m.bossActive = boss.id
        say(s, boss, 'bosscall', 3)
        return true
      end
    end
  end
  -- 2. a first hello from the ones you may race now
  for _, rival in ipairs(m.list) do
    if rules.allowed(m.list, rival.tier) and rules.firstTime(rival, 'intro') then
      s.known[rival.id] = true
      markMet(rival)
      say(s, rival, 'intro', 3)
      return true
    end
  end
  -- 3. a better car
  for _, rival in ipairs(m.list) do
    if rival.upgradeToTell and rules.allowed(m.list, rival.tier) then
      rival.upgradeToTell = nil
      say(s, rival, 'upgrade', 3)
      return true
    end
  end
  -- 4. a bigger bet from one you have raced a few times
  for _, rival in ipairs(m.list) do
    if rules.allowed(m.list, rival.tier) and (not rival.boss or rival.bossBeaten) then      -- (a boss has his showdown first)
      local step = rules.step(rival)
      if step >= 2 and not activeChallenge(s, rival.id) and rng:float() < tune('escalateChance', 0.35) then
        if STEP_KIND[step] == 'pink' then
          if not (m.offers and m.offers[rival.id]) and sl_fleet and sl_fleet.currentCar and sl_fleet.currentCar() then makeOffer(s, m, rival, false) return true end
        else
          local c = challenge(s, rival, STEP_KIND[step])
          if c then say(s, rival, 'escalate', 3) return true end
        end
      end
    end
  end
  -- 5. a taunt, or a word of respect
  local pick = m.list[rng:int(#m.list)]
  if pick and rules.allowed(m.list, pick.tier) and (pick.beaten or 0) + (pick.youLost or 0) > 0 and rng:float() < tune('tauntChance', 0.3) then      -- (a taunt presumes a past race)
    local w = rules.meterWord(pick.meter)
    say(s, pick, (w == 'respect' or w == 'friends') and 'respect' or 'taunt', 3)
    return true
  end
  return false
end

local timer = 0
function M.onUpdate(dtReal)
  timer = timer + (dtReal or 0)
  if timer < 8 then return end
  timer = 0
  local s = career()
  if not s then return end
  local m = state(s)
  if not on() then return end
  applyTuning()
  applyStages(s, m)
  for id, o in pairs(m.offers or {}) do if (s.day or 0) - (o.day or 0) > offerDays() then m.offers[id] = nil roster.pinkForced[id] = nil end end
  if night() and m.lastTextDay ~= s.day and #(s.cars or {}) > 0 and not (sl_streets and sl_streets.raceActive and sl_streets.raceActive()) then
    m.lastTextDay = s.day
    pcall(proactive, s, m)
  end
end

-- ---- the player's answer to a pink slip offer
function M.accept(id)
  local s = career()
  local m = s and state(s)
  local rival = m and rules.byId(m.list, tostring(id))
  local offer = rival and m.offers and m.offers[rival.id]
  if not offer then toast(strings.t('rivals.no_offer')) M.list() return false end
  local mine = sl_fleet and sl_fleet.currentCar and sl_fleet.currentCar()
  if not mine then toast(strings.t('career.pink_slips_for_which_car')) return false end
  if offer.hunt and sl_rivalbeats and sl_rivalbeats.canAcceptHunt then      -- (the hunt: only in the car they want)
    local okh, why = sl_rivalbeats.canAcceptHunt(rival.id, mine.id)
    if okh == false then toast(why) return false end
  end
  local c, answer = challenge(s, rival, 'pink')
  if not c then toast(answer and answer.text or strings.t('rivals.no_offer')) return false end
  c.boss = offer.boss
  if offer.boss then m.bossActive = rival.id end
  if offer.hunt then c.hunt = offer.hunt if sl_rivalbeats and sl_rivalbeats.huntAccepted then sl_rivalbeats.huntAccepted(rival.id) end end
  m.offers[rival.id] = nil
  roster.pinkForced[rival.id] = nil
  toast(string.format(strings.t('rivals.pink_on'), mine.name or '?'))
  extensions.hook('onStreetLegalChanged')
  M.list()      -- (the open Rivals card drops the offer buttons)
  return true
end

-- decline: for money instead (a race at the top bet, which is also the showdown for a boss) or just walk away; either way only the meter pays
function M.decline(id, forMoney)
  local s = career()
  local m = s and state(s)
  local rival = m and rules.byId(m.list, tostring(id))
  local offer = rival and m.offers and m.offers[rival.id]
  if not offer then return false end
  m.offers[rival.id] = nil
  roster.pinkForced[rival.id] = nil
  rival.meter = math.max(rules.METER[1], (rival.meter or 0) - 5)
  if offer.hunt then if sl_rivalbeats and sl_rivalbeats.huntLapsed then sl_rivalbeats.huntLapsed(rival.id) end forMoney = false end      -- (the hunt is the car or nothing)
  toast(strings.t(forMoney and 'rivals.for_money' or 'rivals.walked_away'))
  if forMoney then
    local racer = racerOf(s, rival.id)
    local bet = offer.boss and rules.showdown({ tier = 2 }, racer).bet or rules.stake(rival, racer, 2).bet
    if (s.money or 0) >= bet then
      local c = challenge(s, rival, 'race')      -- (a plain race: the stake is set below, so a poor player is not refused for 'high' = three times a bet)
      if c then
        c.bet = bet
        if offer.boss then c.boss = true m.bossActive = rival.id end
      end
    else
      toast(string.format(strings.t('rivals.need_money'), bet))
    end
  end
  extensions.hook('onStreetLegalChanged')
  M.list()      -- (the open Rivals card drops the offer buttons)
  return true
end

-- ---- what the screens see
function M.list()
  local s = career()
  if not s then return {} end
  local m = state(s)
  local out = {}
  for _, rival in ipairs(m.list) do
    local racer = racerOf(s, rival.id)
    local info = racer and racer.car and racer.car.model and require('sl/carInfo').of({ id = 'rival:' .. rival.id, model = racer.car.model, config = racer.car.config }) or {}
    local met = s.known[rival.id]
    local gateBoss = rules.gatekeeper(m.list, rival.tier)
    out[#out + 1] = { id = rival.id, name = met and racer and roster.displayName(racer) or (met and rival.id or strings.t('rivals.unknown')), tier = rival.tier, boss = rival.boss or nil, nemesis = rival.nemesis or nil,
      beatenBoss = rival.bossBeaten or nil, crew = met and crewName(rival.crew) or nil, meter = rival.meter, word = rules.meterWord(rival.meter), beaten = rival.beaten, youLost = rival.youLost,
      stage = rival.stage, car = met and racer and racer.car and racer.car.name or nil, preview = met and info.preview or nil, step = rules.step(rival), locked = gateBoss and nameOf(s, gateBoss) or nil,
      known = s.known[rival.id] or nil, offer = offerView(s, m, rival) }
  end
  local result = { rivals = out, rank = rules.rank(m.list) }
  guihooks.trigger('slRivals', result)
  return result
end

-- for the phone's Contacts (connor-9e): the rivals you have met, { id, name, kind = 'rival', line, placeId }
function M.met()
  local s = career()
  local out = {}
  if not s then return out end
  for _, rival in ipairs(state(s).list) do
    if s.known[rival.id] then
      local racer = racerOf(s, rival.id)
      local role = rival.boss and (strings.t('rivals.boss_star') .. ' ' .. rival.tier) or strings.t('rivals.nemesis')
      out[#out + 1] = { id = rival.id, name = racer and roster.displayName(racer) or rival.id, kind = 'rival', placeId = rival.metAt,
        line = role .. ((crewName(rival.crew)) and (' · ' .. crewName(rival.crew)) or '') }
    end
  end
  return out
end

-- for sl_streets' cruiser pick: now and then the nemesis cruises the night (their own car, recognisable: the roster's racer.car with its paint and stage), once they have written to you
function M.nemesisToCruise(list, rng)
  local s = career()
  if not s or not rng then return nil end
  for _, rival in ipairs(state(s).list) do
    if rival.nemesis and s.known[rival.id] and rules.allowed(state(s).list, rival.tier) then
      for _, r in ipairs(list or {}) do
        if r.id == rival.id and rng:chance(0.25) then return r end
      end
    end
  end
end

function M.rank() local s = career() return s and rules.rank(state(s).list) or 1 end

function M.onStreetLegalStarted()
  local s = career()
  if not s then return end
  local m = state(s)
  roster.gateHook = gate
  for id in pairs(m.offers or {}) do roster.pinkForced[id] = true end      -- (an offer made before the save)
end

function M.onStreetLegalStopped() roster.gateHook = nil roster.pinkForced = {} end
function M.onExtensionUnloaded() roster.gateHook = nil roster.pinkForced = {} end

return M
