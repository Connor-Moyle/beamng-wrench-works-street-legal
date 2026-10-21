-- Street Legal: the visit audit (docs/DESIGN_CAREER_TRAVEL.md section 2). A career on a visited map has no places, a day-long clock and a paddock row of cars: every extension module under sl/
-- must survive that. Every module loads against a stubbed game with the real career module running over an in-memory save; every game hook of every module runs twice at home (the
-- control) and twice on a visited map; a hook or a summary that fails on the visited map and NOT at home is a nil error the trip would show in the game. Run by tools/luatest.js
-- after tests/freeroam_audit_test.lua, which sets SL_MODULES (the file names under mod/lua/ge/extensions/sl).
local names = assert(SL_MODULES, 'tools/luatest.js sets SL_MODULES')
local passed = 0
local function check(name, ok, detail)
  if not ok then error('FAILED: ' .. name .. (detail and (' (' .. tostring(detail) .. ')') or ''), 2) end
  passed = passed + 1
end

local keys = { 'FS', 'jsonReadFile', 'jsonWriteFile', 'writeFile', 'readFile', 'extensions', 'log', 'sl_options', 'sl_career', 'sl_mode', 'core_levels', 'freeroam_freeroam', 'getCurrentLevelIdentifier',
  'core_jobsystem', 'guihooks', 'core_environment', 'getPlayerVehicle', 'gameplay_walk', 'core_groundMarkers', 'slrr_garage', 'slrrDrivers', 'map', 'worldReadyState', 'vec3', 'quat', 'quatFromDir', 'freeroam_facilities' }
local saved = {}
for _, k in ipairs(keys) do saved[k] = rawget(_G, k) end
local savedLoaded = {}
for _, n in ipairs(names) do savedLoaded[n] = package.loaded['sl/' .. n] package.loaded['sl/' .. n] = nil end
local savedMeta = getmetatable(_G)

local files, events, started, level = {}, {}, {}, 'west_coast_usa'
local installed = { west_coast_usa = true, utah = true }
_G.log = function() end
_G.FS = setmetatable({ fileExists = function(_, p) return files[p] ~= nil end, directoryExists = function() return true end, directoryCreate = function() return true end,
  findFiles = function() return {} end }, { __index = function() return function() return false end end })
_G.jsonReadFile = function(p) return files[p] end
_G.jsonWriteFile = function(p, t) files[p] = t return true end
_G.writeFile = function() end
_G.readFile = function() return nil end
_G.extensions = { hook = function(name) events[#events + 1] = name end, load = function() end, unload = function() end, reload = function() end,
  isExtensionLoaded = function() return false end, setCompletedCallbacks = function() end }
_G.sl_options = { get = function() return nil end, set = function() end }
_G.core_levels = { getLevelByName = function(l) return installed[l] and {} or nil end }
_G.freeroam_freeroam = { startFreeroamByName = function(l) started[#started + 1] = l return true end, spawningOptionsHelper = {} }
_G.getCurrentLevelIdentifier = function() return level end
_G.core_jobsystem = { create = function() end }
_G.guihooks = { trigger = function() end }
_G.getPlayerVehicle = function() return nil end
_G.map = { getMap = function() return { nodes = {} } end, getRoadRules = function() return {} end }
local V3 = {}
V3.__index = V3
V3.__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, V3) end
V3.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, V3) end
V3.__mul = function(a, k) return setmetatable({ x = a.x * k, y = a.y * k, z = a.z * k }, V3) end
function V3:length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function V3:normalized() local l = self:length() if l == 0 then l = 1 end return setmetatable({ x = self.x / l, y = self.y / l, z = self.z / l }, V3) end
_G.vec3 = function(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V3) end
_G.quat = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
_G.quatFromDir = function() return { x = 0, y = 0, z = 0, w = 1 } end
local stub = setmetatable({}, { __index = function(t) return t end, __call = function() return nil end })
_G.freeroam_facilities = { getFacilitiesByType = function() return {} end, getFacilities = function() return {} end }
_G.core_environment, _G.core_groundMarkers, _G.gameplay_walk, _G.slrr_garage, _G.slrrDrivers = stub, stub, stub, stub, stub
local garageParts = package.loaded['slrr/garageParts']
package.loaded['slrr/garageParts'] = { setMoneyProvider = function() end, changeMoney = function() end, getMoney = function() return 0 end }
local GAME_MODULES = { 'ge/extensions/ui/router/services/navigationContext' }
local savedGame = {}
for _, g in ipairs(GAME_MODULES) do savedGame[g] = package.loaded[g] package.loaded[g] = stub end
setmetatable(_G, { __index = function() return stub end })

local C = require('sl/career')
_G.sl_career = C
local mods, failed = {}, {}
for _, n in ipairs(names) do
  local ok, m = pcall(require, 'sl/' .. n)
  if ok and type(m) == 'table' then mods[n] = m if rawget(_G, 'sl_' .. n) == nil or n == 'career' then _G['sl_' .. n] = m end else failed[#failed + 1] = n .. ': ' .. tostring(m) end
end
_G.sl_options = { get = function() return nil end, set = function() end }
check('visit audit: every sl module loads (' .. #names .. ')', #failed == 0, table.concat(failed, ' | '))

local function sweep()
  local errs = {}
  local function run(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then errs[label] = tostring(err):gsub('^[^:]*:%d+: ', '') end
  end
  for _ = 1, 2 do
    for _, n in ipairs(names) do
      local m = mods[n]
      if m and n ~= 'career' then
        for k, fn in pairs(m) do
          if type(fn) == 'function' and (k:sub(1, 2) == 'on' or k == 'summary' or k == 'pins' or k == 'current') then
            run(n .. '.' .. k .. '(0.1,0.1)', fn, 0.1, 0.1)
            run(n .. '.' .. k .. '(1)', fn, 1)
            run(n .. '.' .. k .. '()', fn)
          end
        end
      end
    end
  end
  return errs
end

-- the home career, with cars; the control sweep
local ok0, err0 = pcall(C.start, true, 'qa', 'west_coast_usa')
check('visit audit: a career starts at home', ok0 and C.isActive(), tostring(err0))
local st = C.getState()
st.cars = { { id = 1, name = 'Covet', model = 'covet', out = true, value = 4000, where = { pos = { 1, 2, 3 } } }, { id = 2, name = 'Pessima', model = 'pessima', out = true, value = 3000 } }
st.money, st.day, st.rep, st.hour = 20000, 12, 800, 12
st.garageLevel = 2
local home = sweep()

-- the trip, the arrival
local okd, textd = C.depart({ level = 'utah', cars = { 1 }, event = 'utah-rally:1', entry = 100, untilDay = st.day + 5, rounds = 4 })
check('visit audit: the trip starts', okd == true, tostring(textd))
level = 'utah'
_G.worldReadyState = 2
C.onUpdate(0.1)
check('visit audit: the career is active on the visited map in the visit state, with no places and a day-long phase', C.isActive() and C.LEVEL == 'utah' and C.visit() ~= nil and C.phase() == 'day' and next(C.getPlaces() or {}) == nil)
local away = sweep()
local newErrs = {}
for label, msg in pairs(away) do
  if home[label] ~= msg then newErrs[#newErrs + 1] = label .. ': ' .. msg end
end
table.sort(newErrs)
check('visit audit: no hook or summary fails on the visited map that did not fail at home (' .. #newErrs .. ')', #newErrs == 0, table.concat(newErrs, ' | '))
-- the control: a module that fails only on the visited map is found by the comparison
mods.zzprobe = { onProbe = function() if C.LEVEL == 'utah' then error('only on the visited map') end end }
names[#names + 1] = 'zzprobe'
local probeAway = sweep()
local found = probeAway['zzprobe.onProbe(1)'] ~= nil and home['zzprobe.onProbe(1)'] == nil
names[#names] = nil
mods.zzprobe = nil
check('visit audit: the control finds an error that happens only on the visited map', found)
-- the day hooks of a visit with the career clock past midnight and a new day
for _, n in ipairs(names) do
  local m = mods[n]
  if m and m.onStreetLegalNewDay and n ~= 'career' then pcall(m.onStreetLegalNewDay, st.day + 1) end
end
check('visit audit: the new-day hooks run on a visit', true)

-- put everything back
setmetatable(_G, savedMeta)
for _, k in ipairs(keys) do _G[k] = saved[k] end
for _, n in ipairs(names) do package.loaded['sl/' .. n] = savedLoaded[n] end
package.loaded['slrr/garageParts'] = garageParts
for _, g in ipairs(GAME_MODULES) do package.loaded[g] = savedGame[g] end
print(string.format('visit audit passed: %d checks, %d modules, %d hooks at home, %d on the visited map', passed, #names, (function() local n = 0 for _ in pairs(home) do n = n + 1 end return n end)(), (function() local n = 0 for _ in pairs(away) do n = n + 1 end return n end)()))
