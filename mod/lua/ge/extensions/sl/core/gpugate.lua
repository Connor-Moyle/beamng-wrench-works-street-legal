-- Street Legal: a small gate so the wet world's material reloads and the puddle planes' creation do not hit the GPU in the same moments (the game lost its D3D12 device in heavy rain when both ran at
-- once, 4 of 4 times; either alone survived). Each side notes when it last did its work; the other waits a hold time. Pure: the caller passes the clock.
local M = {}

M.WET_HOLD = 1          -- s the puddle planes are left alone after a wet world batch (the reloads compile shaders)
M.PLANE_HOLD = 0.5      -- s the wet world is left alone after a puddle plane was made or dropped
M.LOG_EVERY = 5         -- s between two "waits" log lines of one side

local lastReload, lastPlanes = -1e9, -1e9
local lastLog, waits = {}, { wet = 0, planes = 0 }

function M.reset() lastReload, lastPlanes, lastLog, waits = -1e9, -1e9, {}, { wet = 0, planes = 0 } end
function M.reloaded(now) lastReload = now end
function M.planesTouched(now) lastPlanes = now end
function M.planesMayChange(now) return now - lastReload >= M.WET_HOLD end
function M.wetMayBatch(now) return now - lastPlanes >= M.PLANE_HOLD end

-- a side waited: returns a line to log (at most one per LOG_EVERY seconds per side, with the waits counted since), or nil
function M.waited(side, now)
  waits[side] = waits[side] + 1
  if now - (lastLog[side] or -1e9) < M.LOG_EVERY then return nil end
  lastLog[side] = now
  local n = waits[side]
  waits[side] = 0
  if side == 'wet' then return string.format('wet world waited %d time(s) for puddle planes (a plane was made or dropped less than %.1f s ago)', n, M.PLANE_HOLD) end
  return string.format('puddle planes waited %d time(s) for the wet world (a material reload less than %.1f s ago)', n, M.WET_HOLD)
end

return M
