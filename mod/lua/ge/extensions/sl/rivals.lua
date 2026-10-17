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

local PERSONA_OF_STYLE = { easy = 'friendly', trash = 'cocky', roller = 'ruthless', careful = 'respectful' }
local STEP_KIND = { 'race', 'race', 'high', 'pink' }      -- the career's challenge kind for each step of the ladder
local ESCALATE_CHANCE, TAUNT_CHANCE, RESULT_TEXT_CHANCE = 0.35, 0.3, 0.7

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
  if not s or not racer then return nil end
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
  if not s then return end
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
    else
      rival.cooldown = s.day + rules.BOSS_COOLDOWN
      say(s, rival, 'bossl', 20)
    end
  elseif math.random() < RESULT_TEXT_CHANCE then
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
local OFFER_DAYS = 3
local function makeOffer(s, m, rival, isBoss)
  m.offers = m.offers or {}
  m.offers[rival.id] = { stake = 'pink', boss = isBoss or nil, day = s.day }
  say(s, rival, isBoss and 'bosscall' or 'escalate', 3)
end

local function offerView(s, m, rival)
  local o = m.offers and m.offers[rival.id]
  if not o then return nil end
  local mine = sl_fleet and sl_fleet.currentCar and sl_fleet.currentCar()
  local racer = racerOf(s, rival.id)
  return { stake = o.stake, boss = o.boss, myCar = mine and mine.name or nil, theirCar = racer and racer.car and racer.car.name or nil }
end

local function proactive(s, m)
  local rng = rngLib.new(rngLib.hash('rivalnight:' .. tostring(s.day) .. ':' .. tostring(s.seed)))
  -- 1. a boss asks for you
  local boss = not m.bossActive and rules.bossReady(m.list, s.rep, m.tierWins[rules.rank(m.list)] or 0, s.day)
  if boss and not activeChallenge(s, boss.id) then
    local racer = racerOf(s, boss.id)
    local sd = rules.showdown(boss, racer)
    if sd.stake == 'pink' then
      if not (m.offers and m.offers[boss.id]) then makeOffer(s, m, boss, true) return true end
    elseif (s.money or 0) >= sd.bet then
      local c = challenge(s, boss, 'high')
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
      if step >= 2 and not activeChallenge(s, rival.id) and rng:float() < ESCALATE_CHANCE then
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
  if pick and rules.allowed(m.list, pick.tier) and rng:float() < TAUNT_CHANCE then
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
  applyStages(s, m)
  for id, o in pairs(m.offers or {}) do if (s.day or 0) - (o.day or 0) > OFFER_DAYS then m.offers[id] = nil end end
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
  if not offer then toast(strings.t('rivals.no_offer')) return false end
  local mine = sl_fleet and sl_fleet.currentCar and sl_fleet.currentCar()
  if not mine then toast(strings.t('career.pink_slips_for_which_car')) return false end
  local c, answer = challenge(s, rival, 'pink')
  if not c then toast(answer and answer.text or strings.t('rivals.no_offer')) return false end
  c.boss = offer.boss
  if offer.boss then m.bossActive = rival.id end
  m.offers[rival.id] = nil
  toast(string.format(strings.t('rivals.pink_on'), mine.name or '?'))
  extensions.hook('onStreetLegalChanged')
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
  rival.meter = math.max(rules.METER[1], (rival.meter or 0) - 5)
  if forMoney then
    local racer = racerOf(s, rival.id)
    local bet = offer.boss and rules.showdown({ tier = 2 }, racer).bet or rules.stake(rival, racer, 2).bet
    if (s.money or 0) >= bet then
      local c = challenge(s, rival, 'high')
      if c then
        c.bet = bet
        if offer.boss then c.boss = true m.bossActive = rival.id end
      end
    else
      toast(string.format(strings.t('rivals.need_money'), bet))
    end
  end
  extensions.hook('onStreetLegalChanged')
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
    out[#out + 1] = { id = rival.id, name = racer and roster.displayName(racer) or rival.id, tier = rival.tier, boss = rival.boss or nil, nemesis = rival.nemesis or nil,
      beatenBoss = rival.bossBeaten or nil, crew = crewName(rival.crew), meter = rival.meter, word = rules.meterWord(rival.meter), beaten = rival.beaten, youLost = rival.youLost,
      stage = rival.stage, car = racer and racer.car and racer.car.name or nil, preview = info.preview, step = rules.step(rival), locked = not rules.allowed(m.list, rival.tier) or nil,
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
        line = role .. ((crewName(rival.crew)) and (' - ' .. crewName(rival.crew)) or '') }
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
  state(s)
  roster.gateHook = gate
end

function M.onStreetLegalStopped() roster.gateHook = nil end
function M.onExtensionUnloaded() roster.gateHook = nil end

return M
