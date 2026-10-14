-- Street Legal: a small seeded random number generator (Park-Miller), so that what the game
-- makes up - racers, cars for sale - comes out the same for the same seed.

local M = {}

local Rng = {}
Rng.__index = Rng

local MOD = 2147483647

function M.new(seed)
  seed = math.floor(math.abs(tonumber(seed) or 1)) % (MOD - 1) + 1
  return setmetatable({ s = seed }, Rng)
end

function Rng:next()
  self.s = (self.s * 48271) % MOD
  return self.s
end

-- [0, 1)
function Rng:float()
  return (self:next() - 1) / (MOD - 1)
end

-- int(n): 1..n   int(lo, hi): lo..hi
function Rng:int(lo, hi)
  if not hi then lo, hi = 1, lo end
  return lo + math.floor(self:float() * (hi - lo + 1))
end

function Rng:range(lo, hi)
  return lo + (hi - lo) * self:float()
end

function Rng:chance(p)
  return self:float() < p
end

function Rng:pick(list)
  return list[self:int(#list)]
end

-- a number from a string (to seed by name, day and so on)
function M.hash(text)
  local h = 5381
  text = tostring(text)
  for i = 1, #text do h = (h * 33 + text:byte(i)) % MOD end
  return h
end

return M
