-- Street Legal: the 0.8.0 economy per save (weekly costs, servicing and wear, contracts, tier perks). A career created on 0.8.0 or later carries the marker s.economy and has all four on; a save
-- without it is a career from before: the four stay off for that save until the player opts in (the global switches stay the player's own preference). Nothing is billed backwards: the
-- parts all begin from the day they are first on. Pure, tested by tools/luatest.js.

local M = {}

M.MARK = 'v080'
M.PARTS = { 'weekly', 'service', 'contracts', 'perks' }          -- sl/core/features ids

-- the marker of a new career (set by the career start on a state it just created; never part of stateLib.new, because migrate fills missing keys from it)
function M.mark(s) s.economy = M.MARK return s end

-- may the player be offered the new economy: a save from before it that has not taken it
function M.pending(s) return type(s) == 'table' and s.economy == nil end

-- the part ids that are off for this save
function M.offFor(s)
  if M.pending(s) then
    local out = {}
    for _, id in ipairs(M.PARTS) do out[#out + 1] = id end
    return out
  end
  return {}
end

return M
