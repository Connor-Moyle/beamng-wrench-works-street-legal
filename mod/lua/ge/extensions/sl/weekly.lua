-- Street Legal: weekly costs and the ledger (extension name: sl_weekly; career expansion #1). Rules in sl/core/weekly. Every 7th day the garage rent and the storage of
-- the cars beyond the free ones are paid; what cannot be paid becomes a debt the next weeks clear first. Never a repossession. The state lives in the career save as s.weekly
-- ({ nextDue, debt, history, earnedMark }); a save without it starts its first week from the day the part is first seen (nothing is billed backwards).

local M = {}

local strings = require('sl/core/strings')
local stateLib = require('sl/core/state')
local rules = require('sl/core/weekly')
local bank = require('sl/core/bank')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

local function weeklyState(s)
  if not s.weekly then
    s.weekly = rules.newState(s.day)
    s.weekly.earnedMark = s.stats and s.stats.earned or 0
  end
  return s.weekly
end

function M.onStreetLegalNewDay(day)
  local s = career()
  if not s then return end
  local w = weeklyState(s)
  if day < w.nextDue then return end
  w.nextDue = day + rules.DAYS
  local turf = sl_crews and sl_crews.turfWeek and sl_crews.turfWeek(s, day)        -- (the week's turf cuts come in before the bills: they help to cover them)
  if turf and turf.total > 0 then sl_career.payOut(turf.total, strings.t('weekly.turf_label')) end
  local lines = rules.lines(s.garageLevel, #s.cars)
  local plan = sl_needs and sl_needs.weeklyBill and sl_needs.weeklyBill()      -- (the Needs part: the meal plan, when the player has it)
  if plan then lines[#lines + 1] = plan end
  local owe = rules.total(lines)
  local r = rules.settle(s.money, w.debt, owe)
  if r.pay > 0 then sl_career.addMoney(-r.pay, strings.t('weekly.ledger_label')) end
  w.debt = r.debt
  local earned = s.stats and s.stats.earned or 0
  local entry = { week = rules.week(day) - 1, income = earned - (w.earnedMark or 0), costs = r.billsPaid, lines = {} }
  for _, l in ipairs(turf and turf.lines or {}) do
    entry.lines[#entry.lines + 1] = { label = strings.t('weekly.turf_' .. l.kind, l.name, l.lost or 0), amount = l.amount }
  end
  for _, l in ipairs(lines) do entry.lines[#entry.lines + 1] = { label = l.label, amount = -l.amount } end
  if r.repaid > 0 then entry.lines[#entry.lines + 1] = { label = strings.t('weekly.debt_repaid'), amount = -r.repaid } end
  local food = sl_needs and sl_needs.weeklyInfo and sl_needs.weeklyInfo()      -- (what was bought as food and drink this week: paid when bought, shown so the cost is visible)
  if food then entry.lines[#entry.lines + 1] = { label = food.label, amount = -food.amount, info = true } end
  entry.costs = r.billsPaid + r.repaid
  entry.net = entry.income - entry.costs
  w.earnedMark = earned
  rules.record(w, entry)
  if r.short > 0 then
    stateLib.addRep(s, rules.MISS_REP)
    sl_career.sendText('benny', strings.t('weekly.short_text', r.short, w.debt), 1)
  end
  extensions.hook('onStreetLegalChanged')
end

-- pay some of the debt now
function M.payDebt(amount)
  local s = career()
  if not s then return false, strings.t('bank.no_career_running') end
  local w = weeklyState(s)
  amount = math.min(math.floor(tonumber(amount) or 0), w.debt, s.money)
  if amount <= 0 then return false, strings.t('weekly.nothing_to_pay') end
  if not sl_career.addMoney(-amount, strings.t('weekly.debt_repaid')) then return false, strings.t('career.not_enough_money') end
  w.debt = w.debt - amount
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('weekly.paid_debt', amount, w.debt)
end

function M.debt()
  local s = career()
  return s and s.weekly and s.weekly.debt or 0
end

-- for the phone's ledger page (the part is off or no career: nil)
function M.summary()
  local s = career()
  if not s then return nil end
  local w = weeklyState(s)
  local bills = {}
  local left = math.max(0, w.nextDue - s.day)
  for _, l in ipairs(rules.lines(s.garageLevel, #s.cars)) do bills[#bills + 1] = { id = l.id, label = l.label, amount = l.amount, due = left } end
  local b = s.bank
  if b and b.policy and b.policy.active then
    bills[#bills + 1] = { id = 'insurance', label = strings.t('bank.insurance_premium'), amount = bank.premium(b.claims, s.day), due = math.max(0, b.policy.nextPremium - s.day) }
  end
  local mealPlan = sl_needs and sl_needs.weeklyBill and sl_needs.weeklyBill()
  if mealPlan then bills[#bills + 1] = { id = 'mealplan', label = mealPlan.label, amount = mealPlan.amount, due = left } end
  if b and b.loan then
    bills[#bills + 1] = { id = 'loan', label = strings.t('bank.loan_payment'), amount = bank.due(b.loan), due = math.max(0, b.loan.nextDue - s.day) }
  end
  return { enabled = true, week = rules.week(s.day), dayOfWeek = rules.dayOfWeek(s.day), nextBillDay = left, debt = w.debt, bills = bills, history = w.history }
end

require('sl/core/features').gate('weekly', M, nil, nil, { 'summary', 'payDebt', 'debt' })      -- (debt reads nil while the part is off: no weekly bills, so no weekly debt to block a loan)

return M
