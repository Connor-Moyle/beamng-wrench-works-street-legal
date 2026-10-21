-- Street Legal: the rules of the wet world (no game calls; tested by tools/luatest.js). In rain every exposed material of the level gets darker and glossier by its kind, in steps,
-- and dries back. This file: which kind a material is (by its name and file), how much each kind changes at full wetness, the steps, and the batches that spread the
-- edits over frames.

local M = {}

-- the terrain's asphalt layers: tier 0 dry, 2 wet (roughness 35/255). A swap makes the engine repack the whole terrain material cache (suspected of a GPU loss), so it happens once per rain: wet or dry, no tiers between
function M.terrainTier(step) step = step or 0 return step >= 2 and 2 or 0 end
M.STEPS = 6                   -- wetness is applied in this many steps (0 = dry); a material is edited only when its step changes
-- per kind: rough = roughness factor at full wetness (times the original), dark = base colour factor at full wetness (times the original), order = who is edited first
M.KINDS = {
  asphalt = { rough = 0.30, dark = 0.60, order = 1 },
  concrete = { rough = 0.32, dark = 0.38, order = 2 },
  paving = { rough = 0.35, dark = 0.45, order = 3 },
  terrain = { rough = 0.70, dark = 0.78, order = 4 },
  building = { rough = 0.5, dark = 0.45, order = 5 },
  roof = { rough = 0.50, dark = 0.76, order = 6 },
  metal = { rough = 0.65, dark = 0.94, order = 7 },
  glass = { rough = 0.75, dark = 1.00, order = 8 },
  foliage = { rough = 0.88, dark = 0.90, order = 9 },
}
-- patterns of the lower-case name, first match wins; the kind of road surface is asked before the rest
local PATTERNS = {
  { 'asphalt', 'asphalt' }, { 'tarmac', 'asphalt' }, { 'road', 'asphalt' }, { 'highway', 'asphalt' }, { 'street', 'asphalt' }, { 'lane', 'asphalt' },
  { 'concrete', 'concrete' }, { 'cement', 'concrete' }, { 'curb', 'concrete' }, { 'kerb', 'concrete' }, { 'barrier', 'concrete' }, { 'jersey', 'concrete' },
  { 'pavement', 'paving' }, { 'sidewalk', 'paving' }, { 'paving', 'paving' }, { 'brick', 'paving' }, { 'cobble', 'paving' }, { 'tile', 'paving' },
  { 'roof', 'roof' }, { 'shingle', 'roof' },
  { 'wall', 'building' }, { 'building', 'building' }, { 'stucco', 'building' }, { 'plaster', 'building' }, { 'facade', 'building' },
  { 'metal', 'metal' }, { 'steel', 'metal' }, { 'iron', 'metal' }, { 'alu', 'metal' }, { 'rail', 'metal' }, { 'pole', 'metal' },
  { 'glass', 'glass' }, { 'window', 'glass' },
  { 'grass', 'foliage' }, { 'leaf', 'foliage' }, { 'leaves', 'foliage' }, { 'bush', 'foliage' }, { 'tree', 'foliage' }, { 'palm', 'foliage' }, { 'foliage', 'foliage' }, { 'plant', 'foliage' },
  { 'dirt', 'terrain' }, { 'sand', 'terrain' }, { 'gravel', 'terrain' }, { 'rock', 'terrain' }, { 'mud', 'terrain' }, { 'ground', 'terrain' }, { 'terrain', 'terrain' }, { 'stone', 'terrain' },
}
-- never touched: what is under cover or is not weather (tunnels and interiors share their names with the open ones, so they are named out), lights, water, sky, decals of
-- ours, particles, and everything that belongs to a car
local SKIP = { 'tunnel', 'interior', 'indoor', 'inside', 'underpass', 'garage', 'cave', 'mine', 'light', 'lamp', 'emissive', 'neon', 'sky', 'cloud', 'water', 'ocean', 'puddle', 'ripple',
  'decal', 'skid', 'particle', 'sprite', 'shadow', 'vehicle', 'wheel', 'tire', 'tyre', 'slrr', 'sl_', 'csfx', 'ui_', 'gui', 'debug', 'invisible', 'collision' }

-- the kind of a material from its name and the file it was loaded from ('' when unknown); nil: leave it alone
function M.classify(name, file)
  local n = tostring(name or ''):lower()
  local f = tostring(file or ''):lower()
  if n == '' or f:find('/vehicles/', 1, true) then return nil end
  for _, s in ipairs(SKIP) do if n:find(s, 1, true) or f:find('tunnel', 1, true) or f:find('interior', 1, true) then return nil end end
  for _, p in ipairs(PATTERNS) do if n:find(p[1], 1, true) then return p[2] end end
  return nil
end

-- the step (0..STEPS) of a wetness 0..1 at a strength 0..1; hysteresis: it moves one step only when the wetness is a third of a step past the boundary, so rain that flickers
-- around a boundary does not edit a hundred materials back and forth
function M.step(wet, strength, current)
  local target = math.max(0, math.min(1, (wet or 0) * (strength or 1))) * M.STEPS
  if current == nil then return math.floor(target + 0.5) end
  if target > current + 0.5 + 1 / 3 then return math.min(M.STEPS, math.floor(target - 1 / 3 + 0.5)) end
  if target < current - 0.5 - 1 / 3 then return math.max(0, math.floor(target + 1 / 3 + 0.5)) end
  return current
end

-- the factor 0..1 of a step
function M.factor(step) return math.max(0, math.min(1, (step or 0) / M.STEPS)) end

-- the wet value of a factor of a kind: orig * (1 - f + f * k)
local function lerpFactor(k, f) return 1 - f + f * k end
function M.roughness(kind, orig, f) local k = M.KINDS[kind] return (tonumber(orig) or 1) * lerpFactor(k and k.rough or 1, f) end
function M.colorFactor(kind, f) local k = M.KINDS[kind] return lerpFactor(k and k.dark or 1, f) end

-- '0.8 0.8 0.8 1' -> { 0.8, 0.8, 0.8, 1 } and back (the alpha is never changed)
-- (the game writes a plain white factor as the word White: that was skipped, and so every material with a White colour factor, the wall and the track road among them, stayed unchanged)
local NAMED = { white = { 1, 1, 1, 1 }, black = { 0, 0, 0, 1 } }
function M.parseColor(text)
  local named = NAMED[tostring(text or ''):lower():match('^%s*(%a+)%s*$') or '']
  if named then return { named[1], named[2], named[3], named[4] } end
  local out = {}
  for v in tostring(text or ''):gmatch('%S+') do out[#out + 1] = tonumber(v) end
  if #out < 3 then return nil end
  return out
end
function M.formatColor(c, mul)
  local t = {}
  for i = 1, #c do t[i] = string.format('%.4f', i <= 3 and c[i] * mul or c[i]) end
  return table.concat(t, ' ')
end

-- the file a material reports: a vehicle-side material gives '' or nil (getFilename returned nothing), both mean "not the level's"; nil only when the call itself failed
function M.fileOf(ok, file)
  if not ok then return nil end
  return file or ''
end

-- order materials: the road surfaces first, then the rest by kind (a stable order by name inside a kind), at most `cap`
function M.plan(list, cap)
  local out = {}
  for _, m in ipairs(list) do
    -- a material the game reports with an EMPTY file is a vehicle-side one (the lamp glass of every model loaded with a car, 20 of them with one car; they stay registered after it is gone): never the level's
    local kind = m.file ~= '' and M.classify(m.name, m.file) or nil
    if kind then out[#out + 1] = { name = m.name, kind = kind } end
  end
  table.sort(out, function(a, b)
    local oa, ob = M.KINDS[a.kind].order, M.KINDS[b.kind].order
    if oa ~= ob then return oa < ob end
    return a.name < b.name
  end)
  while cap and #out > cap do out[#out] = nil end
  return out
end

-- one line of the edit trace (a crash hunt: the last material edited before a GPU hang names the culprit): the n-th edit, its kind and name, the step it went to, the ms it took
function M.traceLine(n, entry, step, ms)
  if ms == nil then return string.format('wet start #%d %s %s -> step %d', n, tostring(entry.kind), tostring(entry.name), step) end      -- (written BEFORE the edit: after a GPU hang the last start names the material being edited)
  return string.format('wet edit #%d %s %s -> step %d (%.1f ms)', n, tostring(entry.kind), tostring(entry.name), step, ms or 0)
end

-- how many materials to edit in this tick: a small batch, fewer when the last ones were slow (ms per edit measured by the caller), never more than `max`
-- real tarmac takes minutes to dry: the wetness the world follows rises with the rain at once and falls over `seconds` (1 to 0) at most
M.DRY_SECONDS = 240
function M.held(held, wet, dt, seconds)
  wet = math.max(0, math.min(1, wet or 0))
  if wet >= (held or 0) then return wet end
  return math.max(wet, held - (dt or 0) / (seconds or M.DRY_SECONDS))
end
-- the materials are edited in three levels only (dry, damp, wet) so there are a third fewer reloads than with six steps; each reload is a stall
function M.materialStep(step) step = step or 0 return step >= M.STEPS and M.STEPS or step >= M.STEPS / 2 and M.STEPS / 2 or 0 end
-- a material whose edit took this long (ms) is only edited at the ends (dry / wet), not at the level in between
M.SLOW_MS = 80

function M.batch(lastMsPerEdit, budgetMs, max)
  budgetMs, max = budgetMs or 3, max or 8
  if not lastMsPerEdit or lastMsPerEdit <= 0 then return math.min(2, max) end
  return math.max(1, math.min(max, math.floor(budgetMs / lastMsPerEdit)))
end

return M
