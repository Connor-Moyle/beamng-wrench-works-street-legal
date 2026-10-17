-- Street Legal: cars as the career sees them. Which real car a racer's class means, and how a
-- car for sale is made into what the offer says: some parts swapped for better ones (a
-- modified car), some missing (a car that needs work), panels to dent (a damaged one).
-- Pure: the game hands in the parts tree and two lookups (tested by tools/luatest.js).

local M = {}

local strings = require('sl/core/strings')

M.CLASSES = { 'beater', 'compact', 'muscle', 'tuner', 'sport', 'super' }

function M.classIndex(name)
  for i, c in ipairs(M.CLASSES) do if c == name then return i end end
  return 1
end

-- configs: { { model, config, name, pw (power to weight), value } } ; a class is a sixth of
-- them by power to weight. Returns one of that sixth.
function M.pickConfig(configs, class, rng)
  local list = {}
  for _, c in ipairs(configs or {}) do
    if type(c.pw) == 'number' then list[#list + 1] = c end
  end
  if #list == 0 then return nil end
  table.sort(list, function(a, b) return a.pw < b.pw end)
  local i, n = M.classIndex(class), #list
  local lo = math.floor((i - 1) / 6 * n) + 1
  local hi = math.max(lo, math.floor(i / 6 * n))
  return list[rng:int(lo, math.min(hi, n))]
end

-- what each fault takes off the car (catalog chapters, see Wrench Works' garageCatalog)
M.FAULT_PARTS = {
  engine = { 'engine/intake' },
  gearbox = { 'engine/clutch' },
  radiator = { 'engine/cooling' },
  battery = { 'engine/fuel' },
  tyres = { 'running/tyres_f', 'running/tyres_r' },
  brakes = { 'running/brakes_f', 'running/brakes_r' },
  exhaust = { 'engine/exhaust' },
}

-- where a modified car has been modified
M.MOD_PARTS = { 'running/rims_f', 'running/rims_r', 'engine/exhaust', 'engine/intake', 'engine/forced', 'running/shocks_f',
  'running/shocks_r', 'running/suspension_f', 'running/suspension_r', 'body/wings', 'body/aero', 'engine/management',
  'running/brakes_f', 'running/brakes_r', 'running/differentials', 'body/hoods' }

-- panels that take the dents of a damaged car. Not the doors: a dent bends the hinge nodes and a LeGran's driver door hung open on the lot (the
-- latches are kept, but a bent hinge lets go anyway); the fenders and bumpers carry the damage
M.DENT_PARTS = { 'body/bumpers_f', 'body/bumpers_r', 'body/fenders', 'body/hoods', 'body/trunk', 'body/roof' }

local function set(list)
  local s = {}
  for _, x in ipairs(list) do s[x] = true end
  return s
end

local function isChosen(node) return node.chosenPartName ~= nil and node.chosenPartName ~= '' end

-- every chosen node under root with its section/sub, parents before children
local function nodes(root, classify)
  local out = {}
  local function walk(node, depth)
    for _, child in pairs(node.children or {}) do
      if isChosen(child) then
        local section, sub = classify(child.id or '', child.chosenPartName, nil)
        out[#out + 1] = { node = child, parent = node, key = section .. '/' .. sub, depth = depth }
        walk(child, depth + 1)
      end
    end
  end
  walk(root, 1)
  table.sort(out, function(a, b)
    if a.depth ~= b.depth then return a.depth < b.depth end
    return (a.node.path or '') < (b.node.path or '')
  end)
  return out
end

local function partPath(node) return (node.path or '/') .. node.chosenPartName end

-- Parts and slots a car for sale never has changed, whatever the model (a piece of the slot path, the slot id or the part name, lower
-- case): a spare wheel is mounted on a door or a carrier and rebuilding it in place killed the game (a midtruck's rear-door spare
-- wheel, swapped, crashed it twice at the same place: T29). opts.refuse replaces the list.
M.REFUSE = { 'sparewheel', 'spare_wheel', 'spare' }

-- Panels a car for sale is never dented on (pieces of the slot path, slot id or part name, lower case; a panel with such a part below it
-- too): dents bend nodes in place, and a body the engine cannot deform that way leaves a broken car (T29: the used lot's dents on a
-- midtruck crashed the game). Empty until tools/probe_tweak.lua (PROBE_DENTS, PROBE_EACH) names the panel; extend it in the console:
-- table.insert(require('sl/carBuilder').REFUSE_DENTS, 'cargo').
M.REFUSE_DENTS = {}

-- Whether a part can go into a slot, as the game's own slot system decides it (jbeam/slotSystem partFitsSlot): the part's
-- slotType (a string or a list) against the slot's allowTypes (slots2) or its single type (slots1); denyTypes refuse.
-- No slot definition at all: it fits (the game will have its say).
function M.partFits(slotType, slot)
  if type(slot) ~= 'table' then return true end
  local function has(list, x) for _, v in ipairs(list) do if v == x then return true end end return false end
  local types = type(slotType) == 'table' and slotType or { slotType }
  for _, t in ipairs(types) do
    if type(slot.denyTypes) == 'table' and has(slot.denyTypes, t) then return false end
  end
  if slot.allowTypes then
    for _, t in ipairs(types) do if has(slot.allowTypes, t) then return true end end
    return false
  elseif slot.type then
    for _, t in ipairs(types) do if t == slot.type then return true end end
    return false
  end
  return true
end

-- A car a street racer may be given (B66: a limousine turned up as an opponent): a road car, not a limousine, bus, van, truck, ambulance or
-- the like (the game's "Body Style"), not a police or service car (its "Config Type"). c.raw is the game's own config entry; a name with
-- "limo" or "bus" in it is out too. Without raw: allowed.
M.RACER_BODY_NOT = { ['limousine'] = true, ['bus'] = true, ['van'] = true, ['minivan'] = true, ['fifth wheel truck'] = true, ['flatbed'] = true,
  ['box truck'] = true, ['ambulance'] = true, ['tanker truck'] = true, ['dump truck'] = true, ['armored'] = true, ['chassis cab'] = true,
  ['logging truck'] = true, ['mixer truck'] = true, ['haul truck'] = true, ['jato truck'] = true, ['wheel loader'] = true, ['atv'] = true }
M.RACER_CONFIG_NOT = { ['police'] = true, ['service'] = true }
local function trimmed(w) return (w:lower():gsub('^%s+', ''):gsub('%s+$', '')) end
local function wordsOf(v)
  local out = {}
  if type(v) == 'string' then out[1] = trimmed(v)
  elseif type(v) == 'table' then
    for k in pairs(v) do if type(k) == 'string' then out[#out + 1] = trimmed(k) end end
  end
  return out
end
function M.racerOk(c)
  if type(c) ~= 'table' then return false end
  local name = tostring(c.name or ''):lower()
  if name:find('%f[%a]limo') or name:find('%f[%a]bus%f[%A]') then return false end          -- (words: not Bluebuck, Sunburst)
  local r = c.raw
  if type(r) ~= 'table' then return true end
  local ag = type(r.aggregates) == 'table' and r.aggregates or {}
  for _, w in ipairs(wordsOf(r['Body Style'])) do if M.RACER_BODY_NOT[w] then return false end end
  for _, w in ipairs(wordsOf(ag['Body Style'])) do if M.RACER_BODY_NOT[w] then return false end end
  for _, w in ipairs(wordsOf(r['Config Type'])) do if M.RACER_CONFIG_NOT[w] then return false end end
  for _, w in ipairs(wordsOf(ag['Config Type'])) do if M.RACER_CONFIG_NOT[w] then return false end end
  return true
end

-- The configs without the excluded models ({ model = true }): ONE rule for every pool the career builds cars from (lots, dealers,
-- private ads, street racers and their opponents), so a model the game cannot build safely never appears (T29: the midtruck).
function M.withoutModels(configs, excluded)
  local out = {}
  for _, c in ipairs(configs or {}) do
    if not (excluded and excluded[c.model]) then out[#out + 1] = c end
  end
  return out
end

-- Make a stock parts tree into the car an offer describes. Changes the tree in place.
-- opts: { rng, classify = function(slotId, partName, desc) -> section, sub,
--         valueOf = function(partName) -> number, faults = { 'engine', ... }, mods = n,
--         slotOf = function(node, parentNode) -> the node's slot definition { coreSlot, allowTypes, denyTypes, type } or nil,
--         partSlotType = function(partName) -> the part's slotType or nil }
-- A part is never taken off from a core slot, nor from one with a core slot below it (the car would be missing what it
-- needs: T29), and a part is swapped in only where the game's slot rules let it (partFits); without slotOf the old rules.
-- Returns { removed = { partPath }, swapped = { { path, from, to } }, refused = { { path, why } } }
function M.tweakTree(tree, opts)
  local rng, classify, valueOf = opts.rng, opts.classify, opts.valueOf or function() return 0 end
  local result = { removed = {}, swapped = {}, refused = {} }
  if type(tree) ~= 'table' then return result end

  local slotOf = opts.slotOf
  local refuseList = opts.refuse or M.REFUSE
  local function refusedNode(n)
    local text = ((n.path or '') .. ' ' .. (n.id or '') .. ' ' .. (n.chosenPartName or '')):lower()
    for _, w in ipairs(refuseList) do if text:find(w, 1, true) then return true end end
    return false
  end
  local function refusedBelow(node)
    for _, child in pairs(node.children or {}) do
      if isChosen(child) and (refusedNode(child) or refusedBelow(child)) then return true end
    end
    return false
  end
  local function coreBelow(node)
    for _, child in pairs(node.children or {}) do
      if isChosen(child) then
        local slot = slotOf(child, node)
        if (slot and slot.coreSlot) or coreBelow(child) then return true end
      end
    end
    return false
  end

  -- faults: the parts go
  for _, fault in ipairs(opts.faults or {}) do
    local wanted = set(M.FAULT_PARTS[fault] or {})
    for _, entry in ipairs(nodes(tree, classify)) do
      local n = entry.node
      if wanted[entry.key] and isChosen(n) then
        local slot = slotOf and slotOf(n, entry.parent)
        if refusedNode(n) or refusedBelow(n) then
          result.refused[#result.refused + 1] = { path = partPath(n), why = 'never changed (spare wheel)' }
        elseif slot and slot.coreSlot then
          result.refused[#result.refused + 1] = { path = partPath(n), why = strings.t('cars.core_slot') }
        elseif slotOf and coreBelow(n) then
          result.refused[#result.refused + 1] = { path = partPath(n), why = strings.t('cars.core_slot_below') }
        else
          result.removed[#result.removed + 1] = partPath(n)
          n.chosenPartName, n.partPath, n.children, n.decisionMethod = '', nil, nil, 'user-empty'
        end
      end
    end
  end

  -- modifications: a few parts swapped for something else that fits, dearer if there is one
  local mods = opts.mods or 0
  if mods > 0 then
    local wanted = set(M.MOD_PARTS)
    local candidates, parents = {}, {}
    for _, entry in ipairs(nodes(tree, classify)) do
      local n = entry.node
      if wanted[entry.key] and (refusedNode(n) or refusedBelow(n)) then
        result.refused[#result.refused + 1] = { path = partPath(n), why = 'never changed (spare wheel)' }
      elseif wanted[entry.key] and type(n.suitablePartNames) == 'table' and #n.suitablePartNames > 1 then
        candidates[#candidates + 1] = n
        parents[n] = entry.parent
      end
    end
    local done = 0
    while done < mods and #candidates > 0 do
      local i = rng:int(#candidates)
      local n = table.remove(candidates, i)
      if isChosen(n) then
        local current = n.chosenPartName
        local better, other = {}, {}
        local slot = slotOf and slotOf(n, parents[n])
        for _, name in ipairs(n.suitablePartNames) do
          local fits = true
          if slot and opts.partSlotType then
            local st = opts.partSlotType(name)
            fits = st ~= nil and M.partFits(st, slot)
          end
          if name ~= current and fits then
            other[#other + 1] = name
            if valueOf(name) > valueOf(current) then better[#better + 1] = name end
          elseif name ~= current then
            result.refused[#result.refused + 1] = { path = (n.path or '/') .. name, why = strings.t('cars.does_not_fit_the_slot') }
          end
        end
        local pick = #better > 0 and better[rng:int(#better)] or (#other > 0 and other[rng:int(#other)] or nil)
        if pick then
          result.swapped[#result.swapped + 1] = { path = n.path, from = current, to = pick }
          n.chosenPartName, n.partPath, n.children, n.decisionMethod = pick, (n.path or '/') .. pick, nil, 'user'
          done = done + 1
        end
      end
    end
  end
  return result
end

-- Dents for a damaged car: which panels, and how bent (0..1 damage -> a few cm at most).
-- Returns { { partPath, dent, seed } } in the form Wrench Works' vehicle extension applies.
function M.dents(tree, classify, rng, damage, refuse)
  local out = {}
  if (damage or 0) <= 0 then return out end
  local words = refuse or M.REFUSE_DENTS
  local function refused(n)
    local text = ((n.path or '') .. ' ' .. (n.id or '') .. ' ' .. (n.chosenPartName or '')):lower()
    for _, w in ipairs(words) do if text:find(w, 1, true) then return true end end
    for _, child in pairs(n.children or {}) do if isChosen(child) and refused(child) then return true end end
    return false
  end
  local wanted = set(M.DENT_PARTS)
  local panels = {}
  for _, entry in ipairs(nodes(tree, classify)) do
    if wanted[entry.key] and not refused(entry.node) then panels[#panels + 1] = entry.node end
  end
  local count = math.min(#panels, math.max(1, math.floor(#panels * damage + 0.5)))
  for _ = 1, count do
    local n = table.remove(panels, rng:int(#panels))
    out[#out + 1] = { partPath = partPath(n), dent = 0.01 + 0.035 * damage * rng:range(0.5, 1), seed = rng:int(1, 99999) }
  end
  return out
end

return M
