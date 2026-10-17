-- Street Legal: when and where a racer's car may be built (#19, B65: lag and freezes while driving). Pure, tested by tools/luatest.js.
-- Building a car (spawn, parts, paint) is the heaviest thing the career does at night; done where the player can see it, or on the road he is
-- driving down, it shows as a hitch and as a car popping up in front of him. So: one at a time, only out of his sight and off his way, and not
-- while he is racing along (unless it has been a long time).

local M = {}

M.FOV = 110              -- degrees across: in view
M.VIEW_UP_TO = 500       -- m: further than this nothing counts as in view
M.AHEAD = 60             -- degrees: inside this of the way he is going (fast enough) is "on his way"
M.MOVING = 4             -- m/s: slower than this he is not going anywhere
M.MIN_GAP = 8            -- s between two builds
M.FAST = 15              -- m/s: above this nothing is built ...
M.PATIENCE = 45          -- ... until this many seconds have passed since the last

-- a spot (x, y) a car may be built at: not in the camera's view, not ahead of the player's travel.
-- player = { x, y, vx, vy }, cam = { x, y, fx, fy } (flat; fx, fy = 0 when unknown)
function M.hidden(pos, player, cam)
  if cam then
    local dx, dy = pos.x - cam.x, pos.y - cam.y
    local d = math.sqrt(dx * dx + dy * dy)
    local fl = math.sqrt((cam.fx or 0) ^ 2 + (cam.fy or 0) ^ 2)
    if fl > 1e-6 and d > 1e-6 and d <= M.VIEW_UP_TO and (dx * cam.fx + dy * cam.fy) / (d * fl) > math.cos(math.rad(M.FOV / 2)) then return false end
  end
  if player then
    local sp = math.sqrt((player.vx or 0) ^ 2 + (player.vy or 0) ^ 2)
    if sp >= M.MOVING then
      local dx, dy = pos.x - player.x, pos.y - player.y
      local d = math.sqrt(dx * dx + dy * dy)
      if d > 1e-6 and (dx * player.vx + dy * player.vy) / (d * sp) > math.cos(math.rad(M.AHEAD)) then return false end
    end
  end
  return true
end

-- may a car be built now: none being built, a gap since the last, and not while he drives fast (unless it has been long)
function M.canBuild(speed, since, busy)
  if busy then return false end
  if (since or 1e9) < M.MIN_GAP then return false end
  if (speed or 0) > M.FAST and (since or 1e9) < M.PATIENCE then return false end
  return true
end

-- the cruisers built behind the fade of the switch to night: what to do this frame with `pre` still wanted
-- -> 'reset' (the fade is over or a race began: forget the rest), 'build', or 'wait' (one at a time, none while too many are out)
function M.preStep(pre, inFade, race, busy, count, max)
  if (pre or 0) <= 0 then return 'none' end
  if not inFade or race then return 'reset' end
  if busy or count >= max then return 'wait' end
  return 'build'
end

return M
