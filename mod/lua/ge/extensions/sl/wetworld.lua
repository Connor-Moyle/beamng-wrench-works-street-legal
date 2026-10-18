-- Street Legal: the wet world (extension name: sl_wetworld; part of the weather, #45).
-- As rain builds, the exposed materials of the level (roads, pavements, terrain, walls, roofs, metal, glass, foliage) get darker and glossier by their kind, in steps, and dry back
-- afterwards. The edit is the one Car Surface FX does to a car's paint: setField on the material, then reload; the original values are kept as text and put back exactly. Hundreds
-- of materials: the edits are spread over frames in small batches whose size follows how long the last ones took (sl_wetworld.profile() says). The kinds and numbers
-- are sl/core/wetworld.lua; the strength is the setting Wet world strength. Materials of tunnels, interiors and the like are skipped by their names; one material is shared by all the
-- geometry that uses it, so a covered spot that uses an open material is wet too.

local M = {}

local rules = require('sl/core/wetworld')
local TAG = 'sl_wetworld'

M.MAX_MATERIALS = 400          -- at most this many materials are touched
M.TICK = 0.1                   -- seconds between batches
M.BUDGET_MS = 3                -- what a batch may cost

local plan                     -- { { name, kind } } in edit order, or false when the level has none
local state = {}               -- material name -> { step = applied step, orig = { [stage] = { rough, color } }, failed }
local current = 0              -- the step the world is heading to
local timer = 0
local held = 0                  -- the wetness we follow: falls slowly (rules.held)
local msPerEdit
local stats = { edits = 0, ms = 0, worst = 0, failed = 0, restored = 0, batches = 0 }

local function option(key, default)
  local v = sl_options and sl_options.get and sl_options.get(key)
  if v == nil then return default end
  return v
end

local function materials()
  local list = {}
  local ok, objs = pcall(function() return getObjectsByClass and getObjectsByClass('Material') or {} end)
  for _, o in ipairs(ok and objs or {}) do
    local okN, name = pcall(function() return o:getName() end)
    local okF, file = pcall(function() return o:getFilename() end)
    if okN and name then list[#list + 1] = { name = name, file = okF and file or '' } end
  end
  return list
end

local function gather()
  if plan ~= nil then return plan end
  plan = rules.plan(materials(), M.MAX_MATERIALS)
  if #plan == 0 then
    plan = false
    log('W', TAG, 'no material of the level matched a wet kind: the world stays as it is')
  else
    local kinds = {}
    for _, m in ipairs(plan) do kinds[m.kind] = (kinds[m.kind] or 0) + 1 end
    local t = {}
    for k, n in pairs(kinds) do t[#t + 1] = k .. ' ' .. n end
    table.sort(t)
    log('I', TAG, string.format('wet world: %d materials (%s)', #plan, table.concat(t, ', ')))
  end
  return plan
end

-- The tarmac of West Coast USA is the terrain's own Asphalt layers, not a Material: their colour is a texture, no factor to lower. Wet, the layer's base colour and roughness textures
-- are swapped for two small plain ones of ours (a dark grey, a smooth one: the layer's own roughness texture as colour came out pale in the game), put back dry; the terrain block redraws
-- the layer (updateMaterial). The layer's detail textures still show on top.
local WET_COLOR = '/art/street_legal/terrain/wet_asphalt_b.png'
local WET_ROUGH = { '/art/street_legal/terrain/wet_asphalt_r1.png', '/art/street_legal/terrain/wet_asphalt_r2.png', '/art/street_legal/terrain/wet_asphalt_r3.png' }      -- (one is loaded at a time)
local terr                     -- { { mat, name, orig, wet } } or false when there is none
local terrWet = 0                 -- the tier on the layers now
local function terrainLayers()
  if terr ~= nil then return terr end
  terr = {}
  local ok, mats = pcall(function() return getObjectsByClass and getObjectsByClass('TerrainMaterial') or {} end)
  for _, m in ipairs(ok and mats or {}) do
    local g = tostring(m:getField('groundmodelName', 0) or ''):upper()
    local orig, origR, name = m:getField('baseColorBaseTex', 0), m:getField('roughnessBaseTex', 0), m:getField('internalName', 0)
    if (g:find('^ASPHALT') or g:find('^CONCRETE')) and orig ~= '' and name ~= '' then terr[#terr + 1] = { mat = m, name = name, orig = orig, origR = origR } end
  end
  if #terr == 0 then terr = false else log('I', TAG, 'wet terrain layers: ' .. #terr) end
  return terr
end
local function applyTerrain(tier)
  local layers = terrainLayers()
  terrWet = tier
  local wetNow = tier > 0
  if not layers then return end
  local t0 = os.clock()
  local blocks = {}
  pcall(function() blocks = getObjectsByClass('TerrainBlock') or {} end)
  for _, l in ipairs(layers) do
    pcall(function()
      l.mat:setField('baseColorBaseTex', 0, wetNow and WET_COLOR or l.orig)
      if l.origR ~= '' then l.mat:setField('roughnessBaseTex', 0, wetNow and WET_ROUGH[tier] or l.origR) end
      if blocks[1] then blocks[1]:updateMaterial(0, l.name) end
    end)
  end
  log('I', TAG, string.format('terrain layers tier %d: %d layers, %.0f ms', tier, #layers, (os.clock() - t0) * 1000))
end

-- one material to a step: the original text of its roughness and colour factors is taken the first time, the wet values come from it, the material is reloaded once
local function apply(entry, step)
  local m = scenetree.findObject(entry.name)
  if not m then return false end
  local st = state[entry.name]
  if not st then st = { step = 0, orig = {} } state[entry.name] = st end
  local f = rules.factor(step)
  for stage = 0, 3 do
    local o = st.orig[stage]
    if not o then
      local rough, color = m:getField('roughnessFactor', stage), m:getField('baseColorFactor', stage)
      o = { rough = rough, color = color }
      st.orig[stage] = o
    end
    if o.rough ~= '' or o.color ~= '' then
      if step == 0 then
        if o.rough ~= '' then m:setField('roughnessFactor', stage, o.rough) end
        if o.color ~= '' then m:setField('baseColorFactor', stage, o.color) end
      else
        local base = tonumber(o.rough)
        if o.rough ~= '' then m:setField('roughnessFactor', stage, string.format('%.4f', rules.roughness(entry.kind, base, f))) end
        local c = rules.parseColor(o.color ~= '' and o.color or '1 1 1 1')
        if c then m:setField('baseColorFactor', stage, rules.formatColor(c, rules.colorFactor(entry.kind, f))) end
      end
    end
  end
  -- (Car Surface FX reloads through Sim.upcast(m): a material found by name is a plain SimObject, and its reload may not reach the renderer; the edits above were read back right and drew nothing)
  local mat = Sim and Sim.upcast and Sim.upcast(m) or m
  -- (the game's own track builder does flush() then reload() after changing a material's fields)
  if mat.flush then pcall(mat.flush, mat) end
  mat:reload()
  st.step = step
  return true
end

-- the next materials whose step is not the target, at most n of them
local function batch(n, target)
  local did = 0
  for _, entry in ipairs(plan) do
    local st = state[entry.name]
    local skip = st and st.slow and ((target > 0 and target < rules.STEPS) or (os.clock() - (M.lastSlowAt or -99) < 4))      -- (a slow material waits for the full wet, and one at a time, four seconds apart)
    if (st and st.step or 0) ~= target and not (st and st.failed) and not skip then
      local t0 = os.clock()
      local ok, err = pcall(apply, entry, target)
      local ms = (os.clock() - t0) * 1000
      if ok and err then
        stats.edits, stats.ms, stats.worst = stats.edits + 1, stats.ms + ms, math.max(stats.worst, ms)
        if ms > rules.SLOW_MS then
          M.lastSlowAt = os.clock()
          local s2 = state[entry.name]
          if s2 then s2.slow = true end
          stats.slow = stats.slow or {}
          if #stats.slow < 10 then stats.slow[#stats.slow + 1] = string.format('%s %.0f ms', entry.name, ms) log('I', TAG, 'slow material edit: ' .. entry.name .. ' ' .. string.format('%.0f', ms) .. ' ms') end
        end
        msPerEdit = msPerEdit and (msPerEdit * 0.7 + ms * 0.3) or ms
        if target == 0 then stats.restored = stats.restored + 1 end
      else
        state[entry.name] = state[entry.name] or { step = 0, orig = {} }
        state[entry.name].failed = true
        stats.failed = stats.failed + 1
        if stats.failed <= 3 then log('W', TAG, 'could not edit ' .. entry.name .. ': ' .. tostring(err)) end
      end
      did = did + 1
      if did >= n then break end
    end
  end
  return did
end

-- called from the weather every frame: wet 0..1 is the wetness of the roads
function M.update(dt, wet)
  local on = option('slWetWorld', true) == true
  held = rules.held(held, wet, dt)
  local target = on and rules.step(held, option('slWetStrength', 0.8), current) or 0
  if target ~= current then
    if target > 0 and gather() == false then return end
    current = target
    log('I', TAG, string.format('wet world heads for step %d of %d (wetness %.2f)', current, rules.STEPS, wet or 0))
  end
  local wantTerrain = (on and option('slWetTarmac', true) == true) and rules.terrainTier(current) or 0      -- (also when the setting is switched while it rains)
  if wantTerrain ~= terrWet then applyTerrain(wantTerrain) end
  if not plan then return end
  timer = timer + (dt or 0)
  if timer < M.TICK then return end
  timer = 0
  local did = batch(rules.batch(msPerEdit, M.BUDGET_MS, 8), rules.materialStep(current))
  if did > 0 then stats.batches = stats.batches + 1 end
end

-- every material back to its original text at once (the level ends, the career stops, or a test)
function M.restore()
  held = 0
  if terrWet > 0 then applyTerrain(0) end
  if plan then
    current = 0
    local guard = 0
    while batch(50, 0) > 0 and guard < 20 do guard = guard + 1 end
  end
  state = {}
end

-- what it costs: edits done, ms per edit and the worst one, the step, how many materials are wet
function M.profile()
  local wetNow = 0
  for _, st in pairs(state) do if (st.step or 0) > 0 then wetNow = wetNow + 1 end end
  return string.format('wet world: step %d/%d, %d materials planned, %d wet now, %d edits (avg %.2f ms, worst %.2f ms), %d restored, %d failed, %d batches',
    current, rules.STEPS, plan and #plan or 0, wetNow, stats.edits, stats.edits > 0 and stats.ms / stats.edits or 0, stats.worst, stats.restored, stats.failed, stats.batches)
end

function M.stats() return stats, current, plan and #plan or 0 end
function M.onStreetLegalStopped() pcall(M.restore) plan = nil end
-- (the level is going away with its materials: reloading hundreds of them in this tick would be a hitch for nothing, so only our state is dropped)
function M.onClientEndMission() plan, state, current, terr, terrWet = nil, {}, 0, nil, 0 end
function M.onClientStartMission() plan, state, current, terr, terrWet = nil, {}, 0, nil, 0 end      -- (a level load rebuilt the materials: nothing of ours is on them)
function M.onExtensionUnloaded() pcall(M.restore) end

return M
