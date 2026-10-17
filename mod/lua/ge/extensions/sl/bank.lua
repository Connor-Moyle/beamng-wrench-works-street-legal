-- Wrench Works: Street Legal: the bank (extension name: sl_bank; BACKLOG X22): a loan and insurance.
-- Rules in sl/core/bank. A loan is paid back a quarter a week; two missed payments are warned, the
-- third repossesses your car (the impound holds it for what is owed). Insurance costs a weekly
-- premium, starts the day after, and pays half of repair and impound bills over a deductible.

local M = {}

local strings = require('sl/core/strings')

local bank = require('sl/core/bank')
local stateLib = require('sl/core/state')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end
local function bankState(s) s.bank = s.bank or {} return s.bank end

local function fleetValue(s)
  local v = 0
  for _, c in ipairs(s.cars) do v = v + (c.value or 0) end
  return v
end

function M.borrow(amount)
  local s = career()
  if not s then return false, strings.t('bank.no_career_running') end
  local b = bankState(s)
  if b.loan then return false, strings.t('bank.pay_off_the_loan_you') end
  amount = math.floor((tonumber(amount) or 0) / 100) * 100
  local limit = bank.loanLimit(s.rep, s.garageLevel, fleetValue(s))
  if amount < 100 or amount > limit then return false, string.format('The bank lends up to $%d.', limit) end
  b.loan = bank.newLoan(amount, s.day)
  sl_career.addMoney(amount, 'Loan')
  extensions.hook('onStreetLegalChanged')
  return true, string.format('$%d lent. A quarter of what you owe is due each week; %d%% a day interest.', amount, math.floor(bank.RATE * 100))
end

function M.repay(amount)
  local s = career()
  local b = s and bankState(s)
  if not b or not b.loan then return false, strings.t('bank.you_owe_the_bank_nothing') end
  amount = math.min(b.loan.owed, math.floor(tonumber(amount) or b.loan.owed), s.money)
  if amount <= 0 then return false, strings.t('bank.nothing_to_pay_with') end
  sl_career.addMoney(-amount, 'Loan repayment')
  b.loan.owed = b.loan.owed - amount
  if b.loan.owed <= 0 then b.loan = nil end
  extensions.hook('onStreetLegalChanged')
  return true, b.loan and string.format('Paid $%d. $%d still owed.', amount, b.loan.owed) or 'The loan is paid off.'
end

function M.insure(on)
  local s = career()
  if not s then return false, strings.t('bank.no_career_running') end
  local b = bankState(s)
  if on then
    if b.policy and b.policy.active then return false, strings.t('bank.you_are_insured_already') end
    if sl_options and sl_options.get('slHardcore') then return false, strings.t('bank.hardcore_career_nobody_will_insure') end
    local premium = bank.premium(fleetValue(s))
    if not sl_career.addMoney(-premium, 'Insurance premium') then return false, string.format('The first week is $%d.', premium) end
    b.policy = { active = true, from = s.day + 1, nextPremium = s.day + bank.WEEK }
    extensions.hook('onStreetLegalChanged')
    return true, string.format('Insured from tomorrow. $%d a week; claims pay half over $%d.', premium, bank.DEDUCTIBLE)
  end
  if b.policy then b.policy.active = false end
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('bank.insurance_cancelled')
end

-- a repair or an impound bill: the insurance pays its share
function M.onStreetLegalSpent(cost, label)
  local s = career()
  local b = s and s.bank
  if not b or not b.policy or type(label) ~= 'string' then return end
  if not (label:find('^Repaired') or label:find('^Impound') or label:find('^Tow') or label:find('^Hospital') or label:find("^Doctor")) then return end
  local payout = bank.claim(b.policy, cost, s.day)
  if payout > 0 then
    sl_career.addMoney(payout, 'Insurance: ' .. label)
    toast(string.format('The insurance pays $%d of that.', payout))
  end
end

local function repossess(s, b, day)
  stateLib.addRep(s, bank.MISS_REP.repossess)
  local car = sl_fleet and sl_fleet.currentCar() or s.cars[1]
  if not car then                              -- (B27: nothing to take: the debt stays, and grows, until there is)
    b.loan.nextDue = day + bank.WEEK
    sl_career.sendText('benny', string.format('The bank came for your car and found none. The debt stays: $%d, and they will be back next week.', b.loan.owed), 1)
    return
  end
  if car then
    car.impounded = b.loan.owed
    car.out = false
    local veh = sl_fleet and sl_fleet.vehicleOf(car.id)
    local player = getPlayerVehicle(0)
    if veh and player and veh:getID() == player:getID() and gameplay_walk then gameplay_walk.setWalkingMode(true, nil, nil, true) end
    if veh then veh:delete() end
    sl_career.sendText('benny', string.format('The bank took the %s. It is in the impound until you pay what you owed: $%d (phone, My cars).', car.name, b.loan.owed), 1)
  end
  b.loan = nil                                 -- (the debt now rides on the car in the impound, nothing more)
end

function M.onStreetLegalNewDay(day)
  local s = career()
  local b = s and s.bank
  if not b then return end
  if b.loan then
    bank.accrue(b.loan)
    if day >= b.loan.nextDue then
      b.loan.nextDue = day + bank.WEEK
      local result, paid = bank.payment(b.loan, s.money)
      if result == 'paid' then
        sl_career.addMoney(-paid, 'Loan payment')
        if b.loan.owed <= 0 then b.loan = nil sl_career.sendText('benny', strings.t('bank.the_bank_says_your_loan'), 1) end
      elseif result == 'warning' then
        stateLib.addRep(s, bank.MISS_REP.warning)
        sl_career.sendText('benny', string.format('The bank wanted $%d this week and you did not have it. They will try again next week.', bank.due(b.loan)), 1)
      elseif result == 'final' then
        stateLib.addRep(s, bank.MISS_REP.final)
        sl_career.sendText('benny', strings.t('bank.second_missed_payment_next_week'), 1)
      else
        repossess(s, b, day)
      end
    end
  end
  local p = b.policy
  if p and p.active and day >= p.nextPremium then
    local premium = bank.premium(fleetValue(s))
    if sl_career.addMoney(-premium, 'Insurance premium') then p.nextPremium = day + bank.WEEK
    else p.active = false sl_career.sendText('benny', strings.t('bank.your_insurance_lapsed_not_enough'), 1) end
  end
  extensions.hook('onStreetLegalChanged')
end

-- for the phone's Bank app
function M.summary()
  local s = career()
  if not s then return nil end
  local b = bankState(s)
  local out = { limit = bank.loanLimit(s.rep, s.garageLevel, fleetValue(s)), rate = bank.RATE, premium = bank.premium(fleetValue(s)), deductible = bank.DEDUCTIBLE }
  if b.loan then out.loan = { owed = b.loan.owed, due = bank.due(b.loan), dueIn = b.loan.nextDue - s.day, missed = b.loan.missed } end
  if b.policy and b.policy.active then out.policy = { from = b.policy.from, startsIn = math.max(0, b.policy.from - s.day) } end
  return out
end

return M
