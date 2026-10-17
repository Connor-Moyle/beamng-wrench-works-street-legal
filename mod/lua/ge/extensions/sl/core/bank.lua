-- Street Legal: the bank (BACKLOG X22): loans and insurance. No game calls.
-- Loans are kept small enough that a few days of jobs pay them back, never grow past half again
-- what was borrowed, and are only repossessed after two warnings. Insurance starts the day after it
-- is bought and pays half a claim over a deductible, so it can't be bought just before a crash.

local M = {}

local strings = require('sl/core/strings')

M.RATE = 0.03              -- interest per in-game day on what is owed
M.MAX_GROWTH = 1.5         -- what is owed never passes this times what was borrowed
M.WEEK = 7
M.DEDUCTIBLE = 200
M.COVER = 0.5              -- of a claim over the deductible

M.MAX_LOAN = 120000
M.GARAGE_STEP = 6000       -- more for each garage above the first
M.COLLATERAL = 0.5         -- of what the cars you own are worth

-- how much the bank will lend: $3,000 to start (about three days of jobs), more with a name ($2 a point of reputation), with the
-- garage you hold ($6,000 for each level above the first) and against the cars you own (half their value, which is what it takes back if
-- you stop paying); in steps of $500, never more than $120,000
function M.loanLimit(rep, garageLevel, fleetValue)
  local raw = 3000 + (rep or 0) * 2 + math.max(0, (garageLevel or 1) - 1) * M.GARAGE_STEP + (fleetValue or 0) * M.COLLATERAL
  return math.min(M.MAX_LOAN, math.floor(raw / 500) * 500)
end

-- what a missed weekly payment costs in reputation: the first is a warning with a small cost, the second a bigger one, the third the car
M.MISS_REP = { warning = -10, final = -20, repossess = -50 }

function M.newLoan(amount, day)
  return { borrowed = amount, owed = amount, day = day, nextDue = day + M.WEEK, missed = 0 }
end

-- a day passes: interest, up to the ceiling
function M.accrue(loan)
  loan.owed = math.min(loan.borrowed * M.MAX_GROWTH, math.floor(loan.owed * (1 + M.RATE) + 0.5))
  return loan.owed
end

-- what is due at a weekly payment: a quarter of what is owed (at least $100, at most all of it)
function M.due(loan)
  return math.min(loan.owed, math.max(100, math.ceil(loan.owed / 4)))
end

-- the weekly payment, with what the player has: 'paid' | 'warning' | 'final' | 'repossess'
function M.payment(loan, money)
  local due = M.due(loan)
  if money >= due then
    loan.owed = loan.owed - due
    loan.missed = 0
    return 'paid', due
  end
  loan.missed = loan.missed + 1
  if loan.missed >= 3 then return 'repossess', 0 end
  return loan.missed == 1 and 'warning' or 'final', 0
end

-- insurance (B10): the weekly premium starts low and only rises with the claims history, never with what the cars are worth. Each claim paid in the last
-- CLAIM_WINDOW days adds CLAIM_LOAD to the base (up to MAX_CLAIMS); the claims fall out of the history after the window and the premium comes back down.
M.BASE_PREMIUM = 80
M.CLAIM_LOAD = 60
M.CLAIM_WINDOW = 28
M.MAX_CLAIMS = 5

-- claims: the days on which a claim was paid
function M.recentClaims(claims, day)
  local n = 0
  for _, d in ipairs(claims or {}) do if (day or 0) - d < M.CLAIM_WINDOW and d <= (day or 0) then n = n + 1 end end
  return math.min(n, M.MAX_CLAIMS)
end

function M.premium(claims, day)
  return M.BASE_PREMIUM + M.CLAIM_LOAD * M.recentClaims(claims, day)
end

-- why it is what it is, in words for the phone and the laptop
function M.premiumWhy(claims, day)
  local n = M.recentClaims(claims, day)
  if n == 0 then return strings.t('bank.no_claims_in_the_last_1_days', M.CLAIM_WINDOW) end
  return strings.t('bank.1_claims_in_the_last_2', n, M.CLAIM_WINDOW, M.CLAIM_LOAD * n)
end

-- what a claim pays: nothing before cover starts (the day after buying), half over the deductible after
function M.claim(policy, cost, day)
  if not policy or not policy.active or day < policy.from or (cost or 0) <= M.DEDUCTIBLE then return 0 end
  return math.floor((cost - M.DEDUCTIBLE) * M.COVER)
end

return M
