-- Street Legal: the laptop's menu rules (docs/LAPTOP_DESIGN.md; no game calls).
-- A computer facility of the map lists the stock career's functions it offers (`functions`, e.g. { tuning = true });
-- this turns that and the career's state into the screen's tiles: which exist, which are greyed, and why.
local M = {}

-- id = the stock function key. group: 'car' tiles act on the chosen car (only at a computer that lists cars), 'general' ones do not.
-- page: what opens in the laptop; soon: not built yet (L3 dealers, L4 garage entry: delete the flag when it is).
-- needs: a map capability (progression.MAPS has) the tile depends on, hidden where the map lacks it.
M.TILES = {
  { id = 'vehicleInventory', label = 'My cars', group = 'general', page = 'cars' },
  { id = 'partInventory', label = 'My parts', group = 'general', page = 'parts' },
  { id = 'vehicleShop', label = 'Dealers', group = 'general', soon = true, shop = true },
  { id = 'insurances', label = 'Bank / insurance', group = 'general', page = 'bank' },
  { id = 'playerAbstract', label = 'Street cred', group = 'general', page = 'cred' },
  { id = 'partShop', label = 'Part customization', group = 'car', soon = true },
  { id = 'tuning', label = 'Tuning', group = 'car', soon = true },
  { id = 'painting', label = 'Painting', group = 'car', soon = true },
  { id = 'repair', label = 'Repair', group = 'car', soon = true },
}

-- functions: the facility's table; state = { hasCar, busy (a race or a job), has = capabilities, carHere (the chosen car stands in this garage) };
-- defs: the tile list (the default one, replaceable for tests)
function M.build(functions, state, defs)
  functions, state = functions or {}, state or {}
  local has = state.has or {}
  local lists = functions.vehicleInventory ~= nil          -- a garage computer lists cars; an office one does not
  local car, general = {}, {}
  for _, def in ipairs(defs or M.TILES) do
    if functions[def.id] and (not def.needs or has[def.needs]) then
      local tile = { id = def.id, label = def.label, page = def.page, enabled = true }
      local onCar = def.group == 'car' and lists
      if (onCar or def.shop) and state.busy then tile.enabled, tile.reason = false, 'Not during a race or a job.'
      elseif onCar and not state.hasCar then tile.enabled, tile.reason = false, 'You have no car yet.'
      elseif def.soon then tile.enabled, tile.reason = false, 'Coming soon.'
      elseif onCar and state.carHere == false then tile.enabled, tile.reason = false, 'Bring the car into the garage first.' end
      local list = onCar and car or general
      list[#list + 1] = tile
    end
  end
  local groups = {}
  if #car > 0 then groups[#groups + 1] = { id = 'car', title = 'Vehicle management', tiles = car } end
  if #general > 0 then groups[#groups + 1] = { id = 'general', title = 'General', tiles = general } end
  return { groups = groups, lists = lists }
end

return M
