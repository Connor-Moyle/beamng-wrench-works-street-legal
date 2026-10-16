-- Street Legal: the laptops. Which of a map's computer facilities become prompts (rules only, no game calls):
-- none unless a career runs, one per facility whose doors give a position (a map without computers gives none).
local M = {}

function M.points(careerOn, facilities, posOf)
  local out = {}
  if not careerOn then return out end
  for _, f in ipairs(facilities or {}) do
    local p = f.id and posOf(f)
    if p then out[#out + 1] = { id = f.id, name = f.name or 'Computer', pos = p } end
  end
  return out
end

return M
