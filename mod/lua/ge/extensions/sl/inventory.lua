-- Street Legal: the player's inventory (extension name: sl_inventory; docs/INVENTORY.md in the Graph repo; Mods > Street Legal > Parts of the game > Inventory, on by default; off = the shops put
-- parts on the garage shelf straight away, as before). What you carry in the boot of the car you drive: the parts bought at shops until you reach your garage, oil, coolant, a battery, jerry cans,
-- the siphon tube and the tools. Rules in sl/core/inventory; the save key s.inventory is made here when something is first put in. On arrival at the garage (Wrench Works' hook
-- onWrenchWorksGarageEntered) the car parts for the cars you own move to the garage shelf with a toast; everything else stays in the boot.

local M = {}

local rules = require('sl/core/inventory')
local strings = require('sl/core/strings')
local features = require('sl/core/features')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end
local function changed(kind, id, delta)
  if extensions and extensions.hook then
    extensions.hook('onStreetLegalInventoryChanged', kind, id, delta)
    extensions.hook('onStreetLegalChanged')
  end
end

-- is the inventory in use: the part is on and there is a career (the shops ask before they use it)
function M.active() return career() ~= nil and features.on('inventory') end

local function scale()
  local v = sl_options and sl_options.get and sl_options.get('slInventoryScale')
  return type(v) == 'number' and v > 0 and v or 1
end

-- the words that say what kind of car this is: the game's body style, type and name of the car the player drives
local function bodyWords()
  local words = {}
  local car = sl_fleet and sl_fleet.currentCar and sl_fleet.currentCar()
  if not car then return words end
  words[#words + 1] = car.name
  pcall(function()
    local m = core_vehicles and core_vehicles.getModel and core_vehicles.getModel(car.model)
    local info = m and (m.model or m)
    if type(info) ~= 'table' then return end
    local style = info['Body Style']
    if type(style) == 'string' then words[#words + 1] = style
    elseif type(style) == 'table' then for k in pairs(style) do if type(k) == 'string' then words[#words + 1] = k end end end
    if type(info.Type) == 'string' then words[#words + 1] = info.Type end
    if type(info.Name) == 'string' then words[#words + 1] = info.Name end
  end)
  return words
end

-- the boot of the car under the player: carry points
function M.capacity()
  local base = rules.capacity(bodyWords())
  return math.max(6, math.floor(base * scale() + 0.5))
end

function M.used() local s = career() return s and rules.used(rules.ensure(s)) or 0 end
function M.free() local s = career() return s and rules.free(rules.ensure(s), M.capacity()) or 0 end
-- can `points` more be carried: true, or false and the free points
function M.fits(points)
  local s = career()
  if not s then return false, 0 end
  return rules.fits(rules.ensure(s), M.capacity(), points)
end

-- what the shops put in
function M.addPart(model, p)
  local s = career()
  if not s then return false, 'bad' end
  local ok, a, b = rules.addPart(rules.ensure(s), M.capacity(), { model = model, part = p.part, slotId = p.slotId, name = p.name, brand = p.brand, price = p.price, bought = s.day or 0, wear = p.wear })
  if ok then changed('part', p.part, 1) end
  return ok, a, b
end
function M.addItem(id, qty)
  local s = career()
  if not s then return false, 'bad' end
  local ok, a, b = rules.addItem(rules.ensure(s), M.capacity(), id, qty)
  if ok then changed('item', id, qty or 1) end
  return ok, a, b
end
function M.addCan(size, litres)
  local s = career()
  if not s then return false, 'bad' end
  local ok, a, b = rules.addCan(rules.ensure(s), M.capacity(), size, litres)
  if ok then changed('can', tostring(size), 1) end
  return ok, a, b
end
function M.addTool(id, uses)
  local s = career()
  if not s then return false, 'bad' end
  local ok, a, b = rules.addTool(rules.ensure(s), M.capacity(), id, uses)
  if ok then changed('tool', id, 1) end
  return ok, a, b
end

-- the labour a shop charges to fit a part (by size, times the setting; 0 = free)
function M.labourPrice(size)
  local v = sl_options and sl_options.get and sl_options.get('slLabourScale')
  local k = type(v) == 'number' and v >= 0 and v or 1
  return math.floor(rules.labour(size) * k + 0.5)
end

-- the carried parts that fit the car of this model: { { id, name, brand, size, price (labour) } }
function M.carriedFor(model)
  local s = career()
  local out = {}
  if not (s and model) then return out end
  for _, p in ipairs(rules.ensure(s).parts) do
    if p.model == model then out[#out + 1] = { id = p.id, name = p.name or p.part, brand = p.brand, size = p.size or 2, price = M.labourPrice(p.size or 2) } end
  end
  return out
end

-- fit a carried part on the car under the counter with Wrench Works' own fit path (slrr_garage.fitPart): the clock moves by the work, the part leaves the boot only when the car took it
function M.fit(invId)
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  if not (slrr_garage and slrr_garage.fitPart) then return false, strings.t('inventory.need_ww_fit') end
  local inv = rules.ensure(s)
  local at
  for i, p in ipairs(inv.parts) do if p.id == invId then at = i end end
  if not at then return false, strings.t('inventory.not_in_boot') end
  local p = inv.parts[at]
  local veh = getPlayerVehicle and getPlayerVehicle(0)
  local car = sl_fleet and sl_fleet.currentCar and sl_fleet.currentCar()
  if not (veh and car and car.model == p.model) then return false, strings.t('inventory.wrong_car') end
  local busy = sl_career.freeToStart and sl_career.freeToStart()      -- (a race, a job or a chase refuse the work first: the same test as the clock's, so a refusal never comes after the fit)
  if busy then return false, tostring(busy) end
  local okCall, ok, text = pcall(slrr_garage.fitPart, veh:getID(), { part = p.part, slotId = p.slotId, name = p.name, value = p.price, wear = p.wear })
  if not okCall or ok ~= true then return false, tostring(okCall and text or strings.t('inventory.not_now')) end
  table.remove(inv.parts, at)
  changed('part', p.part, -1)
  local minutes = rules.fitMinutes(p.size or 2, slrr_garage.getFeatures and slrr_garage.getFeatures() or nil, M.timeScale())
  if minutes > 0 and sl_career.spendTime then pcall(sl_career.spendTime, minutes, 'fitting') end      -- (the work takes its time once the car took the part)
  return true, strings.t('inventory.fitted', p.name or p.part)
end

-- the time the work takes: the setting (0 = no time passes)
function M.timeScale()
  local v = sl_options and sl_options.get and sl_options.get('slFitTimeScale')
  return type(v) == 'number' and v >= 0 and v or 1
end

-- what the other modules take out (the answer is whether it was there)
function M.take(id, qty)
  local s = career()
  if not s then return false end
  local ok = rules.take(rules.ensure(s), id, qty)
  if ok then changed('item', id, -(qty or 1)) end
  return ok
end
function M.count(id) local s = career() return s and rules.count(rules.ensure(s), id) or 0 end
function M.useTool(id)
  local s = career()
  if not s then return false end
  local ok = rules.useTool(rules.ensure(s), id)
  if ok then changed('tool', id, -1) end
  return ok
end
function M.toolCount(id) local s = career() return s and rules.toolCount(rules.ensure(s), id) or 0 end

-- the work done on the lift in this visit, in minutes (batched: one fade when you drive out)
local workMin = 0

-- the parts for the cars you own go on the garage shelf when you drive in; the rest wait
function M.onWrenchWorksGarageEntered()
  local s = career()
  if not s or not features.on('inventory') or not (slrr_garage and slrr_garage.addShelfPart) then return end
  local inv = rules.ensure(s)
  if #inv.parts == 0 then return end
  local owned = {}
  for _, car in ipairs(s.cars or {}) do if car.model then owned[car.model] = true end end
  local move, keep = rules.transferPlan(inv, owned)
  if #move == 0 then return end
  inv.parts = keep
  local failed, moved = {}, 0
  for _, p in ipairs(move) do
    local okc, res = pcall(slrr_garage.addShelfPart, p.model, { part = p.part, name = p.name, slotId = p.slotId, value = p.price, wear = p.wear })
    if okc and res ~= nil then moved = moved + 1 else failed[#failed + 1] = p end      -- (the shelf answers nil for a part it cannot take: that is not a move)
  end
  rules.keepParts(inv, failed)      -- (a part the shelf did not take stays in the boot and goes next time)
  if moved > 0 then
    toast(#failed == 0 and strings.t('inventory.transferred', moved) or strings.t('inventory.transferred_some', moved, moved + #failed))
    changed('parts', 'garage', -moved)
  end
end

-- Wrench Works finished one fit or removal on the lift (kind 'fit' | 'remove', the part's name, its weight in kg): the work takes time, added up for the visit
function M.onWrenchWorksWorkDone(vehId, kind, partName, weight)
  if not career() or M.timeScale() <= 0 then return end
  workMin = workMin + rules.workMinutes(weight, slrr_garage and slrr_garage.getFeatures and slrr_garage.getFeatures() or nil, M.timeScale())
end

-- driving out of the garage: the work of the visit moves the clock once (a fade and a line "2 h 15 min later"); never during a race, job or chase (the clock refuses and no time passes)
function M.onWrenchWorksGarageLeft()
  if slrr_garage and slrr_garage.bayMoving and slrr_garage.bayMoving() then return end      -- (moving to another bay leaves and re-enters: the minutes wait for the real drive-out)
  local minutes = math.min(rules.VISIT_MAX, workMin)
  workMin = 0
  if minutes < 5 or not (career() and sl_career.spendTime) then return end
  local ok, _, spent = pcall(sl_career.spendTime, minutes, 'fitting')
  if not ok then return end
  local h, m = rules.later(type(spent) == 'number' and spent or minutes)
  if h > 0 or m > 0 then toast(strings.t(h > 0 and 'inventory.time_later_h' or 'inventory.time_later_m', h, m)) end
end
function M.onStreetLegalStopped() workMin = 0 end

-- for the phone's Inventory page: nil with no career
function M.summary()
  local s = career()
  if not s then return nil end
  return rules.summary(rules.ensure(s), M.capacity())
end

-- the page's Drop button: a stack of one item, a can, or a tool (never a car part: it cost money)
function M.discard(kind, id)
  local s = career()
  if not s then return false end
  local inv = rules.ensure(s)
  if kind == 'item' then
    if not rules.take(inv, tostring(id), 1) then return false end
  elseif kind == 'can' then
    if not inv.cans[tonumber(id) or 0] then return false end
    table.remove(inv.cans, tonumber(id))
  elseif kind == 'tool' then
    local list = inv.tools[tostring(id)]
    if not list or #list == 0 then return false end
    table.remove(list)
    if #list == 0 then inv.tools[tostring(id)] = nil end
  else
    return false
  end
  changed(kind, tostring(id), -1)
  return true
end

-- use an item on the car you drive: engine oil, coolant or a battery (Part Wear's useItem on the player's car, guarded). The item leaves the boot only when the car took it.
local USE = { oil = 'oil', coolant = 'coolant', battery = 'battery' }
function M.use(id)
  local s = career()
  local kind = USE[id]
  if not (s and kind) then return false, strings.t('inventory.cannot_use') end
  local inv = rules.ensure(s)
  if rules.count(inv, id) < 1 then return false, strings.t('inventory.none_left') end
  local veh = getPlayerVehicle and getPlayerVehicle(0)
  if not (veh and extensions and extensions.isExtensionLoaded and extensions.isExtensionLoaded('slrr_partwear') and slrr_partwear and slrr_partwear.useItem) then
    return false, strings.t('inventory.need_partwear')
  end
  local car = sl_fleet and sl_fleet.currentCar and sl_fleet.currentCar()
  if not car then return false, strings.t('inventory.drive_your_car') end
  local okCall, ok, why = pcall(slrr_partwear.useItem, veh:getID(), kind, kind == 'battery' and { charge = 1 } or {})
  if not okCall or ok ~= true then return false, tostring(okCall and why or strings.t('inventory.not_now')) end
  rules.take(inv, id, 1)
  changed('item', id, -1)
  local text = strings.t('inventory.used_' .. id, car.name or '?')
  toast(text)
  return true, text
end

features.gate('inventory', M, nil, nil, { 'summary', 'discard', 'use' })

return M
