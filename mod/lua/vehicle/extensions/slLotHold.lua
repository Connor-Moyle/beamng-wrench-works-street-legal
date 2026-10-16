-- Street Legal: a lot car, in the car's own Lua (vehicle extension slLotHold; rules in lua/common/sl_lothold.lua)
-- After Wrench Works' damage has let the latches go, the car pushes them shut and freezes ITSELF when they are shut (or after
-- 2 s). The game side never touches a car that is still starting up.

local M = {}

local rules = require('sl_lothold')
local hold

local function latches()
  local list = {}
  for _, c in pairs(controller.getAllControllers and controller.getAllControllers() or {}) do
    if type(c) == 'table' and c.tryAttachGroupImpulse and c.getGroupState then list[#list + 1] = c end
  end
  return list
end

function M.hold() hold = rules.new() end
function M.cancel() hold = nil end         -- (the car was bought or taken for a drive: it must not freeze after all)

function M.updateGFX(dt)
  if not hold then return end
  local list, states = latches(), {}
  for i, c in ipairs(list) do states[i] = c.getGroupState() end
  local act = rules.step(hold, dt, states)
  if act == 'push' then
    for i, c in ipairs(list) do if states[i] ~= 'attached' then c.tryAttachGroupImpulse() end end
  elseif act == 'freeze' then
    hold = nil
    input.event('parkingbrake', 1, FILTER_DIRECT)
    controller.setFreeze(1)
  end
end

return M
