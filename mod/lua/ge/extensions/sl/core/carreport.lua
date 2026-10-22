-- Street Legal: the full car report (#58). Pure, tested by tools/luatest.js. Every part of a used car by section (engine, drivetrain,
-- suspension, brakes, wheels and tyres, body, interior) with its condition, the dents, the open faults and a repair estimate per section.
-- It is built from what the offer already carries (condition, damage, mileage, faults, value) and nothing else, so the card, an ad and
-- the car in your garage (the same fields on the car record, after repairs: market.effectiveCondition) show the same numbers.

local market = require('sl/core/market')
local rngLib = require('sl/core/rng')

local M = {}

local strings = require('sl/core/strings')

M.SECTIONS = {
  { id = 'engine', title = 'Engine', mech = true, parts = { strings.t('carreport.engine_block'), 'Cooling', 'Battery', 'Exhaust', strings.t('carreport.intake_and_fuel') } },
  { id = 'drivetrain', title = 'Drivetrain', mech = true, parts = { 'Gearbox', 'Clutch', 'Driveshaft', 'Differential' } },
  { id = 'suspension', title = 'Suspension', mech = true, parts = { strings.t('carreport.springs_and_dampers'), strings.t('carreport.arms_and_bushings') } },
  { id = 'brakes', title = 'Brakes', mech = true, parts = { strings.t('carreport.pads_and_discs'), strings.t('carreport.calipers_and_lines') } },
  { id = 'wheels', title = strings.t('carreport.wheels_and_tyres'), parts = { 'Tyres', 'Wheels' } },
  { id = 'body', title = 'Body', parts = { strings.t('carreport.panels_and_doors'), strings.t('carreport.frame_and_glass') } },
  { id = 'interior', title = 'Interior', parts = { 'Seats', strings.t('carreport.dash_and_trim') } },
}

-- which section (and which of its parts, by index) a fault belongs to
M.FAULT_PART = { engine = { 'engine', 1 }, radiator = { 'engine', 2 }, battery = { 'engine', 3 }, exhaust = { 'engine', 4 }, gearbox = { 'drivetrain', 1 },
  tyres = { 'wheels', 1 }, brakes = { 'brakes', 1 } }
M.FAULT_CAP = 0.3             -- a part with a fault is worse than this
M.FAULT_COST = 0.05           -- of the car's value: what a fault costs to put right (market takes the same share off the price)
M.MILEAGE_WEAR = 0.1         -- condition the mechanical sections lose by 300 000 km

function M.label(c)
  return c >= 85 and 'Excellent' or c >= 70 and 'Good' or c >= 50 and 'Fair' or c >= 30 and 'Worn' or 'Poor'
end
function M.damageLabel(d)
  return d < 0.03 and 'None' or d < 0.15 and 'Light' or d < 0.4 and 'Moderate' or 'Heavy'
end

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
local function pct(x) return math.floor(clamp(x, 0, 1) * 100 + 0.5) end
local function r10(x) return math.floor(x / 10 + 0.5) * 10 end

-- car: { name, value, condition (0-1), damage (0-1), mileage, faults = { name }, fixed = { fault = $ }, repaired = $ }
-- Returns { condition, label, mileage, damage = { amount, label }, faults = { open }, sections = { { id, title, condition, label, parts = { { name, condition, label, fault } },
-- faults, estimate } }, total ($ to bring it to 95 %) }
function M.build(car)
  local value = car.value or 0
  local cond = market.effectiveCondition(car)
  local damage = clamp(car.damage or 0, 0, 1)
  local mileage = car.mileage or 0
  local open = market.unfixed(car)
  local openSet = {}
  for _, f in ipairs(open) do openSet[f] = true end
  local rng = rngLib.new(rngLib.hash('report:' .. tostring(car.name) .. ':' .. tostring(mileage) .. ':' .. tostring(car.value)))
  local sections, deficitSum = {}, 0
  for _, def in ipairs(M.SECTIONS) do
    local base = cond
    if def.mech then base = base - M.MILEAGE_WEAR * clamp(mileage / 300000, 0, 1) end
    if def.id == 'body' then base = base * (1 - 0.6 * damage) end
    base = base - ((car.wear or {})[def.id] or 0)              -- the wear of a car of yours (sl/core/wear)
    local sec = { id = def.id, title = def.title, parts = {}, faults = {}, estimate = 0 }
    local sum = 0
    for i, name in ipairs(def.parts) do
      local c = clamp(base + rng:range(-0.08, 0.08), 0.03, 1)
      local fault
      for f, where in pairs(M.FAULT_PART) do
        if openSet[f] and where[1] == def.id and where[2] == i then fault = f end
      end
      if fault then c = math.min(c, M.FAULT_CAP) sec.faults[#sec.faults + 1] = fault end
      sum = sum + c
      sec.parts[i] = { name = name, condition = pct(c), label = M.label(pct(c)), fault = fault }
    end
    table.sort(sec.faults)
    sec.condition = pct(sum / #def.parts)
    sec.label = M.label(sec.condition)
    sec.deficit = math.max(0, 0.95 - sec.condition / 100)
    deficitSum = deficitSum + sec.deficit
    sections[#sections + 1] = sec
  end
  -- the repair: what market says a point of condition costs, shared out by how worn each section is, plus the open faults (each in its section)
  local wear = math.max(0, 0.95 - cond) * value / market.REPAIR_CONDITION
  local total = 0
  for _, sec in ipairs(sections) do
    local share = deficitSum > 0 and sec.deficit / deficitSum or 0
    local worn = ((car.wear or {})[sec.id] or 0) * value / market.REPAIR_CONDITION          -- what the wear since you bought it costs to put right
    sec.faultCost = r10(#sec.faults * M.FAULT_COST * value)          -- (of the estimate: the open faults of the section; the rest is the wear of the car and since you bought it)
    sec.estimate = r10(wear * share + #sec.faults * M.FAULT_COST * value + worn)
    sec.wearCost = math.max(0, sec.estimate - sec.faultCost)
    sec.deficit = nil
    total = total + sec.estimate
  end
  return {
    condition = pct(cond), label = M.label(pct(cond)), mileage = mileage, damage = { amount = pct(damage), label = M.damageLabel(damage) },
    faults = open, sections = sections, total = total,
  }
end

return M
