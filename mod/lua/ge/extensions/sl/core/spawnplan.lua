-- Street Legal: when and where a racer's car may be built (#19, B65: lag and freezes while driving). Pure, tested by tools/luatest.js.
-- Building a car (spawn, parts, paint) is the heaviest thing the career does at night; done where the player can see it, or on the road he is
-- driving down, it shows as a hitch and as a car popping up in front of him. So: one at a time, only out of his sight and off his way, and not
-- while he is racing along (unless it has been a long time).

local M = {}

M.FOV = 110              -- degrees across: in view
M.VIEW_UP_TO = 500       -- m: further than this nothing counts as in view
M.AHEAD = 60             -- degrees: inside this of the way he is going (fast enough) is "on his way"
M.MOVING = 4             -- m/s: slower than this he is not going anywhere
M.MIN_GAP = 20           -- s between two builds (a build is a 1.1-1.7 s freeze and a run of slow frames after it: hitch recording, 3 min of night driving)
M.POOL_GAP = 4           -- s after which a pooled car may be put back on a road (a teleport, not a build)
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
function M.canBuild(speed, since, busy, pooled)
  if busy then return false end
  if (since or 1e9) < (pooled and M.POOL_GAP or M.MIN_GAP) then return false end
  if (speed or 0) > M.FAST and (since or 1e9) < M.PATIENCE then return false end
  return true
end

-- may an ambient police patrol be built now: the same rule as a racer's car (one build at a time anywhere, a gap since the last build by anyone,
-- not while the player drives fast), except that a patrol that belongs to a chase or to heat 4-5 (urgent) is never held back
function M.patrolOk(speed, since, busy, urgent)
  if busy then return false end
  if urgent then return true end
  return M.canBuild(speed, since, false, false)
end

-- the racers (of `list`) whose car waits in the pool and still exists (alive(vehicleId) -> bool); a stale id counts for nothing
function M.reusable(list, pool, alive)
  local out = {}
  for _, r in ipairs(list or {}) do if pool and pool[r.id] and alive(pool[r.id]) then out[#out + 1] = r end end
  return out
end

-- a build leaves ~1 s of slow frames after its 1.2-1.4 s call (hitch recordings): the next one waits until frames have been normal for RECOVER s;
-- on a machine that is slow all the time that would be never, so after PATIENCE_FRAMES s since the last build it is ignored
M.SLOW_FRAME, M.RECOVER, M.PATIENCE_FRAMES = 0.06, 2.0, 60
function M.framesRecovered(sinceSlowFrame, sinceBuild)
  return (sinceSlowFrame or 1e9) >= M.RECOVER or (sinceBuild or 0) >= M.PATIENCE_FRAMES
end

-- the cruisers built behind the fade of the switch to night: what to do this frame with `pre` still wanted
-- -> 'reset' (the fade is over or a race began: forget the rest), 'build', or 'wait' (one at a time, none while too many are out)
function M.preStep(pre, inFade, race, busy, count, max)
  if (pre or 0) <= 0 then return 'none' end
  if not inFade or race then return 'reset' end
  if busy or count >= max then return 'wait' end
  return 'build'
end

-- when a car meet is tried (#17: a night is never empty): the first one of a night 30 s in, later ones every 90 s with a 35 % chance;
-- a try that found no place or no hidden spot is repeated 20 s later, not a whole interval later
M.MEET_FIRST, M.MEET_EVERY, M.MEET_CHANCE, M.MEET_RETRY = 30, 90, 0.35, 20
-- -> nil (not yet), 'try' (go and start one), 'skip' (due, but the chance said no: the caller restarts the timer)
function M.meetDue(timer, meetsTonight, roll)
  if (meetsTonight or 0) == 0 then return timer >= M.MEET_FIRST and 'try' or nil end
  if timer < M.MEET_EVERY then return nil end
  return roll < M.MEET_CHANCE and 'try' or 'skip'
end
-- the timer after a try: 0 once a meet started (or a later try missed its chance), a short retry when the very try failed
function M.meetTimerAfter(started, meetsTonight)
  if started then return 0 end
  return ((meetsTonight or 0) == 0 and M.MEET_FIRST or M.MEET_EVERY) - M.MEET_RETRY
end

return M
