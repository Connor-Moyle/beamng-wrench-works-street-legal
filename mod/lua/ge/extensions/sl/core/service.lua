-- Street Legal: servicing (career expansion #2). Wear (core/wear) is real-life slow: hundreds of thousands of km. With the "Servicing and wear" part on, the kilometres a car
-- drives count SCALE times for wear, a service is due every INTERVAL km, and skipping it makes the wear faster (the km past the interval count half again). A basic service
-- resets the interval; an overhaul also puts the worn sections right (a credit the report subtracts). Pure, no game calls: tested by tools/luatest.js.
-- A car's record: car.service = { baseKm (engine km at the last service), penalty (extra km from skipped intervals), credit = { section = wear put right }, count }.

local M = {}

local strings = require('sl/core/strings')
local wear = require('sl/core/wear')

M.SCALE = 40            -- a km driven is this many km of wear
M.INTERVAL = 150        -- km between services (about one in-game week of driving)
M.OVERDUE = 0.5         -- extra km of wear per km driven past the interval
M.BASIC = { base = 60, share = 0.004 }       -- price: $60 + 0.4 % of the car's value
M.NO_BENCH = 1.5        -- no workbench in the garage: the mobile mechanic's factor (core/progression MOBILE_MECHANIC)

function M.state(car)
  if type(car.service) ~= 'table' then car.service = { penalty = 0, credit = {}, count = 0 } end
  local sv = car.service
  sv.penalty, sv.credit, sv.count = sv.penalty or 0, sv.credit or {}, sv.count or 0
  return sv
end

-- km driven since the last service (the whole time you have had the car if never serviced)
function M.since(sv, engineKm, mileage)
  return math.max(0, (tonumber(engineKm) or 0) - (sv.baseKm or tonumber(mileage) or 0))
end
function M.due(km) return km >= M.INTERVAL end
local function over(km) return M.OVERDUE * math.max(0, km - M.INTERVAL) end
function M.wearFactor(km) return M.due(km) and 1 + M.OVERDUE or 1 end

-- the wear since you bought the car, per section (the same ids as core/wear, 0..MAX_LOSS), before any credit
function M.gross(sv, engineKm, mileage, abuse)
  local km = (wear.kmSince(engineKm, mileage) + sv.penalty + over(M.since(sv, engineKm, mileage))) * M.SCALE
  local scaled = {}
  for k, v in pairs(type(abuse) == 'table' and abuse or {}) do scaled[k] = (tonumber(v) or 0) * M.SCALE end
  return wear.lost(km, scaled)
end

-- what the report shows: the gross wear less what an overhaul put right
function M.net(sv, gross)
  local out = {}
  for sec, g in pairs(gross) do out[sec] = math.max(0, g - (sv.credit[sec] or 0)) end
  return out
end

function M.basicCost(value, bench) return math.floor(((M.BASIC.base + (value or 0) * M.BASIC.share) * (bench and 1 or M.NO_BENCH)) / 10 + 0.5) * 10 end
-- the overhaul pays for the worn sections the way the car report prices them (value x wear / repairCondition), on top of the basic service
function M.overhaulCost(value, net, repairCondition, bench)
  local worn = 0
  for _, v in pairs(net) do worn = worn + v end
  return M.basicCost(value, bench) + math.floor((worn * (value or 0) / repairCondition) * (bench and 1 or M.NO_BENCH) / 10 + 0.5) * 10
end

function M.doBasic(sv, engineKm, mileage)
  sv.penalty = sv.penalty + over(M.since(sv, engineKm, mileage))     -- the wear of the skipped interval stays
  sv.baseKm = tonumber(engineKm) or sv.baseKm
  sv.count = sv.count + 1
end
function M.doOverhaul(sv, engineKm, mileage, abuse)
  M.doBasic(sv, engineKm, mileage)
  sv.credit = M.gross(sv, engineKm, mileage, abuse)                -- everything worn so far is put right
end

M.SECTIONS = { 'engine', 'drivetrain', 'suspension', 'brakes', 'wheels' }
local PW_SECTION = { drive = 'drivetrain' }                          -- Part Wear's names for ours
-- the sections to show: { id, label, condition 0..1 (1 = new) }. Ours come from the wear model; with Part Wear's parts ({ section, condition }, read-only) a section it knows
-- shows its worst part, and its sections we have none for (exhaust, body, anything new) are added, an unknown name as "other"
function M.sections(net, pwParts)
  local worst = {}
  for _, p in ipairs(pwParts or {}) do
    local id = PW_SECTION[p.section] or p.section or 'other'
    if not strings.TEXT['service.sec_' .. id] then id = 'other' end
    if type(p.condition) == 'number' and (worst[id] == nil or p.condition < worst[id]) then worst[id] = p.condition end
  end
  local out, seen = {}, {}
  local function add(id, cond) seen[id] = true out[#out + 1] = { id = id, label = strings.t('service.sec_' .. id), condition = math.max(0, math.min(1, cond)) } end
  for _, id in ipairs(M.SECTIONS) do
    add(id, worst[id] or (1 - (net[id] or 0) / wear.MAX_LOSS))
  end
  local extra = {}
  for id in pairs(worst) do if not seen[id] then extra[#extra + 1] = id end end
  table.sort(extra)
  for _, id in ipairs(extra) do add(id, worst[id]) end
  return out
end

return M
