-- Lists every point of interest the game would draw for the career's places (T33). Run in the game's GE Lua with a career running:
--   node bng.js run_lua @tools/poi_probe.lua      then read the returned text (or  return POI_PROBE_REPORT)
-- For each element: the game's raw list (gameplay_rawPois, what the big map and the markers are made from), whether the play-mode
-- marker clusters hold it (what is drawn in the world and gives the prompt), and the prompt buttons it would show.
local out = {}
local function say(...) out[#out + 1] = string.format(...) end

local level = getCurrentLevelIdentifier()
if not (sl_career and sl_career.isActive()) then return 'no career running' end
local places = sl_career.getPlaces() or {}
local nPlaces = 0
for _ in pairs(places) do nPlaces = nPlaces + 1 end
say('level %s, %d career places, stock career active: %s', tostring(level), nPlaces, tostring(career_career and career_career.isActive()))

local raw = gameplay_rawPois.getRawPoiListByLevel(level)
local ours, stockOnes = {}, 0
for _, e in ipairs(raw) do
  local d = e.data or {}
  if d.placeId or tostring(e.id):find('^sl_') then ours[#ours + 1] = e
  elseif d.type == 'dealership' or d.type == 'garage' or d.type == 'computer' then stockOnes = stockOnes + 1 end
end
say('raw POIs: %d, ours %d, stock dealership/garage/computer POIs from the game itself: %d (must be 0 while the stock career is off)', #raw, #ours, stockOnes)

-- which clusters (the markers drawn in the world) hold each of our elements: a mission marker's cluster lists containedIds, a walking
-- marker's only has its elemData (the first version of this probe looked only at containedIds and called every dealer "not drawn")
local clustered = {}
local okc, clusters = pcall(gameplay_playmodeMarkers.getPlaymodeClusters)
for _, c in ipairs(okc and clusters or {}) do
  local kind = tostring(c.id):match('^(%a+)#') or '?'
  for _, id in ipairs(c.containedIds or {}) do clustered[id] = clustered[id] or {} clustered[id][kind] = true end
  for _, d in ipairs(c.elemData or {}) do
    if type(d) == 'table' and d.id then clustered[d.id] = clustered[d.id] or {} clustered[d.id][kind] = true end
  end
end
local function drawnList(id)
  local t = {}
  for k in pairs(clustered[id] or {}) do t[#t + 1] = k end
  table.sort(t)
  return #t > 0 and table.concat(t, ',') or 'NO'
end

for _, e in ipairs(ours) do
  local d, mi = e.data or {}, e.markerInfo or {}
  local kinds = {}
  for k in pairs(mi) do kinds[#kinds + 1] = k end
  table.sort(kinds)
  local bm = mi.bigmapMarker
  local pos = (mi.walkingMarker and mi.walkingMarker.pos) or (mi.missionMarker and mi.missionMarker.pos) or (bm and bm.pos)
  say('%-28s type=%-10s place=%-14s markers=[%s]  at %s  bigmap=%s (%s)  drawn-in-world=%s', tostring(e.id), tostring(d.type), tostring(d.placeId),
    table.concat(kinds, ','), pos and string.format('%.0f,%.0f,%.0f', pos.x, pos.y, pos.z) or '?', bm and 'yes' or 'NO',
    bm and tostring(bm.name) or '-', drawnList(e.id))
  -- the prompt the game would put up here
  local act = {}
  extensions.hook('onActivityAcceptGatherData', { d }, act)
  for _, a in ipairs(act) do say('    prompt: "%s" > button "%s"', tostring(a.heading), tostring(a.buttonLabel)) end
  if #act == 0 then say('    prompt: NONE (it depends on being on foot or in a car: run again in the other state)') end
end
-- the places that should have one and do not
for id, p in pairs(places) do
  if p.kind == 'dealer' or p.kind == 'junkyard' or p.kind == 'scrapyard' then
    local found = false
    for _, e in ipairs(ours) do if e.data and e.data.placeId == id then found = true end end
    if not found then say('MISSING: place %s (%s, %s) has no POI', id, p.kind, tostring(p.name)) end
  end
end
rawset(_G, 'POI_PROBE_REPORT', table.concat(out, '\n'))
return table.concat(out, '\n')
