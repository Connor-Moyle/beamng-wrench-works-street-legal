-- Street Legal: which buttons a lot's marker prompt shows. Pure (tested by tools/luatest.lua).

local M = {}

-- kind: the lot's kind ('used' junkyard, 'dealer', 'scrap' scrapyard). Every lot that shows cars lets anyone look at them, on foot or driving
-- (a driver at Jefferson Motors and at the junkyard had nothing to press: T33). A driver in one of their own fleet cars is offered selling it too,
-- second; a dealer does not buy cars. Returns the modes in the order of the buttons: 'browse', 'sell'.
function M.modes(kind, onFoot, inFleetCar)
  local out = { 'browse' }
  if not onFoot and inFleetCar and kind ~= 'dealer' then out[2] = 'sell' end
  return out
end

return M
