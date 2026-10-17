-- Street Legal: named rivals (design note to connor-62 2026-10-18). Pure rules, no game calls; tested by tools/luatest.js.
-- Six of the roster become recurring characters: the best racer of each tier is that tier's BOSS, and one more from tier 2-3 is the NEMESIS who follows you.
-- They keep what the roster lacks: a persona (how they text), a crew, a car that gets better, and a rivalry meter (-100 bad blood .. +100 respect).
-- Your RANK is 1 + the bosses you have beaten; racers more than one tier above your rank will not race you until you have beaten the boss in front of them.

local strings = require('sl/core/strings')
local rngLib = require('sl/core/rng')
local roster = require('sl/core/roster')

local M = {}

M.PERSONAS = { 'cocky', 'cool', 'friendly', 'ruthless', 'respectful', 'chaotic' }
M.KINDS = { 'intro', 'taunt', 'won', 'lost', 'upgrade', 'escalate', 'respect', 'bosscall', 'bossw', 'bossl', 'gate' }
M.LINES_PER = 2              -- strings 'rivals.<persona>.<kind>_<1..LINES_PER>'
M.METER = { -100, 100 }
M.MAX_STAGE = 3
M.NARROW_SECONDS = 3         -- a win by less is a close race: respect
M.UPGRADE_DAYS = 5           -- a rival's car gets a stage better this often, and after every defeat by you
M.BOSS_WINS = 3              -- wins over racers of the tier before its boss asks for you
M.BOSS_COOLDOWN = 3          -- days after losing to a boss
M.STEP_RACES = 3             -- races between you and a rival per step of the stake ladder
M.HIGH_STAKES = 2.5          -- of the top bet, on the third step
M.PINK_TIER = 4              -- from this tier a rival will put a car on the line (the 4th step), or at -60 bad blood
M.PINK_BLOOD = -60

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

-- the six: seeded from the career; racers = roster.generate's list, crews = sl/core/crews.CREWS ({ id, name })
function M.generate(seed, racers, crews)
  local rng = rngLib.new(rngLib.hash('rivals:' .. tostring(seed)))
  local pick, taken = {}, {}
  for tier = 1, 5 do
    local best
    for _, r in ipairs(racers) do
      if r.tier == tier and (not best or r.skill > best.skill or (r.skill == best.skill and r.id < best.id)) then best = r end
    end
    if best then pick[#pick + 1] = { racer = best, boss = true } taken[best.id] = true end
  end
  local pool = {}
  for _, r in ipairs(racers) do if (r.tier == 2 or r.tier == 3) and not taken[r.id] then pool[#pool + 1] = r end end
  table.sort(pool, function(a, b) return a.id < b.id end)
  if #pool > 0 then pick[#pick + 1] = { racer = pool[rng:int(#pool)], nemesis = true } end
  local personas = {}
  for i, p in ipairs(M.PERSONAS) do personas[i] = p end
  for i = #personas, 2, -1 do local j = rng:int(i) personas[i], personas[j] = personas[j], personas[i] end
  local list = {}
  for i, p in ipairs(pick) do
    list[i] = { id = p.racer.id, tier = p.racer.tier, boss = p.boss or nil, nemesis = p.nemesis or nil, persona = personas[((i - 1) % #personas) + 1],
      crew = crews and #crews > 0 and crews[rng:int(#crews)].id or nil, stage = 0, paint = rng:int(1, 9999), meter = 0,
      races = 0, beaten = 0, youLost = 0, told = {}, cooldown = 0 }
  end
  return list
end

function M.byId(list, id) for _, r in ipairs(list or {}) do if r.id == id then return r end end end
function M.bossOfTier(list, tier) for _, r in ipairs(list or {}) do if r.boss and r.tier == tier then return r end end end

-- your rank: 1 + the bosses beaten
function M.rank(list)
  local n = 1
  for _, r in ipairs(list or {}) do if r.boss and r.bossBeaten then n = n + 1 end end
  return n
end

-- a save from before the rivals (or any career whose rep is already high): the tiers its rep reaches are open, their bosses count as beaten, so nobody is locked
-- out of races they could already do. Returns the rank.
function M.grandfather(list, rep)
  local mine = 1
  for t, def in ipairs(roster.TIERS) do if (rep or 0) >= def.rep[1] then mine = t end end
  for _, r in ipairs(list or {}) do if r.boss and r.tier < mine then r.bossBeaten, r.grandfathered = true, true end end
  return M.rank(list)
end

-- may you race a racer of this tier: not more than one above your rank
function M.allowed(list, tier) return (tier or 1) <= M.rank(list) + 1 end

-- the boss you have to beat to get at this tier (nil when you may)
function M.gatekeeper(list, tier)
  if M.allowed(list, tier) then return nil end
  return M.bossOfTier(list, M.rank(list))
end

-- the next boss asks for you: it is the boss of the tier = your rank, once you have the rep for the tier and enough wins in it
function M.bossReady(list, rep, winsInTier, day)
  local boss = M.bossOfTier(list, M.rank(list))
  if not boss or boss.bossBeaten or (boss.cooldown or 0) > (day or 0) then return nil end
  local floor = roster.TIERS[boss.tier] and roster.TIERS[boss.tier].rep[1] or 0
  if (rep or 0) >= floor and (winsInTier or 0) >= M.BOSS_WINS then return boss end
end

-- the meter after a race against them. won: you won; margin: seconds; stake: 'money' | 'pink'. Close wins win respect; a big win humiliates the proud ones;
-- a loss makes the cocky and the ruthless gloat (bad blood) and the others respect you for trying
local PROUD = { cocky = true, ruthless = true }
function M.meterAfter(rival, won, margin, stake)
  local d
  if won then
    if (margin or 99) <= M.NARROW_SECONDS then d = 8 elseif PROUD[rival.persona] then d = -10 else d = 4 end
  else
    d = PROUD[rival.persona] and -4 or 2
  end
  if stake == 'pink' then d = d * 3 end
  return clamp((rival.meter or 0) + d, M.METER[1], M.METER[2])
end

function M.meterWord(meter)
  if meter <= -60 then return 'blood' elseif meter <= -20 then return 'rivals' elseif meter < 30 then return 'neutral' elseif meter < 70 then return 'respect' end
  return 'friends'
end

-- a race happened: updates the record
function M.recordRace(rival, won, margin, stake, day)
  rival.races = (rival.races or 0) + 1
  if won then rival.beaten = (rival.beaten or 0) + 1 else rival.youLost = (rival.youLost or 0) + 1 end      -- (beaten: the times you beat them; their car gets better after each)
  rival.meter = M.meterAfter(rival, won, margin, stake)
  rival.lastDay = day
end

-- the stake ladder: step 1 pocket money, 2 their top bet, 3 high stakes, 4 pink slips (top tiers or bad blood)
function M.step(rival)
  local s = 1 + math.floor((rival.races or 0) / M.STEP_RACES)
  local canPink = (rival.tier or 1) >= M.PINK_TIER or (rival.meter or 0) <= M.PINK_BLOOD
  return math.min(s, canPink and 4 or 3)
end

-- what a rival puts up at a step: { stake = 'money'|'pink', bet }
function M.stake(rival, racer, step)
  step = step or M.step(rival)
  local lo, hi = racer.betMin or 100, racer.betMax or 300
  if step <= 1 then return { stake = 'money', bet = math.floor((lo + (hi - lo) * 0.3) / 50 + 0.5) * 50 } end
  if step == 2 then return { stake = 'money', bet = hi } end
  if step == 3 then return { stake = 'money', bet = math.floor(hi * M.HIGH_STAKES / 50 + 0.5) * 50 } end
  return { stake = 'pink', bet = 0 }
end

-- the boss's showdown: twice the tier's top bet, pink slips at the top tier
function M.showdown(rival, racer)
  if (rival.tier or 1) >= 5 then return { stake = 'pink', bet = 0 } end
  return { stake = 'money', bet = math.floor((racer.betMax or 300) * 2 / 50 + 0.5) * 50 }
end

-- their car: a stage better after each defeat by you and every UPGRADE_DAYS days, to what the tier allows; the skill follows
local STAGE_CAP = { 1, 2, 3, 3, 3 }
function M.stageNow(rival, day)
  local want = (rival.beaten or 0) + math.floor((day or 0) / M.UPGRADE_DAYS)
  return math.min(want, STAGE_CAP[rival.tier or 1] or M.MAX_STAGE, M.MAX_STAGE)
end
function M.skillNow(racerSkill, stage) return math.min(0.99, math.floor(((racerSkill or 0.3) + 0.02 * (stage or 0)) * 100 + 0.5) / 100) end

-- a line in their voice: kind (M.KINDS), a number picks the variant (rng for a random one); a rival never answers with an empty string
function M.text(rival, kind, rng, ...)
  local n = rng and rng:int(M.LINES_PER) or 1
  local key = 'rivals.' .. (rival.persona or 'cool') .. '.' .. kind .. '_' .. n
  local text = strings.t(key)
  if text == key then text = strings.t('rivals.cool.' .. kind .. '_1') end
  if select('#', ...) > 0 and text:find('%%') then return string.format(text, ...) end
  return text
end

-- tell each story beat once: told[key]
function M.firstTime(rival, key) if rival.told[key] then return false end rival.told[key] = true return true end

return M
