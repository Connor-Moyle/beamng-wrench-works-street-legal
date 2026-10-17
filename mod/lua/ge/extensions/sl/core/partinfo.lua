-- Street Legal: how a part for sale is shown (T39). Pure, tested by tools/luatest.js. BeamNG has no picture file for a part (its own
-- part shops show the real 3D model in the garage, and its part inventory shows the CAR's thumbnail and a category icon), so an ad
-- for a part shows: the part's real display name (the jbeam "information.name"), what kind of part it is (the Wrench Works catalog's
-- chapter, e.g. "Exhaust systems") and which car it fits (name and the car's own picture), with a category icon as the fallback.

local M = {}

local strings = require('sl/core/strings')

M.CATEGORIES = { engine = 'Engine', body = 'Body', running = strings.t('partinfo.running_gear'), interior = 'Interior', paint = 'Paint' }

-- the catalog's chapter title in words ("EXHAUST SYSTEMS" -> "Exhaust systems")
local function sentence(t)
  t = tostring(t or ''):lower()
  return (t:gsub('^%l', string.upper))
end

-- a guess at the section from the slot's name, when the catalog is not there
local GUESS = {
  { 'engine', { 'engine', 'intake', 'exhaust', 'turbo', 'supercharger', 'nitrous', 'ecu', 'fuel', 'radiator', 'cooling', 'clutch', 'transmission', 'gearbox', 'flywheel', 'muffler', 'header' } },
  { 'running', { 'wheel', 'tire', 'tyre', 'rim', 'brake', 'suspension', 'shock', 'spring', 'swaybar', 'diff', 'axle', 'steering' } },
  { 'interior', { 'seat', 'dash', 'interior', 'gauge', 'pedal', 'cabin', 'wheel_cover' } },
  { 'paint', { 'paint', 'livery', 'decal' } },
  { 'body', { 'bumper', 'fender', 'hood', 'door', 'trunk', 'tailgate', 'roof', 'spoiler', 'wing', 'mirror', 'body', 'panel', 'light', 'skirt' } },
}
local function guessSection(slotId)
  local id = tostring(slotId or ''):lower()
  for _, g in ipairs(GUESS) do
    for _, w in ipairs(g[2]) do if id:find(w, 1, true) then return g[1] end end
  end
end

-- A jbeam name field is usually a string but some are tables (a translation { txt = '...' }, a list): always reduce one to a string,
-- or nil when there is no text in it (never "table: 0x...").
function M.text(v)
  if type(v) == 'string' then return v ~= '' and v or nil end
  if type(v) == 'table' then
    return M.text(v.txt) or M.text(v.val) or M.text(v.en) or M.text(v[1])
  end
end

-- a part's name as a person says it: the jbeam name when it is one, else the internal id turned into words
-- ("covet_exhaust_sport_2" -> "Exhaust sport 2" with the model "covet")
function M.displayName(name, partId, model)
  local n = M.text(name) or ''
  if n:find('^ui%.') then                                  -- a game translation key ("ui.vehicleconfig.generic.wheelName"): translated when the game can, else the id in words
    if type(translateLanguage) == 'function' then local ok, t = pcall(translateLanguage, n, n, true) if ok and type(t) == 'string' then n = t end end
    if n:find('^ui%.') then n = '' end
  end
  local internal = n == '' or n == tostring(partId) or (not n:find('%s') and (n:find('_', 1, true) or n:find('/', 1, true)))
  if not internal then return n end
  local s = M.text(partId) or n
  local prefix = tostring(model or ''):gsub('%p', '%%%0') .. '_'
  s = s:gsub('^' .. prefix, '', 1):gsub('[_/]+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if s == '' then s = 'Part' end
  return sentence(s)
end

-- The part's own picture (T41: tools/part_shots in the Wrench Works repo renders one for every stock part and the mod ships them in
-- art/street_legal/parts with a manifest). pictures = { fileName = true | the picture's fileName } from the manifest (parts, alias); nil or a part without one: no picture.
M.PICTURE_DIR = '/art/street_legal/parts/'
function M.fileName(partName) return (tostring(partName or ''):gsub('[^%w_%-]', '_')) end
function M.picture(partName, pictures)
  local f = M.fileName(partName)
  local v = pictures and pictures[f]
  if v then return M.PICTURE_DIR .. (type(v) == 'string' and v or f) .. '.png' end      -- (a string: the picture of a part drawn with the same meshes)
end

-- item = { part, name, slotId, model }; catalog = { classify = function(slotId, partName, desc) -> section, sub, sections = { { id, title, subs = { { id, title } } } } }
-- (Wrench Works' slrr/garageCatalog) or nil.  Returns { name, category (a key of CATEGORIES, or 'part'), categoryTitle, chapter }
function M.describe(item, catalog)
  local section, sub
  if catalog and catalog.classify then
    local ok, a, b = pcall(catalog.classify, item.slotId, item.part, nil)
    if ok then section, sub = a, b end
  end
  if not M.CATEGORIES[section or ''] then section = guessSection(item.slotId) end
  local chapter
  if catalog and catalog.sections and section and sub then
    for _, sec in ipairs(catalog.sections) do
      if sec.id == section then
        for _, sb in ipairs(sec.subs or {}) do if sb.id == sub then chapter = sentence(sb.title) end end
      end
    end
  end
  return { name = M.displayName(item.name, item.part, item.model), category = section or 'part', categoryTitle = section and M.CATEGORIES[section] or 'Part', chapter = chapter }
end

return M
