-- Street Legal: contracts on the job board (career expansion #4). A few of the delivery offers (part runs and courier parcels) come with terms: if the terms are met at the drop the
-- job pays MULT times the normal pay, if not it pays the normal pay (never less than a job without terms). Pure, no game calls: tested by tools/luatest.js.

local M = {}

local strings = require('sl/core/strings')

M.MIN_REP = 100          -- reputation before contracts are offered
M.COUNT = 2              -- at most this many on the board
M.UPSCALE_VALUE = 15000  -- a car worth this much
M.TIGHT = 0.8            -- of the time limit
M.BONUS_REP = 5          -- extra reputation for a met contract

-- the terms: mult = what the job pays when they are met
M.REQS = {
  clean = { mult = 1.6 },       -- no damage to the load or the car
  tight = { mult = 2.0 },       -- in 80 % of the time limit
  rain = { mult = 2.2 },        -- delivered while the road is wet
  upscale = { mult = 1.8 },     -- in a car worth $15,000 or more
}
M.ORDER = { 'clean', 'tight', 'rain', 'upscale' }

function M.label(req) return strings.t('contract.' .. tostring(req)) end

-- which terms to give: rain only when it is wet or raining now
function M.pick(rng, wet)
  local list = {}
  for _, id in ipairs(M.ORDER) do if id ~= 'rain' or wet then list[#list + 1] = id end end
  return list[rng:int(#list)]
end

-- put terms on a job (a part run or a courier parcel): the pay rises, the plain pay is kept
function M.apply(job, req)
  if job.contract or not M.REQS[req] then return false end
  job.basePay = job.pay
  job.pay = math.floor(job.pay * M.REQS[req].mult / 10 + 0.5) * 10
  job.contract = { req = req, mult = M.REQS[req].mult }
  return true
end

-- are the terms met at the drop? c = { damage 0..1, elapsed s, seconds (the limit), wet bool, carValue }
function M.met(req, c)
  if req == 'clean' then return (c.damage or 0) <= 0.01 end
  if req == 'tight' then return (c.seconds or 0) > 0 and (c.elapsed or 1e9) <= c.seconds * M.TIGHT end
  if req == 'rain' then return c.wet == true end
  if req == 'upscale' then return (c.carValue or 0) >= M.UPSCALE_VALUE end
  return false
end

return M
