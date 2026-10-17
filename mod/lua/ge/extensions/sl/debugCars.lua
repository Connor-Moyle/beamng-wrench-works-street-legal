-- Street Legal Racing: the custom cars, for testing (extension name: sl_debugCars)
-- The showroom lineup (sl/core/showroom) - the street builds and track cars the racers drive -
-- kept out of the game's vehicle selector on purpose. Nothing is written to disk: a car is
-- built when it is asked for, from the console:
--   sl_debugCars.list()            the lineup, numbered
--   sl_debugCars.spawn(12)         that car, in front of you, and you in it
--   sl_debugCars.spawn("Night Fury")   the first one whose name contains that

local M = {}

local strings = require('sl/core/strings')

local showroom = require('sl/core/showroom')
local builder = require('sl/carBuilder')

local lineupCache

local function lineup()
  lineupCache = lineupCache or showroom.lineup(builder.configs(), showroom.SEED)
  return lineupCache
end

function M.list()
  local lines = {}
  for i, e in ipairs(lineup()) do lines[#lines + 1] = string.format('%2d  %s', i, e.label) end
  local text = table.concat(lines, '\n')
  print(text)
  return #lines .. ' cars'
end

local function find(which)
  local list = lineup()
  if tonumber(which) then return list[tonumber(which)] end
  local q = tostring(which or ''):lower()
  for _, e in ipairs(list) do
    if e.label:lower():find(q, 1, true) then return e end
  end
end

function M.spawn(which)
  local entry = find(which)
  if not entry then return strings.t('debugCars.no_such_car_sl_debugcars') end
  local player = getPlayerVehicle(0)
  local pos, rot
  if player then
    local dir = vec3(player:getDirectionVector())
    dir.z = 0
    dir = dir:length() > 0.01 and dir:normalized() or vec3(0, 1, 0)
    pos = player:getPosition() + dir * 7 + vec3(0, 0, 0.5)
    rot = quatFromDir(dir, vec3(0, 0, 1))
  else
    pos = core_camera.getPosition()
  end
  core_jobsystem.create(function(job)
    local veh = builder.buildCustom(job, entry.model, entry.config, { stage = entry.stage, seed = entry.seed }, pos, rot)
    if not veh then
      log('W', 'street_legal', strings.t('debugCars.debug_car_could_not_be') .. entry.label)
      return
    end
    if gameplay_walk and gameplay_walk.getInVehicle then gameplay_walk.getInVehicle(veh) else be:enterVehicle(0, veh) end
    log('I', 'street_legal', strings.t('debugCars.debug_car') .. entry.label)
  end)
  return strings.t('debugCars.building_1', (entry.label))
end

return M
