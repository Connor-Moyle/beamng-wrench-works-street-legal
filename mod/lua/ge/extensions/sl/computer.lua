-- Wrench Works: Street Legal: the laptops (extension name: sl_computer)
-- BeamNG's maps list computer facilities (West Coast USA has five); the stock career opens its menu there. In a
-- Street Legal career they are a game marker (the ring and prompt the lots use): stopping or walking into it
-- offers "Use the laptop", which opens the laptop (sl/core/laptop: the tiles the computer's own `functions` table lists,
-- greyed with a reason when they cannot be used; the screen is ui/modModules/slLaptop). Valo City has none.

local M = {}

local strings = require('sl/core/strings')

local computer = require('sl/core/computer')
local laptop = require('sl/core/laptop')

local ICON = 'mission_arrival_triangle'

local function careerOn() return sl_career ~= nil and sl_career.isActive() == true end

local function posOf(f)
  local p = freeroam_facilities.getAverageDoorPositionForFacility(f)
  return p and p:length() > 0.01 and p or nil      -- (no door objects found: the game returns a zero vector)
end

-- the game asks every extension for its markers once per level (cached): ours join them while a career runs
function M.onGetRawPoiListForLevel(level, elements)
  if not (careerOn() and freeroam_facilities and freeroam_facilities.getFacilitiesByType) then return end
  local list = freeroam_facilities.getFacilitiesByType('computer', level) or {}
  for _, c in ipairs(computer.points(true, list, posOf)) do
    elements[#elements + 1] = { id = 'sl_computer_' .. c.id, data = { type = 'slrrComputer', id = c.id, name = c.name, date = 0 },
      markerInfo = { missionMarker = { pos = c.pos, rot = quat(0, 0, 0, 1), icon = ICON } } }
  end
end

local function facilityById(id)
  for _, f in ipairs(freeroam_facilities and freeroam_facilities.getFacilitiesByType and freeroam_facilities.getFacilitiesByType('computer') or {}) do
    if f.id == id then return f end
  end
end

local function name(f) return translateLanguage and translateLanguage(f.name, 'Computer', true) or 'Computer' end

-- the shelf of Wrench Works (parts taken off and delivered), per model of the player's cars
local function shelf(s)
  local out, seen = {}, {}
  for _, car in ipairs(s.cars) do
    if car.model and not seen[car.model] then
      seen[car.model] = true
      for _, it in ipairs(slrr_garage and slrr_garage.shelfItems and slrr_garage.shelfItems(car.model) or {}) do
        local card = sl_classifieds and sl_classifieds.partCard and sl_classifieds.partCard(it, car.model) or {}      -- (the phone's names and pictures: never a raw table)
        out[#out + 1] = { model = car.model, car = car.name, name = card.name or it.name, slot = it.slotId, count = it.count, value = it.value, wear = it.wear,
          categoryTitle = card.categoryTitle, chapter = card.chapter, fits = card.fits, preview = card.preview, partPic = card.partPic }
      end
    end
  end
  return out
end

local at          -- the laptop open now: { id, pos, functions }

-- the player's own Windows wallpaper, if tools/wallpaper.ps1 has copied it into the user folder (the UI can read only the game's
-- virtual file system, not the registry or the Pictures folder); the setting can choose the built-in one instead
local WALLPAPER = '/settings/street_legal/wallpaper.jpg'
local function wallpaper()
  local photo = sl_photos and sl_photos.wallpapers and sl_photos.wallpapers().laptop      -- (a photo chosen in the Gallery wins)
  if photo then return photo end
  if sl_options and sl_options.get and sl_options.get('slWallpaper') == 'builtin' then return nil end
  return FS and FS.fileExists and FS:fileExists(WALLPAPER) and WALLPAPER or nil
end

-- the id of the Wrench Works garage a point is at (nil: none, or Wrench Works is not running)
local function garageOf(pos) return pos and slrr_garage and slrr_garage.garageAt and slrr_garage.garageAt(pos) or nil end

-- the tiles for a car (carHere is per car), and for the no-car case; byCar is keyed by the car's id
local function buildViews(s)
  local base = { busy = (s.jobs and s.jobs.active ~= nil) or (sl_streets and sl_streets.isRacing and sl_streets.isRacing()) or false,
    phase = sl_career.phase and sl_career.phase() or nil,
    has = { clubs = sl_career.has('clubs'), crews = sl_career.has('crews'), classifieds = sl_career.has('classifieds') } }
  local function state(extra) local t = {} for k, v in pairs(base) do t[k] = v end for k, v in pairs(extra) do t[k] = v end return t end
  local computerGarage = garageOf(at.pos)
  local byCar, first = {}, nil
  for _, car in ipairs(s.cars) do
    local veh = sl_fleet.vehicleOf(car.id)
    local v = laptop.build(at.functions, state({ hasCar = true, carHere = veh ~= nil and laptop.carHere(computerGarage, garageOf(veh:getPosition())) }))
    byCar[car.id], first = v.groups, first or v
  end
  return first or laptop.build(at.functions, state({ hasCar = false })), byCar
end

function M.parts()
  local s = careerOn() and sl_career.getState()
  if s then guihooks.trigger('slLaptopParts', { parts = shelf(s) }) end
end

function M.close()
  at = nil
  guihooks.trigger('slLaptopClose', {})
end

-- "Use the laptop" at computer `id`: the screen gets its tiles, and the phone's data (cars, bank, street cred) comes as the phone's own event
function M.open(id)
  local f = careerOn() and facilityById(id)
  if not f then return end
  local s = sl_career.getState()
  at = { id = id, pos = posOf(f), functions = f.functions }
  local view, byCar = buildViews(s)
  do      -- (B61: what this computer offers and which tiles came of it, for the log)
    local fn, tiles = {}, {}
    for k in pairs(at.functions or {}) do fn[#fn + 1] = k end
    table.sort(fn)
    for _, g in ipairs(view.groups or {}) do for _, t in ipairs(g.tiles) do tiles[#tiles + 1] = t.label .. (t.enabled and '' or strings.t('computer.off_1', (tostring(t.reason)))) end end
    if log then log('I', 'sl_computer', 'laptop ' .. tostring(id) .. ' functions [' .. table.concat(fn, ',') .. '] tiles [' .. table.concat(tiles, '; ') .. '] classifieds=' .. tostring(sl_career.has('classifieds'))) end
  end
  if sl_phone and sl_phone.request then sl_phone.request() end
  guihooks.trigger('slLaptopOpen', { name = name(f), groups = view.groups, byCar = byCar, lists = view.lists, parts = shelf(s), wallpaper = wallpaper() })
end

-- the player's car `carId` is at this computer's garage and ready to go into it: the Wrench Works garage opens on it in `mode`
function M.enterGarage(mode, carId)
  local s = careerOn() and at and sl_career.getState()
  if not s then return end
  local veh = sl_fleet.vehicleOf(tonumber(carId))
  local here = veh ~= nil and laptop.carHere(garageOf(at.pos), garageOf(veh:getPosition()))
  if not here then return guihooks.trigger('slPhoneToast', { text = strings.t('computer.bring_the_car_into_the') }) end
  local ok, why = slrr_garage.enterWith(veh:getID(), tostring(mode))
  if ok then M.close() else guihooks.trigger('slPhoneToast', { text = why or strings.t('career.not_now') }) end
end

-- walked or driven away from the computer: it closes
local timer = 0
function M.onUpdate(dtReal)
  if not at then return end
  timer = timer + (dtReal or 0)
  if timer < 1 then return end
  timer = 0
  local v = getPlayerVehicle(0)
  if not careerOn() or not v or (at.pos and (v:getPosition() - at.pos):length() > 25) then M.close() end
end

-- standing in the marker: the game's prompt gets our button
function M.onActivityAcceptGatherData(elemData, activityData)
  if not careerOn() then return end
  for _, elem in ipairs(elemData or {}) do
    if elem.type == 'slrrComputer' then
      table.insert(activityData, {
        icon = 'poi_arrival_round', heading = translateLanguage and translateLanguage(elem.name, 'Computer', true) or 'Computer',   -- (the facility's name is a translation key)
        preheadings = { 'Laptop' },
        sorting = { type = 'slrrComputer', id = elem.id },
        buttonLabel = strings.t('computer.use_the_laptop'), buttonFun = function() M.open(elem.id) end,
        buttonSoundClass = 'bng_hover_generic',
      })
    end
  end
end

-- the marker list is cached by the game: build it again when a career starts or stops
local function refresh() if gameplay_rawPois and gameplay_rawPois.clear then gameplay_rawPois.clear() end end
M.onStreetLegalStarted = refresh
M.onStreetLegalStopped = function() refresh() M.close() end

-- (the Mods menu's Parts of the game: with this part off, the hooks above do nothing)
require('sl/core/features').gate('laptop', M, nil, nil, { 'open', 'enterGarage' }, { 'onStreetLegalStarted' })

return M
