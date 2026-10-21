-- Street Legal: may a feature run now? (extension name: sl_mode) The game side of sl/core/mode: in a career always; in free roam only when the master switch and the feature's switch are on
-- (Mods menu > Street Legal > Free roam, all off by default; kept in options.json). state(): the career's state, or in free roam the sandbox state that is never saved.
local M = {}

local core = require('sl/core/mode')

local function careerActive() return sl_career ~= nil and sl_career.isActive() == true end
local function sw(key) return sl_options ~= nil and sl_options.get(key) == true end

function M.kind() return core.kind(careerActive(), sw) end
function M.enabled(feature) return core.enabled(careerActive(), sw, feature) end

-- the career's state in a career; in free roam with the feature on, the sandbox state (seed, day, phase, hour: see core/mode, never saved); else nil
local sandbox
local function gameHour()
  local tod = core_environment and core_environment.getTimeOfDay and core_environment.getTimeOfDay()
  if type(tod) ~= 'table' or not tod.time then return nil end
  return (tod.time * 24 + 12) % 24
end
function M.state(feature)
  if careerActive() then return sl_career.getState() end
  if not M.enabled(feature) then return nil end
  sandbox = core.sandbox(sandbox, gameHour(), os.time() % 100000)
  return sandbox
end
function M.onClientEndMission() sandbox = nil end

return M
