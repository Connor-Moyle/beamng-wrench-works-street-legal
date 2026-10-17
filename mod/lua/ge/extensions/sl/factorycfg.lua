-- Street Legal: reading a model's factory configs for the dealer's catalogue and configurator (C4, docs/FACTORY_ORDER.md).
-- Not an extension: required by the lot. Only what the game's own configs (.pc) and jbeam files hold is offered.

local M = {}

local factoryLib = require('sl/core/factory')
local partinfo = require('sl/core/partinfo')

function M.modelInfo(key)
  local ok, m = pcall(core_vehicles.getModel, key)
  return ok and m and m.model or {}, ok and m or nil
end

-- the picture the game ships for a config (or the model's default): /vehicles/<model>/<config>.jpg|png
function M.picture(model, configPath)
  local name = tostring(configPath or ''):match('([^/]+)%.pc$')
  for _, ext in ipairs({ 'jpg', 'png' }) do
    local p = string.format('/vehicles/%s/%s.%s', model, name or 'default', ext)
    if name and FS and FS.fileExists and FS:fileExists(p) then return p end
  end
  for _, ext in ipairs({ 'jpg', 'png' }) do
    local p = string.format('/vehicles/%s/default.%s', model, ext)
    if FS and FS.fileExists and FS:fileExists(p) then return p end
  end
  return nil
end

-- the card of a model: name, body style, picture, price from
function M.modelCard(m, i)
  local info = M.modelInfo(m.model)
  return { i = i, name = (m.brand ~= '' and (m.brand .. ' ') or '') .. tostring(info.Name or m.model), body = tostring(info['Body Style'] or info.Type or ''),
    picture = M.picture(m.model, m.trims[1].config), from = m.trims[1].value, trims = #m.trims, special = m.special }
end

-- a trim's card: price, key specs (from the game's config list entry kept in the catalogue, if any)
function M.trimCard(m, t, i)
  local raw = t.raw or {}
  return { i = i, name = t.name, price = t.value, picture = M.picture(m.model, t.config), power = tonumber(raw.Power), weight = tonumber(raw.Weight),
    drive = raw.Drivetrain, transmission = raw.Transmission }
end

local function readParts(path)
  local pc = jsonReadFile and jsonReadFile(path)
  return type(pc) == 'table' and pc or nil
end

-- the configurator data of a model, read once: the factory parts of every trim, the options, and what each part is called and worth
function M.configurator(m)
  local configs, pcs = {}, {}
  for i, t in ipairs(m.trims) do
    pcs[i] = readParts(t.config)
    configs[#configs + 1] = pcs[i] and type(pcs[i].parts) == 'table' and pcs[i].parts or {}
  end
  local ctx
  local ok, jbeamIO = pcall(require, 'jbeam/io')
  if ok then
    local okLoad, c = pcall(jbeamIO.startLoading, { '/vehicles/' .. m.model .. '/', '/vehicles/common/' })
    if okLoad then ctx = c pcall(jbeamIO.finishLoading) end
  end
  local cache = {}
  local function info(part)
    if cache[part] == nil then
      local okPart, p = false, nil
      if ctx then okPart, p = pcall(jbeamIO.getPart, ctx, part) end
      cache[part] = okPart and p and p.information or false
    end
    return cache[part] or {}
  end
  return {
    pcs = pcs, options = factoryLib.optionsOf(configs),
    value = function(part) return part and part ~= '' and tonumber(info(part).value) or 0 end,
    name = function(part) return partinfo.displayName(info(part).name, part, m.model) end,
  }
end

-- the screen's groups for a trim and the picks so far: { { id, slots = { { n, label, options = { { part, name, delta, on } } } } } }, and the total delta
function M.groups(cfg, trimIdx, picks)
  local base = (cfg.pcs[trimIdx] and cfg.pcs[trimIdx].parts) or {}
  local byGroup, slots = {}, {}
  for slot in pairs(cfg.options) do slots[#slots + 1] = slot end
  table.sort(slots)
  local n, deltas = 0, {}
  for _, slot in ipairs(slots) do
    n = n + 1
    local current = picks[slot] or base[slot] or ''
    local entry = { n = n, slot = slot, label = partinfo.displayName(nil, slot, ''), options = {} }
    local own = cfg.value(base[slot])
    for j, part in ipairs(cfg.options[slot]) do
      entry.options[j] = { j = j, part = part, name = cfg.name(part), delta = cfg.value(part) - own, on = part == current }
    end
    if picks[slot] then deltas[slot] = cfg.value(picks[slot]) - own end
    local g = factoryLib.groupOf(slot)
    byGroup[g] = byGroup[g] or { id = g, slots = {} }
    table.insert(byGroup[g].slots, entry)
  end
  local out = {}
  for _, g in ipairs(factoryLib.GROUPS) do if byGroup[g] then out[#out + 1] = byGroup[g] end end
  return out, deltas
end

-- the .pc table to spawn for an order: the trim's config with the picked parts and the chosen paint
function M.pcFor(configPath, picks, paint)
  local pc = readParts(configPath)
  if not pc then return configPath end
  pc.parts = pc.parts or {}
  for slot, part in pairs(picks or {}) do pc.parts[slot] = part end
  if paint then pc.paints = factoryLib.withPaint(pc.paints, paint) end
  return pc
end

return M
