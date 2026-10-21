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

local composing, failed      -- the atlas being drawn in the game (overlay mode): { name, step, out }; names that could not be drawn

local function sync()
  if sl_career.LEVEL ~= 'west_coast_usa' then return end
  local name = wanted()
  if name == current then return end
  if composing and composing.name ~= name then composing = nil end
  if composing or (failed and failed[name]) then return end
  local plan = rules.plan(name, function(f) return FS:fileExists(f) end)
  if name and not plan then log('W', 'sl_billboards', 'no atlas ' .. tostring(rules.file(name))) return end
  if plan and plan.kind == 'tiles' then
    -- overlay mode: no atlas in the mod, so the game's own is drawn on with our five ads (a few frames' work)
    local ok, step, why = pcall(rules.composer, function() return GBitmap() end, function() return ColorI(0, 0, 0, 255) end, original or rules.ORIGINAL, plan,
      { budget = 0.003, clock = os.clock, prepare = function() if FS.directoryCreate then FS:directoryCreate(rules.TEMP, true) end end })
    if not ok or not step then
      failed = failed or {}
      failed[name] = true
      log('W', 'sl_billboards', 'billboards: ' .. tostring(not ok and step or why))
      return
    end
    composing = { name = name, step = step, out = plan.out }
    return
  end
  if setAtlas(plan and plan.file or nil) then current = name end
end

function M.current() return current end
function M.onStreetLegalStarted() sync() end
function M.onStreetLegalChanged() sync() end
function M.onUpdate(dtReal)
  if composing then
    local done, ok, why = composing.step()
    if done then
      local c = composing
      composing = nil
      if ok and setAtlas(c.out) then current = c.name
      else failed = failed or {} failed[c.name] = true log('W', 'sl_billboards', 'billboards: ' .. tostring(why or 'cannot use ' .. c.out)) end
    end
    return
  end
  timer = timer + (dtReal or 0)
  if timer > 5 then timer = 0 if career() then sync() end end         -- (a new sponsor comes with a day's end)
end

local function restore()
  if current ~= nil and original then setAtlas(nil) end
  current, original, composing = nil, nil, nil
end
function M.onStreetLegalStopped() restore() end
function M.onClientEndMission() current, original, composing, failed = nil, nil, nil, nil end
function M.onExtensionUnloaded() restore() end

-- (the Mods menu's Parts of the game: with this part off, the hooks above do nothing)
require('sl/core/features').gate('billboards', M)

return M
