-- Street Legal: show and shine at the car meets (Design 2 D2). The judges look at what a car is
-- worth and how clean it is; the racers' cars are judged by their tier (the better the racer, the
-- better kept the car). No game calls.

local M = {}

M.FEE = 50
M.PRIZES = { 1.0, 0.4, 0.15 }        -- of the purse, for 1st, 2nd and 3rd
M.REP = { 20, 8, 3 }

-- a car: { value = $, condition = 0..1 (as bought), dents = bent beams kept in the save }
function M.score(car)
  local clean = 1 - math.min(0.6, (car.dents or 0) / 300)
  return math.floor((car.value or 0) * (0.6 + 0.4 * (car.condition or 0.7)) * clean)
end

-- a racer's car, by tier (1..5), with the night's luck
function M.rival(tier, rng)
  return math.floor(3000 * (tier or 1) ^ 1.6 * rng:range(0.8, 1.2))
end

-- where you finish among the rivals, and what it pays: the purse grows with the field
function M.result(mine, rivals)
  local place = 1
  for _, r in ipairs(rivals) do if r > mine then place = place + 1 end end
  local purse = 0
  for _, r in ipairs(rivals) do purse = purse + r end
  purse = math.floor(purse / math.max(1, #rivals) * 0.08 / 10) * 10
  local share = M.PRIZES[place]
  return place, share and math.floor(purse * share / 10) * 10 or 0, M.REP[place] or 0
end

return M
