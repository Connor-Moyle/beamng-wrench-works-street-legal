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

-- The sandbox state of a free-roam session: only what the features need to run (a seed for the weather, the day, the phase and the hour from the game's clock). No money, no cars, no
-- rep: nothing a wallet or a garage could be asked for. Never saved, never the career's. `sb` is the table kept by the caller; hour = the game's hour of day (0-24) or nil.
function M.sandbox(sb, hour, seed)
  sb = sb or { seed = math.floor(tonumber(seed) or 1), day = 1, phase = 'day', hour = 12, sandbox = true }
  if type(hour) == 'number' then
    if hour < sb.hour - 12 then sb.day = sb.day + 1 end      -- (the clock went past midnight)
    sb.hour = hour
    local dark = hour >= 21 or hour < 4
    sb.phase = dark and 'night' or 'day'
  end
  return sb
end

return M
