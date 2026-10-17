-- Street Legal: the laptop's menu rules (docs/LAPTOP_DESIGN.md; no game calls).
-- A computer facility of the map lists the stock career's functions it offers (`functions`, e.g. { tuning = true });
-- this turns that and the career's state into the screen's tiles: which exist, which are greyed, and why.
local M = {}

local strings = require('sl/core/strings')

-- id = the stock function key. group: 'car' tiles act on the chosen car (only at a computer that lists cars), 'general' ones do not.
-- page: what opens in the laptop; soon: not built yet (L3 dealers, L4 garage entry: delete the flag when it is).
-- ids: a tile of ours that stands for any of several stock functions (the parts market needs a parts shop or a dealer).
-- needs: a map capability (progression.MAPS has) the tile depends on, hidden where the map lacks it.
local S = require('sl/core/strings')
M.TILES = {
  { id = 'vehicleInventory', label = S.t('laptop.mycars'), group = 'general', page = 'cars' },
  { id = 'partInventory', label = S.t('laptop.myparts'), group = 'general', page = 'parts' },
  { id = 'vehicleShop', label = S.t('laptop.carmarket'), group = 'general', page = 'dealers', shop = true },
  { id = 'partsMarket', ids = { 'partShop', 'vehicleShop' }, label = S.t('laptop.partmarket'), group = 'general', page = 'partmarket', shop = true, needs = 'classifieds' },
  { id = 'clubs', ids = { 'vehicleInventory', 'vehicleShop', 'partShop' }, label = S.t('laptop.club'), group = 'general', page = 'club', needs = 'clubs' },
  { id = 'help', ids = { 'vehicleInventory', 'vehicleShop', 'partShop', 'insurances', 'playerAbstract' }, label = S.t('laptop.help'), group = 'general', page = 'help' },
  { id = 'insurances', label = S.t('laptop.bank'), group = 'general', page = 'bank' },
  { id = 'playerAbstract', label = S.t('laptop.cred'), group = 'general', page = 'cred' },
  { id = 'partShop', label = S.t('laptop.partshop'), group = 'car', mode = 'catalog' },
  { id = 'tuning', label = S.t('laptop.tuning'), group = 'car', mode = 'tune' },
  { id = 'painting', label = S.t('laptop.painting'), group = 'car', mode = 'paint' },
  { id = 'repair', label = S.t('laptop.repair'), group = 'car', mode = 'repair' },
}

-- mode: the Wrench Works garage opens on the chosen car in that mode (slrr_garage.enterWith).
-- A car is "here" when it stands at the very garage the computer belongs to (both ids from slrr_garage.garageAt).
function M.carHere(computerGarage, carGarage) return computerGarage ~= nil and computerGarage == carGarage end

-- functions: the facility's table; state = { hasCar, busy (a race or a job), has = capabilities, carHere (the chosen car stands in this garage) };
-- defs: the tile list (the default one, replaceable for tests)
local phase = require('sl/core/phase')
function M.build(functions, state, defs)
  functions, state = functions or {}, state or {}
  local has = state.has or {}
  local lists = functions.vehicleInventory ~= nil          -- a garage computer lists cars; an office one does not
  local car, general = {}, {}
  for _, def in ipairs(defs or M.TILES) do
    local offered = functions[def.id]
    for _, other in ipairs(def.ids or {}) do offered = offered or functions[other] end
    if offered and (not def.needs or has[def.needs]) then
      local tile = { id = def.id, label = def.label, page = def.page, mode = def.mode, enabled = true }
      local onCar = def.group == 'car' and lists
      if def.group == 'car' and not lists then tile.enabled, tile.reason = false, strings.t('laptop.use_a_computer_in_a')
      elseif (onCar or def.shop) and state.busy then tile.enabled, tile.reason = false, strings.t('laptop.not_during_a_race_or')
      elseif onCar and not state.hasCar then tile.enabled, tile.reason = false, strings.t('laptop.you_have_no_car_yet')
      elseif def.soon then tile.enabled, tile.reason = false, strings.t('laptop.coming_soon')
      elseif onCar and state.carHere == false then tile.enabled, tile.reason = false, strings.t('laptop.bring_the_car_into_the') end
      local list = onCar and car or general
      list[#list + 1] = tile
    end
  end
  -- (D1) a garage computer starts the night or the day
  if lists and state.phase then
    local tile = { id = 'phaseSwitch', label = phase.switchLabel(state.phase), run = 'phase', enabled = true }
    if state.busy then tile.enabled, tile.reason = false, strings.t('laptop.not_during_a_race_or') end
    general[#general + 1] = tile
  end
  local groups = {}
  if #car > 0 then groups[#groups + 1] = { id = 'car', title = strings.t('laptop.vehicle_management'), tiles = car } end
  if #general > 0 then groups[#groups + 1] = { id = 'general', title = 'General', tiles = general } end
  return { groups = groups, lists = lists }
end

return M
