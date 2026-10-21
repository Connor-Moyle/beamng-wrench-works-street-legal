-- Street Legal: barn finds (extension name: sl_barnfinds; campaign idea #3). Rules in sl/core/barn. A few days apart a contact texts about an old car in a yard far from town; once you drive
-- to the spot, the car shows as an ad in the Car market (sl_classifieds.addBarn / revealBarn), bought like any private ad (and its faults show after a mechanic's check).
-- Saved in the career as s.barn = { levels = { [level] = { spots = { { id, x, y, z, listing, found } } } }, nextHint = day }.

local M = {}

local strings = require('sl/core/strings')
local rules = require('sl/core/barn')
local rngLib = require('sl/core/rng')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) if ui_message then ui_message(text, 6, 'streetLegal') end end
local function level() return getCurrentLevelIdentifier and getCurrentLevelIdentifier() or '' end

local function places()
  local out = {}
  for id, p in pairs(sl_career.getPlaces() or {}) do
    if p.pos then out[#out + 1] = { id = id, name = p.name, x = p.pos.x, y = p.pos.y } end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- the spots of this map (chosen once from the road graph)
local function ensure(s)
  local lv = level()
  local b = s.barn
  if type(b) ~= 'table' then b = { nextHint = (s.day or 1) + 2 } end
  b.levels = b.levels or {}
  s.barn = b
  local e = b.levels[lv]
  if e and type(e.spots) == 'table' then return e, b end
  local ok, nodes = pcall(function() return map.getMap().nodes end)
  if not (ok and nodes and next(nodes)) then return nil end
  e = { spots = rules.select(nodes, places(), rngLib.new(rngLib.hash('barn:' .. lv .. ':' .. tostring(s.seed)))) }
  b.levels[lv] = e
  return e, b
end

-- a new day: when it is time, a rumour about a spot that has no car yet
function M.onStreetLegalNewDay(day)
  local s = career()
  if not s or (s.rep or 0) < rules.MIN_REP or not sl_classifieds or not sl_classifieds.addBarn then return end
  local e, b = ensure(s)
  if not e or day < (b.nextHint or 0) then return end
  local rng = rngLib.new(rngLib.hash('barnhint:' .. day .. ':' .. tostring(s.seed)))
  local free = {}
  for _, sp in ipairs(e.spots) do if not sp.listing then free[#free + 1] = sp end end
  b.nextHint = day + rng:int(rules.GAP[1], rules.GAP[2])
  if #free == 0 then return end
  local spot = free[rng:int(#free)]
  local id, name = sl_classifieds.addBarn(spot, rng:int(1, 1000000))
  if not id then b.nextHint = day + 1 return end        -- (no car to offer just now: tried again tomorrow)
  spot.listing, spot.car = id, name
  sl_career.sendText('benny', rules.hint(spot, places(), name), 2)
  extensions.hook('onStreetLegalChanged')
end

local timer = 0
function M.onUpdate(dt)
  timer = timer + (dt or 0)
  if timer < 1 then return end
  timer = 0
  local s = career()
  local v = s and s.barn and getPlayerVehicle(0)
  if not v then return end
  local e = ensure(s)
  if not e then return end
  local p = v:getPosition()
  for _, sp in ipairs(e.spots) do
    if sp.listing and not sp.found and (sp.x - p.x) ^ 2 + (sp.y - p.y) ^ 2 < rules.FOUND_RADIUS ^ 2 then
      sp.found = true
      if sl_classifieds and sl_classifieds.revealBarn then sl_classifieds.revealBarn(sp.listing) end
      toast(strings.t('barn.found', sp.car or '?'))
      extensions.hook('onStreetLegalChanged')
    end
  end
end

-- the spots that have a rumour and are not found yet, for the Map app: { { id, x, y, car } }
function M.summary()
  local s = career()
  local e = s and s.barn and ensure(s)
  if not e then return nil end
  local out = {}
  for _, sp in ipairs(e.spots) do
    if sp.listing and not sp.found then out[#out + 1] = { id = sp.id, x = sp.x, y = sp.y, car = sp.car } end
  end
  return { rumours = out }
end

require('sl/core/features').gate('barn', M, nil, nil, { 'summary' })

return M
