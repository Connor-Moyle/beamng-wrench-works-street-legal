-- Wrench Works: Street Legal: what your garage has (extension name: sl_upgrades; X58, Design 7)
-- In the career, Wrench Works' tools are bought for the garage: a lift, a workbench, a dyno, a paint booth, more
-- shelving, a photo corner (prices and rules in sl/core/progression). Bought ones stay with that garage; the club
-- garages come with the lift and the bench. Wrench Works is told what this garage has (slrr_garage.setFeatures);
-- off the career it has everything again.

local M = {}

local strings = require('sl/core/strings')

local progression = require('sl/core/progression')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

local function bought(s)
  s.upgrades = s.upgrades or {}
  local level = tostring(s.garageLevel or 1)
  s.upgrades[level] = s.upgrades[level] or {}
  return s.upgrades[level]
end

function M.features(s)
  s = s or career()
  return s and progression.garageFeatures(bought(s), s.garageLevel or 1) or nil
end

-- Wrench Works told whenever what the garage has changes
local sent
local function push()
  if not (slrr_garage and slrr_garage.setFeatures) then return end
  local f = M.features()
  local sig = f and string.format('%s%s%s%s%s%s%d', tostring(f.lift), tostring(f.crane), tostring(f.workbench), tostring(f.dyno), tostring(f.paint), tostring(f.photo), f.shelfSize) or 'all'
  if sig == sent then return end
  sent = sig
  slrr_garage.setFeatures(f)
end

function M.buy(id)
  local s = career()
  if not s then return false, strings.t('bank.no_career_running') end
  local u = progression.upgrade(id)
  if not u then return false, strings.t('upgrades.no_such_thing') end
  local f = M.features(s)
  if (id == 'shelves' and f.shelfSize > progression.SHELF.base) or (id ~= 'shelves' and f[id]) then return false, strings.t('upgrades.the_garage_has_one_already') end
  local price = math.floor(u.price * (sl_perks and sl_perks.factor('upgrades') or 1) / 10 + 0.5) * 10
  if not sl_career.addMoney(-price, strings.t('upgrades.garage_1', (u.name))) then return false, string.format(strings.t('upgrades.s_d_you_have_d'), u.name, price, s.money) end
  bought(s)[id] = true
  push()
  extensions.hook('onStreetLegalChanged')
  return true, string.format(strings.t('upgrades.s_fitted_in_the_garage'), u.name, price)
end

-- for the phone's Garage app
function M.summary()
  local s = career()
  if not s then return nil end
  local f, out = M.features(s), {}
  for _, u in ipairs(progression.UPGRADES) do
    local has = (u.id == 'shelves') and f.shelfSize > progression.SHELF.base or f[u.id] == true
    out[#out + 1] = { id = u.id, name = u.name, price = math.floor(u.price * (sl_perks and sl_perks.factor('upgrades') or 1) / 10 + 0.5) * 10, desc = u.desc, has = has }
  end
  return out
end

local timer = 0
function M.onUpdate(dtReal)
  timer = timer + (dtReal or 0)
  if timer < 2 then return end
  timer = 0
  if career() then push() end
end
function M.onStreetLegalStopped()
  sent = nil
  if slrr_garage and slrr_garage.setFeatures then slrr_garage.setFeatures(nil) end
end
function M.onStreetLegalStarted() sent = nil push() end

-- (the Mods menu's Parts of the game: with this part off, the hooks above do nothing)
require('sl/core/features').gate('upgrades', M, nil, nil, { 'buy', 'summary' }, { 'onStreetLegalStarted' })

return M
