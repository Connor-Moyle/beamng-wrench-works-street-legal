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

-- the game builds this list once per level: again when a career starts or stops and when the places change
local function refresh() if gameplay_rawPois and gameplay_rawPois.clear then gameplay_rawPois.clear() end end
M.onStreetLegalStarted = refresh
M.onStreetLegalStopped = refresh
M.onStreetLegalPlacesChanged = refresh

return M
