-- Street Legal: swap one function of a game module for ours while a career runs, and put the game's own back after (B67). Pure, tested by
-- tools/luatest.js. The original is kept in `saved` (a table the caller owns) and only once: installing twice, or after the game reloaded the
-- module (a fresh original), is safe; restoring puts back exactly the original if our function is still the one in place.

local M = {}

-- target[key] becomes fn. Returns true when it was changed now.
function M.install(target, key, fn, saved)
  if type(target) ~= 'table' or type(fn) ~= 'function' then return false end
  if target[key] == fn then return false end
  saved[key] = { original = target[key], ours = fn }
  target[key] = fn
  return true
end

-- the original back, if ours is still in place. Returns true when it was restored now.
function M.restore(target, key, saved)
  local s = saved[key]
  if type(target) ~= 'table' or not s then return false end
  saved[key] = nil
  if target[key] == s.ours then target[key] = s.original return true end
  return false
end

return M
