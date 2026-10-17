-- Street Legal: where the lot camera stands (T37). Pure; the walls are the game's (ray(a, b) -> the distance from a to the first
-- thing hit on the way to b, or nil), tested by tools/luatest.js. The camera looks at the shown car's centre from a rear quarter, a
-- few metres out and about 1.5 m up, on the side with room: a wall behind or beside the car (the lot is against a building)
-- no longer fills the picture, and an eye that would be inside something is pulled back in front of it.

local M = {}

M.DIST = 6.5                          -- m from the car's centre
M.PITCH = math.rad(12)                -- 6.5 m * sin 12 + 0.4 = about 1.75 m above the car's centre
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

return M
