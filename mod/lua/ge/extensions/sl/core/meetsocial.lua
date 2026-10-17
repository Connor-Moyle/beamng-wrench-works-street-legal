-- Street Legal: the meet as a social hub (#43). Pure, tested by tools/luatest.js. What owners say about their car,
-- who stands with whom, which car plays the music, and when the police raid a meet.

local strings = require('sl/core/strings')

local M = {}

M.RAID_LEVEL = 4                  -- heat level from which a meet can be raided
M.RAID_EVERY = 45                 -- s between two rolls of the raid
M.RAID_CHANCE = { [4] = 0.2, [5] = 0.45 }

-- what an owner says about the car, by the night's theme and the owner's offer kind
function M.story(themeId, owner)
  local key = 'meetsocial.story_' .. tostring(themeId)
  local line = strings.t(key)
  if line == key then line = strings.t('meetsocial.story_default') end
  return string.format(line, owner.car or '?')
end

-- the offsets (m, relative to the owner's car, beside it) of the people standing with an owner: a pair for every second car, a trio for every third
function M.group(index)
  local n = index % 3 == 0 and 2 or index % 2 == 0 and 1 or 0
  local out = {}
  for k = 1, n do out[k] = { side = 2.2 + 1.1 * k, back = 0.6 * k } end
  return n, out
end

-- the car that plays the music: the owner with the smallest key (the same one all night)
function M.speaker(owners)
  local best
  for key, o in pairs(owners or {}) do if o.pos and (not best or key < best) then best = key end end
  return best
end

-- is the meet raided at this roll: level = the heat level, r = a number in [0, 1)
function M.raided(level, r)
  local c = M.RAID_CHANCE[math.min(5, level or 0)]
  return c ~= nil and r < c
end

return M
