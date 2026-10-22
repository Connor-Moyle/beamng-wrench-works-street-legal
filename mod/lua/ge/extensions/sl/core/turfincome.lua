-- Street Legal: turf income (career expansion #12). Every week the districts the player holds pay a cut, a raid by an angry crew can take one district's cut for the week (and some of its
-- control, never the district by itself), and the district with the player's third garage is a base (a bigger cut, half the raid cost). Pure, no game calls: tested by tools/luatest.js
-- and tuned with tools/economy_sim.py --turf. territory = the career's s.crews.territory ({ [districtId] = { owner, control } }).

local M = {}

M.CUT_MAX = 100            -- $ a week from a district at full control
M.BASE_BONUS = 0.5         -- the base district pays this much more
M.RAID_BASE = 0.12         -- a week's chance a held district is raided
M.RAID_ANGRY = 0.08        -- more for each crew that is angry with the player
M.RAID_MAX = 0.5
M.RAID_CONTROL = 15        -- control a raid takes (half at the base)
M.MIN_CONTROL = 1          -- a raid alone never takes the district

-- the cut of one district
function M.cut(entry, isBase)
  if type(entry) ~= 'table' or entry.owner ~= 'player' then return 0 end
  local control = math.max(0, math.min(100, tonumber(entry.control) or 0))
  local cut = M.CUT_MAX * control / 100
  if isBase then cut = cut * (1 + M.BASE_BONUS) end
  return math.floor(cut / 10 + 0.5) * 10
end

-- the chance of a raid on a held district this week, from how many crews are angry (c.angry = { [crewId] = day }, newer than `since` days)
function M.raidChance(angryCount)
  return math.min(M.RAID_MAX, M.RAID_BASE + M.RAID_ANGRY * math.max(0, angryCount or 0))
end

function M.angryCount(angry, day, within)
  local n = 0
  for _, since in pairs(angry or {}) do if (day or 0) - (since or -1e9) <= (within or 14) then n = n + 1 end end
  return n
end

-- the week for the territory. opts = { base = districtId of the base or nil, callouts = { [districtId] = true } (unanswered), angry = count of angry crews, king = bool, names = { [id] = name }, rng }
-- Returns { lines = { { id, label_key, name, amount } }, total (money in), raids = { { district, lost, control } } }; changes the territory (control of raided districts).
function M.week(territory, opts)
  local out = { lines = {}, total = 0, raids = {} }
  local ids = {}
  for id, e in pairs(territory or {}) do if type(e) == 'table' and e.owner == 'player' then ids[#ids + 1] = id end end
  table.sort(ids)
  local chance = opts.king and 0 or M.raidChance(opts.angry)
  for _, id in ipairs(ids) do
    local e = territory[id]
    local isBase = opts.base == id
    local cut = M.cut(e, isBase)
    local raided = chance > 0 and opts.rng and opts.rng:chance(chance)
    local name = opts.names and opts.names[id] or id
    if raided then
      local took = math.floor(M.RAID_CONTROL * (isBase and 0.5 or 1) + 0.5)
      e.control = math.max(M.MIN_CONTROL, (e.control or 0) - took)
      out.raids[#out.raids + 1] = { district = id, name = name, lost = cut, control = took }
      out.lines[#out.lines + 1] = { id = 'raid:' .. id, kind = 'raid', name = name, amount = 0, lost = cut }
    elseif opts.callouts and opts.callouts[id] then
      out.lines[#out.lines + 1] = { id = 'leaned:' .. id, kind = 'leaned', name = name, amount = 0, lost = cut }
    elseif cut > 0 then
      out.lines[#out.lines + 1] = { id = 'cut:' .. id, kind = 'cut', name = name, amount = cut }
      out.total = out.total + cut
    end
  end
  return out
end

return M
