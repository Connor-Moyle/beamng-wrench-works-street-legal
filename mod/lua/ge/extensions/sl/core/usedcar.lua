-- Street Legal: used-car checks (career expansion #3). A private ad for a car shows its history but not its faults: a paid check ("take it to a mechanic") shows them and what each costs
-- to put right. The history lines are read off the listing (mileage, faults, condition) by a seeded roll, so a careful buyer can guess from a patchy service record. Pure, no game calls:
-- tested by tools/luatest.js.

local M = {}

local strings = require('sl/core/strings')
local rngLib = require('sl/core/rng')

M.FEE_BASE, M.FEE_SHARE = 40, 0.005       -- the mechanic's check: $40 + 0.5 % of the asking price

function M.fee(ask) return math.floor((M.FEE_BASE + (ask or 0) * M.FEE_SHARE) / 10 + 0.5) * 10 end

-- lines about the car's past: { owners = n, lines = { text } }. condition 0..1, faults = the list of open faults
function M.history(seed, mileage, faults, condition)
  local rng = rngLib.new(rngLib.hash(tostring(seed)))
  local owners = math.max(1, math.floor((mileage or 0) / 60000) + rng:int(0, 1))
  local bad = math.min(0.85, 0.2 + 0.2 * math.min(3, #(faults or {})))
  local roll = rng:float()
  local service = roll < bad * 0.5 and 'none' or (roll < bad and 'patchy' or 'full')
  local crash = rng:chance(0.08 + 0.3 * math.max(0, 0.9 - (condition or 0.8)))
  return { owners = owners, lines = {
    strings.t('usedcar.owners', owners),
    strings.t('usedcar.service_' .. service),
    strings.t(crash and 'usedcar.accident_yes' or 'usedcar.accident_no'),
  } }
end

-- what the check finds: { { label, cost } } with each fault's cost (share of the car's value, core/carreport FAULT_COST)
function M.faultCosts(faults, value, share)
  local out = {}
  for _, f in ipairs(faults or {}) do out[#out + 1] = { label = strings.t('usedcar.fault_' .. tostring(f)), cost = math.floor((value or 0) * share / 10 + 0.5) * 10 } end
  return out
end

return M
