-- Street Legal: the race flares' flicker, as pure rules (what sl_markers writes to its lights each update).
-- A light's intensity is an engine write: at most RATE apart, and only for flares within REACH of the camera.

local M = {}

M.RATE = 0.1          -- s between flicker updates
M.REACH = 120         -- m from the camera: further flares burn steady

-- lights: { { phase, x, y } }; t: now; lastT: the last update's time (nil at first); cam: { x, y } or nil
-- Returns the writes due, { { index, intensity } }, and the time to remember as lastT.
function M.flicker(lights, t, lastT, cam)
  if lastT and t - lastT < M.RATE then return {}, lastT end
  local out = {}
  for i, l in ipairs(lights) do
    if not cam or (l.x - cam.x) ^ 2 + (l.y - cam.y) ^ 2 <= M.REACH ^ 2 then
      out[#out + 1] = { i, 0.8 + 0.35 * math.sin(t * 13 + l.phase) + 0.2 * math.sin(t * 29 + l.phase * 2) }
    end
  end
  return out, t
end

-- the lockdown's one rule: apply only on a change (repeated hooks must not touch the input filters again)
function M.lockStep(locked, on)
  if (on and true or false) == (locked and true or false) then return nil end
  return on and 'lock' or 'unlock'
end

return M
