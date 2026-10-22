-- Street Legal: car theft's rules (Graph docs/CAR_THEFT.md). Pure, no game calls: tested by tools/luatest.js.
-- The era of a car from its years (the game has no lock, key or immobiliser data), what each era needs (a tool), how hard and how long the
-- break-in is (the mini-games' numbers, 9e's screens read them), the noise and the witnesses, the stolen-vehicle tracker, the plates rule,
-- what a stolen car is worth to the fence and what the black market asks, and the five pursuit deliveries. The game side is sl/theft.lua.
-- Every number in CAPITALS is a Mods menu row (sl/balance sets it; the defaults are the design's).

local M = {}

local strings = require('sl/core/strings')
local rng = require('sl/core/rng')

-- ---- eras
M.ERAS = { 'old', 'mid', 'modern' }
M.MID_FROM, M.MODERN_FROM, M.PRESTIGE_MODERN_FROM = 1990, 2010, 2000
-- a few stock models without Years in their files (model or config): the year we take for them
M.MODEL_YEARS = { etki = 1988, moonhawk = 1973, miramar = 1965, pigeon = 1988, wendover = 1990, hopper = 1990, roamer = 2002, pickup = 1990, van = 1988, vivace = 2015, scintilla = 2014, sunburst2 = 2020, lansdale = 1996, midsize = 1995, legran = 1990, pessima = 1990, sbr = 2010, bastion = 2016, etkc = 2015, etk800 = 2013, bx = 1990, covet = 1986, autobello = 1957, barstow = 1969, bluebuck = 1962, bolide = 1981, burnside = 1952, fullsize = 1990, utv = 2018, atv = 2008 }
function M.year(configYears, modelYears, model)
  local y = type(configYears) == 'table' and tonumber(configYears.min) or nil
  y = y or (type(modelYears) == 'table' and tonumber(modelYears.min)) or M.MODEL_YEARS[model]
  return y
end
function M.era(year, prestige)
  if not year then return 'old' end
  if year >= M.MODERN_FROM or (prestige and year >= M.PRESTIGE_MODERN_FROM) then return 'modern' end
  if year >= M.MID_FROM then return 'mid' end
  return 'old'
end

-- ---- tools (the fence sells them; a tool with uses runs down; the player inventory, when it lands, carries them as `tool` items with `uses`)
M.TOOL_PRICE_X, M.TOOL_USES_X = 1, 1
M.TOOLS = {
  { id = 'slimjim', title = 'Slim jim', price = 40, uses = nil, era = 'old', optional = true },      -- (old cars open without it, slower)
  { id = 'bypass', title = 'Bypass box', price = 600, uses = 10, era = 'mid' },
  { id = 'relay', title = 'Relay kit', price = 2500, uses = 6, era = 'modern' },
  { id = 'cloner', title = 'Cloning tool', price = 6000, uses = nil, era = 'modern', slower = 3 },
  { id = 'finder', title = 'Tracker finder', price = 450, uses = 3, kind = 'tracker' },      -- (the search for the tracker goes faster)
  { id = 'jammer', title = 'Jammer', price = 900, uses = 4, kind = 'tracker' },             -- (the tracker is silent for a while)
}
local function round10(x) return math.floor(x / 10 + 0.5) * 10 end
-- a tool's definition with the menu's price and uses factors applied
function M.tool(id)
  for _, t in ipairs(M.TOOLS) do
    if t.id == id then
      local c = {}
      for k, v in pairs(t) do c[k] = v end
      c.price = round10(t.price * M.TOOL_PRICE_X)
      c.uses = t.uses and math.max(1, math.floor(t.uses * M.TOOL_USES_X + 0.5)) or nil
      return c
    end
  end
  return nil
end
-- what an era needs: the tool ids that do (any one); nil = nothing needed
function M.needs(era)
  if era == 'mid' then return { 'bypass' } end
  if era == 'modern' then return { 'relay', 'cloner' } end
  return nil
end
-- the tool the player holds for the era (with uses left), or nil; `owned` = { [id] = { uses } }
function M.toolFor(era, owned)
  for _, id in ipairs(M.needs(era) or {}) do
    local o = owned and owned[id]
    if o and (o.uses == nil or o.uses > 0) then return id end
  end
  return nil
end
function M.has(owned, id) local o = owned and owned[id] return o ~= nil and (o.uses == nil or o.uses > 0) end
function M.useTool(owned, id)
  local o = owned and owned[id]
  if o and o.uses then o.uses = math.max(0, o.uses - 1) end
  return o
end
-- a bought tool joins the kit: uses stack
function M.giveTool(owned, id)
  local t = M.tool(id)
  if not t then return nil end
  local o = owned[id]
  owned[id] = { uses = t.uses and ((o and o.uses or 0) + t.uses) or nil }
  return owned[id]
end

-- ---- the mini-games' numbers by era and class (the screens read these; the autoplay rolls on them)
-- stages: old = lock, wires; mid = lock, box, wires; modern = fob. value: the car's value new.
M.PRESTIGE_VALUE = 40000
M.SECONDS_OLD, M.SECONDS_MID, M.SECONDS_MODERN = 25, 40, 60
M.CHANCE_OLD, M.CHANCE_MID, M.CHANCE_MODERN = 0.85, 0.7, 0.55
function M.difficulty(era, value, prestige, retry)
  local rich = prestige or (tonumber(value) or 0) >= M.PRESTIGE_VALUE
  local d
  if era == 'old' then d = { stages = { 'lock', 'wires' }, pins = rich and 5 or 4, wires = rich and 7 or 5, cut = 3, seconds = M.SECONDS_OLD + (rich and 10 or 0), chance = M.CHANCE_OLD - (rich and 0.15 or 0) }
  elseif era == 'mid' then d = { stages = { 'lock', 'box', 'wires' }, pins = 6, wires = 7, cut = 3, seconds = M.SECONDS_MID + (rich and 10 or 0), chance = M.CHANCE_MID - (rich and 0.15 or 0) }
  else d = { stages = { 'fob' }, windows = rich and 1 or 2, sliders = 3, seconds = M.SECONDS_MODERN + (rich and 15 or 0), chance = M.CHANCE_MODERN - (rich and 0.15 or 0) } end
  if retry then d.pins = (d.pins or 0) + 1 d.seconds = d.seconds + 10 d.chance = d.chance * 0.8 d.windows = d.windows and math.max(1, d.windows - 1) or nil end
  d.chance = math.max(0.05, d.chance)
  d.era, d.prestige = era, rich
  return d
end

-- ---- noise and witnesses
M.NOISE_PIN, M.NOISE_WIRE = 0.12, 0.2
M.NOISE = { crank = 0.15, fail = 0.5 }
M.WITNESS_AT, M.ALARM_AT = 0.5, 1
M.WITNESS_S, M.ALARM_S, M.WITNESS_M = 30, 20, 40
function M.noiseAfter(noise, event)
  local add = event == 'pin' and M.NOISE_PIN or event == 'wire' and M.NOISE_WIRE or M.NOISE[event] or 0
  return math.min(1, (noise or 0) + add)
end
-- a witness: people about, the noise past the mark (half the mark by day)
function M.witness(noise, peopleAbout, isDay) return peopleAbout == true and (noise or 0) >= (isDay and M.WITNESS_AT / 2 or M.WITNESS_AT) end
function M.alarm(noise) return (noise or 0) >= M.ALARM_AT end
-- the same two rules in one answer (ba's fuel siphoning asks this)
function M.exposure(noise, peopleAbout, isDay) return { witness = M.witness(noise, peopleAbout, isDay), alarm = M.alarm(noise) } end
-- the placeholder result while the screens are not there (the autoplay switch): a roll against the chance, the noise it made
function M.autoplay(d, roll)
  local ok = (roll or 1) < (d.chance or 0.5)
  local noise = ok and (0.2 + (1 - d.chance) * 0.5) or 1
  return ok, noise
end
-- a second try on the same car within an hour is a step harder
M.RETRY_S = 3600
M.STOOD_S, M.REACH_M, M.PATROL_M = 10, 60, 300      -- a traffic car counts once it has stood still this long; the prompt's reach on foot; the alarm's patrol reach

-- ---- the stolen-vehicle tracker (Connor: "like it was a car being tracked by the cops"): the chance a car carries one rises with the era
-- and the value, and with how loud the break-in was; while it is on, the police are sent to the car every TRACK_RESEND_S, the first
-- time TRACK_S after driving off. Out: pull it (a timed search in the car, faster with the finder), the jammer (silent for JAM_S), the fence.
M.TRACKER_OLD, M.TRACKER_MID, M.TRACKER_MODERN, M.TRACKER_PRESTIGE = 0.05, 0.25, 0.6, 0.2
M.TRACK_S, M.TRACK_RESEND_S = 8, 30
M.PULL_S, M.PULL_FINDER_X, M.JAM_S = 45, 0.4, 120
-- f = { noise 0..1, alarm, day, witness, patrol }: the break-in's exposure
function M.trackerChance(era, prestige, f)
  f = f or {}
  local c = era == 'modern' and M.TRACKER_MODERN or era == 'mid' and M.TRACKER_MID or M.TRACKER_OLD
  if prestige then c = c + M.TRACKER_PRESTIGE end
  c = c + (f.noise or 0) * 0.15 + (f.alarm and 0.25 or 0) + (f.day and 0.1 or 0) + (f.witness and 0.15 or 0) + (f.patrol and 0.1 or 0)
  return math.min(0.95, math.max(0.02, c))      -- (never zero: a clean theft at night can still be a tracked car)
end
function M.tracked(era, prestige, f, roll) return (roll or 1) < M.trackerChance(era, prestige, f) end
function M.pullSeconds(hasFinder) return hasFinder and M.PULL_S * M.PULL_FINDER_X or M.PULL_S end
-- the police are called to a tracked car again: not while jammed, and TRACK_RESEND_S after the last call
function M.trackerDue(rec, now)
  return rec.tracked == true and (rec.jammedUntil or 0) <= now and (now - (rec.lastTrack or -1e9)) >= M.TRACK_RESEND_S
end

-- ---- the stolen car
function M.stolenRecord(car, era, day, reported)
  return { model = car.model, config = car.config, name = car.name, value = tonumber(car.value) or 0, era = era, day = day, reported = reported == true, plated = false, resprayed = false }
end
M.REPORT_DAYS = 1                     -- unreported: the owner notices after a day
function M.reportedBy(rec, day) return rec.reported or (day - (rec.day or day)) >= M.REPORT_DAYS end
-- a hot car stops being wanted once it is BOTH resprayed AND on bought plates (Connor's rule; a normal wanted car keeps P9's either-or)
function M.legal(rec) return rec.resprayed == true and rec.plated == true end

-- ---- plates: every career car keeps its plate text; a new plate is bought, $300 for a normal car, $700 for a stolen one
M.PLATE_LEGAL, M.PLATE_STOLEN = 300, 700
function M.platePrice(stolen) return stolen and M.PLATE_STOLEN or M.PLATE_LEGAL end
local LETTERS = 'ABCDEFGHJKLMNPRSTUVWXYZ'      -- (no I, O, Q: they read as digits)
function M.plateText(seed)
  local h = rng.hash(seed)
  local out = {}
  for _ = 1, 3 do local i = h % #LETTERS + 1 out[#out + 1] = LETTERS:sub(i, i) h = math.floor(h / #LETTERS) end
  return table.concat(out) .. ' ' .. string.format('%03d', h % 1000)
end

-- ---- the fence: sell (a fifth hot, half once legal: the sim showed a third paid twice any job), strip (40 % plus a used part of it), new plates ($700), a title (15 %, at least $400), the tracker out
M.SELL_HOT, M.SELL_PLATED, M.STRIP, M.TITLE_SHARE, M.TITLE_MIN, M.TRACKER_STRIP = 0.2, 0.5, 0.4, 0.15, 400, 350
function M.sellPrice(rec) return round10((rec.value or 0) * (M.legal(rec) and M.SELL_PLATED or M.SELL_HOT)) end
function M.stripPay(rec) return round10((rec.value or 0) * M.STRIP) end
function M.platesPrice() return M.PLATE_STOLEN end
function M.titlePrice(rec) return math.max(M.TITLE_MIN, round10((rec.value or 0) * M.TITLE_SHARE)) end
-- the car a stolen one becomes with a title: a fleet record with a history line and a resale cut
function M.titled(rec) return { model = rec.model, config = rec.config, name = rec.name, value = math.floor((rec.value or 0) * 0.7), condition = 0.8, history = strings.t('theft.history_line'), plate = rec.plate } end

-- ---- the black market: stolen cars sold cheap at night; a car bought there is hot (wanted) until resprayed and plated, and may be tracked
M.MARKET_SHARE, M.MARKET_COUNT = 0.45, 3
function M.marketPrice(value) return round10((tonumber(value) or 0) * M.MARKET_SHARE) end
-- the day's cars from a pool of { model, config, name, value, era, prestige }: the same for the same day and seed
function M.blackMarketList(pool, day, seed)
  local r = rng.new(rng.hash(tostring(seed or 0) .. ':' .. tostring(day or 0) .. ':market'))
  local list, used = {}, {}
  for _ = 1, math.min(M.MARKET_COUNT, #pool) do
    local i = r:int(#pool)
    while used[i] do i = i % #pool + 1 end
    used[i] = true
    local c = pool[i]
    list[#list + 1] = { model = c.model, config = c.config, name = c.name, value = c.value, era = c.era, prestige = c.prestige == true,
      price = M.marketPrice(c.value), tracked = M.tracked(c.era, c.prestige, nil, r:float()) }
  end
  return list
end

-- ---- fair game: never the player's, a lot's or a meet's car, a police car, a car with its engine running or moving, nobody's seat taken
function M.fairGame(f)
  f = f or {}
  if f.own or f.lot or f.meet or f.police or f.player then return false, 'own' end
  if f.engineOn or (f.speed or 0) > 0.5 then return false, 'running' end
  return true
end

-- ---- the five pursuit deliveries (the jobs board; the chase starts at heat 4 the moment you drive off)
M.DELIVERY_UNLOCK = 1000
M.DELIVERY_HEAT, M.DELIVERY_PAY_X = 0.75, 1
M.DELIVERIES = {
  { id = 'showroom', title = 'The showroom car', from = 'dealer', car = { era = 'modern', models = { 'scintilla', 'bastion', 'etkc' } }, share = 0.3, alarm = true, after = 3 },
  { id = 'longway', title = 'The long way round', from = 'quarry', car = { era = 'old', models = { 'barstow', 'moonhawk', 'bluebuck' } }, share = 0.2, minMetres = 5000 },
  { id = 'handoff', title = 'The hand-off', from = 'kerb', car = { era = 'mid', models = { 'pessima', 'legran', 'fullsize' } }, swap = { models = { 'covet', 'sunburst2', 'vivace' } }, share = 0.25, clean = true },
  { id = 'tow', title = 'The tow', from = 'kerb', car = { era = 'old', models = { 'burnside', 'autobello', 'miramar' }, limp = 0.15 }, tow = true, share = 0.2 },
  { id = 'decoy', title = 'The decoy', from = 'kerb', car = { era = 'mid', models = { 'midsize', 'lansdale', 'bx' } }, wash = true, tracked = true, share = 0.15 },      -- (the car starts tracked; the wash leg pulls the tracker)
}
function M.delivery(id) for _, d in ipairs(M.DELIVERIES) do if d.id == id then return d end end return nil end
-- which deliveries are open: the showroom one after three done
function M.openDeliveries(done)
  local out = {}
  for _, d in ipairs(M.DELIVERIES) do if not d.after or (done or 0) >= d.after then out[#out + 1] = d end end
  return out
end
function M.deliveryPay(d, value) return math.max(400, math.floor((tonumber(value) or 0) * d.share * M.DELIVERY_PAY_X / 100 + 0.5) * 100) end

return M
