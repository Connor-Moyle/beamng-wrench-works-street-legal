-- Street Legal: the swap meet's rules (#44). Pure, tested by tools/luatest.js.
-- Valo City has a fixed meet place (the Tuning shop lot). A map without one (West Coast USA) gets the place with the most room for stalls:
-- a dealership lot or meet place with the most parking spots, the lowest id breaking a tie. The meet is on the weekend (days 6 and 7 of the
-- week); where the map says so (stock maps) it is a night meet: open after the phase turns to night.

local M = {}

M.FIXED = 'meet_tuning'

-- places = { id -> { kind, pos, displays = { spots } } }; returns the id of the meet place, or nil
function M.pickPlace(places, fixed)
  if fixed and places[fixed] then return fixed end
  local best, bestN
  for id, p in pairs(places or {}) do
    if (p.kind == 'dealer' or p.kind == 'meet') and p.pos then
      local n = #(p.displays or {})
      if not best or n > bestN or (n == bestN and id < best) then best, bestN = id, n end
    end
  end
  return best
end

function M.weekend(day) return (day or 0) % 7 >= 5 end

-- is the meet open now? nightOnly: the map's meet is a night event
function M.isOpen(day, isNight, nightOnly)
  return M.weekend(day) and (not nightOnly or isNight == true)
end

return M
