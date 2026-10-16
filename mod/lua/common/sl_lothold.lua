-- Street Legal: a car just built for a lot waits for its doors, bonnet and boot to shut before it is frozen (T27). Pure: the
-- vehicle extension slLotHold feeds it the latch groups' states each frame and does what it answers (tested by tools/luatest.js).
--   new() -> hold;  step(hold, dt, states) -> 'push' (shut the ones that are open), 'freeze' (all shut after MIN, or MAX passed), or nil.
-- states: a list of controller group states ('attached' when shut).

local M = {}

M.MIN = 0.5       -- s: the damage has let the latches go (slrrGarageVeh) by then; shut before this is not believed
M.MAX = 2.0       -- s: freeze anyway after this
M.PUSH = 0.5      -- s between pushes

function M.new() return { t = 0, nextPush = 0.3 } end

function M.step(h, dt, states)
  h.t = h.t + (dt or 0)
  local pending = false
  for _, st in ipairs(states or {}) do if st ~= 'attached' then pending = true end end
  if h.t >= M.MAX or (not pending and h.t >= M.MIN) then return 'freeze' end
  if pending and h.t >= h.nextPush then
    h.nextPush = h.t + M.PUSH
    return 'push'
  end
end

return M
