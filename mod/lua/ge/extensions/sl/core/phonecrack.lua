-- Street Legal: the cracked phone screen, the rules (pure, no game calls: tools/luatest.js). A crash cracks the phone's glass; the stage (0 to 3) follows how hard the crash was, an impact point
-- and a seed give the spider web its shape (the UI draws it), a repair of the car mends it. The crash signal is the jump of the car's damage reading between two looks (the game's
-- map.objects[id].damage); the numbers (threshold, chance, ...) are settings because the scale of that reading is calibrated in the game, not known from the code.
local M = {}

M.THRESHOLD = 1500       -- a damage jump this big cracks the screen to stage 1 (a guess: the game's reading is not documented; the setting Crash threshold moves it)
M.CHANCE = 0.8           -- the chance a crash that is hard enough cracks it at all
M.MAX_STAGE = 3
M.STAGE_AT = { 1, 2.5, 5 }   -- stage 1 at the threshold, stage 2 at 2.5 times, stage 3 at 5 times

-- the stage a damage jump gives (0 when it is under the threshold), never above max
function M.stageFor(jump, threshold, max)
  jump, threshold = tonumber(jump) or 0, math.max(1, tonumber(threshold) or M.THRESHOLD)
  local stage = 0
  for i, at in ipairs(M.STAGE_AT) do if jump >= threshold * at then stage = i end end
  return math.min(stage, math.max(0, math.min(M.MAX_STAGE, math.floor(tonumber(max) or M.MAX_STAGE))))
end

-- one crash: the new state of the phone given the old one (nil or { stage, x, y, seed }) and a random value r in [0,1) for the chance and two more for the impact point
-- Returns the state, and whether anything changed. A crash never lowers the stage; a harder crash than the cracks already there raises it and moves the impact point.
function M.crash(old, jump, opts, r, rx, ry, seed)
  opts = opts or {}
  local stage = M.stageFor(jump, opts.threshold, opts.max)
  if stage <= 0 then return old, false end
  if (tonumber(r) or 0) >= (tonumber(opts.chance) or M.CHANCE) then return old, false end
  local cur = old and tonumber(old.stage) or 0
  if stage <= cur then return old, false end
  return { stage = stage, x = math.max(0.05, math.min(0.95, tonumber(rx) or 0.5)), y = math.max(0.05, math.min(0.95, tonumber(ry) or 0.4)), seed = tonumber(seed) or 1 }, true
end

-- the damage reading dropped back: the car was repaired (a drop of most of what was there, after a reading that was worth a crack)
function M.repaired(prev, now, threshold)
  prev, now = tonumber(prev) or 0, tonumber(now) or 0
  return prev >= math.max(1, tonumber(threshold) or M.THRESHOLD) * 0.5 and now <= prev * 0.4
end

-- what the UI is told: nil with no crack; strength 0.3..1 is the overlay's opacity (a setting)
function M.view(state, strength)
  local stage = state and tonumber(state.stage) or 0
  if stage <= 0 then return nil end
  return { stage = math.min(3, stage), x = state.x or 0.5, y = state.y or 0.4, seed = state.seed or 1, strength = math.max(0.3, math.min(1, tonumber(strength) or 0.85)) }
end

return M
