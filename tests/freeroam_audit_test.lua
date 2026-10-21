-- Street Legal: the free-roam audit (docs/FREEROAM_AUDIT.md). A free-roam session with every switch on and no career: every extension module under sl/ loads against a stubbed game,
-- every game hook of every module runs, and nothing writes a wallet, a garage or a career file: no Wrench Works shelf, garage or money call (slrr_garage, slrr/garageParts), no
-- driver appearance call, no save file, no money or career event, and the sandbox state carries no money, cars or rep. Run by tools/luatest.js after tools/luatest.lua, which
-- sets SL_MODULES (the file names under mod/lua/ge/extensions/sl). The strict career test (luatest.lua, "free roam never writes a career") covers sl/career alone; this one
-- covers the rest with it.
local names = assert(SL_MODULES, 'tools/luatest.js sets SL_MODULES')
local passed = 0
local function check(name, ok, detail)
  if not ok then error('FAILED: ' .. name .. (detail and (' (' .. tostring(detail) .. ')') or ''), 2) end
  passed = passed + 1
end

local saved = {}
for _, k in ipairs({ 'FS', 'jsonWriteFile', 'jsonReadFile', 'writeFile', 'readFile', 'extensions', 'log', 'sl_options', 'sl_career', 'sl_mode', 'slrr_garage', 'slrrDrivers', 'guihooks' }) do saved[k] = rawget(_G, k) end
local savedLoaded = {}
for _, n in ipairs(names) do savedLoaded[n] = package.loaded['sl/' .. n] package.loaded['sl/' .. n] = nil end
local savedParts = package.loaded['slrr/garageParts']

-- the recorders: file writes, calls into another mod that change its state, events fired
local writes, calls, events = {}, {}, {}
local FS_WRITES = { writeFile = true, removeFile = true, copyFile = true, directoryCreate = true, renameFile = true, remove = true }
_G.log = function() end
_G.FS = setmetatable({}, { __index = function(_, k)
  return function(_, p)
    if FS_WRITES[k] then writes[#writes + 1] = 'FS:' .. k .. ' ' .. tostring(p) end
    if k == 'findFiles' then return {} end
    return false
  end
end })
_G.jsonWriteFile = function(p) writes[#writes + 1] = 'json ' .. tostring(p) return true end
_G.jsonReadFile = function() return nil end
_G.writeFile = function(p) writes[#writes + 1] = 'writeFile ' .. tostring(p) end
_G.readFile = function() return nil end
_G.extensions = { hook = function(n) events[#events + 1] = tostring(n) end, load = function() end, unload = function() end, reload = function() end,
  isExtensionLoaded = function() return false end, setCompletedCallbacks = function() end }
_G.guihooks = { trigger = function() end }
local GARAGE_WRITES = { addShelfPart = true, putShelfItem = true, takeShelfItem = true, markJobCar = true, enterWith = true, enter = true, leave = true, setFeatures = true }
local garageReads = { shelfItems = function() return {} end, getPhase = function() return 'idle' end, garageAt = function() return nil end, driverHasHelmet = function() return false end }
_G.slrr_garage = setmetatable({}, { __index = function(_, k)
  if garageReads[k] then return garageReads[k] end
  return function(a) if not (k == 'setFeatures' and a == nil) then calls[#calls + 1] = 'slrr_garage.' .. k end return false end      -- (setFeatures(nil) clears: a read-back, not a write)
end })
_G.slrrDrivers = { setAppearance = function() calls[#calls + 1] = 'slrrDrivers.setAppearance' end, getAppearance = function() return {} end, getDriver = function() return nil end }
package.loaded['slrr/garageParts'] = { setMoneyProvider = function(p) if p ~= nil then calls[#calls + 1] = 'garageParts.setMoneyProvider' end end,
  changeMoney = function() calls[#calls + 1] = 'garageParts.changeMoney' end, getMoney = function() return 0 end }

-- every free-roam switch on, nothing else set; no career
local modeCore = require('sl/core/mode')
local on = { [modeCore.MASTER] = true }
for _, id in ipairs(modeCore.IDS) do on[modeCore.key(id)] = true end
_G.sl_options = { get = function(k) return on[k] end, set = function() end }
_G.sl_career = require('sl/career')
_G.sl_mode = require('sl/mode')
check('audit: no career is active', sl_career.isActive() == false and sl_career.getState() == nil and sl_mode.kind() == 'freeroam')

-- any other global the modules reach for (be, vec3, core_camera, map...) is a stub: indexing it gives the stub, calling it gives nil, so a hook takes its early exits
local stub = setmetatable({}, { __index = function(t) return t end, __call = function() return nil end })
setmetatable(_G, { __index = function() return stub end })
local GAME_MODULES = { 'ge/extensions/ui/router/services/navigationContext' }          -- the game's own modules an sl module requires at load (lockdown.lua)
local savedGame = {}
for _, g in ipairs(GAME_MODULES) do savedGame[g] = package.loaded[g] package.loaded[g] = stub end

local failed, mods = {}, {}
for _, n in ipairs(names) do
  local ok, m = pcall(require, 'sl/' .. n)
  if ok and type(m) == 'table' then mods[n] = m if rawget(_G, 'sl_' .. n) == nil then _G['sl_' .. n] = m end else failed[#failed + 1] = n .. ': ' .. tostring(m) end      -- (sl_options stays the switches above, not the real module reading a settings file)
end
check('audit: every sl module loads with no career (' .. #names .. ')', #failed == 0, table.concat(failed, ' | '))

-- the session: every game hook of every module, with the argument shapes the game uses (a dt, an id, nothing), twice over so late-bound cross-calls run too
local hooks = 0
for _ = 1, 2 do
  for _, n in ipairs(names) do
    local m = mods[n]
    if m then
      for k, fn in pairs(m) do
        if type(fn) == 'function' and k:sub(1, 2) == 'on' then hooks = hooks + 1 pcall(fn, 0.1, 0.1) pcall(fn, 1) pcall(fn) end
      end
    end
  end
end
setmetatable(_G, nil)
check('audit: the hooks ran (' .. hooks .. ')', hooks > 100)
if MUTATION then slrr_garage.addShelfPart('x', {}) end

check('audit: still no career after the session', sl_career.isActive() == false and sl_career.getState() == nil)
check('audit: no call changed Wrench Works (shelf, garage, driver, wallet): ' .. table.concat(calls, ','), #calls == 0)
local bad = {}
for _, w in ipairs(writes) do
  local p = w:match('%s(.*)$') or ''
  if not (p:find('^/?temp/') or p:find('^/?settings/street_legal/hud') or p:find('^/?settings/street_legal/options') or p:find('^/?settings/street_legal/photos')) then bad[#bad + 1] = w end
end
check('audit: no save, slot, places or wallet file is written (only settings/hud/photos and temp shapes may be): ' .. table.concat(bad, ','), #bad == 0)
local fired = {}
for _, e in ipairs(events) do
  if e == 'onStreetLegalStarted' or e == 'onStreetLegalBeforeSave' or e == 'onStreetLegalSpent' or e == 'onStreetLegalCarSold' or e == 'onStreetLegalRaceResult' or e == 'onStreetLegalCarDelivered'
    or e == 'onStreetLegalDistrictTaken' or e == 'onStreetLegalKingOfValo' or e == 'onStreetLegalGarageMoved' or e:find('Rival') or e:find('Heat') or e:find('Wanted') then fired[#fired + 1] = e end
end
check('audit: no career, money, sale, race-result or rival event is fired: ' .. table.concat(fired, ','), #fired == 0)

-- the sandbox state: what the free-roam features see is never a wallet or a garage
for _, id in ipairs(modeCore.IDS) do
  local s = sl_mode.state(id)
  local keys = {}
  if type(s) == 'table' then for k in pairs(s) do keys[#keys + 1] = tostring(k) end end
  check('audit: sandbox state for ' .. id .. ' carries no money, cars, rep or garage', type(s) == 'table' and s.sandbox == true and s.money == nil and s.cars == nil and s.rep == nil and s.garageLevel == nil and s.activeCar == nil and s.slot == nil,
    type(s) == 'table' and table.concat(keys, ',') or tostring(s))
end
check('audit: career-only features stay off in free roam', not sl_mode.enabled('rivals') and not sl_mode.enabled('bank') and not sl_mode.enabled('classifieds') and not sl_mode.enabled('races') and not sl_mode.enabled('jobs'))

for _, n in ipairs(names) do package.loaded['sl/' .. n] = savedLoaded[n] _G['sl_' .. n] = nil end
package.loaded['slrr/garageParts'] = savedParts
for _, g in ipairs(GAME_MODULES) do package.loaded[g] = savedGame[g] end
for k, v in pairs(saved) do _G[k] = v end
local seen, uniq = {}, {}
for _, e in ipairs(events) do if not seen[e] then seen[e] = true uniq[#uniq + 1] = e end end
print('free-roam audit passed: ' .. passed .. ' checks, ' .. #names .. ' modules, ' .. hooks .. ' hook calls; writes: ' .. table.concat(writes, ', ') .. '; events: ' .. table.concat(uniq, ', '))
