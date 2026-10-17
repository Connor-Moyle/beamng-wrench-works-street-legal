-- Street Legal: spectators (extension name: sl_spectators; #40)
-- West Coast USA's level has no crowds of its own. The career tells the SLRR Drivers mod (slrrPedestrians.addSpectatorZones) where people stand: beside the
-- drag strip's lanes, at the stretches of the race track's circuit (the start and finish and three more), and in a ring at every car meet spot. The mod
-- fills them near the camera, out of view, inside its frame-time budget, and everybody cheers when a race ends (onSlrrRaceFinished). A win at the drag
-- strip or in the Race of Champions sends the same cheer.

local M = {}

local rules = require('sl/core/spectators')

local CIRCUIT_FILE = '/gameplay/missions/west_coast_usa/aiRace/001-circuit/race.race.json'
local sent

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

local function dragLanes()
  local out = {}
  local ok, strips = pcall(function() return gameplay_drag_core and gameplay_drag_core.getDragDataForLevel(getCurrentLevelIdentifier()) end)
  local strip = ok and strips and strips[1] and strips[1].strip
  for _, lane in ipairs(strip and strip.lanes or {}) do
    local st = lane.waypoints and lane.waypoints.stage and lane.waypoints.stage.transform
    local en = lane.waypoints and lane.waypoints.endLine and lane.waypoints.endLine.transform
    if st and en and st.position and en.position then
      out[#out + 1] = { from = { x = st.position.x, y = st.position.y, z = st.position.z }, to = { x = en.position.x, y = en.position.y, z = en.position.z } }
    end
  end
  return out
end

local function circuitNodes()
  local race = jsonReadFile(CIRCUIT_FILE)
  local out = {}
  for _, n in ipairs(type(race) == 'table' and race.pathnodes or {}) do
    if type(n.pos) == 'table' and #n.pos >= 3 then out[#out + 1] = { pos = n.pos, radius = tonumber(n.radius) } end
  end
  return out
end

local function build()
  local zones = {}
  local function add(z) if z then zones[#zones + 1] = z end end
  add(rules.zone('wcusa_drag', 'race', rules.dragStrip(dragLanes())))
  for i, spots in ipairs(rules.circuitStands(circuitNodes())) do add(rules.zone('wcusa_track_' .. i, 'race', spots)) end
  for id, p in pairs(sl_career.getPlaces() or {}) do
    if p.kind == 'meet' and p.pos then add(rules.zone('wcusa_meet_' .. id, 'meet', rules.ring({ x = p.pos.x, y = p.pos.y, z = p.pos.z }, 9, 13, 24))) end
  end
  return zones
end

local function send()
  if not career() or not (slrrPedestrians and slrrPedestrians.addSpectatorZones) then return end
  if sl_career.LEVEL ~= 'west_coast_usa' then return end            -- Valo City's level has its own crowds
  local ok, zones = pcall(build)
  if ok and #zones > 0 then
    slrrPedestrians.addSpectatorZones(zones)
    sent = #zones
  end
end

function M.zonesSent() return sent or 0 end
function M.onStreetLegalStarted() send() end
function M.onStreetLegalPlacesChanged() send() end
function M.onClientPostStartMission() sent = nil end
function M.onStreetLegalStopped()
  sent = nil
  if slrrPedestrians and slrrPedestrians.clearSpectatorZones then slrrPedestrians.clearSpectatorZones() end
end

return M
