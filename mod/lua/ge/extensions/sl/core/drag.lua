-- Street Legal: the drag strip in the career (#23). Pure, tested by tools/luatest.js. The strip itself (staging lights, the tree, reaction time,
-- ET and trap speed, the timeslip, the bracket dial and its handicap start) is the game's own freeroam drag (gameplay_drag_*); what is ours is
-- what it costs, who the opponent is and how fast their car is dialled, and what a win pays.

local M = {}

local strings = require('sl/core/strings')

M.ENTRY_FEE = 50          -- $ to line up
M.WIN_RATE = 1.9          -- of the entry fee back on a win (the other car's fee, less the strip's cut)
M.WIN_REP = 12            -- reputation for a win by day (the street gives rep at night; the strip pays money)
M.QUALIFY_MIN_REP = 0

local HP_PER_PS = 0.98632
local LB_PER_KG = 2.20462

-- quarter-mile estimate from power (PS) and weight (kg): the classic weight-to-power rule, ET = 5.825 (lb/hp)^(1/3); the trap speed
-- (m/s) from 234 (hp/lb)^(1/3) mph. A guess for the opponent's dial, not a measurement.
function M.etEstimate(powerPs, weightKg)
  powerPs, weightKg = tonumber(powerPs), tonumber(weightKg)
  if not powerPs or not weightKg or powerPs <= 0 or weightKg <= 0 then return nil end
  local lbPerHp = (weightKg * LB_PER_KG) / (powerPs * HP_PER_PS)
  return 5.825 * lbPerHp ^ (1 / 3)
end

function M.trapSpeed(powerPs, weightKg)
  powerPs, weightKg = tonumber(powerPs), tonumber(weightKg)
  if not powerPs or not weightKg or powerPs <= 0 or weightKg <= 0 then return nil end
  local hpPerLb = (powerPs * HP_PER_PS) / (weightKg * LB_PER_KG)
  return 234 * hpPerLb ^ (1 / 3) * 0.44704
end

-- the opponent's dial-in: its estimated ET, off by up to 6 % of an unskilled driver's guess (skill 0..1), and never under 6 s. roll: -1..1
function M.aiDial(et, skill, roll)
  et = tonumber(et) or 14.5
  skill = math.max(0, math.min(1, tonumber(skill) or 0.5))
  local off = 0.06 * (1 - skill) * math.max(-1, math.min(1, roll or 0))
  return math.max(6, math.floor(et * (1 + off) * 100 + 0.5) / 100)
end

-- what a run pays: { money, rep } for the player; the entry fee is paid up front
function M.purse(won, fee)
  fee = fee or M.ENTRY_FEE
  if not won then return { money = 0, rep = 0 } end
  return { money = math.floor(fee * M.WIN_RATE / 10 + 0.5) * 10, rep = M.WIN_REP }
end

-- the numbers of a run for the slip card and the toast: racer = { et (s), reaction (s), speed (m/s), dial (s), dq }
function M.slip(racer)
  local out = { et = racer.et, reaction = racer.reaction, mph = racer.speed and racer.speed * 2.23694 or nil, kmh = racer.speed and racer.speed * 3.6 or nil,
    dial = racer.dial, dq = racer.dq }
  if racer.et and racer.dial and racer.dial > 0 then
    out.diff = racer.et - racer.dial               -- negative: faster than the dial (a break-out, in a bracket race)
    out.breakout = racer.et < racer.dial
  end
  return out
end

function M.slipText(s)
  if s.dq then return strings.t('drag.disqualified_1', (tostring(s.dq))) end
  if not s.et then return strings.t('drag.no_time') end
  local parts = { string.format('ET %.3f s', s.et) }
  if s.mph then parts[#parts + 1] = string.format(strings.t('drag.1f_mph'), s.mph) end
  if s.reaction then parts[#parts + 1] = string.format('R/T %.3f', s.reaction) end
  if s.dial and s.dial > 0 then parts[#parts + 1] = string.format(strings.t('drag.dial_2f_s'), s.dial, s.breakout and ' (break-out)' or '') end
  return table.concat(parts, ' · ')
end

return M
