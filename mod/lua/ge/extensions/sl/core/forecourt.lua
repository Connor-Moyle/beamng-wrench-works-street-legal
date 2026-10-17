-- Street Legal: which parking spot of the garage forecourt is free for a car that is about to be built or put there (no game calls).
-- Spots and other vehicles are { x, y }; a spot is free when nothing stands within `clear` metres of it (any vehicle, the player's car too).

local M = {}

M.CLEAR = 4          -- metres round a spot that must be empty
M.SPOTS = 12         -- the forecourt has three spots across and four rows back (sl_fleet.forecourt slots 0..11)

-- the index of the first free spot in the list, or nil when every one is taken
function M.pick(spots, others, clear)
  clear = clear or M.CLEAR
  for i, s in ipairs(spots) do
    local free = true
    for _, o in ipairs(others) do
      if math.sqrt((s.x - o.x) ^ 2 + (s.y - o.y) ^ 2) < clear then free = false break end
    end
    if free then return i end
  end
  return nil
end

return M
