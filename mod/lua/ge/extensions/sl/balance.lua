-- Wrench Works: Street Legal: the game's balance, tunable in the Mods menu (extension name: sl_balance). Each sl_options entry with a `tab` here sets one constant of the rules
-- (a field of a core module, read at the moment it is used); the value the rules were written with is kept and comes back when a setting is reset.

local M = {}

-- { sl_options key, module, field }
M.MAP = {
  { 'slPayPerKm', 'sl/core/jobs', 'PAY_PER_KM' },
  { 'slDayJobPay', 'sl/core/jobs', 'DAY_PAY' },
  { 'slJobSlack', 'sl/core/jobs', 'SLACK' },
  { 'slLoanInterest', 'sl/core/bank', 'RATE' },
  { 'slLoanMax', 'sl/core/bank', 'MAX_LOAN' },
  { 'slInsDeductible', 'sl/core/bank', 'DEDUCTIBLE' },
  { 'slInsCover', 'sl/core/bank', 'COVER' },
  { 'slListingFee', 'sl/core/listings', 'LISTING_FEE' },
  { 'slWashPrice', 'sl/station', 'WASH_PRICE' },
  { 'slStartMoney', 'sl/core/progression', 'START_MONEY' },
  { 'slHeatRace', 'sl/core/heat', 'RACE' },
  { 'slHeatNearMiss', 'sl/core/heat', 'NEAR_MISS' },
  { 'slHeatBust', 'sl/core/heat', 'BUST' },
  { 'slHeatEscape', 'sl/core/heat', 'ESCAPE' },
  { 'slHeatCool', 'sl/core/heat', 'COOL_PER_MINUTE' },
  { 'slPinkChance', 'sl/core/roster', 'PINK_NIGHT_CHANCE' },
  { 'slRematchChance', 'sl/core/roster', 'REMATCH_CHANCE' },
  { 'slTauntChance', 'sl/core/roster', 'TAUNT_CHANCE' },
  { 'slDoctorBase', 'sl/hospital', 'DOCTOR_BASE' },
  { 'slBoneFee', 'sl/hospital', 'BONE_FEE' },
  { 'slDoctorSeverity', 'sl/hospital', 'DOCTOR_SEVERITY' },
  { 'slHospitalBase', 'sl/hospital', 'HOSPITAL_BASE' },
  { 'slHospitalDied', 'sl/hospital', 'HOSPITAL_DIED' },
  { 'slHospitalSeverity', 'sl/hospital', 'HOSPITAL_SEVERITY' },
  { 'slBuildGap', 'sl/core/spawnplan', 'MIN_GAP' },
  { 'slTicketBase', 'sl/core/chase', 'TICKET_BASE' },
  { 'slTicketOffence', 'sl/core/chase', 'TICKET_OFFENCE' },
  { 'slTicketDueDays', 'sl/core/chase', 'TICKET_DUE_DAYS' },
  { 'slContestWith', 'sl/core/chase', 'CONTEST_WITH' },
  { 'slContestWithout', 'sl/core/chase', 'CONTEST_WITHOUT' },
  { 'slLostRaise', 'sl/core/chase', 'LOST_RAISE' },
  { 'slLawyerFee', 'sl/core/chase', 'LAWYER_FEE' },
  { 'slSuspendAt', 'sl/core/chase', 'SUSPEND_AT' },
  { 'slBountyBase', 'sl/core/chase', 'BOUNTY_BASE' },
  { 'slBountyStep', 'sl/core/chase', 'BOUNTY_STEP' },
  { 'slInformantShare', 'sl/core/chase', 'INFORMANT_SHARE' },
  { 'slImpoundBase', 'sl/core/heat', 'IMPOUND_BASE' },
  { 'slImpoundStep', 'sl/core/heat', 'IMPOUND_STEP' },
  { 'slPitEvery', 'sl/core/chase', 'PIT_EVERY' },
  { 'slPitAggr', 'sl/core/chase', 'PIT_AGGR' },
  { 'slBoxAggr', 'sl/core/chase', 'BOX_AGGR' },
  { 'slPitMaxFails', 'sl/core/chase', 'MAX_FAILS' },
  { 'slPatrolShiftS', 'sl/core/chase', 'PATROL_SHIFT_S' },
  { 'slPatrolArrests', 'sl/core/chase', 'PATROL_ARRESTS' },
  { 'slPatrolBase', 'sl/core/chase', 'PATROL_BASE' },
  { 'slPatrolArrestPay', 'sl/core/chase', 'PATROL_ARREST_PAY' },
  { 'slDuelBetX', 'sl/core/hillduel', 'BET_X' },
  { 'slDuelBetMin', 'sl/core/hillduel', 'BET_MIN' },
  { 'slDuelRepWin', 'sl/core/hillduel', 'REP_WIN' },
  { 'slDuelRepLoss', 'sl/core/hillduel', 'REP_LOSS' },
  { 'slDuelLeadGap', 'sl/core/hillduel', 'LEAD_GAP' },
  { 'slDuelCloseGap', 'sl/core/hillduel', 'CLOSE_GAP' },
  { 'slDuelOffGrace', 'sl/core/hillduel', 'OFF_GRACE' },
  { 'slGrabJobs', 'sl/core/grabbag', 'GOOD_JOBS' },
  { 'slGrabWins', 'sl/core/grabbag', 'GOOD_WINS' },
  { 'slGrabEarned', 'sl/core/grabbag', 'GOOD_EARNED' },
  { 'slGrabPartsMax', 'sl/core/grabbag', 'PARTS_MAX' },
  { 'slGrabMaxValue', 'sl/core/grabbag', 'MAX_VALUE' },
  { 'slBarnPriceShare', 'sl/core/barn', 'PRICE_SHARE' },
  { 'slBarnMinRep', 'sl/core/barn', 'MIN_REP' },
  { 'slBarnGapMin', 'sl/core/barn', 'GAP_MIN' },
  { 'slBarnGapMax', 'sl/core/barn', 'GAP_MAX' },
  { 'slTrapPay', 'sl/core/traps', 'PAY_TRAP' },
  { 'slZonePay', 'sl/core/traps', 'PAY_ZONE' },
  { 'slTrapRep', 'sl/core/traps', 'REP' },
  { 'slTrapCount', 'sl/core/traps', 'TRAPS' },
  { 'slZoneCount', 'sl/core/traps', 'ZONES' },
  { 'slZoneMaxTime', 'sl/core/traps', 'ZONE_MAX_TIME' },
}

local original = {}

local function target(path) local ok, mod = pcall(require, path) return ok and type(mod) == 'table' and mod or nil end

function M.apply()
  if not (sl_options and sl_options.get) then return end
  for _, e in ipairs(M.MAP) do
    local mod = target(e[2])
    if mod then
      if original[e[1]] == nil then original[e[1]] = mod[e[3]] end
      local v = sl_options.get(e[1])
      if type(v) == 'number' then mod[e[3]] = v elseif v == nil and original[e[1]] ~= nil then mod[e[3]] = original[e[1]] end
    end
  end
end

function M.onStreetLegalStarted() M.apply() end
function M.onStreetLegalOption() M.apply() end
local timer = 0
function M.onUpdate(dtReal) timer = timer + (dtReal or 0) if timer > 10 then timer = 0 M.apply() end end

return M
