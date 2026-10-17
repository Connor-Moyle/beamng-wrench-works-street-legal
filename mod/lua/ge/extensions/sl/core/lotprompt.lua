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

-- stopping at a lot with no map markers (so no prompt to choose from; with them the prompt shows modes() and this is never asked): one thing opens.
-- On foot, or a driver with no fleet car to sell: the cars. A driver in a fleet car at a junkyard or scrapyard: selling it (the one thing the walk-up
-- cannot do), as before.
function M.driveUp(kind, onFoot, inFleetCar)
  if onFoot then return 'browse' end
  local m = M.modes(kind, onFoot, inFleetCar)
  return m[#m]
end

return M
