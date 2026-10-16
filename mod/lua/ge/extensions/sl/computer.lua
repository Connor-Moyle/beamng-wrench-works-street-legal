-- Wrench Works: Street Legal: the laptops (extension name: sl_computer)
-- BeamNG's maps list computer facilities (West Coast USA has five); the stock career opens its menu there. In a
-- Street Legal career they are a game marker (the ring and prompt the lots use): stopping or walking into it
-- offers "Use the laptop", which opens the phone. Valo City has none, so nothing happens there.

local M = {}

local computer = require('sl/core/computer')

local ICON = 'mission_arrival_triangle'

local function careerOn() return sl_career ~= nil and sl_career.isActive() == true end

local function posOf(f)
  local p = freeroam_facilities.getAverageDoorPositionForFacility(f)
  return p and p:length() > 0.01 and p or nil      -- (no door objects found: the game returns a zero vector)
end

-- the game asks every extension for its markers once per level (cached): ours join them while a career runs
function M.onGetRawPoiListForLevel(level, elements)
  if not (careerOn() and freeroam_facilities and freeroam_facilities.getFacilitiesByType) then return end
  local list = freeroam_facilities.getFacilitiesByType('computer', level) or {}
  for _, c in ipairs(computer.points(true, list, posOf)) do
    elements[#elements + 1] = { id = 'sl_computer_' .. c.id, data = { type = 'slrrComputer', id = c.id, name = c.name },
      markerInfo = { missionMarker = { pos = c.pos, rot = quat(0, 0, 0, 1), icon = ICON } } }
  end
end

-- standing in the marker: the game's prompt gets our button
function M.onActivityAcceptGatherData(elemData, activityData)
  if not careerOn() then return end
  for _, elem in ipairs(elemData or {}) do
    if elem.type == 'slrrComputer' then
      table.insert(activityData, {
        icon = 'poi_arrival_round', heading = translateLanguage and translateLanguage(elem.name, 'Computer', true) or 'Computer',   -- (the facility's name is a translation key) preheadings = { 'Laptop' },
        sorting = { type = 'slrrComputer', id = elem.id },
        buttonLabel = 'Use the laptop', buttonFun = function() if sl_phone then sl_phone.toggle() end end,
        buttonSoundClass = 'bng_hover_generic',
      })
    end
  end
end

-- the marker list is cached by the game: build it again when a career starts or stops
local function refresh() if gameplay_rawPois and gameplay_rawPois.clear then gameplay_rawPois.clear() end end
M.onStreetLegalStarted = refresh
M.onStreetLegalStopped = refresh

return M
