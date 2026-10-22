-- Street Legal: the Needs part in the player's car (loaded by sl_needs). A tired driver's steering, throttle and brake follow the input with a lag;
-- a hungry one has a faint shake on the steering. The game's input.event is wrapped (as the Driver Injuries add-on wraps it for a broken limb):
-- with nothing to apply every event passes straight through. slNeeds.set(lagSeconds, tremor) from the game side; set(0, 0) lets go.

local M = {}

local filter = require('sl_needsfilter')

local lag, tremor = 0, 0
local KEYS = { steering = true, throttle = true, brake = true }
local target, cur, extra = {}, {}, {}
local t = 0
local nodLeft = 0      -- seconds of a micro-sleep to go: the throttle is let go, the steering and the brake hold, what the driver does meanwhile applies when he is awake again

local function install()
  if input.slNeedsEvent then return end
  input.slNeedsEvent = input.event
  input.event = function(itype, value, ...)
    if KEYS[itype] and (lag > 0 or nodLeft > 0 or (tremor > 0 and itype == 'steering')) then
      target[itype], extra[itype] = value, { ... }
      if cur[itype] == nil then cur[itype] = value end
      return
    end
    return input.slNeedsEvent(itype, value, ...)
  end
end

local function flush(itype)
  local tg = target[itype]
  if tg ~= nil then input.slNeedsEvent(itype, tg, unpack(extra[itype] or {})) end
  target[itype], cur[itype], extra[itype] = nil, nil, nil
end

function M.set(l, tr)
  l, tr = tonumber(l) or 0, tonumber(tr) or 0
  local was = lag > 0 or tremor > 0
  lag, tremor = math.max(0, l), math.max(0, tr)
  if lag > 0 or tremor > 0 then install()
  elseif was and input.slNeedsEvent then for k in pairs(KEYS) do flush(k) end end
end
function M.get() return lag, tremor end

-- let go of everything at once: a switch of car, a reset, the career ending, the part switched off
function M.release()
  if nodLeft > 0 then
    nodLeft = 0
    for k in pairs(KEYS) do flush(k) end
  end
end

-- a micro-sleep of `seconds` (at most a second and a half: the game side asks for 0.5 to 1)
function M.nod(seconds)
  nodLeft = math.max(nodLeft, math.min(1.5, tonumber(seconds) or 0))
  if nodLeft > 0 then install() end
end

function M.updateGFX(dt)
  if nodLeft > 0 then
    nodLeft = nodLeft - dt
    if nodLeft > 0 then
      if input.slNeedsEvent then input.slNeedsEvent('throttle', 0) end
      return
    end
    nodLeft = 0
    for k in pairs(KEYS) do flush(k) end      -- (awake: the last input of each pedal and of the steering applies)
  end
  if lag <= 0 and tremor <= 0 then return end
  t = t + dt
  for itype in pairs(KEYS) do
    local tg = target[itype]
    if tg ~= nil then
      local c = filter.lagStep(cur[itype] or tg, tg, dt, lag)
      cur[itype] = c
      local out = c
      if itype == 'steering' then out = filter.clamp(c + filter.tremor(t, tremor), -1, 1) end
      input.slNeedsEvent(itype, out, unpack(extra[itype] or {}))
    end
  end
end

function M.onReset() nodLeft = 0 for k in pairs(KEYS) do target[k], cur[k], extra[k] = nil, nil, nil end end

return M
