-- Street Legal: danger zones (campaign idea #2): a jump-distance ladder anywhere on the map, and drift zones on long roads. Pure, no game calls: tested by tools/luatest.js.
-- A drift is a car moving fast and sliding: the angle between where it goes and where it points is between DRIFT_MIN and DRIFT_MAX degrees. A jump is a stretch of air time; its
-- distance is the ground covered between take-off and landing.

local M = {}

M.DRIFT_SPEED = 8                 -- m/s: slower than that is no drift
M.DRIFT_MIN, M.DRIFT_MAX = 15, 80 -- degrees of slip
M.AIR_MIN = 0.4                   -- s in the air before it counts as a jump
M.JUMP_MAX = 400                  -- m: further than that was a teleport
M.JUMPS = { { 20, 150 }, { 40, 300 }, { 70, 600 }, { 110, 1000 } }       -- the ladder: metres, prize (paid once each)
M.DRIFT_PAY, M.DRIFT_REP = 300, 5

-- points for dt seconds of driving at `speed` m/s with `angle` degrees of slip: faster and sideways-er scores more (45 degrees is the full rate)
function M.driftPoints(speed, angle, dt)
  angle = math.abs(angle or 0)
  if (speed or 0) < M.DRIFT_SPEED or angle < M.DRIFT_MIN or angle > M.DRIFT_MAX then return 0 end
  return speed * (angle / 45) * dt
end

-- the angle in degrees between the way a car moves (vx, vy) and the way it points (fx, fy)
function M.slipAngle(vx, vy, fx, fy)
  local sv, sf = math.sqrt(vx * vx + vy * vy), math.sqrt(fx * fx + fy * fy)
  if sv < 1e-6 or sf < 1e-6 then return 0 end
  local c = (vx * fx + vy * fy) / (sv * sf)
  c = math.max(-1, math.min(1, c))
  return math.deg(math.acos(c))
end

function M.newJump() return { air = false, t = 0 } end

-- one step: airborne (bool), the position now, the seconds since the last step. Returns the distance in metres when a jump has just ended (landing), else nil.
function M.jumpStep(st, airborne, x, y, dt)
  if airborne then
    if not st.air then st.air, st.t, st.x0, st.y0 = true, 0, x, y end
    st.t = st.t + dt
    return nil
  end
  if not st.air then return nil end
  local took = st.t
  st.air = false
  if took < M.AIR_MIN then return nil end
  local d = math.sqrt((x - st.x0) ^ 2 + (y - st.y0) ^ 2)
  if d > M.JUMP_MAX then return nil end
  return d
end

-- the ladder rungs a jump of `d` metres newly reaches, given how many are already paid: returns the new count and the list of prizes
function M.ladder(paid, d)
  local prizes, n = {}, paid or 0
  while M.JUMPS[n + 1] and d >= M.JUMPS[n + 1][1] do n = n + 1 prizes[#prizes + 1] = M.JUMPS[n][2] end
  return n, prizes
end

return M
