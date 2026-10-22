-- Street Legal: the grab bag's rules (campaign idea #12). Pure, no game calls: tested by tools/luatest.js.
-- A good week (the weekly ledger's week: enough jobs done, race wins or money earned) earns one box of used parts for the car you bring to the
-- garage next: two to four parts that fit it, of random condition, on the shelf for nothing. Never for money, never a purchase.

local M = {}

M.GOOD_JOBS, M.GOOD_WINS, M.GOOD_EARNED = 3, 2, 2000     -- any one of these over the week (the Mods rows)
M.PARTS_MIN, M.PARTS_MAX = 2, 4                          -- parts in a box
M.CONDITION = { 0.35, 0.9 }                        -- used: from rough to nearly new
M.MAX_VALUE = 1500                                 -- a part dearer than this (new) stays out of the box

function M.newStore() return { week = nil, mark = nil, pending = false, given = 0 } end
function M.repair(st) return type(st) == 'table' and st or M.newStore() end

-- a snapshot of the counters at the start of a week
function M.mark(jobsDone, wins, earned) return { jobs = tonumber(jobsDone) or 0, wins = tonumber(wins) or 0, earned = tonumber(earned) or 0 } end

-- was the week between two marks a good one?
function M.goodWeek(before, after)
  if type(before) ~= 'table' or type(after) ~= 'table' then return false end
  local jobs, wins, earned = (after.jobs or 0) - (before.jobs or 0), (after.wins or 0) - (before.wins or 0), (after.earned or 0) - (before.earned or 0)
  return jobs >= M.GOOD_JOBS or wins >= M.GOOD_WINS or earned >= M.GOOD_EARNED
end

-- the parts of the box from the list of parts that fit the car ({ part, name, slotId, price, brand }): distinct slots, cheap enough, each with a
-- condition and a used value (the market's rule: 35 % of new at the worst, all of it as new)
function M.pick(list, rng, count)
  local pool = {}
  for _, e in ipairs(list or {}) do
    if type(e) == 'table' and e.part and (tonumber(e.price) or 0) <= M.MAX_VALUE then pool[#pool + 1] = e end
  end
  local n = math.min(count or rng:int(M.PARTS_MIN, math.max(M.PARTS_MIN, M.PARTS_MAX)), #pool)
  local out, slots = {}, {}
  while #pool > 0 and #out < n do
    local e = table.remove(pool, rng:int(#pool))
    if not slots[e.slotId or e.name] then
      slots[e.slotId or e.name] = true
      local condition = M.CONDITION[1] + (M.CONDITION[2] - M.CONDITION[1]) * rng:range(0, 1)
      condition = math.floor(condition * 100 + 0.5) / 100
      out[#out + 1] = { part = e.part, name = e.name, slotId = e.slotId, brand = e.brand, condition = condition,
        value = math.floor((tonumber(e.price) or 0) * (0.35 + 0.65 * condition) / 10 + 0.5) * 10 }
    end
  end
  return out
end

function M.names(parts)
  local t = {}
  for _, p in ipairs(parts or {}) do t[#t + 1] = tostring(p.name) .. ' (' .. math.floor(p.condition * 100 + 0.5) .. '%)' end
  return table.concat(t, ', ')
end

return M
