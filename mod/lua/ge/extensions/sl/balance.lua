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
  { 'slTheftSecondsOld', 'sl/core/theft', 'SECONDS_OLD' },
  { 'slTheftSecondsMid', 'sl/core/theft', 'SECONDS_MID' },
  { 'slTheftSecondsModern', 'sl/core/theft', 'SECONDS_MODERN' },
  { 'slTheftChanceOld', 'sl/core/theft', 'CHANCE_OLD' },
  { 'slTheftChanceMid', 'sl/core/theft', 'CHANCE_MID' },
  { 'slTheftChanceModern', 'sl/core/theft', 'CHANCE_MODERN' },
  { 'slTheftNoisePin', 'sl/core/theft', 'NOISE_PIN' },
  { 'slTheftNoiseWire', 'sl/core/theft', 'NOISE_WIRE' },
  { 'slTheftWitnessAt', 'sl/core/theft', 'WITNESS_AT' },
  { 'slTheftWitnessS', 'sl/core/theft', 'WITNESS_S' },
  { 'slTheftAlarmAt', 'sl/core/theft', 'ALARM_AT' },
  { 'slTheftTrackerOld', 'sl/core/theft', 'TRACKER_OLD' },
  { 'slTheftTrackerMid', 'sl/core/theft', 'TRACKER_MID' },
  { 'slTheftTrackerModern', 'sl/core/theft', 'TRACKER_MODERN' },
  { 'slTheftTrackerPrestige', 'sl/core/theft', 'TRACKER_PRESTIGE' },
  { 'slTheftTrackS', 'sl/core/theft', 'TRACK_S' },
  { 'slTheftTrackResend', 'sl/core/theft', 'TRACK_RESEND_S' },
  { 'slTheftPullS', 'sl/core/theft', 'PULL_S' },
  { 'slTheftJamS', 'sl/core/theft', 'JAM_S' },
  { 'slTheftSellHot', 'sl/core/theft', 'SELL_HOT' },
  { 'slTheftSellPlated', 'sl/core/theft', 'SELL_PLATED' },
  { 'slTheftStrip', 'sl/core/theft', 'STRIP' },
  { 'slTheftTitleShare', 'sl/core/theft', 'TITLE_SHARE' },
  { 'slTheftPlateLegal', 'sl/core/theft', 'PLATE_LEGAL' },
  { 'slTheftPlateStolen', 'sl/core/theft', 'PLATE_STOLEN' },
  { 'slTheftTrackerStrip', 'sl/core/theft', 'TRACKER_STRIP' },
  { 'slTheftMarketShare', 'sl/core/theft', 'MARKET_SHARE' },
  { 'slTheftToolPriceX', 'sl/core/theft', 'TOOL_PRICE_X' },
  { 'slTheftToolUsesX', 'sl/core/theft', 'TOOL_USES_X' },
  { 'slTheftDeliveryPayX', 'sl/core/theft', 'DELIVERY_PAY_X' },
  { 'slTheftDeliveryHeat', 'sl/core/theft', 'DELIVERY_HEAT' },
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
