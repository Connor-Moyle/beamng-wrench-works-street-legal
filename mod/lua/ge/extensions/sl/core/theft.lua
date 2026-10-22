-- Street Legal: car theft's rules (Graph docs/CAR_THEFT.md). Pure, no game calls: tested by tools/luatest.js.
-- The era of a car from its years (the game has no lock, key or immobiliser data), what each era needs (a tool), how hard and how long the
-- break-in is (the mini-games' numbers, 9e's screens read them), the noise and the witnesses, what a stolen car is worth to the fence, and
-- the five pursuit deliveries. The game side is sl/theft.lua.

local M = {}

local strings = require('sl/core/strings')

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

-- ---- tools (the fence sells them; a tool with uses runs down)
M.TOOLS = {
  { id = 'slimjim', title = 'Slim jim', price = 40, uses = nil, era = 'old', optional = true },      -- (old cars open without it, slower)
  { id = 'bypass', title = 'Bypass box', price = 600, uses = 10, era = 'mid' },
  { id = 'relay', title = 'Relay kit', price = 2500, uses = 6, era = 'modern' },
  { id = 'cloner', title = 'Cloning tool', price = 6000, uses = nil, era = 'modern', slower = 3 },
}
function M.tool(id) for _, t in ipairs(M.TOOLS) do if t.id == id then return t end end return nil end
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
function M.useTool(owned, id)
  local o = owned and owned[id]
  if o and o.uses then o.uses = math.max(0, o.uses - 1) end
  return o
end

-- ---- the mini-games' numbers by era and class (the screens read these; the autoplay rolls on them)
-- stages: old = lock, wires; mid = lock, box, wires; modern = fob. value: the car's value new.
M.PRESTIGE_VALUE = 40000
function M.difficulty(era, value, prestige, retry)
  local rich = prestige or (tonumber(value) or 0) >= M.PRESTIGE_VALUE
  local d
  if era == 'old' then d = { stages = { 'lock', 'wires' }, pins = rich and 5 or 4, wires = rich and 7 or 5, cut = 3, seconds = rich and 35 or 25, chance = rich and 0.7 or 0.85 }
  elseif era == 'mid' then d = { stages = { 'lock', 'box', 'wires' }, pins = 6, wires = 7, cut = 3, seconds = rich and 50 or 40, chance = rich and 0.55 or 0.7 }
  else d = { stages = { 'fob' }, windows = rich and 1 or 2, sliders = 3, seconds = rich and 75 or 60, chance = rich and 0.4 or 0.55 } end
  if retry then d.pins = (d.pins or 0) + 1 d.seconds = d.seconds + 10 d.chance = d.chance * 0.8 d.windows = d.windows and math.max(1, d.windows - 1) or nil end
  d.era, d.prestige = era, rich
  return d
end

-- ---- noise and witnesses
M.NOISE = { pin = 0.12, wire = 0.2, crank = 0.15, fail = 0.5, half = 0.5 }
M.WITNESS_S, M.ALARM_S, M.WITNESS_M = 30, 20, 40
function M.noiseAfter(noise, event) return math.min(1, (noise or 0) + (M.NOISE[event] or 0)) end
-- a witness: people about, the noise past half (twice as fast by day)
function M.witness(noise, peopleAbout, isDay) return peopleAbout == true and (noise or 0) >= (isDay and M.NOISE.half / 2 or M.NOISE.half) end
function M.alarm(noise) return (noise or 0) >= 1 end
-- the placeholder result while the screens are not there (the autoplay switch): a roll against the chance, the noise it made
function M.autoplay(d, roll)
  local ok = (roll or 1) < (d.chance or 0.5)
  local noise = ok and (0.2 + (1 - d.chance) * 0.5) or 1
  return ok, noise
end
-- a second try on the same car within an hour is a step harder
M.RETRY_S = 3600
M.STOOD_S, M.REACH_M, M.PATROL_M = 10, 60, 300      -- a traffic car counts once it has stood still this long; the prompt's reach on foot; the alarm's patrol reach

-- ---- the stolen car
function M.stolenRecord(car, era, day, reported)
  return { model = car.model, config = car.config, name = car.name, value = tonumber(car.value) or 0, era = era, day = day, reported = reported == true, plated = false }
end
M.REPORT_DAYS = 1                     -- unreported: the owner notices after a day
function M.reportedBy(rec, day) return rec.reported or (day - (rec.day or day)) >= M.REPORT_DAYS end
-- the fence: sell (a third hot, half plated), strip (40 % plus a used part of it), new plates (clears the record), a title (the car becomes yours)
M.FENCE = { sellHot = 0.34, sellPlated = 0.5, strip = 0.4, platesBase = 800, platesShare = 0.05, titleBase = 1500, titleShare = 0.1 }
function M.sellPrice(rec) return math.floor((rec.value or 0) * (rec.plated and M.FENCE.sellPlated or M.FENCE.sellHot) / 10 + 0.5) * 10 end
function M.stripPay(rec) return math.floor((rec.value or 0) * M.FENCE.strip / 10 + 0.5) * 10 end
function M.platesPrice(rec) return M.FENCE.platesBase + math.floor((rec.value or 0) * M.FENCE.platesShare / 10 + 0.5) * 10 end
function M.titlePrice(rec) return M.FENCE.titleBase + math.floor((rec.value or 0) * M.FENCE.titleShare / 10 + 0.5) * 10 end
-- the car a stolen one becomes with a title: a fleet record with a history line and a resale cut
function M.titled(rec) return { model = rec.model, config = rec.config, name = rec.name, value = math.floor((rec.value or 0) * 0.7), condition = 0.8, history = strings.t('theft.history_line') } end

-- ---- fair game: never the player's, a lot's or a meet's car, a police car, a car with its engine running or moving, nobody's seat taken
function M.fairGame(f)
  f = f or {}
  if f.own or f.lot or f.meet or f.police or f.player then return false, 'own' end
  if f.engineOn or (f.speed or 0) > 0.5 then return false, 'running' end
  return true
end

-- ---- the five pursuit deliveries (the jobs board; the chase starts at heat 4 the moment you drive off)
M.DELIVERY_UNLOCK = 1000
M.DELIVERY_HEAT = 0.75
M.DELIVERIES = {
  { id = 'showroom', title = 'The showroom car', from = 'dealer', car = { era = 'modern', models = { 'scintilla', 'bastion', 'etkc' } }, share = 0.3, alarm = true, after = 3 },
  { id = 'longway', title = 'The long way round', from = 'quarry', car = { era = 'old', models = { 'barstow', 'moonhawk', 'bluebuck' } }, share = 0.2, minMetres = 5000 },
  { id = 'handoff', title = 'The hand-off', from = 'kerb', car = { era = 'mid', models = { 'pessima', 'legran', 'fullsize' } }, swap = { models = { 'covet', 'sunburst2', 'vivace' } }, share = 0.25, clean = true },
  { id = 'tow', title = 'The tow', from = 'kerb', car = { era = 'old', models = { 'burnside', 'autobello', 'miramar' }, limp = 0.15 }, tow = true, share = 0.2 },
  { id = 'decoy', title = 'The decoy', from = 'kerb', car = { era = 'mid', models = { 'midsize', 'lansdale', 'bx' } }, wash = true, tracker = 30, share = 0.15 },
}
function M.delivery(id) for _, d in ipairs(M.DELIVERIES) do if d.id == id then return d end end return nil end
-- which deliveries are open: the showroom one after three done
function M.openDeliveries(done)
  local out = {}
  for _, d in ipairs(M.DELIVERIES) do if not d.after or (done or 0) >= d.after then out[#out + 1] = d end end
  return out
end
function M.deliveryPay(d, value) return math.max(400, math.floor((tonumber(value) or 0) * d.share / 100 + 0.5) * 100) end
-- the tracker: a patrol is sent every `tracker` seconds until the wash leg is done
function M.trackerDue(d, sinceLast, washed) return d.tracker ~= nil and not washed and (sinceLast or 0) >= d.tracker end

return M
