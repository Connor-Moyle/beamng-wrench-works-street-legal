-- Street Legal: the order a lot is made in (T43). Pure, tested by tools/luatest.js. First every car is spawned and rebuilt, one at a time;
-- then the dents go on, one car at a time, each waited for; nothing spawns while a car is being dented. The lot shows when all is done.

local M = {}

-- the plan for a row: the cars to spawn in order (all offers), then the cars to dent in order (those with dents), as two lists of
-- indexes. pending: index -> its dents.
function M.plan(count, pending)
  local spawn, dent = {}, {}
  for i = 1, count do spawn[i] = i end
  for i = 1, count do if pending and pending[i] and #pending[i] > 0 then dent[#dent + 1] = i end end
  return { spawn = spawn, dent = dent }
end

-- the car to show: the one asked for if it was made, else the first made, else nil. made(i) -> bool
function M.shown(count, index, made)
  if index and made(index) then return index end
  for i = 1, count do if made(i) then return i end end
  return nil
end

return M
