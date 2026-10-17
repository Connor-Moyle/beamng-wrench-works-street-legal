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

-- the depth-of-field values (the game's DOFPostEffect fields) for a car L metres long at `dist` metres: the car and about a car length
-- round it sharp, the background soft; w (0..1) fades the blur in and out
function M.dofParams(dist, L, w)
  w = math.max(0, math.min(1, w or 1))
  return { focalDist = dist, minRange = 2 * L, maxRange = 4 * L, nearBlurMax = 0.25 * w, farBlurMax = 0.35 * w, nearSlope = -5, farSlope = 5 }
end

return M
