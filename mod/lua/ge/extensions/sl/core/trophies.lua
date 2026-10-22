-- Street Legal: the trophy list (s.trophies, newest last): a win at a sprint, an invitational or the end of a series. Pure, tested by tools/luatest.js. The phone and the laptop list it (9e).
--   entry: { name, kind = 'sprint' | 'invite' | 'series', day, place }

local M = {}

M.MAX = 40
M.KINDS = { sprint = true, invite = true, series = true }

-- a damaged list gives only the entries that are understood
function M.repair(list)
  local out = {}
  if type(list) ~= 'table' then return out end
  for _, t in ipairs(list) do
    if type(t) == 'table' and type(t.name) == 'string' and M.KINDS[t.kind] then out[#out + 1] = { name = t.name, kind = t.kind, day = tonumber(t.day) or 0, place = tonumber(t.place) or 1 } end
  end
  while #out > M.MAX do table.remove(out, 1) end
  return out
end

-- put a win on the list (returns the list)
function M.add(list, name, kind, day, place)
  list = M.repair(list)
  if type(name) == 'string' and M.KINDS[kind] then
    list[#list + 1] = { name = name, kind = kind, day = tonumber(day) or 0, place = tonumber(place) or 1 }
    while #list > M.MAX do table.remove(list, 1) end
  end
  return list
end

return M
