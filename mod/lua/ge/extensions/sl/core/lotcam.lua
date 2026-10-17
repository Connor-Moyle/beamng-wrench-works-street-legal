-- Street Legal: where the lot camera stands (T37). Pure; the walls are the game's (ray(a, b) -> the distance from a to the first
-- thing hit on the way to b, or nil), tested by tools/luatest.js. The camera looks at the shown car's centre from a rear quarter, a
-- few metres out and about 1.5 m up, on the side with room: a wall behind or beside the car (the lot is against a building)
-- no longer fills the picture, and an eye that would be inside something is pulled back in front of it.

local M = {}

M.DIST = 7.5                          -- m from the car's centre (before the car's own size sets it: frame)
M.PITCH = math.rad(14)                -- (likewise)
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

-- Detail shots (C5 purchase reveal, C6 browsing): s in 0..1 along a slow drift. c = the car's centre, f = its flat forward {x, y}, L, W = its
-- length and width, eye = the driver camera's position (nil: a guess). Returns the eye and the look-at point. Every shot but the two cabin
-- ones keeps its eye outside the car's box (see M.outside) along its whole drift.
--   front (quarter hero), front_sweep (low sweep across the nose), side (dolly at sill height), wheel and wheel_rear (close-ups), badge (grille
--   macro), taillight (macro), rear, rear_rise (rear three-quarter, rising), top (roof-level drift), exhaust, orbit (high establishing orbit),
--   engine (front: over the open hood) and engine_rear (over the open engine lid), cabin (driver's eye turning its head), cabin_pass (the
--   passenger's seat turning towards the driver)
M.REVEAL_SHOTS = { 'front', 'wheel', 'cabin', 'rear' }
M.BROWSE_SHOTS = { 'front', 'front_sweep', 'side', 'wheel', 'wheel_rear', 'badge', 'taillight', 'rear', 'rear_rise', 'top', 'exhaust', 'orbit',
  'engine', 'engine_rear', 'cabin', 'cabin_pass' }
-- the camera's view, for the shots that fill a share of the frame: the horizontal half-angle's tangent = tan(fov / 2) (the game's field of view
-- is the horizontal one: checked in game, the 60 % side shot filled more than the frame when it was taken as the vertical) -- set by the lot
M.viewTan = math.tan(math.rad(65) / 2)
function M.setView(fovDeg) M.viewTan = math.tan(math.rad(tonumber(fovDeg) or 65) / 2) end
M.SIDE_FILL = 0.6                     -- the side shot: the car fills this share of the frame's width

function M.shot(kind, c, f, L, W, s, eye)
  s = math.max(0, math.min(1, s or 0))
  local r = { x = f.y, y = -f.x }
  local function at(af, ar, z) return { x = c.x + f.x * af + r.x * ar, y = c.y + f.y * af + r.y * ar, z = c.z + z } end
  local H = L * 0.3                                    -- (a car's height, roughly: enough to place the high shots)
  if kind == 'side' then
    local D = math.max(W / 2 + 1.2, L / (2 * M.SIDE_FILL * M.viewTan))      -- (the car's length is SIDE_FILL of the width seen at that distance)
    return at(L * 0.3 - L * 0.6 * s, D, -0.15), at(L * 0.18 - L * 0.36 * s, 0, 0.05)
  elseif kind == 'wheel' then return at(L * 0.36, W / 2 + 1.5 - 0.3 * s, -0.3), at(L * 0.34, W / 2, -0.3)
  elseif kind == 'wheel_rear' then return at(-L * 0.36, W / 2 + 1.5 - 0.3 * s, -0.3), at(-L * 0.34, W / 2, -0.3)
  elseif kind == 'cabin' or kind == 'cabin_pass' then
    local pass = kind == 'cabin_pass'
    local e = eye
    if e then
      if pass then   -- mirrored across the car's centre line: the passenger's seat
        local b = (e.x - c.x) * r.x + (e.y - c.y) * r.y
        e = { x = e.x - r.x * 2 * b, y = e.y - r.y * 2 * b, z = e.z }
      end
      local th = math.rad((pass and 35 or -35) + (pass and -70 or 70) * s)      -- (turning only: the head stays where it is)
      local dx, dy = f.x * math.cos(th) + r.x * math.sin(th), f.y * math.cos(th) + r.y * math.sin(th)
      return { x = e.x, y = e.y, z = e.z }, { x = e.x + dx * 6, y = e.y + dy * 6, z = e.z - 0.15 }
    end
    local side = pass and 0.25 or -0.25
    return at(-0.05 * L, side * W, 0.3), at(6, (pass and 2 or -2) + (pass and -4 or 4) * s, 0.2)
  elseif kind == 'badge' then return at(L / 2 + 1.2 - 0.2 * s, 0.4, -0.05), at(L / 2, 0, 0)
  elseif kind == 'taillight' then return at(-(L / 2 + 1.3 - 0.2 * s), W * 0.55, 0.1), at(-L / 2, W * 0.35, 0.15)
  elseif kind == 'rear' then return at(-(L / 2 + 2.4 - 0.6 * s), 1.2 - 0.8 * s, 0), at(-L * 0.2, 0, 0.1)
  elseif kind == 'rear_rise' then return at(-(L / 2 + 3 - 0.5 * s), W / 2 + 2, -0.1 + 1.5 * s), at(-L * 0.05, 0, 0.1)
  elseif kind == 'front_sweep' then return at(L / 2 + 2.2, W * 1.2 * (-1 + 2 * s), -0.2), at(L / 2 - 0.5, 0, 0)
  elseif kind == 'top' then return at(L * 0.6 - L * 1.2 * s, W / 2 + 1.8, H / 2 + 3.2), at(0, 0, 0)
  elseif kind == 'exhaust' then return at(-(L / 2 + 1.2 - 0.2 * s), -W * 0.25, -0.45), at(-L / 2, -W * 0.25, -0.4)
  elseif kind == 'orbit' then
    local a = math.rad(30 + 80 * s)
    local d = L * 1.1 + 3.5
    return at(math.cos(a) * d, math.sin(a) * d, H / 2 + 2.4), at(0, 0, 0)
  elseif kind == 'engine' then return at(L / 2 + 1.5, W * 0.9 * (-0.5 + s), 0.9), at(L * 0.3, 0, 0.05)
  elseif kind == 'engine_rear' then return at(-(L / 2 + 1.5), W * 0.9 * (-0.5 + s), 0.9), at(-L * 0.3, 0, 0.05)
  end
  local a = math.rad(35 + 10 * s)       -- front quarter, the hero shot
  local d = L * 0.8 + 2.5 - 0.8 * s
  return at(math.cos(a) * d, math.sin(a) * d, -0.1), at(0, 0, 0.1)
end

-- The next shot out of a shuffle bag (C6): every kind once in random order before any comes round again, and the first of a new bag is never
-- the last one shown. state = { bag = {}, last }; rnd(n) = a random integer 1..n; usable(kind) = false drops the kind from this bag (no line of
-- sight, no hood to open ...). Returns the kind, or nil when nothing is usable.
function M.draw(state, rnd, usable)
  for _ = 1, 2 do
    if #state.bag == 0 then
      for i, k in ipairs(M.BROWSE_SHOTS) do state.bag[i] = k end
      for i = #state.bag, 2, -1 do local j = rnd(i) state.bag[i], state.bag[j] = state.bag[j], state.bag[i] end
      if state.bag[#state.bag] == state.last and #state.bag > 1 then state.bag[#state.bag], state.bag[1] = state.bag[1], state.bag[#state.bag] end
    end
    while #state.bag > 0 do
      local k = table.remove(state.bag)
      if k ~= state.last and usable(k) then state.last = k return k end
    end
  end
end

-- Line of sight (C5/C6): a detail shot is usable only when, along its whole drift, nothing static stands between the eye and the car (which
-- also means the eye is not inside a wall or pillar). ray(a, b) as in M.pull: the distance to the first hit, or nil.
function M.shotClear(kind, c, f, L, W, ray, eye)
  local from = { x = c.x, y = c.y, z = c.z + 0.5 }
  for _, s in ipairs({ 0, 0.25, 0.5, 0.75, 1 }) do
    local e = M.shot(kind, c, f, L, W, s, eye)
    local total = len(from, e)
    local hit = total > 0.5 and ray(from, e)
    if hit and hit < total - 0.3 then return false end
  end
  return true
end

-- The eye kept outside the car's box (C6): the car's length, width and height (H) plus a margin m on every side. A point inside is pushed
-- straight out from the car's centre to the box's surface (continuous: a path through the car swings round it instead).
M.BOX_MARGIN = 0.6
function M.inBox(c, f, L, W, H, p, m)
  m = m or M.BOX_MARGIN
  local dx, dy, dz = p.x - c.x, p.y - c.y, p.z - c.z
  local a, b = dx * f.x + dy * f.y, dx * f.y - dy * f.x
  return math.abs(a) < L / 2 + m and math.abs(b) < W / 2 + m and math.abs(dz) < (H or 1.5) / 2 + m, a, b
end
function M.outside(c, f, L, W, H, p, m)
  m = m or M.BOX_MARGIN
  local inside, a, b = M.inBox(c, f, L, W, H, p, m)
  if not inside then return p end
  if a == 0 and b == 0 then b = 0.01 end
  local t = math.min((L / 2 + m + 0.01) / math.max(math.abs(a), 1e-9), (W / 2 + m + 0.01) / math.max(math.abs(b), 1e-9))
  a, b = a * t, b * t
  return { x = c.x + f.x * a + f.y * b, y = c.y + f.y * a - f.x * b, z = p.z }
end

-- A path round the car (C6): from pose a to pose b about the car's centre c, by angle and radius, so a move between two shots swings
-- round the car instead of cutting through it. u in 0..1. box = { f, L, W, H }: the eye is also kept out of the car's box. Returns the eye.
function M.arc(c, a, b, u, box)
  local atan = math.atan2 or math.atan
  local a1, a2 = atan(a.y - c.y, a.x - c.x), atan(b.y - c.y, b.x - c.x)
  local d = (a2 - a1 + math.pi) % (2 * math.pi) - math.pi
  local r1, r2 = math.sqrt((a.x - c.x) ^ 2 + (a.y - c.y) ^ 2), math.sqrt((b.x - c.x) ^ 2 + (b.y - c.y) ^ 2)
  local ang, r = a1 + d * u, r1 + (r2 - r1) * u
  local p = { x = c.x + math.cos(ang) * r, y = c.y + math.sin(ang) * r, z = a.z + (b.z - a.z) * u }
  return box and M.outside(c, box.f, box.L, box.W, box.H, p) or p
end

-- The browsing shots as one flowing camera (C6). st = the state (nil = at rest on the normal orbit), auto = the shots may run (false: the
-- player moved the camera), orbit = { pos, look } the normal orbit pose now, ctx = { c, f, L, W, H, eye } the car (eye: the driver camera's
-- position), pick() = the next usable shot kind or nil. Phases: in (orbit -> the first shot), shot (the live shot), trans (the end of one
-- shot -> the start of the next along an arc round the car: never via the orbit pose), out (back to the orbit; only when the player moves
-- the camera or no shot is usable). The eye never enters the car's box (plus a margin) except for the short move through the driver's
-- window into or out of the cabin shot. Returns the new state, the eye, the look-at point, the shot weight 0..1 (how far the picture is the
-- shots' rather than the orbit's), and true when no shot was usable at the start.
function M.chain(st, dt, auto, orbit, ctx, pick)
  local function smooth(u) u = math.max(0, math.min(1, u)) return u * u * (3 - 2 * u) end
  local function mix(a, b, e) return { x = a.x + (b.x - a.x) * e, y = a.y + (b.y - a.y) * e, z = a.z + (b.z - a.z) * e } end
  local function live(kind, s) return M.shot(kind, ctx.c, ctx.f, ctx.L, ctx.W, s, ctx.eye) end
  local box = { f = ctx.f, L = ctx.L, W = ctx.W, H = ctx.H or 1.5 }
  local function windowOf(kind)      -- the window of the driver's side (cabin) or the passenger's (cabin_pass), outside the box
    local k = (kind == 'cabin_pass' and 1 or -1) * (ctx.W / 2 + 0.8)
    return { x = ctx.c.x + ctx.f.y * k, y = ctx.c.y - ctx.f.x * k, z = ctx.c.z + 0.3 }
  end
  local function isCabin(kind) return kind == 'cabin' or kind == 'cabin_pass' end
  -- one move from fromPos to toPos at u (0..1): round the car; into or out of the cabin through its window (cabinFrom / cabinTo = the kind or nil)
  local function leg(fromPos, toPos, u, cabinFrom, cabinTo)
    if cabinFrom and cabinTo then       -- cabin to cabin: out of one window, round the car, in at the other
      local wf, wt = windowOf(cabinFrom), windowOf(cabinTo)
      if u < 0.25 then return mix(fromPos, wf, smooth(u / 0.25)) end
      if u < 0.75 then return M.arc(ctx.c, wf, wt, smooth((u - 0.25) / 0.5), box) end
      return mix(wt, toPos, smooth((u - 0.75) / 0.25))
    end
    local window = windowOf(cabinTo or cabinFrom)
    if cabinTo then
      if u < 0.75 then return M.arc(ctx.c, fromPos, window, smooth(u / 0.75), box) end
      return mix(window, toPos, smooth((u - 0.75) / 0.25))
    elseif cabinFrom then
      if u < 0.25 then return mix(fromPos, window, smooth(u / 0.25)) end
      return M.arc(ctx.c, window, toPos, smooth((u - 0.25) / 0.75), box)
    end
    return M.arc(ctx.c, fromPos, toPos, smooth(u), box)
  end
  if not st then
    if not auto then return nil end
    local kind = pick()
    if isCabin(kind) then kind = pick() end            -- (never start inside the car: the first shot is one seen from outside)
    if not kind or isCabin(kind) then return nil, nil, nil, 0, true end
    st = { phase = 'in', kind = kind, u = 0, t = 0, pos = orbit.pos, look = orbit.look }
  end
  if not auto and st.phase ~= 'out' then
    st = { phase = 'out', u = 0, fromPos = st.pos, fromLook = st.look, cabinFrom = M.inBox(ctx.c, ctx.f, ctx.L, ctx.W, ctx.H or 1.5, st.pos) and (st.kind or 'cabin') }
  end
  local pos, look, w
  if st.phase == 'in' then
    st.u, st.t = st.u + dt / M.SHOT_EASE, st.t + dt
    local p, l = live(st.kind, st.t / M.SHOT_TIME)
    local e = smooth(st.u)
    pos, look, w = M.arc(ctx.c, orbit.pos, p, e, box), mix(orbit.look, l, e), e
    if st.u >= 1 then st.phase = 'shot' end
  elseif st.phase == 'shot' then
    st.t = st.t + dt
    pos, look = live(st.kind, st.t / M.SHOT_TIME)
    w = 1
    if st.t >= M.SHOT_TIME then
      local nextKind = pick()
      if nextKind then st.phase, st.nextKind, st.u, st.fromPos, st.fromLook = 'trans', nextKind, 0, pos, look
        st.dur = (isCabin(st.kind) and isCabin(nextKind)) and 2.8 * M.SHOT_TRANS or M.SHOT_TRANS      -- (out of one window and in at the other: a longer move)
      else st.phase, st.u, st.fromPos, st.fromLook, st.cabinFrom = 'out', 0, pos, look, isCabin(st.kind) and st.kind or nil end
    end
  elseif st.phase == 'trans' then
    st.u = st.u + dt / (st.dur or M.SHOT_TRANS)
    local p, l = live(st.nextKind, 0)
    pos, look, w = leg(st.fromPos, p, math.min(st.u, 1), isCabin(st.kind) and st.kind or nil, isCabin(st.nextKind) and st.nextKind or nil), mix(st.fromLook, l, smooth(st.u)), 1
    if st.u >= 1 then st.phase, st.kind, st.t = 'shot', st.nextKind, 0 end
  else
    st.u = st.u + dt / M.SHOT_EASE
    local e = smooth(st.u)
    pos, look, w = leg(st.fromPos, orbit.pos, math.min(st.u, 1), st.cabinFrom or nil, nil), mix(st.fromLook, orbit.look, e), 1 - e
    if st.u >= 1 then return nil, orbit.pos, orbit.look, 0 end
  end
  st.pos, st.look = pos, look
  return st, pos, look, w
end

M.SHOT_TRANS = 1.4                    -- s a move from the end of one shot to the start of the next takes
M.SHOT_TIME = 5                       -- s a browsing shot lasts
M.SHOT_EASE = 1.0                     -- s it takes to ease in from, and out to, the normal orbit
M.IDLE = 6                            -- s without input before the browsing shots start

-- where the game's chase camera stands (7.5 m behind, 2.4 m up): where the purchase reveal ends and hands over to the driver's seat
function M.chase(c, f)
  return { x = c.x - f.x * 7.5, y = c.y - f.y * 7.5, z = c.z + 2.4 }, { x = c.x, y = c.y, z = c.z + 0.4 }
end

return M
