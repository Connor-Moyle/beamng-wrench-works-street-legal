-- Street Legal Racing: its entry in the game's menu (extension name: sl_menuTile)
-- A tile in Gameplay, next to the campaigns and scenarios, with Continue and New career.
-- (The buttons on the main menu's first page are built into the game's own interface and
-- cannot be added to by a mod; the Gameplay screen is where the game lists modes like this.)

local M = {}

local KEY = 'streetLegalRacing'
local PREVIEW = '/levels/slrr_valo_city/slrr_valo_city_preview.jpg'

local function levelInstalled()
  return core_levels and core_levels.getLevelByName and core_levels.getLevelByName(sl_career and sl_career.LEVEL or 'slrr_valo_city') ~= nil
end

function M.onGameplaySelectorGetTiles(items, backend)
  if backend.backendName ~= 'gameplaySelector' then return end
  items[#items + 1] = {
    key = KEY, name = 'Wrench Works: Street Legal',
    preview = FS:fileExists(PREVIEW) and PREVIEW or nil,
    favouriteIdx = 0, showFavouriteIconPercent = 0,
    showDetails = { key = KEY, streetLegal = true },
    system = 'Wrench Works: Street Legal', type = 'career', level = 'Wrench Works: Valo City',
    sourceIcons = {}, order = -1e12,
    validBackends = { gameplaySelector = true },
  }
end

function M.onGameplaySelectorGetDetails(itemDetails, details, buttonInstance, backend)
  if type(itemDetails) ~= 'table' or not itemDetails.streetLegal then return end
  local installed = levelInstalled()
  local summary = sl_career and sl_career.saveSummary()
  local specs = {
    { icon = 'flag', label = 'Map', value = installed and 'Valo City' or 'Valo City - not installed' },
    { icon = 'personSolid', label = 'Career', value = summary or 'No career yet' },
  }
  local buttons = {}
  local function start(fresh, n)
    return function()
      backend.trackRecent(itemDetails.key)
      extensions.ui_router.navigate('play')
      sl_career.start(fresh, n)
    end
  end
  if installed and sl_career then
    if summary then
      buttons[#buttons + 1] = buttonInstance.addButton(start(false), { label = 'Continue', icon = 'clapperboard', primary = true, isDoubleClickAction = true, waitForLoadingScreen = true })
    end
    -- the other careers (save slots); renaming and deleting are on the main menu's career chooser
    for _, c in ipairs(sl_career.listSlots and sl_career.listSlots() or {}) do
      if not c.last then
        buttons[#buttons + 1] = buttonInstance.addButton(start(false, c.slot), { label = 'Load ' .. c.name .. (c.summary and (' (' .. c.summary .. ')') or ''), icon = 'clapperboard', waitForLoadingScreen = true })
      end
    end
    buttons[#buttons + 1] = buttonInstance.addButton(start(true), { label = 'New career', icon = 'flag',
      primary = not summary, isDoubleClickAction = not summary, waitForLoadingScreen = true })
  end
  details[#details + 1] = {
    headerTitle = 'Wrench Works: Street Legal',
    description = 'Valo City at night. No car, a few thousand in your pocket and a name nobody knows. Buy a wreck at the junkyard, '
      .. 'build it up in your garage, race the city\'s street racers for money and pink slips, and climb from the first garage to the ROC.'
      .. (installed and '' or '\n\nThis needs the Valo City map mod (level slrr_valo_city).'),
    preview = FS:fileExists(PREVIEW) and PREVIEW or nil,
    isFavourite = backend.isFavourite(itemDetails.key),
    specifications = { specs },
    tags = {},
    buttonInfo = buttons,
  }
end

----------------------------------------------------------------------------------------------
-- A button on the main menu itself (drawn by the phone's UI module, which is loaded on every
-- screen): shown while no level is loaded.

local shown, timer = nil, 0

local function send(force)
  local inMenu = not (getCurrentLevelIdentifier and getCurrentLevelIdentifier())
  if inMenu == shown and not force then return end
  shown = inMenu
  guihooks.trigger('slMenu', { show = inMenu, installed = levelInstalled(), summary = sl_career and sl_career.saveSummary() or nil,
    slots = sl_career and sl_career.listSlots and sl_career.listSlots() or {}, maxSlots = sl_career and sl_career.SLOTS })
end

function M.onUpdate(dtReal)
  timer = timer + dtReal
  if timer > 0.5 then timer = 0 send(false) end
end

function M.request() send(true) end
M.onUiReady = function() send(true) end

function M.startFromMenu(fresh, n)
  if not sl_career or not levelInstalled() then return end
  guihooks.trigger('slMenu', { show = false })
  shown = false
  sl_career.start(fresh == true, n)
end

-- the chooser's slot buttons
function M.renameSlot(n, name) if sl_career then sl_career.renameSlot(n, name) end send(true) end
function M.deleteSlot(n) if sl_career then sl_career.deleteSlot(n) end send(true) end

-- the Gameplay screen builds its list once; have it look again now that this tile is here
function M.onExtensionLoaded()
  if ui_gameplaySelector_general and ui_gameplaySelector_general.onModActivated then ui_gameplaySelector_general.onModActivated() end
end

return M
