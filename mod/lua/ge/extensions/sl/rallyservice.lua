-- Street Legal: the rally service stall (extension name: sl_rallyservice; part of Career travel, T6). On a rally visit (sl_career.visit() on a map
-- with a rally loop, sl/core/rallyservice.LOOPS) the game's service stall is the one workbench: sl_service asks atStall() for the service card's
-- rate; the stall is a pin on the big map and a marker in play mode; a toast says so the first time the car stops there in a day.

local M = {}

local rules = require('sl/core/rallyservice')
local strings = require('sl/core/strings')
local features = require('sl/core/features')

local stall, stallLevel = nil, nil        -- read once per level

local function visiting() return sl_career and sl_career.isActive and sl_career.isActive() and sl_career.visit and sl_career.visit() ~= nil end
local function load()
  local level = sl_career and sl_career.LEVEL
  if stallLevel == level then return stall end
  stallLevel, stall = level, nil
  local file = level and rules.LOOPS[level]
  if not file then return nil end
  local ok, info = pcall(jsonReadFile, file)
  stall = ok and rules.stallOf(info) or nil
  return stall
end

function M.stall() return visiting() and load() or nil end

-- true while the player's car stands at the stall (a visit on a rally map only)
function M.atStall()
  local st = M.stall()
  local v = st and getPlayerVehicle(0)
  if not v then return false end
  return rules.atStall(v:getPosition(), st)
end

-- the pin: on the big map and in play mode, not interactable (the service card is on the phone)
function M.onGetRawPoiListForLevel(level, elements)
  local st = M.stall()
  if not st or level ~= sl_career.LEVEL then return end
  local pos = vec3(st.pos.x, st.pos.y, st.pos.z)
  elements[#elements + 1] = {
    id = 'sl_rally_stall', data = { type = 'other', name = strings.t('rallyservice.service_stall'), date = 0 }, clusterType = 'missionMarker', clusterInBigMap = true, clusterInPlayMode = true,
    interactableInPlayMode = false, quickTravelAvailable = false,
    markerInfo = {
      missionMarker = { pos = pos, rot = quat(0, 0, 0, 1), icon = 'mission_arrival_triangle' },
      bigmapMarker = { pos = pos, icon = 'mission_arrival_triangle', name = strings.t('rallyservice.service_stall'), description = strings.t('rallyservice.stall_desc') },
    },
  }
end

-- a toast the first time the car stops at the stall each day
local toldDay, tickT = nil, 0
function M.onUpdate(dtReal)
  tickT = tickT + dtReal
  if tickT < 1 then return end
  tickT = 0
  local s = visiting() and sl_career.getState() or nil
  if not s or toldDay == s.day then return end
  if M.atStall() then
    toldDay = s.day
    guihooks.trigger('slPhoneToast', { text = strings.t('rallyservice.at_the_stall') })
  end
end

function M.onClientStartMission() stallLevel, stall, toldDay = nil, nil, nil end
function M.onStreetLegalStopped() stallLevel, stall, toldDay = nil, nil, nil end
function M.onClientEndMission() stallLevel, stall, toldDay = nil, nil, nil end
function M.status()
  local st = M.stall()
  if not st then return 'no stall here' end
  return string.format('stall at %.0f, %.0f (r %.0f): %s', st.pos.x, st.pos.y, st.radius, M.atStall() and 'at it' or 'away')
end

features.gate('travel', M, nil, nil, { 'atStall', 'stall' })      -- (the Career travel part off: no stall, no pin)

return M
