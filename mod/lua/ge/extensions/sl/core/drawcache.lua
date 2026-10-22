-- Street Legal: a small cache for what a marker draws every frame (the positions as vec3, the label as a String): built once for a key, handed back until the key changes or the cache is cleared.
-- debugDrawer is immediate, so a marker is drawn again every frame; building its objects again every frame is garbage for nothing. Pure: tested by tools/luatest.js.

local M = {}

M.CAP = 64                          -- keys kept; more than this and the cache starts over (a marker is rebuilt once, not forever)

local store, n = {}, 0

function M.get(key, build)
  local v = store[key]
  if v == nil then
    if n >= M.CAP then store, n = {}, 0 end
    v = build()
    store[key] = v
    n = n + 1
  end
  return v
end

function M.clear() store, n = {}, 0 end
function M.size() return n end

return M
