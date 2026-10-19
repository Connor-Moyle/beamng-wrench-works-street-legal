-- Street Legal: may a feature run now? In a career always (as before); in free roam only when the master switch and the feature's switch are on (Mods menu,
-- off by default). Pure, tested by tools/luatest.js; sl/mode.lua is the game side (the switches, the sandbox state).
local strings = require('sl/core/strings')

local M = {}

M.MASTER = 'freeroam'
-- the features that can run in free roam, in menu order (0.6.0); jobs, races and police follow in 0.6.1. Everything else (rep, rivals, the campaign, the career's
-- shops of cars, the bank...) is career-only: enabled() is false for it in free roam whatever the switches.
M.IDS = { 'phone', 'maps', 'places', 'weather', 'traffic', 'shops', 'wash', 'cab', 'hud', 'clock' }

local known = { [M.MASTER] = true }
for _, id in ipairs(M.IDS) do known[id] = true end

-- { id, title, tip, default } for the Mods menu rows (the master first)
function M.FEATURES()
  local out = {}
  local ids = { M.MASTER }
  for _, id in ipairs(M.IDS) do ids[#ids + 1] = id end
  for _, id in ipairs(ids) do
    out[#out + 1] = { id = id, title = strings.t('mode.' .. id), tip = strings.t('mode.' .. id .. '_tip'), default = false }
  end
  return out
end

-- the settings key of a switch (the master keeps its own id)
function M.key(id) return id == M.MASTER and id or ('freeroam_' .. id) end

-- 'career' | 'freeroam' (no career, master on) | nil; sw(key) -> boolean reads a switch
function M.kind(careerActive, sw)
  if careerActive then return 'career' end
  if sw and sw(M.key(M.MASTER)) == true then return 'freeroam' end
  return nil
end

function M.enabled(careerActive, sw, feature)
  if careerActive then return true end
  return M.kind(false, sw) == 'freeroam' and known[feature] == true and feature ~= M.MASTER and sw(M.key(feature)) == true
end

return M
