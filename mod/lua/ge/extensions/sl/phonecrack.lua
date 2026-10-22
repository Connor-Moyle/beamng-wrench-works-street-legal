-- Street Legal: the cracked phone screen (extension name: sl_phonecrack). A hard crash cracks the glass of the phone (the phone and the HUD phone draw the cracks: slPhone.js), a repair of the car
-- mends it; the state is saved with the career (s.phoneCrack = { stage 0..3, x, y, seed }). The crash signal is the jump of the player's car's damage reading (map.objects[id].damage) between two looks,
-- and Drivers' Injury hook onSlrrDriverInjured counts as a crack of at least stage 1 when the part is on. The rules are sl/core/phonecrack.lua. Settings: Mods > Street Legal > Screens and texts >
-- Cracked phone (on/off, crash threshold, chance, highest stage, overlay strength). Not seen in the game: the scale of the damage reading, hence the threshold as a setting and the console reader
-- sl_phonecrack.reading() (what the car reads now) and sl_phonecrack.crack(stage) (a test crack).

local M = {}

local core = require('sl/core/phonecrack')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function opt(key, default)
  local v = sl_options and sl_options.get and sl_options.get(key)
  if v == nil then return default end
  return v
end
local function opts()
  return { threshold = opt('slPhoneCrackThreshold', core.THRESHOLD), chance = opt('slPhoneCrackChance', core.CHANCE), max = opt('slPhoneCrackMax', core.MAX_STAGE) }
end

local last, timer = nil, 0

local function reading()
  local v = getPlayerVehicle and getPlayerVehicle(0)
  if not v then return nil, nil end
  local id = v:getID()
  local o = map and map.objects and map.objects[id]
  return o and tonumber(o.damage) or nil, id
end
function M.reading() local d = reading() return d end

local function changed() extensions.hook('onStreetLegalChanged') end

-- a crack (test or a crash): the state and the UI
local function setCrack(st)
  local s = career()
  if not s then return end
  s.phoneCrack = st
  changed()
  guihooks.trigger('slPhoneCrack', M.view())
end

function M.view()
  local s = career()
  return s and core.view(s.phoneCrack, opt('slPhoneCrackStrength', 0.85)) or nil
end

-- a test crack from the console: stage 0 mends it
function M.crack(stage)
  stage = math.max(0, math.min(3, math.floor(tonumber(stage) or 1)))
  if stage == 0 then M.clear('test') return true end
  setCrack({ stage = stage, x = 0.3 + math.random() * 0.4, y = 0.25 + math.random() * 0.4, seed = math.random(1, 1e6) })
  return true
end

function M.clear(why)
  local s = career()
  if not (s and s.phoneCrack) then return false end
  setCrack(nil)
  guihooks.trigger('slPhoneToast', { text = require('sl/core/strings').t('phonecrack.mended') })
  return true
end

local function tick()
  local s = career()
  if not s then last = nil return end
  local now = reading()
  if not now then last = nil return end
  local o = opts()
  if last then
    if s.phoneCrack and core.repaired(last, now, o.threshold) then M.clear('repair')
    else
      local state, did = core.crash(s.phoneCrack, now - last, o, math.random(), math.random(), math.random(), math.random(1, 1e6))
      if did then
        setCrack(state)
        guihooks.trigger('slPhoneToast', { text = require('sl/core/strings').t('phonecrack.cracked') })
      end
    end
  end
  last = now
end

local failures = 0
function M.onUpdate(dtReal)
  if failures >= 3 then return end      -- (a tick that keeps failing is stopped, not repeated forever)
  timer = timer + (dtReal or 0)
  if timer < 0.25 then return end
  timer = 0
  local ok, err = pcall(tick)
  if not ok then
    failures = failures + 1
    log('E', 'sl_phonecrack', 'tick failed (' .. failures .. '/3): ' .. tostring(err))
  end
end

-- another car: its damage reading is not a crash of this one (the first reading after a switch or a respawn only sets the baseline)
function M.onVehicleSwitched() last = nil end
function M.onVehicleResetted() last = nil end
function M.onVehicleActiveChanged() last = nil end

-- Injury hooked a crash that hurt the driver: at least a stage 1 crack
function M.onSlrrDriverInjured(vehId, injuries)
  local s = career()
  if not s or type(injuries) ~= 'table' or not injuries.player then return end
  local o = opts()
  local stage = math.max(1, math.min(core.MAX_STAGE, o.max, (injuries.level == 'unconscious' and 3) or (injuries.level == 'broken' and 2) or 1))
  if (s.phoneCrack and s.phoneCrack.stage or 0) >= stage then return end
  setCrack({ stage = stage, x = 0.3 + math.random() * 0.4, y = 0.25 + math.random() * 0.4, seed = math.random(1, 1e6) })
end

-- a car leaving a Wrench Works garage with no dents left was repaired there
function M.onWrenchWorksDriveOut(vid, info)
  local s = career()
  if s and s.phoneCrack and type(info) == 'table' and (tonumber(info.dents) or 1) == 0 then M.clear('garage') end
end

function M.onClientEndMission() last = nil end

require('sl/core/features').gate('phonecrack', M, nil, nil, { 'view' })

return M
