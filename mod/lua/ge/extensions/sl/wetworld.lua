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
  mat:reload()
  st.step = step
  return true
end

-- the next materials whose step is not the target, at most n of them
local function batch(n, target)
  local did = 0
  for _, entry in ipairs(plan) do
    local st = state[entry.name]
    if (st and st.step or 0) ~= target and not (st and st.failed) then
      local t0 = os.clock()
      local ok, err = pcall(apply, entry, target)
      local ms = (os.clock() - t0) * 1000
      if ok and err then
        stats.edits, stats.ms, stats.worst = stats.edits + 1, stats.ms + ms, math.max(stats.worst, ms)
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
  local target = on and rules.step(wet, option('slWetStrength', 0.8), current) or 0
  if target ~= current then
    if target > 0 and gather() == false then return end
    current = target
    log('I', TAG, string.format('wet world heads for step %d of %d (wetness %.2f)', current, rules.STEPS, wet or 0))
  end
  if not plan then return end
  timer = timer + (dt or 0)
  if timer < M.TICK then return end
  timer = 0
  local did = batch(rules.batch(msPerEdit, M.BUDGET_MS, 8), current)
  if did > 0 then stats.batches = stats.batches + 1 end
end

-- every material back to its original text at once (the level ends, the career stops, or a test)
function M.restore()
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
function M.onStreetLegalStopped() M.restore() plan = nil end
function M.onClientEndMission() M.restore() plan = nil end
function M.onClientStartMission() plan, state, current = nil, {}, 0 end      -- (a level load rebuilt the materials: nothing of ours is on them)
function M.onExtensionUnloaded() M.restore() end

return M
