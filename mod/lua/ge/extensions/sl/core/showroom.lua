-- Street Legal: the lineup of custom cars kept for testing (they are not in the vehicle selector).
-- A fixed lineup chosen from the stock cars - the same every time (a fixed seed): from every
-- performance class a few street builds, Stage 1 to 3, and from the three fastest classes a few
-- track cars. Pure: the game hands in its stock configs (tested by tools/luatest.js); the
-- extension sl_debugCars builds them on request.

local M = {}

local rngLib = require('sl/core/rng')
local builds = require('sl/core/builds')

M.SEED = 20261014
M.STREET_PER_CLASS = 4
M.TRACK_PER_CLASS = 3          -- for classes 4, 5 and 6
local STREET_STAGES = { 1, 2, 3, 3 }
local VALUE = { [1] = 1.15, [2] = 1.35, [3] = 1.6, race = 2.0 }

local function slug(text)
  return (tostring(text):lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', ''))
end

-- configs: { { model, config (.pc path), name, brand, pw, value } }
-- Returns { { model, config, stage, seed, nick, label, file, value, class } }
function M.lineup(configs, seed)
  local list = {}
  for _, c in ipairs(configs or {}) do
    if type(c.pw) == 'number' and c.model and c.config then list[#list + 1] = c end
  end
  table.sort(list, function(a, b)
    if a.pw ~= b.pw then return a.pw < b.pw end
    return a.config < b.config
  end)
  local rng = rngLib.new(seed or M.SEED)
  local out, files = {}, {}
  local n = #list
  for class = 1, 6 do
    local lo, hi = math.floor((class - 1) / 6 * n) + 1, math.floor(class / 6 * n)
    local pool = {}
    for i = lo, hi do pool[#pool + 1] = list[i] end
    local function take(stage)
      if #pool == 0 then return end
      local c = table.remove(pool, rng:int(#pool))
      local s = rngLib.hash(c.config .. ':' .. tostring(stage))
      local nick = builds.nickname(s)
      local tag = stage == 'race' and 'track' or ('stage' .. stage)
      local file = 'street_legal_' .. slug(nick) .. '_' .. tag
      local key = c.model .. '/' .. file
      local k = 2
      while files[key] do
        file = 'street_legal_' .. slug(nick) .. '_' .. tag .. '_' .. k
        key = c.model .. '/' .. file
        k = k + 1
      end
      files[key] = true
      out[#out + 1] = {
        model = c.model, config = c.config, stage = stage, seed = s, nick = nick, class = class, file = file,
        label = string.format('%s "%s" (%s)', c.name, nick, stage == 'race' and 'Track' or ('Stage ' .. stage)),
        brand = c.brand, value = math.floor((c.value or 0) * VALUE[stage] / 50 + 0.5) * 50,
      }
    end
    for i = 1, M.STREET_PER_CLASS do take(STREET_STAGES[i]) end
    if class >= 4 then
      for _ = 1, M.TRACK_PER_CLASS do take('race') end
    end
  end
  return out
end

return M
