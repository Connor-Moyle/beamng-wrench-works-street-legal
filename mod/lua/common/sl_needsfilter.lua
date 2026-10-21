-- Street Legal: the input filter of the Needs part (shared by the car's slNeeds extension and the offline tests). Pure.
-- A tired driver: steering and pedals follow the input with a first-order lag; hungry: a faint shake on the steering. Never more than the caps.

local M = {}

M.TREMOR_DEG = 0.03          -- full tremor: 3 % of the steering range
M.TREMOR_HZ = 9

-- one step of the lag: the current value moves towards the target with time constant `lag` (seconds); lag 0 jumps
function M.lagStep(cur, target, dt, lag)
  if not (lag and lag > 0) or not (dt and dt > 0) then return target end
  return cur + (target - cur) * (1 - math.exp(-dt / lag))
end

-- the shake on the steering at phase t (seconds): two sines so it does not look mechanical
function M.tremor(t, amount)
  if not (amount and amount > 0) then return 0 end
  local w = 2 * math.pi * M.TREMOR_HZ
  return amount * M.TREMOR_DEG * math.sin(w * t) * (0.6 + 0.4 * math.sin(w * 0.37 * t))
end

function M.clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

return M
