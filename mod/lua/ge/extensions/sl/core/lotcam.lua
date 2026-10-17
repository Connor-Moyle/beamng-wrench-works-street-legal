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

-- Detail shots (C5 purchase reveal, C6 browsing): kind in front | side | wheel | cabin | badge | rear, s in 0..1 along a slow drift. c = the car's
-- centre, f = its flat forward {x, y}, L and W = its length and width. Returns the eye and the look-at point.
M.REVEAL_SHOTS = { 'front', 'wheel', 'cabin', 'rear' }
M.BROWSE_SHOTS = { 'side', 'wheel', 'cabin', 'badge', 'rear', 'front' }
function M.shot(kind, c, f, L, W, s)
  s = math.max(0, math.min(1, s or 0))
  local r = { x = f.y, y = -f.x }
  local function at(af, ar, z) return { x = c.x + f.x * af + r.x * ar, y = c.y + f.y * af + r.y * ar, z = c.z + z } end
  if kind == 'side' then return at(L * 0.7 - L * 1.4 * s, W / 2 + 3.2, -0.15), at(L * 0.45 - L * 0.9 * s, 0, 0.05)
  elseif kind == 'wheel' then return at(L * 0.36, W / 2 + 1.5 - 0.3 * s, -0.3), at(L * 0.34, W / 2, -0.3)
  elseif kind == 'cabin' then return at(-0.05 * L, -0.25 * W, 0.3), at(6, (-2 + 4 * s) , 0.2)
  elseif kind == 'badge' then return at(L / 2 + 2 - 0.5 * s, 0.4, -0.1), at(L / 2, 0, 0)
  elseif kind == 'rear' then return at(-(L / 2 + 2.4 - 0.6 * s), 1.2 - 0.8 * s, 0), at(-L / 2, 0, 0.1)
  end
  local a = math.rad(35 + 10 * s)       -- front quarter, the hero shot
  local d = L * 0.8 + 2.5 - 0.8 * s
  return at(math.cos(a) * d, math.sin(a) * d, -0.1), at(0, 0, 0.1)
end

M.SHOT_TIME = 5                       -- s a browsing shot lasts
M.SHOT_EASE = 1.0                     -- s it takes to ease in from, and out to, the normal orbit
M.IDLE = 6                            -- s without input before the browsing shots start

-- where the game's chase camera stands (7.5 m behind, 2.4 m up): where the purchase reveal ends and hands over to the driver's seat
function M.chase(c, f)
  return { x = c.x - f.x * 7.5, y = c.y - f.y * 7.5, z = c.z + 2.4 }, { x = c.x, y = c.y, z = c.z + 0.4 }
end

return M
