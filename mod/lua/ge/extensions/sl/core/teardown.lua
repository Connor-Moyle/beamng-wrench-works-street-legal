-- Street Legal: the end of a career, one GPU-touching job at a time (docs: the control repo's GPU_TEARDOWN_2026-10-22.md). A career that stops puts the game back as it was: the billboard atlas (a material reload),
-- the wet world's terrain textures (a terrain material swap), the puddle planes (deleted), the sky. Done in the same frame they are a burst of GPU work in the moment the game is also freeing the player's car
-- and its meshes; the game lost its D3D12 device 8 s after such an end once (crash_shutdown_1018). This queue runs the jobs one after the other, at least GAP seconds apart. Pure: the caller passes the time.
local M = {}

M.GAP = 1.5           -- s between two jobs
M.FIRST = 1.0         -- s before the first one (the frames of the stop itself are left alone)
M.MAX = 12            -- jobs kept

function M.new() return { jobs = {}, readyAt = nil, ran = {} } end

-- label: a short name for the log; fn: the work. A second job with the same label replaces the first (the same restore twice is one restore).
function M.defer(q, label, fn, now)
  for i, j in ipairs(q.jobs) do if j.label == label then table.remove(q.jobs, i) break end end
  if #q.jobs >= M.MAX then return false end
  q.jobs[#q.jobs + 1] = { label = label, fn = fn }
  if q.readyAt == nil then q.readyAt = now + M.FIRST end
  return true
end

-- the next job when it is due: returns its label and fn (removed from the queue), or nil
function M.due(q, now)
  if #q.jobs == 0 then q.readyAt = nil return nil end
  if q.readyAt == nil or now < q.readyAt then return nil end
  local j = table.remove(q.jobs, 1)
  q.readyAt = now + M.GAP
  q.ran[#q.ran + 1] = j.label
  return j.label, j.fn
end

function M.pending(q) return #q.jobs end
function M.clear(q) q.jobs, q.readyAt = {}, nil end

return M
