-- Wrench Works: Street Legal: no freeroam shortcuts in the career (extension name: sl_lockdown)
-- While a career runs: the vehicle selector, the parts and tuning menus, the environment and level pages, the
-- World Editor, teleports to the camera, the rewind and the free resets are off (parts come from Wrench Works,
-- repairs cost money). The reset key instead offers a paid pull back onto the nearest road, as the car is.
-- The map's races (missions) keep their own reset.

local M = {}

local strings = require('sl/core/strings')

local progression = require('sl/core/progression')
local rules = require('sl/core/flares')       -- (lockStep: apply only on a change)

local FILTER = 0
local GROUP = 'streetLegalBlocked'
local CONFIRM_SECONDS = 5

-- the game's own templates, plus the sandbox radial menus and the reset's rewind and reload
local function blockedActions()
  local af = core_input_actionFilter
  local list = af.createActionTemplate({ 'vehicleTeleporting', 'vehicleMenues', 'physicsControls', 'aiControls', 'vehicleSwitching', 'funStuff', 'editor', 'trackBuilder' })
  for _, a in ipairs({ 'recover_vehicle', 'recover_vehicle_alt', 'recover_to_last_road', 'reload_vehicle', 'reload_all_vehicles',
    'toggleRadialMenuSandbox', 'toggleRadialMenuMulti', 'objectEditorToggle', 'editorSafeModeToggle' }) do
    list[#list + 1] = a
  end
  return list
end

local navContext = require('ge/extensions/ui/router/services/navigationContext')
local originalReset, originalContext
local locked = false
local offer                 -- { fee, until } while the reset is waiting for a second press

local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end
local function inMission() return gameplay_missions_missionManager and gameplay_missions_missionManager.getForegroundMissionId() ~= nil end

-- the reset key: the first press quotes, the second (within a few seconds) pays and pulls the car to the road
local function reset(playerID)
  if inMission() then return originalReset(playerID) end
  local veh = getPlayerVehicle(0)
  if not veh or (gameplay_walk and gameplay_walk.isWalking()) then toast(strings.t('lockdown.on_foot_nothing_to_pull')) return end
  if veh:getVelocity():length() > 3 then toast(strings.t('lockdown.stop_first_then_call_for')) return end
  if sl_options and sl_options.get('slHardcore') then toast(strings.t('lockdown.hardcore_nobody_pulls_you_out')) return end
  local now = os.clock()
  if offer and now < offer.untilT then
    local fee = offer.fee
    offer = nil
    if not sl_career.addMoney(-fee, 'Pulled back to the road') then toast(string.format('That is $%d. You do not have it.', fee)) return end
    spawn.teleportToLastRoad(veh, { resetVehicle = false })
    toast(string.format('Pulled back onto the road for $%d. The damage is still there.', fee))
    return
  end
  local _, _, dist = map.findClosestRoad(veh:getPosition())
  offer = { fee = progression.roadFee(dist or 0), untilT = now + CONFIRM_SECONDS }
  toast(string.format('A pull back to the nearest road, as the car is (no repairs): $%d. Press reset again to pay. Will it not drive? Phone > My cars > Tow it home.', offer.fee))
end

-- nothing runs per frame here: the input filters, the reset key and the pause menu's mode are set once on a
-- change and put back once (a repeated hook is ignored: sl/core/flares.lockStep)
local function lock(on)
  if not rules.lockStep(locked, on) then return end
  locked = on and true or false
  local af = core_input_actionFilter
  if af then
    if on then af.setGroup(GROUP, blockedActions()) end
    af.addAction(FILTER, GROUP, on)
  end
  if on and not originalReset then
    originalReset = resetGameplay
    resetGameplay = function(playerID) return reset(playerID) end
    -- the pause menu: a mode of its own, so its freeroam pages (vehicles, parts, environment, levels) stay shut
    originalContext = navContext.getContext
    navContext.getContext = function()
      local c = originalContext()
      if c.mode == 'freeroam' or c.mode == 'freeroamTutorial' then c.mode = 'streetLegal' end
      return c
    end
  elseif not on and originalReset then
    resetGameplay, originalReset = originalReset, nil
    navContext.getContext, originalContext = originalContext, nil
  end
  offer = nil
end

function M.onStreetLegalStarted() lock(true) end
function M.onStreetLegalStopped() lock(false) end
function M.onClientEndMission() lock(false) end
function M.onExtensionUnloaded() lock(false) end

M.isLocked = function() return originalReset ~= nil end

return M
