-- Street Legal: the cinematic touches of the lot camera (letterbox bars, depth of field, a slow field-of-view drift). Pure: what to show for
-- the camera chain's state (sl/core/lotcam.chain). The game glue is in sl/lot.lua, each touch behind a flag (sl_lot.FX).

local M = {}

M.FOV_DRIFT = 3                       -- degrees tighter by the end of a shot

local function isCabin(kind) return kind == 'cabin' or kind == 'cabin_pass' end
local function smooth(u) u = math.max(0, math.min(1, u or 0)) return u * u * (3 - 2 * u) end
M.isCabin = isCabin

-- letterbox bars: on while a shot (or the move to the next) is on, off in the cabin shots and when the camera is back on the orbit
function M.barsOn(st)
  if not st or st.phase == 'out' then return false end
  return not isCabin(st.phase == 'trans' and st.nextKind or st.kind)
end

-- degrees tighter than the normal field of view: 0 to FOV_DRIFT along a shot, back to 0 along the move to the next one (so every shot starts at
-- the normal view); none inside the cabin. shotTime = the length of a shot.
function M.fovDrift(st, shotTime)
  if not st then return 0 end
  local d = M.FOV_DRIFT
  if st.phase == 'shot' then return isCabin(st.kind) and 0 or d * math.min((st.t or 0) / (shotTime or 5), 1) end
  if st.phase == 'trans' then return (isCabin(st.kind) and 0 or d) * (1 - smooth(st.u)) end
  if st.phase == 'out' then return d * (1 - smooth(st.u)) * 0.5 end
  return 0
end

-- Depth of field (the game's DOFPostEffect), worked out from its own formulas (ge/client/postFx/dof.lua setShaderConsts and
-- shaders/common/postFx/dof/DOF_Final_P.hlsl), depth being the distance along the view axis divided by the far distance:
--   fd = focalDist / farDist;  rN, rF = the near and far range = lerp(minRange, maxRange, fd) / farDist / 2 and lerp(maxRange, minRange, fd) / farDist / 2
--   ned = fd + min(rN, rF);  fsd = fd + rF;  the shader's focusDist = farSlope * (depth - fsd);  near blur where focusDist < -nearSlope * ned,
--   far blur where focusDist > -nearSlope * ned (nearSlope is negative).  So the sharp window is  fsd -/+ (nearSlope/farSlope) * ned  in depth.
-- Setting minRange = maxRange = R and slopes of the same size gives ned = fsd = fd + R / (2 farDist): the window runs from the camera to
-- 2 * (fd + R / (2 farDist)) * farDist = 2 * focalDist + R metres, nothing is blurred in front of it, and only what lies beyond it is.
M.MARGIN = 1.5                        -- m of extra sharpness behind the car
M.FAR_BLUR = 0.5                      -- the strongest blur of the background

-- the DOFPostEffect fields for a car (centre c, L x W x H) seen from `eye` looking at `look`, and { near, far } the depths (m) that must stay sharp.
-- w (0..1) fades the background blur in and out; farDist = the game's far distance ($Param::FarDist).
function M.dofParams(eye, look, c, L, W, H, farDist, w)
  w = math.max(0, math.min(1, w or 1))
  local fx, fy, fz = look.x - eye.x, look.y - eye.y, look.z - eye.z
  local n = math.sqrt(fx * fx + fy * fy + fz * fz)
  if n < 1e-6 then n = 1 end
  local depthC = ((c.x - eye.x) * fx + (c.y - eye.y) * fy + (c.z - eye.z) * fz) / n
  local ext = 0.5 * math.sqrt(L * L + W * W + H * H)                   -- (the car's own bounding sphere: any turn of the car stays inside)
  local far = depthC + ext + M.MARGIN
  local focal = math.max(0, math.min(depthC, far / 2))
  local range = far - 2 * focal
  return { focalDist = focal, minRange = range, maxRange = range, nearBlurMax = 0, farBlurMax = M.FAR_BLUR * w, nearSlope = -5, farSlope = 5 },
    { near = depthC - ext, far = far }
end

-- the sharp window (metres of depth, from, to) the effect makes of these fields: the formulas above, for tests and checks
function M.dofWindow(p, farDist)
  local fd = p.focalDist / farDist
  local function lerp(a, b, t) return a + (b - a) * t end
  local rNT = lerp(p.minRange, p.maxRange, fd) / farDist * 0.5
  local rF = lerp(p.maxRange, p.minRange, fd) / farDist * 0.5
  local rN = math.max(0, math.min(rNT, rF))
  local ned, fsd = math.min(fd + rN, 1), math.min(fd + rF, 1)
  local b = -p.nearSlope * ned                    -- (dofEqWorld.y)
  local fb = -p.farSlope * fsd                    -- (dofEqFar.y)
  return ((-b - fb) / p.farSlope) * farDist, ((b - fb) / p.farSlope) * farDist
end

return M
