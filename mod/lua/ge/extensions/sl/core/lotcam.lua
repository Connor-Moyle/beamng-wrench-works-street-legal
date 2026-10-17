-- Street Legal: where the lot camera stands (T37). Pure; the walls are the game's (ray(a, b) -> the distance from a to the first
-- thing hit on the way to b, or nil), tested by tools/luatest.js. The camera looks at the shown car's centre from a rear quarter, a
-- few metres out and about 1.5 m up, on the side with room: a wall behind or beside the car (the lot is against a building)
-- no longer fills the picture, and an eye that would be inside something is pulled back in front of it.

local M = {}

M.DIST = 7.5                          -- m from the car's centre (before the car's own size sets it: frame)
M.PITCH = math.rad(14)                -- (likewise)
M.DROP = 0.20                         -- the look-at point is this much of the distance below the car's centre: the car sits in the upper
                                      -- part of the screen, clear of the lot's info card over the bottom 40 %
M.EYE_UP = 0.8                        -- m the eye stands above the car's centre (about 1.5 m above the ground): a low hero shot
M.YAWS = { 145, -145, 120, -120, 90, -90, 35, -35, 180 }       -- degrees from the way the car faces: rear quarters first
M.KEEP = 0.6                          -- m kept between the eye and a wall

local function eyeAt(target, dir, yaw, pitch, dist)
  local side = { x = dir.y, y = -dir.x }
  local c, s = math.cos(yaw), math.sin(yaw)
  local flat = dist * math.cos(pitch)
  return { x = target.x + (dir.x * c + side.x * s) * flat, y = target.y + (dir.y * c + side.y * s) * flat, z = target.z + dist * math.sin(pitch) + 0.4 }
end
M.eyeAt = eyeAt

local function len(a, b) return math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2 + (b.z - a.z) ^ 2) end

-- Distance and pitch from the car's size (diag = the length of its bounding box's diagonal): the whole car fits, the eye is EYE_UP
-- above its centre, and 6.5 to 10 m out.
function M.frame(diag)
  local dist = math.max(6.5, math.min(10, 1.35 * (tonumber(diag) or 5)))
  local pitch = math.asin(math.min(0.6, math.max(0.05, (M.EYE_UP - 0.4) / dist)))      -- (eyeAt adds 0.4 m)
  return dist, pitch
end

-- the eye, pulled in front of whatever is between it and the car
function M.pull(target, eye, ray)
  local from = { x = target.x, y = target.y, z = target.z + 0.8 }
  local total = len(from, eye)
  local hit = total > 0 and ray(from, eye)
  if not hit or hit >= total - 0.01 then return eye, 1 end
  local keep = math.max(1.5, hit - M.KEEP)
  local f = keep / total
  return { x = from.x + (eye.x - from.x) * f, y = from.y + (eye.y - from.y) * f, z = from.z + (eye.z - from.z) * f }, f
end

-- the yaw (radians from the car's facing) with the most room: the first of YAWS that is clear, else the clearest
function M.choose(target, dir, pitch, dist, ray)
  local best, bestFrac = math.rad(M.YAWS[1]), -1
  for _, deg in ipairs(M.YAWS) do
    local yaw = math.rad(deg)
    local _, frac = M.pull(target, eyeAt(target, dir, yaw, pitch or M.PITCH, dist or M.DIST), ray)
    if frac >= 1 then return yaw, 1 end
    if frac > bestFrac + 1e-6 then best, bestFrac = yaw, frac end
  end
  return best, bestFrac
end

-- The camera's yaw and pitch (degrees) for a look along (dx, dy, dz), in scriptedFree's own convention (core/cameraModes/scriptedFree.lua:
-- forward = (sin yaw * cos pitch, cos yaw * cos pitch, -sin pitch): yaw clockwise from +Y, pitch POSITIVE LOOKING DOWN). Giving the
-- camera these instead of a rotation quaternion keeps its Euler conversion out of it (the view pointed into the sky).
function M.angles(dx, dy, dz)
  local flat = math.sqrt(dx * dx + dy * dy)
  local len = math.sqrt(flat * flat + dz * dz)
  if len < 1e-9 then return 0, 0 end
  return math.deg((math.atan2 or math.atan)(dx, dy)), math.deg(math.asin(math.max(-1, math.min(1, -dz / len))))
end

-- From one framing to the next, along the lot (B69: the camera used to jump between cars). Position and look-at point go from the first to
-- the second by a smoothstep over `dur` seconds (still at both ends), the position lifted `lift` metres at the middle so it passes over the
-- cars in between. Returns pos, look at time t (clamped), and whether it is done.
M.GLIDE = 1.6                         -- (a slow dolly along the row; the lift is the arc over the cars between)
M.GLIDE_LIFT = 0.9
function M.glide(fromPos, toPos, fromLook, toLook, t, dur, lift)
  dur = dur or M.GLIDE
  local u = dur > 0 and math.max(0, math.min(1, t / dur)) or 1
  local s = u * u * (3 - 2 * u)
  local function mix(a, b) return { x = a.x + (b.x - a.x) * s, y = a.y + (b.y - a.y) * s, z = a.z + (b.z - a.z) * s } end
  local pos = mix(fromPos, toPos)
  pos.z = pos.z + (lift or M.GLIDE_LIFT) * math.sin(math.pi * s)
  return pos, mix(fromLook, toLook), u >= 1
end

-- The camera drifts a few degrees to and fro round the car on show (a slow arc, never still): extra yaw in radians at time t seconds.
M.SWAY = math.rad(10)
function M.sway(t) return M.SWAY * math.sin((tonumber(t) or 0) * 0.35) end

-- The purchase reveal (C2): s in 0..1 runs an orbit round the car from its front quarter to the back, pushing in at the middle, and ends
-- exactly where the game's chase camera stands (7.5 m behind, 2.4 m up) so the hand-over to the driver's seat has no jump.
-- c = the car's centre, f = its flat unit forward {x, y}. Returns the eye and the look-at point.
M.REVEAL_FROM = math.rad(40)          -- degrees from the car's facing at s = 0 (180 = straight behind)
function M.reveal(c, f, s)
  s = math.max(0, math.min(1, s))
  local e = s * s * (3 - 2 * s)
  local a = M.REVEAL_FROM + (math.pi - M.REVEAL_FROM) * e
  local d = 7.5 - 2.3 * math.sin(math.pi * e)
  local ca, sa = math.cos(a), math.sin(a)
  local side = { x = f.y, y = -f.x }
  local pos = { x = c.x + (f.x * ca + side.x * sa) * d, y = c.y + (f.y * ca + side.y * sa) * d, z = c.z + 0.6 + 1.8 * e }
  return pos, { x = c.x, y = c.y, z = c.z + 0.4 }
end

return M
