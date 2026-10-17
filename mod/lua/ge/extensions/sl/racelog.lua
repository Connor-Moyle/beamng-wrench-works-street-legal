-- Street Legal: the race log (A6). The game's log stops at 15000 lines and cut the races out of a long session, so the races, sprints,
-- drag runs and meets write their own file: settings/street_legal/race_log.txt, one line per step (setup, positions and facing of both
-- cars, the opponent's model, the start, the finish, why an event was cancelled). The file of the session before is kept as race_log.prev.txt.
-- Not an extension: required by sl_races, sl_streets and sl_drag.

local M = {}

local PATH, PREV = '/settings/street_legal/race_log.txt', '/settings/street_legal/race_log.prev.txt'
local lines, started = {}, false
local MAX_LINES = 4000

local function begin()
  if started then return end
  started = true
  local ok, old = pcall(function() return FS:fileExists(PATH) and readFile(PATH) or nil end)
  if ok and old and writeFile then pcall(writeFile, PREV, old) end
  lines = { string.format('-- race log, session %s', os.date('%Y-%m-%d %H:%M:%S')) }
end

local function fmt(v)
  if type(v) == 'table' and v.x and v.y then return string.format('(%.1f,%.1f,%.1f)', v.x, v.y, v.z or 0) end
  if type(v) == 'number' then return string.format('%.2f', v) end
  return tostring(v)
end

-- the car's place and the way it faces, for a log line
function M.car(v)
  if not v then return 'none' end
  local p, f = v:getPosition(), v:getDirectionVector()
  return string.format('%s facing (%.2f,%.2f)', fmt(p), f.x, f.y)
end

-- M.add('sprint', 'setup', { route = 'sr3', start = vec3, ... }): one line, in the order of the keys sorted
function M.add(kind, what, fields)
  begin()
  local keys = {}
  for k in pairs(fields or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = k .. '=' .. fmt(fields[k]) end
  lines[#lines + 1] = string.format('[%s] %s %s %s', os.date('%H:%M:%S'), kind, what, table.concat(parts, ' '))
  if #lines > MAX_LINES then table.remove(lines, 2) end
  if writeFile then pcall(writeFile, PATH, table.concat(lines, '\n') .. '\n') end
  log('I', 'race_log', lines[#lines])
end

return M
