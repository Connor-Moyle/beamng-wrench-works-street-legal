-- Street Legal: how a part for sale is shown (T39). Pure, tested by tools/luatest.js. BeamNG has no picture file for a part (its own
-- part shops show the real 3D model in the garage, and its part inventory shows the CAR's thumbnail and a category icon), so an ad
-- for a part shows: the part's real display name (the jbeam "information.name"), what kind of part it is (the Wrench Works catalog's
-- chapter, e.g. "Exhaust systems") and which car it fits (name and the car's own picture), with a category icon as the fallback.

local M = {}

M.CATEGORIES = { engine = 'Engine', body = 'Body', running = 'Running gear', interior = 'Interior', paint = 'Paint' }

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

-- a part's name as a person says it: the jbeam name when it is one, else the internal id turned into words
-- ("covet_exhaust_sport_2" -> "Exhaust sport 2" with the model "covet")
function M.displayName(name, partId, model)
  local n = tostring(name or '')
  local internal = n == '' or n == tostring(partId) or (not n:find('%s') and (n:find('_', 1, true) or n:find('/', 1, true)))
  if not internal then return n end
  local s = tostring(partId or n)
  local prefix = tostring(model or ''):gsub('%p', '%%%0') .. '_'
  s = s:gsub('^' .. prefix, '', 1):gsub('[_/]+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if s == '' then s = 'Part' end
  return sentence(s)
end

-- The part's own picture (T41: tools/part_shots in the Wrench Works repo renders one for every stock part and the mod ships them in
-- art/street_legal/parts with a manifest). pictures = the set of file names the manifest lists (partPictures); nil or a part without one: no picture.
M.PICTURE_DIR = '/art/street_legal/parts/'
function M.fileName(partName) return (tostring(partName or ''):gsub('[^%w_%-]', '_')) end
function M.picture(partName, pictures)
  local f = M.fileName(partName)
  if pictures and pictures[f] then return M.PICTURE_DIR .. f .. '.png' end
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
