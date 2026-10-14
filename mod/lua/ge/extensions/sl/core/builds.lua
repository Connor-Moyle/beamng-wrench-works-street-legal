-- Street Legal: custom cars. Stock cars made into street racers and track cars by recipe:
-- for every part the recipe touches, the option that fits with the most performance in it -
-- the dearest, more so when its name says sport, race, turbo and the like. A street build goes
-- in stages; a track build has everything and loses what a race car does not carry. Each one
-- gets a nickname and a paint job, the same every time for the same seed.
-- Pure: the game hands in the parts tree and lookups (tested by tools/luatest.js).

local M = {}

local rngLib = require('sl/core/rng')

-- the street stages: each adds to the one before
M.STAGES = {
  { 'engine/exhaust', 'engine/intake', 'running/rims_f', 'running/rims_r' },
  { 'engine/management', 'running/shocks_f', 'running/shocks_r', 'running/tyres_f', 'running/tyres_r', 'running/bars' },
  { 'engine/forced', 'running/brakes_f', 'running/brakes_r', 'body/wings', 'body/aero', 'running/differentials',
    'running/suspension_f', 'running/suspension_r', 'engine/clutch' },
}

-- a track car: everything above, the engine's insides, and the cage
M.RACE_EXTRA = { 'engine/internals', 'engine/fuel', 'engine/cooling', 'engine/transmission', 'body/chassis', 'running/brakes' }
-- and what comes out of it
M.RACE_STRIP = { 'interior/seats_r', 'interior/trim', 'interior/extras', 'body/plates', 'body/misc' }

local STREET_WORDS = { 'sport', 'street', 'tuner', 'turbo', 'stage', 'race', 'performance', 'drift' }
local RACE_WORDS = { 'race', 'racing', 'track', 'slick', 'semi', 'competition', 'drag', 'cage', 'pro', 'rally', 'stage', 'ultralight', 'lightweight' }

M.NICKNAMES = { 'Night Fury', 'Asphalt Ghost', 'Red Mist', 'Widowmaker', 'Boost Junkie', 'Static', 'Black Mamba', 'Midnight Express',
  'Sleeper', 'Hellcat', 'Tarmac Shark', 'Northern Lights', 'Neon Wolf', 'Paper Plane', 'Lowrider', 'Kingpin', 'Graveyard Shift',
  'Second Chance', 'Monday Morning', 'Ricochet', 'Blue Thunder', 'Nightcrawler', 'Hot Wire', 'Wild Card' }

-- street colours: loud, metallic or matte; track cars wear a livery colour and a stripe colour
local STREET_COLOURS = { { 0.9, 0.05, 0.05 }, { 0.02, 0.15, 0.85 }, { 0.95, 0.6, 0.02 }, { 0.1, 0.8, 0.15 }, { 0.6, 0.02, 0.7 },
  { 0.02, 0.02, 0.02 }, { 0.92, 0.92, 0.95 }, { 0.95, 0.85, 0.05 }, { 0.02, 0.6, 0.65 }, { 0.75, 0.75, 0.78 } }

local function set(list)
  local s = {}
  for _, x in ipairs(list) do s[x] = true end
  return s
end

local function isChosen(node) return node.chosenPartName ~= nil and node.chosenPartName ~= '' end

local function hits(text, words)
  text = tostring(text or ''):lower()
  local n = 0
  for _, w in ipairs(words) do if text:find(w, 1, true) then n = n + 1 end end
  return n
end

-- the subs a recipe works on: stage 1..3, or 'race'
function M.recipe(stage)
  local subs = {}
  local top = stage == 'race' and 3 or math.max(0, math.min(3, tonumber(stage) or 0))
  for i = 1, top do for _, s in ipairs(M.STAGES[i]) do subs[#subs + 1] = s end end
  if stage == 'race' then for _, s in ipairs(M.RACE_EXTRA) do subs[#subs + 1] = s end end
  return subs
end

-- what stage a racer of a tier drives
function M.stageFor(tier)
  return ({ 0, 1, 2, 3, 3 })[tier] or 1
end

-- Build a car. Changes the tree in place.
-- opts: { stage = 0..3 | 'race', rng, classify(slotId, partName) -> section, sub, valueOf(partName), nameOf(partName) }
-- Returns { upgraded = { { path, from, to } }, stripped = { path } }
function M.apply(tree, opts)
  local result = { upgraded = {}, stripped = {} }
  if type(tree) ~= 'table' then return result end
  local race = opts.stage == 'race'
  local wanted = set(M.recipe(opts.stage))
  local strip = race and set(M.RACE_STRIP) or {}
  local words = race and RACE_WORDS or STREET_WORDS
  local valueOf, nameOf, rng = opts.valueOf or function() return 0 end, opts.nameOf or function(n) return n end, opts.rng
  local function score(name)
    return (valueOf(name) + 1) * (1 + 0.6 * hits(name .. ' ' .. nameOf(name), words))
  end
  local function walk(node)
    for _, child in pairs(node.children or {}) do
      -- an empty slot counts too (a turbo or a wing the stock car came without): its id says what it is for
      local section, sub = opts.classify(child.id or '', child.chosenPartName or '')
      local key = section .. '/' .. sub
      if strip[key] and isChosen(child) then
        result.stripped[#result.stripped + 1] = child.path
        child.chosenPartName, child.partPath, child.children, child.decisionMethod = '', nil, nil, 'user-empty'
      elseif not strip[key] then
        do
          if wanted[key] and type(child.suitablePartNames) == 'table' and #child.suitablePartNames > 0 then
            -- the best two by score; the seed decides between them, so two builds of one car differ a little
            local ranked = {}
            for _, name in ipairs(child.suitablePartNames) do
              if name ~= '' then ranked[#ranked + 1] = { name = name, score = score(name) } end
            end
            table.sort(ranked, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.name < b.name end)
            local current = isChosen(child) and score(child.chosenPartName) or 0
            local pick = ranked[1]
            if ranked[2] and rng and rng:chance(0.3) and ranked[2].score > current then pick = ranked[2] end
            if pick and pick.name ~= child.chosenPartName and pick.score > current then
              result.upgraded[#result.upgraded + 1] = { path = child.path, from = child.chosenPartName, to = pick.name }
              child.chosenPartName, child.partPath, child.children, child.decisionMethod = pick.name, (child.path or '/') .. pick.name, nil, 'user'
            end
          end
          if isChosen(child) then walk(child) end
        end
      end
    end
  end
  walk(tree)
  return result
end

function M.nickname(seed)
  local rng = rngLib.new(rngLib.hash('nick' .. tostring(seed)))
  return M.NICKNAMES[rng:int(#M.NICKNAMES)]
end

-- the car's three paint slots
function M.paints(seed, race)
  local rng = rngLib.new(rngLib.hash('paint' .. tostring(seed)))
  local function paint(c, metallic)
    return { baseColor = { c[1], c[2], c[3], 1 }, metallic = metallic, roughness = metallic > 0.5 and 0.25 or 0.6, clearcoat = 1, clearcoatRoughness = 0.05 }
  end
  local main = STREET_COLOURS[rng:int(#STREET_COLOURS)]
  local second = STREET_COLOURS[rng:int(#STREET_COLOURS)]
  local finish = race and 0.3 or (rng:chance(0.7) and 0.85 or 0.1)
  return { paint(main, finish), paint(second, finish), paint({ 0.03, 0.03, 0.03 }, 0.2) }
end

return M
