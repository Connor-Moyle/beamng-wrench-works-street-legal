-- Street Legal: the markers of the career's places (extension name: sl_pois; T33)
-- The game draws a marker, a big-map entry and a prompt for every point of interest an extension lists in
-- onGetRawPoiListForLevel. Nothing listed the career's lots on West Coast USA (Valo City's map mod did), so no lot had a marker
-- or a prompt. Here: every dealer, used lot and scrap yard of sl_career.getPlaces(). A stock dealership gets the game's own marker
-- (freeroam_facilities.formatFacilityToRawPoi: its doors, its icon, its name, its big-map card), with our data on it so
-- its prompt opens sl_lot: ONE marker, the walking marker at the dealership door (a driver drives up, gets out and walks in, as in the
-- game's career); the used lot and the scrap yard get the game's mission marker. The stock career's own markers are not added (it is not running).

local M = {}

local pois = require('sl/core/pois')

local ICON = 'mission_arrival_triangle'

local function careerOn() return sl_career ~= nil and sl_career.isActive() == true end
local function stockCareerOn() return career_career ~= nil and career_career.isActive and career_career.isActive() == true end

local function stockFacility(id, level)
  if not (id and freeroam_facilities and freeroam_facilities.getFacilitiesByType) then return nil end
  for _, f in ipairs(freeroam_facilities.getFacilitiesByType('dealership', level) or {}) do
    if f.id == id then return f end
  end
end

function M.onGetRawPoiListForLevel(level, elements)
  if not careerOn() or stockCareerOn() then return end
  for _, r in ipairs(pois.records(sl_career.getPlaces())) do
    local data = { type = r.type, id = r.poiId, placeId = r.placeId, name = r.name }
    local fac = stockFacility(r.stockId, level)
    local el
    if fac then
      local tmp = {}
      local ok = pcall(freeroam_facilities.formatFacilityToRawPoi, fac, tmp)
      el = ok and tmp[1] or nil
      if el then el.id, el.data = r.poiId, data end                     -- (no .facility: the game's own dealership prompt would call its career shop)
    end
    if not el then
      local pos = vec3(r.pos[1], r.pos[2], r.pos[3])
      el = {
        id = r.poiId, data = data, clusterType = 'missionMarker', clusterInBigMap = true, clusterInPlayMode = false,
        interactableInPlayMode = true, quickTravelAvailable = false,
        markerInfo = {
          missionMarker = { pos = pos, rot = quat(0, 0, 0, 1), icon = ICON },
          bigmapMarker = { pos = pos, icon = ICON, cardIcon = r.cardIcon, name = r.name, description = r.what },
        },
      }
    end
    elements[#elements + 1] = el
  end
end

-- Fast travel keeps the damage (B67). The game's big map teleport outside ITS career resets the car (spawn.safeTeleport with a reset, then
-- resetBrokenFlexMesh) and so repairs it for nothing; inside its own career it does not reset. So while this career runs,
-- freeroam_bigMapMode.teleportToPoi is ours: the same steps, with no reset. The game's own is put back when the career stops.
local patch = require('sl/core/patch')
local saved = {}
local savedRaw = {}
local rules = require('sl/core/activityrules')

local function teleportToPoi(poiId)
  local bm = freeroam_bigMapMode
  for _, cluster in ipairs(gameplay_playmodeMarkers.getPlaymodeClusters()) do       -- the target for the marker interaction, as the game does
    if cluster.containedIdsLookup and cluster.containedIdsLookup[poiId] then
      cluster.focus = true
      extensions.hook('onNavigateToMission', cluster.id)
      gameplay_markerInteraction.reachedTargetPos = cluster.pos
    end
  end
  for _, poi in ipairs(gameplay_rawPois.getRawPoiListByLevel(getCurrentLevelIdentifier())) do
    if poiId == poi.id then
      local veh = getPlayerVehicle(0)
      if veh then
        local pos, rot = (poi.markerInfo.bigmapMarker.quickTravelPosRotFunction or nop)(poi, veh)
        if pos and rot then
          spawn.safeTeleport(veh, pos, rot, nil, nil, nil, nil, false)          -- false: no reset, the damage stays
          if core_groundMarkers.currentlyHasTarget() then bm.setNavFocus(core_groundMarkers.endWP[1]) end
          bm.exitBigMap(false, true, true)
          core_camera.resetCamera(0)
          extensions.hook('teleportedFromBigmap')
        end
      end
    end
  end
end

-- At night the stock track events (time trials, drag strips, circuits) have no marker and no prompt (D2): the list the game builds once
-- stays whole, what the markers and the big map get is a copy without them (the same copy while the list and the phase are the same).
local filtered = {}
local function dayEventsHidden(levelId, list, gen)
  local phase = sl_career.phase()
  if phase ~= 'night' then return list, gen end
  if filtered.src ~= list or filtered.phase ~= phase then
    local out = {}
    for _, e in ipairs(list) do
      if not (e.data and e.data.type == 'mission' and rules.closed(levelId, e.data.missionId, phase)) then out[#out + 1] = e end
    end
    filtered = { src = list, phase = phase, out = out }
  end
  return filtered.out, gen
end
local function rawList(levelId)
  local orig = savedRaw.getRawPoiListByLevel and savedRaw.getRawPoiListByLevel.original
  if not orig then return {} end
  local list, gen = orig(levelId)
  if not (careerOn() and type(list) == 'table') then return list, gen end
  return dayEventsHidden(levelId, list, gen)
end

local function installTeleport()
  if freeroam_bigMapMode and careerOn() and not stockCareerOn() then patch.install(freeroam_bigMapMode, 'teleportToPoi', teleportToPoi, saved) end
  if gameplay_rawPois and careerOn() and not stockCareerOn() then patch.install(gameplay_rawPois, 'getRawPoiListByLevel', rawList, savedRaw) end
end
local function removeTeleport()
  if freeroam_bigMapMode then patch.restore(freeroam_bigMapMode, 'teleportToPoi', saved) end
  if gameplay_rawPois then patch.restore(gameplay_rawPois, 'getRawPoiListByLevel', savedRaw) end
end

-- the game builds this list once per level: again when a career starts or stops and when the places change
local function refresh() if gameplay_rawPois and gameplay_rawPois.clear then gameplay_rawPois.clear() end end
M.onStreetLegalStarted = function() refresh() installTeleport() end
M.onStreetLegalStopped = function() refresh() removeTeleport() end
M.onBigMapActivated = installTeleport            -- (the big map is opening: ours is in place, also after the game reloaded its module)
M.onExtensionUnloaded = removeTeleport
M.onStreetLegalPlacesChanged = refresh
M.onStreetLegalPhase = refresh            -- (the day events come back in the morning, go at night)

return M
