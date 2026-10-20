-- Street Legal: a small gate so the wet world's material reloads and the puddle planes' creation do not hit the GPU in the same moments (the game lost its D3D12 device in heavy rain when both ran at
-- once, 4 of 4 times; either alone survived). Each side notes when it last did its work; the other waits a hold time. Pure: the caller passes the clock.
local M = {}

M.WET_HOLD = 1          -- s the puddle planes are left alone after a wet world batch (the reloads compile shaders)
M.PLANE_HOLD = 0.5      -- s the wet world is left alone after a puddle plane was made or dropped
M.STARVED_AFTER = 10     -- s the planes may have waited, without making any, before the wet world pauses for them
M.WINDOW = 1.5          -- s the wet world pauses then (the planes need 1 s after the last reload: they get about half a second of building)
M.TERRAIN_HOLD = 60      -- s after a terrain material swap in which the puddles make no terrain material lookups (a crash with the swap on, 8 s later, with only those running)
M.TERRAIN_QUIET = 10     -- s after a terrain material swap in which Car Surface FX's terrain hollows write no heights (updateGrid rebuilds terrain geometry)
M.LOG_EVERY = 5         -- s between two "waits" log lines of one side

local lastReload, lastPlanes = -1e9, -1e9
local lastLog, waits = {}, { wet = 0, planes = 0 }
local lastTerrain = -1e9
local waitSince, lastWait, windowUntil = nil, -1e9, -1e9      -- the planes' waiting spell, and the pause the wet world takes for it

function M.reset() lastTerrain = -1e9 lastReload, lastPlanes, lastLog, waits, waitSince, lastWait, windowUntil = -1e9, -1e9, {}, { wet = 0, planes = 0 }, nil, -1e9, -1e9 end
function M.reloaded(now) lastReload = now end
function M.terrainSwapped(now) lastTerrain = now end
function M.terrainLookupsOk(now) return now - lastTerrain >= M.TERRAIN_HOLD end
-- Car Surface FX's terrain hollows ask this before each updateGrid flush, and tell planesTouched after it so the wet world waits too
function M.terrainEditOk(now) return now - lastTerrain >= M.TERRAIN_QUIET and now - lastReload >= M.WET_HOLD end
function M.planesTouched(now) lastPlanes, waitSince = now, nil end
function M.planesMayChange(now) return now - lastReload >= M.WET_HOLD end
function M.wetMayBatch(now)
  if waitSince and now - waitSince > M.STARVED_AFTER then windowUntil, waitSince = now + M.WINDOW, nil end      -- (the planes starved: the wet world steps aside for a moment)
  return now - lastPlanes >= M.PLANE_HOLD and now >= windowUntil
end

-- a side waited: returns a line to log (at most one per LOG_EVERY seconds per side, with the waits counted since), or nil
function M.waited(side, now)
  if side == 'planes' then
    if not waitSince or now - lastWait > 2 then waitSince = now end      -- (a new spell when the last wait was a while ago)
    lastWait = now
  end
  waits[side] = waits[side] + 1
  if now - (lastLog[side] or -1e9) < M.LOG_EVERY then return nil end
  lastLog[side] = now
  local n = waits[side]
  waits[side] = 0
  if side == 'wet' then return string.format('wet world waited %d time(s) for puddle planes (a plane was made or dropped less than %.1f s ago)', n, M.PLANE_HOLD) end
  return string.format('puddle planes waited %d time(s) for the wet world (a material reload less than %.1f s ago)', n, M.WET_HOLD)
end

return M
