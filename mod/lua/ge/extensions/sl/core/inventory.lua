-- Street Legal: the player's inventory (docs/INVENTORY.md in the Graph repo). What you carry in the boot of the car you drive: car parts bought at shops until you reach your garage, oil, coolant, a
-- battery, jerry cans, the siphon tube and the theft tools. Everything has a size in carry points; the boot holds a number of points that depends on the kind of car (a pickup carries more than a
-- small coupe). Pure, no game calls: tested by tools/luatest.js. The save key s.inventory is created and repaired here, only when something is first needed (an old save is left alone).
--   s.inventory = { version = 1, items = { [itemId] = qty }, parts = { { id, model, part, slotId, name, brand, price, bought, wear, size } }, cans = { { size, litres } }, tools = { [toolId] = { { uses } } } }

local M = {}

local strings = require('sl/core/strings')

M.VERSION = 1
M.BASE, M.MIN, M.MAX = 20, 12, 40

-- carry points of the plain stackable items (a part's size comes from its slot, see M.partSize)
M.ITEMS = {
  oil = { name = strings.t('inventory.item_oil'), size = 1 }, coolant = { name = strings.t('inventory.item_coolant'), size = 1 }, brakefluid = { name = strings.t('inventory.item_brakefluid'), size = 1 },
  battery = { name = strings.t('inventory.item_battery'), size = 2 }, siphontube = { name = strings.t('inventory.item_siphontube'), size = 1 },
}
M.CAN_SIZES = { [10] = 2, [20] = 3 }           -- a jerry can of this many litres takes this many points
M.TOOL_SIZE = 1

-- the kind of car -> the boot: words of the game's body style / type / config name (lower case). Unknown: BASE.
local BODY = {
  { 40, { 'pickup', 'van', 'truck', 'utility', 'ute', 'flatbed' } },
  { 28, { 'suv', 'wagon', 'estate', 'crossover', 'offroad', 'off-road', 'minivan', 'mpv' } },
  { 14, { 'coupe', 'convertible', 'roadster', 'spyder', 'spider', 'kei', 'microcar', 'sports', 'supercar', 'hypercar', 'targa' } },
  { 20, { 'sedan', 'saloon', 'hatchback', 'hatch', 'liftback', 'fastback' } },
}
function M.capacity(words)
  if type(words) == 'string' then words = { words } end
  for _, w in ipairs(words or {}) do
    local lw = tostring(w):lower()
    for _, row in ipairs(BODY) do
      for _, key in ipairs(row[2]) do
        if lw:find(key, 1, true) then return math.max(M.MIN, math.min(M.MAX, row[1])) end
      end
    end
  end
  return M.BASE
end

-- a part's size from its slot (and name): an engine or gearbox 6, the big pieces 3, small fittings 1, the rest 2
local BIG = { 'engine', 'transmission', 'gearbox' }
local HEAVY = { 'turbo', 'supercharger', 'exhaust', 'brake', 'suspension', 'differential', 'driveshaft', 'axle', 'radiator', 'intercooler', 'wheel', 'tire', 'tyre', 'seat', 'bumper', 'hood', 'bonnet' }
local SMALL = { 'filter', 'gauge', 'badge', 'sticker', 'plate', 'mirror', 'light', 'lamp', 'spacer', 'knob', 'cap', 'fuse' }
local function has(text, list)
  for _, k in ipairs(list) do if text:find(k, 1, true) then return true end end
  return false
end
function M.partSize(slotId, name)
  local t = (tostring(slotId or '') .. ' ' .. tostring(name or '')):lower()
  if has(t, BIG) then return 6 end
  if has(t, HEAVY) then return 3 end
  if has(t, SMALL) then return 1 end
  return 2
end

-- the labour to fit a part at a shop (docs/INVENTORY.md): by size
M.LABOUR = { [1] = 20, [2] = 45, [3] = 90, [6] = 250 }
function M.labour(size) return M.LABOUR[size] or M.LABOUR[2] end

-- the minutes of work to fit one part (by size): the shops' labour takes the same time. features = { lift, crane, bench } shorten it (the crane halves an engine, the lift and the bench take a fifth off)
M.MINUTES = { [1] = 5, [2] = 15, [3] = 30, [6] = 120 }
function M.fitMinutes(size, features, scale)
  local m = M.MINUTES[size] or M.MINUTES[2]
  features = features or {}
  if features.lift then m = m * 0.8 end
  if features.bench then m = m * 0.9 end
  if features.crane and size >= 6 then m = m * 0.5 end
  return math.max(0, math.floor(m * (tonumber(scale) or 1) + 0.5))
end

-- the time the work at your own garage takes, from the weight of what was fitted or taken off (Wrench Works' parts.partWeight, kg): minutes for a bolt-on, half an hour for an exhaust or suspension,
-- hours for an engine or gearbox. The lift and the bench shorten it, the crane halves the heavy work (over 100 kg). One visit adds up (VISIT_MAX minutes at most).
M.VISIT_MAX = 240
function M.workMinutes(weight, features, scale)
  local w = tonumber(weight) or 0
  local m = w <= 5 and 5 or (w <= 15 and 15 or (w <= 40 and 30 or (w <= 100 and 60 or 150)))
  features = features or {}
  if features.lift then m = m * 0.8 end
  if features.bench or features.workbench then m = m * 0.9 end
  if features.crane and w > 100 then m = m * 0.5 end
  return math.max(0, math.floor(m * (tonumber(scale) or 1) + 0.5))
end
function M.later(minutes)
  minutes = math.max(0, math.floor(tonumber(minutes) or 0))
  return math.floor(minutes / 60), minutes % 60
end

-- ---- the save key
function M.ensure(s)
  local inv = s.inventory
  if type(inv) ~= 'table' then inv = {} s.inventory = inv end
  inv.version = M.VERSION
  if type(inv.items) ~= 'table' then inv.items = {} end
  if type(inv.parts) ~= 'table' then inv.parts = {} end
  if type(inv.cans) ~= 'table' then inv.cans = {} end
  if type(inv.tools) ~= 'table' then inv.tools = {} end
  for id, q in pairs(inv.items) do if type(id) ~= 'string' or type(q) ~= 'number' or q <= 0 or q ~= q then inv.items[id] = nil else inv.items[id] = math.floor(q) end end
  return inv
end

-- ---- points
function M.used(inv)
  local n = 0
  for id, q in pairs(inv.items or {}) do n = n + (M.ITEMS[id] and M.ITEMS[id].size or 1) * q end
  for _, p in ipairs(inv.parts or {}) do n = n + (p.size or 2) end
  for _, c in ipairs(inv.cans or {}) do n = n + (M.CAN_SIZES[c.size] or 2) end
  for _, list in pairs(inv.tools or {}) do n = n + #list * M.TOOL_SIZE end
  return n
end
function M.free(inv, cap) return math.max(0, (cap or M.BASE) - M.used(inv)) end

-- can `points` more be carried? true, or false and the free points (for the shop's refusal)
function M.fits(inv, cap, points)
  local free = M.free(inv, cap)
  return points <= free, free
end

-- ---- putting things in (each returns true, or false and the reason: 'full' with the free points, 'bad')
local function room(inv, cap, points)
  local ok, free = M.fits(inv, cap, points)
  if not ok then return false, 'full', free end
  return true
end

function M.addItem(inv, cap, id, qty)
  local def = M.ITEMS[id]
  qty = math.floor(tonumber(qty) or 1)
  if not def or qty < 1 then return false, 'bad' end
  local ok, why, free = room(inv, cap, def.size * qty)
  if not ok then return false, why, free end
  inv.items[id] = (inv.items[id] or 0) + qty
  return true
end

function M.addPart(inv, cap, p)
  if type(p) ~= 'table' or not p.part then return false, 'bad' end
  local size = p.size or M.partSize(p.slotId, p.name)
  local ok, why, free = room(inv, cap, size)
  if not ok then return false, why, free end
  inv.next = (inv.next or 0) + 1
  inv.parts[#inv.parts + 1] = { id = inv.next, model = p.model, part = p.part, slotId = p.slotId, name = p.name, brand = p.brand, price = p.price or 0, bought = p.bought or 0, wear = p.wear or 0, size = size }
  return true, inv.next
end

function M.addCan(inv, cap, size, litres)
  local pts = M.CAN_SIZES[size]
  if not pts then return false, 'bad' end
  local ok, why, free = room(inv, cap, pts)
  if not ok then return false, why, free end
  inv.cans[#inv.cans + 1] = { size = size, litres = math.max(0, math.min(size, tonumber(litres) or 0)) }
  return true
end

function M.addTool(inv, cap, id, uses)
  if type(id) ~= 'string' or id == '' then return false, 'bad' end
  local ok, why, free = room(inv, cap, M.TOOL_SIZE)
  if not ok then return false, why, free end
  inv.tools[id] = inv.tools[id] or {}
  table.insert(inv.tools[id], { uses = uses })
  return true
end

-- ---- taking things out
function M.take(inv, id, qty)
  qty = math.floor(tonumber(qty) or 1)
  if (inv.items[id] or 0) < qty or qty < 1 then return false end
  inv.items[id] = inv.items[id] - qty
  if inv.items[id] == 0 then inv.items[id] = nil end
  return true
end
function M.count(inv, id) return inv.items[id] or 0 end

-- one use of a tool: the one with the fewest uses left goes first; a tool with no uses left is dropped. Returns true, or false when there is none.
function M.useTool(inv, id)
  local list = inv.tools[id]
  if not list or #list == 0 then return false end
  local best
  for i, t in ipairs(list) do
    if t.uses == nil then if not best then best = i end
    elseif not best or list[best].uses == nil or t.uses < list[best].uses then best = i end
  end
  local t = list[best]
  if t.uses ~= nil then
    t.uses = t.uses - 1
    if t.uses <= 0 then table.remove(list, best) end
  end
  if #list == 0 then inv.tools[id] = nil end
  return true
end
function M.toolCount(inv, id) return inv.tools[id] and #inv.tools[id] or 0 end

-- pour a can into a car or tank: up to `litres`; returns how many litres left the can
function M.pour(inv, index, litres)
  local c = inv.cans[index]
  if not c then return 0 end
  local out = math.max(0, math.min(c.litres, tonumber(litres) or 0))
  c.litres = c.litres - out
  return out
end
function M.fill(inv, index, litres)
  local c = inv.cans[index]
  if not c then return 0 end
  local add = math.max(0, math.min(c.size - c.litres, tonumber(litres) or 0))
  c.litres = c.litres + add
  return add
end

-- ---- the move to the garage: every part for a model the player owns goes to the shelf; the rest stays. owned = { [model] = true }. Returns the parts to move (removed from the inventory) and how many stay.
function M.transferPlan(inv, owned)
  local move, keep = {}, {}
  for _, p in ipairs(inv.parts) do
    if p.model and owned[p.model] then move[#move + 1] = p else keep[#keep + 1] = p end
  end
  return move, keep
end
-- put back parts the shelf did not take (the garage mod failed on them): they stay in the inventory, whatever the free points say
function M.keepParts(inv, parts) for _, p in ipairs(parts) do inv.parts[#inv.parts + 1] = p end end

-- ---- the phone page
function M.summary(inv, cap)
  local groups = {}
  local function add(kind, label, count, points, extra)
    groups[#groups + 1] = { kind = kind, name = label, count = count, points = points, extra = extra }
  end
  local ids = {}
  for id in pairs(inv.items) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do add('item', M.ITEMS[id] and M.ITEMS[id].name or id, inv.items[id], (M.ITEMS[id] and M.ITEMS[id].size or 1) * inv.items[id], { id = id }) end
  for i, c in ipairs(inv.cans) do add('can', strings.t('inventory.can_name', c.size), 1, M.CAN_SIZES[c.size] or 2, { index = i, litres = c.litres, size = c.size }) end
  local tids = {}
  for id in pairs(inv.tools) do tids[#tids + 1] = id end
  table.sort(tids)
  for _, id in ipairs(tids) do
    local uses, unlimited = 0, false
    for _, t in ipairs(inv.tools[id]) do if t.uses == nil then unlimited = true else uses = uses + t.uses end end
    add('tool', id, #inv.tools[id], #inv.tools[id] * M.TOOL_SIZE, { id = id, uses = unlimited and nil or uses })
  end
  for _, p in ipairs(inv.parts) do add('part', p.name or p.part, 1, p.size or 2, { id = p.id, model = p.model, brand = p.brand, wear = p.wear }) end
  return { used = M.used(inv), cap = cap or M.BASE, groups = groups }
end

return M
