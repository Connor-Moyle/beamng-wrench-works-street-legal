-- Street Legal: tier perks (extension name: sl_perks; career expansion #6). Rules in sl/core/perks. Other modules ask sl_perks.factor('upgrades' | 'service' | 'jobs' | 'fines' | 'loans');
-- with the part off or no career the answer is nil (they use 1).

local M = {}

local perks = require('sl/core/perks')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

function M.rank()
  return career() and sl_rivals and sl_rivals.rank and sl_rivals.rank() or 1
end

function M.factor(kind)
  if not career() then return nil end
  local f = perks.factor(M.rank(), kind)
  local v = sl_options and sl_options.get and tonumber((sl_options.get('slPerkStrength')))
  if v and v ~= 100 then f = 1 + (f - 1) * v / 100 end          -- (the Perk strength setting)
  return f
end

function M.perks()
  if not career() then return nil end
  return perks.list(M.rank())
end

require('sl/core/features').gate('perks', M, nil, nil, { 'factor', 'perks' })

return M
