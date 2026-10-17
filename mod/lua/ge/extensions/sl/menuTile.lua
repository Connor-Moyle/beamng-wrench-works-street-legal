-- Street Legal Racing: its entry in the game's menu (extension name: sl_menuTile)
-- A tile in Gameplay, next to the campaigns and scenarios, with Continue and New career.
-- (The buttons on the main menu's first page are built into the game's own interface and
-- cannot be added to by a mod; the Gameplay screen is where the game lists modes like this.)

local M = {}

local strings = require('sl/core/strings')

local KEY = 'streetLegalRacing'
local PREVIEW = '/levels/slrr_valo_city/slrr_valo_city_preview.jpg'

-- the maps a career can be played on, and whether any is here (W1)
local function maps() return sl_career and sl_career.listMaps and sl_career.listMaps() or {} end
local function levelInstalled()
  for _, m in ipairs(maps()) do if m.installed then return true end end
  return false
end

function M.onGameplaySelectorGetTiles(items, backend)
  if backend.backendName ~= 'gameplaySelector' then return end
  items[#items + 1] = {
    key = KEY, name = strings.t('menuTile.wrench_works_street_legal'),
    preview = FS:fileExists(PREVIEW) and PREVIEW or nil,
    favouriteIdx = 0, showFavouriteIconPercent = 0,
    showDetails = { key = KEY, streetLegal = true },
    system = strings.t('menuTile.wrench_works_street_legal'), type = 'career', level = strings.t('menuTile.valo_city_or_west_coast'),
    sourceIcons = {}, order = -1e12,
    validBackends = { gameplaySelector = true },
  }
end

function M.onGameplaySelectorGetDetails(itemDetails, details, buttonInstance, backend)
  if type(itemDetails) ~= 'table' or not itemDetails.streetLegal then return end
  local installed = levelInstalled()
  local summary = sl_career and sl_career.saveSummary()
  local names = {}
  for _, m in ipairs(maps()) do names[#names + 1] = m.name .. (m.installed and '' or ' (not installed)') end
  local specs = {
    { icon = 'flag', label = 'Maps', value = table.concat(names, ', ') },
    { icon = 'personSolid', label = 'Career', value = summary or strings.t('menuTile.no_career_yet') },
  }
  if sl_career and sl_career.inMultiplayer and sl_career.inMultiplayer() then
    specs[#specs + 1] = { icon = 'info', label = 'Multiplayer', value = strings.t('menuTile.the_career_is_single_player') }
  end
  local buttons = {}
  local function start(fresh, n, level)
    return function()
      backend.trackRecent(itemDetails.key)
      extensions.ui_router.navigate('play')
      sl_career.start(fresh, n, level)
    end
  end
  if installed and sl_career and not (sl_career.inMultiplayer and sl_career.inMultiplayer()) then
    if summary then
      buttons[#buttons + 1] = buttonInstance.addButton(start(false), { label = 'Continue', icon = 'clapperboard', primary = true, isDoubleClickAction = true, waitForLoadingScreen = true })
    end
    -- the other careers (save slots); renaming and deleting are on the main menu's career chooser
    for _, c in ipairs(sl_career.listSlots and sl_career.listSlots() or {}) do
      if not c.last then
        buttons[#buttons + 1] = buttonInstance.addButton(start(false, c.slot), { label = strings.t('menuTile.load_1_2', (c.name), (c.summary and (' (' .. c.summary .. ')') or '')), icon = 'clapperboard', waitForLoadingScreen = true })
      end
    end
    local firstMap = true
    for _, m in ipairs(maps()) do
      if m.installed then
        local main = firstMap and not summary          -- (one primary button: the first map's)
        firstMap = false
        buttons[#buttons + 1] = buttonInstance.addButton(start(true, nil, m.id), { label = strings.t('menuTile.new_career_1', (m.name)), icon = 'flag',
          primary = main, isDoubleClickAction = main, waitForLoadingScreen = true })
      end
    end
  end
  details[#details + 1] = {
    headerTitle = strings.t('menuTile.wrench_works_street_legal'),
    description = strings.t('menuTile.no_car_a_few_thousand', (installed and '' or strings.t('menuTile.this_needs_the_valo_city'))),
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
  guihooks.trigger('slMenu', { show = inMenu, installed = levelInstalled(), maps = maps(), summary = sl_career and sl_career.saveSummary() or nil,
    slots = sl_career and sl_career.listSlots and sl_career.listSlots() or {}, maxSlots = sl_career and sl_career.SLOTS })
end

function M.onUpdate(dtReal)
  timer = timer + dtReal
  if timer > 0.5 then timer = 0 send(false) end
end

function M.request() send(true) end
M.onUiReady = function() send(true) end

function M.startFromMenu(fresh, n, level)
  if not sl_career or not levelInstalled() or (sl_career.inMultiplayer and sl_career.inMultiplayer()) then return end
  guihooks.trigger('slMenu', { show = false })
  shown = false
  sl_career.start(fresh == true, n, level)
end

-- the game-over screen's way out
function M.toMainMenu() if returnToMainMenu then returnToMainMenu() end end

-- the chooser's slot buttons
function M.renameSlot(n, name) if sl_career then sl_career.renameSlot(n, name) end send(true) end
function M.deleteSlot(n) if sl_career then sl_career.deleteSlot(n) end send(true) end

-- the Gameplay screen builds its list once; have it look again now that this tile is here
function M.onExtensionLoaded()
  if ui_gameplaySelector_general and ui_gameplaySelector_general.onModActivated then ui_gameplaySelector_general.onModActivated() end
end

return M
