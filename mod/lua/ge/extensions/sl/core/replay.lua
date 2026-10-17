-- Street Legal: race replays (#48). Pure (tested by tools/luatest.js).

local M = {}

-- a race's name as a replay file's base name: no path or Windows-forbidden characters, one line, not too long, with the time it was made
-- ('Street Legal - Quarry sprint 2026-10-17 21-30'). The game keeps it next to the recording and adds .rpl.
function M.clipName(raceName, stamp)
  local n = tostring(raceName or 'Race'):gsub('[<>:"/\\|%?%*%c]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if n == '' then n = 'Race' end
  if #n > 60 then n = n:sub(1, 60):gsub('%s+$', '') end
  local s = tostring(stamp or ''):gsub('[<>:"/\\|%?%*%c]', '-')
  return 'Street Legal - ' .. n .. (s ~= '' and (' ' .. s) or '')
end

-- the race's name for the clip: the race's own, else against whom, else 'Race'
function M.raceName(r)
  if type(r) ~= 'table' then return 'Race' end
  if type(r.raceName) == 'string' and r.raceName ~= '' then return r.raceName end
  if type(r.name) == 'string' and r.name ~= '' then return r.name end
  if type(r.opponent) == 'string' and r.opponent ~= '' then return 'Race against ' .. r.opponent end
  return 'Race'
end

return M
