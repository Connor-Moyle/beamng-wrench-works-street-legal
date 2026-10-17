-- Street Legal: sponsor billboards (extension name: sl_billboards; #47)
-- West Coast USA's stock billboards share one ad atlas (material 'billboards'). While the career has a sponsor (or a club) the atlas with five of the
-- ads replaced by its own is put on the material (sl/core/billboards; the atlases come from tools/make_billboards.py), and it changes when the sponsor
-- does. The material's own atlas is put back when the career stops. Only on West Coast USA.

local M = {}

local rules = require('sl/core/billboards')

local current            -- the name now on the billboards (nil: the stock ads)
local original           -- the material's own atlas, kept to put back
local timer = 0

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

local function material() return scenetree.findObject(rules.MATERIAL) end

local function setAtlas(path)
  local mat = material()
  if not mat then return false end
  if not original then original = mat:getField('baseColorMap', 0) end
  if original == '' then original = rules.ORIGINAL end
  mat:setField('baseColorMap', 0, path or original)
  mat:reload()
  return true
end

local function wanted()
  local s = career()
  if not s then return nil end
  local sponsor = sl_jobs and sl_jobs.summary and (sl_jobs.summary() or {}).sponsor
  local clubLevel = s.club and s.club.club
  return rules.choose(sponsor and sponsor.name, clubLevel)
end

local function sync()
  if sl_career.LEVEL ~= 'west_coast_usa' then return end
  local name = wanted()
  if name == current then return end
  local file = rules.file(name)
  if file and not FS:fileExists(file) then log('W', 'sl_billboards', 'no atlas ' .. file) return end
  if setAtlas(file) then current = name end
end

function M.current() return current end
function M.onStreetLegalStarted() sync() end
function M.onStreetLegalChanged() sync() end
function M.onUpdate(dtReal)
  timer = timer + (dtReal or 0)
  if timer > 5 then timer = 0 if career() then sync() end end         -- (a new sponsor comes with a day's end)
end

local function restore()
  if current ~= nil and original then setAtlas(nil) end
  current, original = nil, nil
end
function M.onStreetLegalStopped() restore() end
function M.onClientEndMission() current, original = nil, nil end
function M.onExtensionUnloaded() restore() end

return M
