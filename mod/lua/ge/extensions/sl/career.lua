-- Street Legal Racing (extension name: sl_career)
-- The career: a remake of Street Legal Racing: Redline's game in BeamNG, played on the Valo
-- City map. You start on foot in the first garage with a little money and no car; the city's
-- street racers are in your phone; reputation from racing - better at night - takes you up
-- through the garages to the ROC.
--
-- This file is the conductor: starting and continuing a career, the save, the clock, the
-- shared wallet (Wrench Works' garage and the map's night races spend and pay into it), the
-- places a taxi goes to, and the races arranged on the phone. The rules themselves are in
-- sl/core (tested outside the game), the phone in sl/phone and ui/modModules/slPhone.

local M = {}

local progression = require('sl/core/progression')
local stateLib = require('sl/core/state')
local roster = require('sl/core/roster')
local rngLib = require('sl/core/rng')
local stockLib = require('sl/core/stockdealers')
local phaseLib = require('sl/core/phase')
local visitLib = require('sl/core/visit')
local heatLib = require('sl/core/heat')
local strings = require('sl/core/strings')

local logTag = 'street_legal'
M.MAPS = progression.MAPS         -- the maps a career is played on (W1)
M.LEVEL = progression.DEFAULT_MAP -- the map of the career being played (a new career picks one; the save keeps it)
local SAVE_DIR = '/settings/street_legal/'
-- save slots (X52): slot 1 is the original career.json (so the career from before slots is slot 1, untouched),
-- slot n is careerN.json; their names and the last one played are in slots.json
M.SLOTS = 6
local SLOTS_FILE = SAVE_DIR .. 'slots.json'
local function slotFile(n) return SAVE_DIR .. (n == 'qa' and 'career_qa.json' or n == 1 and 'career.json' or ('career' .. n .. '.json')) end      -- ('qa': the automated tests' own slot, never one of the player's)
local slot = 1
local SAVE_FILE = slotFile(1)          -- the slot being played; set by M.start
local PLACES_DIR = '/street_legal/places/'          -- any mod (the map) can bring its places here
local USER_PLACES = SAVE_DIR .. 'places.json'       -- and the player can add their own

local s                   -- the save, while a career is played
local active = false
local pending             -- 'start' while the level loads for a career
local visitEnded          -- { was, how }: a visit that ended at this start; the hook goes out once the career is up
local dirty, saveTimer = false, 0
local syncTimer = 0
local lastHour
local places              -- { [id] = { id, kind, name, pos = vec3, dir = vec3 } } for this map
local replyQueue = {}     -- text messages on their way: { at (os.clock), thread, text }

----------------------------------------------------------------------------------------------
-- helpers

local function now() return os.time() end

local function changed()
  dirty = true
  extensions.hook('onStreetLegalChanged')
end

local function tell(text, seconds)
  if ui_message then ui_message(text, seconds or 5, 'streetLegal') end
end

local function garageModule(name)
  local ok, mod = pcall(require, name)
  return ok and type(mod) == 'table' and mod or nil
end

-- in-game hour, 0..24 (the engine's day fraction has noon at 0)
local function hour()
  local tod = core_environment and core_environment.getTimeOfDay and core_environment.getTimeOfDay()
  if type(tod) ~= 'table' or not tod.time then return 12 end
  return (tod.time * 24 + 12) % 24
end

-- the sun the sky is drawn with now: its elevation in degrees (the game's ScatterSky), or nil
local function sunElevation()
  local names = scenetree.findClassObjects and scenetree.findClassObjects('ScatterSky') or {}
  local sky = names[1] and scenetree.findObject(names[1])
  return sky and tonumber(sky.elevation) or nil
end
M.sunElevation = sunElevation

-- The sky is positioned by the game's core_celestial from the level's time and date. Some ways of launching the game do not load that extension
-- (seen: a level loaded through the MCP tools: core_celestial nil, the sun stuck at the level's authored hour). The career must not depend on it:
-- it loads the extension when it is missing, and if there is still none it puts the sun where the clock says itself (sl/core/sun).
local sunLib = require('sl/core/sun')
local function ensureCelestial()
  if not core_celestial and extensions and extensions.load then pcall(extensions.load, 'core_celestial') end
  if core_celestial and core_celestial.setEnabled then pcall(core_celestial.setEnabled, true) end
  return core_celestial ~= nil
end
-- The big map (M) is the game's freeroam_vueBigMap, loaded with the other preset extensions when a freeroam level starts. A level that came up another way
-- has none: M then throws "attempt to index global 'freeroam_vueBigMap'" on opening and on leaving, and the player is stuck on it. Loaded here (and checked
-- every second while the career runs, in case the game unloads it); the bigmap places are listed by sl/pois.lua.
local function ensureBigMap()
  if freeroam_vueBigMap and freeroam_bigMapMode and freeroam_bigMapPoiProvider then return end
  if extensions and extensions.load then
    for _, name in ipairs({'freeroam_bigMapMode', 'freeroam_bigMapPoiProvider', 'freeroam_vueBigMap'}) do pcall(extensions.load, name) end
  end
end
M.ensureBigMap = ensureBigMap
local function skyFollow()
  if core_celestial then return end
  local tod = core_environment and core_environment.getTimeOfDay and core_environment.getTimeOfDay()
  local names = scenetree.findClassObjects and scenetree.findClassObjects('ScatterSky') or {}
  local sky = names[1] and scenetree.findObject(names[1])
  if type(tod) ~= 'table' or not tod.time or not sky then return end
  local lat, lon = tonumber(tod.latitude) or 47, tonumber(tod.longitude) or 8
  local y, mo, d = tod.year or 2026, tod.month or 6, tod.day or 20
  local utc = tonumber(tod.utcOffset) or sunLib.utcOffsetFor(lat, lon, tod.dstRule, y, mo, d)
  local el, az = sunLib.position(lat, lon, utc, mo, d, (tod.time * 24 + 12) % 24, y)
  sky.elevation = el
  sky.azimuth = az
  if sky.postApply then pcall(sky.postApply, sky) end
end

-- frames the game has drawn (onPreRender): the sky is positioned there (core_celestial), so a clock set while nothing is drawn leaves the sun where it was
local framesDrawn = 0
function M.onPreRender() framesDrawn = framesDrawn + 1 end

-- one line to the log about the clock and the sky, to see which of them is not following (sl_career)
local lastFrames = 0
local function skyReport(tag)
  local tod = core_environment and core_environment.getTimeOfDay and core_environment.getTimeOfDay() or {}
  local names = scenetree.findClassObjects and scenetree.findClassObjects('ScatterSky') or {}
  local sky = names[1] and scenetree.findObject(names[1])
  local cel = core_celestial and core_celestial.getState and core_celestial.getState() or {}
  local paused = false
  pcall(function() paused = bullettime and bullettime.getPause and bullettime.getPause() or false end)
  log('I', 'sl_career', string.format('sky %s: tod.time %s play %s, celestial %s (sees time %s, %s-%s-%s), sun elevation %s azimuth %s, %d frames drawn since the last report, paused %s',
    tag, tostring(tod.time), tostring(tod.play), core_celestial and tostring(cel.enabled) or 'not loaded', tostring(cel.time), tostring(cel.year), tostring(cel.month), tostring(cel.day),
    sky and tostring(sky.elevation) or 'no sky', sky and tostring(sky.azimuth) or '-', framesDrawn - lastFrames, tostring(paused)))
  lastFrames = framesDrawn
end

-- (D1) the clock runs inside the phase and stands still when the phase has run out (the phase's end hour), at the speed of the Clock setting
local function clockRuns(h) return not (s and s.phase and phaseLib.ended(s.phase, h)) end
local function setHour(h)
  local tod = core_environment and core_environment.getTimeOfDay and core_environment.getTimeOfDay()
  if type(tod) ~= 'table' then return end
  local run = clockRuns(h)
  local length = phaseLib.dayLength(sl_options and sl_options.get and sl_options.get('slClock'))
  tod.time = ((h - 12) % 24) / 24
  tod.play = run
  tod.dayLength = length
  tod.year, tod.month, tod.day = phaseLib.SKY_DATE.year, phaseLib.SKY_DATE.month, phaseLib.SKY_DATE.day      -- (the equinox: see sl/core/phase)
  core_environment.setTimeOfDay(tod)
  -- the setter leaves "play" off on this level (seen in game: the clock stood at 20:30 all night),
  -- so start it on the TimeOfDay object itself
  local names = scenetree.findClassObjects and scenetree.findClassObjects('TimeOfDay') or {}
  local obj = names[1] and scenetree.findObject(names[1])
  if obj then
    obj:setField('play', 0, run and '1' or '0')
    obj:setField('animate', 0, run and '1' or '0')
    obj:setField('dayLength', 0, tostring(length))
  end
  skyFollow()
end

local function v3(t) return type(t) == 'table' and vec3(tonumber(t[1] or t.x) or 0, tonumber(t[2] or t.y) or 0, tonumber(t[3] or t.z) or 0) or nil end

----------------------------------------------------------------------------------------------
-- the save

local function writeSave()
  if not s then return end
  extensions.hook('onStreetLegalBeforeSave')      -- the cars out in the world note where they are first
  if not FS:directoryExists(SAVE_DIR) then FS:directoryCreate(SAVE_DIR, true) end
  -- never half a save: write it aside and read it back, keep the last good one as .bak, then put it in
  -- place (a crash or Alt-F4 at any point leaves a whole save behind; readSave tries them in turn)
  local fresh = SAVE_FILE .. '.new'
  jsonWriteFile(fresh, s, true)
  if type(jsonReadFile(fresh)) ~= 'table' then log('E', 'sl_career', 'the save did not read back; the last one is kept') return end
  if FS:fileExists(SAVE_FILE) then FS:copyFile(SAVE_FILE, SAVE_FILE .. '.bak') end
  FS:copyFile(fresh, SAVE_FILE)
  FS:removeFile(fresh)
  dirty = false
end

local function readSave(file)
  file = file or SAVE_FILE
  for _, f in ipairs({ file, file .. '.new', file .. '.bak' }) do
    local data = FS:fileExists(f) and jsonReadFile(f) or nil
    if type(data) == 'table' then
      if f ~= file then log('W', 'sl_career', 'the save was damaged; continuing from ' .. f) end
      return stateLib.migrate(data)
    end
  end
  return stateLib.migrate(nil)
end

local function slotsMeta()
  local m = FS:fileExists(SLOTS_FILE) and jsonReadFile(SLOTS_FILE) or nil
  if type(m) ~= 'table' then m = {} end
  m.names = type(m.names) == 'table' and m.names or {}
  m.last = tonumber(m.last) or 1
  return m
end
local function writeMeta(m)
  if not FS:directoryExists(SAVE_DIR) then FS:directoryCreate(SAVE_DIR, true) end
  jsonWriteFile(SLOTS_FILE, m, true)
end
local function slotUsed(n) local f = slotFile(n) return FS:fileExists(f) or FS:fileExists(f .. '.bak') end

local function mapOf(level) return progression.MAPS[level] or progression.MAPS[progression.DEFAULT_MAP] end

-- what this career's map can host (progression.MAPS has), and its name in texts
-- a map's feature, and for the parts the player can switch off (Mods menu: Parts of the game) that switch too
local PART_OF = { clubs = 'clubs', clubDays = 'clubs', crews = 'crews', classifieds = 'market' }
function M.has(feature)
  if PART_OF[feature] and not require('sl/core/features').on(PART_OF[feature]) then return false end
  return progression.has(M.LEVEL, feature)
end
function M.mapName() return mapOf(M.LEVEL).name end
-- free roam (no career): the places plus the map's Wrench Works garages, which a career lists through its garage ladder (progression.garages, remapped at a career's start) and
-- which are therefore missing without one
function M.freeRoamPlaces()
  local out = {}
  for id, p in pairs(M.allPlaces() or {}) do out[id] = p end
  local sites = garageModule('slrr/garageSites')
  for _, site in ipairs(sites and sites.getSites() or {}) do
    if site.id and site.spot and site.dir and not out[site.id] then
      out[site.id] = { id = site.id, kind = 'garage', name = site.name or site.id, pos = site.spot + site.dir * 2, dir = -site.dir }
    end
  end
  return out
end
function M.mapText(text) return progression.mapText(text, M.LEVEL) end

local function levelInstalled(level)
  return core_levels and core_levels.getLevelByName and core_levels.getLevelByName(level) ~= nil or false
end

local function summaryOf(data)
  if not data then return nil end
  local level = progression.levelOf(data)
  local line = string.format(strings.t('career.day_d_d_s_s'), data.day or 1, data.money or 0, (progression.titleFor(data.rep or 0, level)),
    mapOf(level).name, data.ended and ' (ended)' or '')
  if not levelInstalled(level) then line = strings.t('career.this_career_is_on_1_map', mapOf(level).name) .. ' - ' .. line end
  return line
end

-- every map a career can be played on, in order: { id, name, installed }
function M.listMaps()
  local out = {}
  for _, id in ipairs(progression.MAP_ORDER) do
    out[#out + 1] = { id = id, name = progression.MAPS[id].name,
      installed = core_levels and core_levels.getLevelByName and core_levels.getLevelByName(id) ~= nil or false }
  end
  return out
end

-- the career's map: the garage ladder gets that map's Wrench Works sites (one ladder table, read by every module)
local function useMap(level)
  M.LEVEL = level
  local map = mapOf(level)
  for i, g in ipairs(progression.garages) do
    g.site0, g.name0 = g.site0 or g.site, g.name0 or g.name
    local site = map.garages and (map.garages[i] or map.garages[#map.garages])
    g.site, g.name = site and site.id or g.site0, site and site.name or g.name0
  end
end

-- the extension that runs this map's street races (the map's own slrrValoRaces, or the career's sl_races), if loaded
local function raceMod()
  local name = mapOf(M.LEVEL).races
  return name and rawget(_G, name) or nil
end

-- every career there is: { { slot, name, summary, last } }
function M.listSlots()
  local m, out = slotsMeta(), {}
  for n = 1, M.SLOTS do
    if slotUsed(n) then
      local data = readSave(slotFile(n))
      out[#out + 1] = { slot = n, name = m.names[tostring(n)] or (strings.t('career.career_1', (n))), summary = summaryOf(data), last = m.last == n, ended = data and data.ended ~= nil,
        level = progression.levelOf(data), installed = levelInstalled(progression.levelOf(data)) }
    end
  end
  return out
end

function M.hasSave() for n = 1, M.SLOTS do if slotUsed(n) then return true end end return false end

-- a line for the menu: "Day 4 - $12,300 - Street kid" (the career played last)
function M.saveSummary()
  local m = slotsMeta()
  local n = slotUsed(m.last) and m.last or nil
  for i = 1, M.SLOTS do if not n and slotUsed(i) then n = i end end
  return n and summaryOf(readSave(slotFile(n))) or nil
end

function M.renameSlot(n, name)
  n = tonumber(n)
  if not n or not slotUsed(n) or type(name) ~= 'string' then return false end
  local m = slotsMeta()
  name = name:gsub('[%c]', ''):sub(1, 32)
  m.names[tostring(n)] = name ~= '' and name or nil
  writeMeta(m)
  return true
end

-- a career gone for good (not the one being played): its save, its .new and .bak
function M.deleteSlot(n)
  n = tonumber(n)
  if not n or not slotUsed(n) or (active and n == slot) then return false end
  -- parts it had up for sale are held in the save: back onto Wrench Works' shelf (it is shared by every career)
  local data = sl_classifieds and sl_classifieds.returnListed and readSave(slotFile(n))
  if data then sl_classifieds.returnListed(data) end
  for _, f in ipairs({ slotFile(n), slotFile(n) .. '.new', slotFile(n) .. '.bak' }) do if FS:fileExists(f) then FS:removeFile(f) end end
  local m = slotsMeta()
  m.names[tostring(n)] = nil
  writeMeta(m)
  return true
end

function M.getSlot() return slot end

function M.getState() return s end

-- the 0.8.0 economy for a save from before it: offered once on the phone (snapshot field economyOffer), opted in with the button
function M.economyOffer() return active and require('sl/core/economy').pending(s) or nil end
function M.optInEconomy()
  local economy = require('sl/core/economy')
  if not (active and economy.pending(s)) then return false, strings.t('career.economy_none') end
  economy.mark(s)
  local features = require('sl/core/features')
  features.setSaveOff({})
  for _, id in ipairs(economy.PARTS) do extensions.hook('onStreetLegalOption', features.get(id).opt, true) end          -- (each part starts as if its switch had just been turned on)
  changed()
  return true, strings.t('career.economy_on')
end
function M.isActive() return active end

----------------------------------------------------------------------------------------------
-- the wallet: Wrench Works' garage and the map's races spend from and pay into the career

local wallet = {
  get = function() return s and s.money or 0 end,
  add = function(amount, label)
    if not s then return false end
    local ok = stateLib.addMoney(s, amount, label, now())
    if ok then changed() end
    if ok and amount < 0 then extensions.hook('onStreetLegalSpent', -amount, label) end   -- (the bank's insurance looks at repairs)
    return ok
  end,
  walkIn = false,       -- no body shells over the counter: cars come from the lots
  -- on foot in a garage doorway Wrench Works takes you in with this car (your current one, if it is out)
  car = function() return s and s.activeCar and sl_fleet and sl_fleet.vehicleOf(s.activeCar) or nil end,
  -- the garage ladder: the garages above your level are not available (Wrench Works shows no marker and says why at the door)
  garageAccess = function(siteId) return progression.garageAccess(s or {}, siteId) end,
  -- on foot in a garage's doorway: the cars panel on the phone's screen (take another car out, work on one, put one away)
  panel = function(siteId) return sl_phone ~= nil and sl_phone.openGarage ~= nil and sl_phone.openGarage(siteId) == true end,
  -- on foot at the doorway with your car stored in the garage: it is brought out front (My cars' "Drive this one"), then Wrench Works goes in with it
  fetch = function()
    if not (s and sl_fleet) then return false end
    local pick
    for _, c in ipairs(s.cars) do if not c.impounded and (not pick or c.id == s.activeCar) then pick = c end end
    return pick ~= nil and sl_fleet.setActive(pick.id) == true
  end,
}

local function connectWallet(on)
  local parts = garageModule('slrr/garageParts')
  if parts and parts.setMoneyProvider then parts.setMoneyProvider(on and wallet or nil) end
end

-- the cab's fare, charged when it has taken you there: what you have covers it, or what is left; returns what was paid
function M.chargeFare(fee, placeName)
  local paid = require('sl/core/cabplan').fareDue(fee, s and s.money)
  if paid > 0 then wallet.add(-paid, strings.t('career.cab_to_1', placeName)) end
  return paid
end

-- money in and out, from anywhere in the career (negative = paid). Returns ok.
function M.addMoney(amount, label)
  return wallet.add(amount, label)
end

-- money earned (jobs, purses, prizes, sponsors): as much as the career's Pay setting says (sl_options; not
-- sales, refunds or bets, which stay as they are)
function M.payOut(amount, label)
  local k = sl_options and sl_options.get('slEconomy') or 1
  k = k * (sl_weather and sl_weather.bonus and sl_weather.bonus() or 1)        -- a little more in the wet (#45)
  return wallet.add(math.floor((amount or 0) * k / 10 + 0.5) * 10, label)
end

----------------------------------------------------------------------------------------------
-- places on the map: the junkyard, the dealer, the scrap yard, the garages. Read from
-- /street_legal/places/*.json (the map brings them) and the player's own places.json:
-- { "slrr_valo_city": { "places": [ { "id": "junkyard", "kind": "junkyard", "name": "...", "pos": [x, y, z], "dir": [x, y] } ] } }

-- one place from its json shape (the map's file, the player's, or the stock facilities) into places
local function addPlace(p, file)
  local pos = v3(p.pos)
  if type(p.id) == 'string' and pos then
    local function flat(t)
      local d = v3(t)
      if not d then return nil end
      d.z = 0
      return d:length() > 0.01 and d:normalized() or nil
    end
    local place = { id = p.id, kind = tostring(p.kind or p.id), name = tostring(p.name or p.id), pos = pos,
      dir = flat(p.dir) or vec3(0, 1, 0), display = v3(p.display), displayDir = flat(p.displayDir),
      stock = type(p.stock) == 'table' and p.stock or nil,
      stockId = type(p.stockId) == 'string' and p.stockId or nil }      -- (stock: a stock dealer's { kind, filter }, sl_lot)
    -- a lot's display spots, one car each: "displays": [ { "pos": [x, y, z], "dir": [x, y] } ]
    if type(p.displays) == 'table' then
      place.displays = {}
      for _, d in ipairs(p.displays) do
        local dp = type(d) == 'table' and v3(d.pos)
        if dp then place.displays[#place.displays + 1] = { pos = dp, dir = flat(d.dir) or place.displayDir or -place.dir } end
      end
      if #place.displays == 0 then place.displays = nil end
    end
    -- a showroom's way out to the street: "exit": [ [x, y, z] ... ] from inside the door to a city lane
    if type(p.exit) == 'table' then
      place.exit = {}
      for _, q in ipairs(p.exit) do place.exit[#place.exit + 1] = v3(q) end
      if #place.exit == 0 then place.exit = nil end
    end
    -- a lot whose drop-off is the display spot itself: you arrive 8 m in front of the car, facing it
    if place.kind ~= 'meet' and place.display and (place.display - place.pos):length() < 6 then
      local facing = place.displayDir or -place.dir
      place.pos = place.display + facing * 8
      place.dir = -facing
    end
    place.at = place.pos          -- (where the place is: its markers stand here, whatever the lane nudge does to .pos)
    places[p.id] = place
  else
    log('W', logTag, file .. ': a place without "id" or "pos" was left out')
  end
end

-- the map's own dealerships and garages, from the game's facilities (data only: no career module of the game is
-- loaded), as places in the json shape (T12). A map whose progression has no stockFacilities gets none.
-- The level's painted parking bays (the city parking sites parked traffic uses) around a point, and the public roads there
-- (T37). nil, nil while the sites or the navgraph are not loaded yet (baysMissing then asks getPlaces to build the places again).
local baysMissing = false
-- the city parking sites: loaded here if nothing has (the game loads them with a mission, which a freeroam start may not have done),
-- from gameplay_city or, failing that, the level's own city.sites.json through the sites manager
local function citySites()
  pcall(extensions.load, 'gameplay_city')
  if gameplay_city and gameplay_city.getSites then
    if not gameplay_city.getSites() and gameplay_city.loadSites then pcall(gameplay_city.loadSites) end
    local s = gameplay_city.getSites()
    if s then return s end
  end
  pcall(extensions.load, 'gameplay_sites_sitesManager')
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier()
  local file = level and ('/levels/' .. level .. '/city.sites.json')
  if file and gameplay_sites_sitesManager and FS:fileExists(file) then
    local ok, s = pcall(gameplay_sites_sitesManager.loadSites, file)
    if ok and s then return s end
  end
end

function M.paintedBays(o)
  local sites = citySites()
  local okm, nodes = pcall(function() return map.getMap().nodes end)
  if not sites or not okm or type(nodes) ~= 'table' or next(nodes) == nil then
    baysMissing = true
    return nil, nil
  end
  local list = {}
  for _, r in ipairs(sites:getRadialParkingSpots(vec3(o.x, o.y, o.z), 0, stockLib.BAY_RADIUS + 5) or {}) do
    local ps = r.ps
    if ps and ps.pos and ps.rot then
      local d = ps.rot * vec3(0, 1, 0)
      list[#list + 1] = { x = ps.pos.x, y = ps.pos.y, z = ps.pos.z, dx = d.x, dy = d.y, occupied = ps.vehicle ~= nil }
    end
  end
  return list, require('sl/core/roadspot').roadSegments(nodes, o.x, o.y, stockLib.BAY_RADIUS + 40)
end

local told = {}            -- the stock facilities already reported, once each
local function stockApi(level)
  if not progression.has(level, 'stockFacilities') then return nil end
  -- a career can start before the level has loaded the facilities (a scripted load, a restart, the menu): load them
  -- here, and the sites their parking spots are read from
  if extensions and extensions.load then
    pcall(extensions.load, 'freeroam_facilities')
    pcall(extensions.load, 'gameplay_sites_sitesManager')
  end
  local fac = freeroam_facilities
  if not (fac and fac.getFacilitiesByType) then return nil end
  local function tr(key) local ok, t = pcall(translateLanguage, key, key, true) return ok and t or key end
  local function tell1(f, why) if not told[f.id] then told[f.id] = true log('W', logTag, 'stock facility ' .. tostring(f.id) .. ': ' .. why) end end
  return {
    list = function(kind, lvl) return fac.getFacilitiesByType(kind, lvl) end,
    bays = function(o) return M.paintedBays(o) end,
    ownSpots = function()
      local out, sites = {}, garageModule('slrr/garageSites')
      local ok, list = pcall(function() return sites and sites.getSites() or {} end)
      for _, site in ipairs(ok and list or {}) do if site.spot then out[#out + 1] = { x = site.spot.x, y = site.spot.y } end end
      return out
    end,
    spots = function(f)
      local out = {}
      local ok, list = pcall(fac.getParkingSpotsForFacility, f)
      if not ok then tell1(f, strings.t('career.parking_spots_failed_1', (tostring(list)))) end
      for _, sp in ipairs(ok and type(list) == 'table' and list or {}) do
        if sp.pos and sp.rot then
          -- a spot with something above its ground (a kerb) is not a place to stand a car: the ray from 1.5 m up
          -- should reach the spot's own height
          local okg, hit = pcall(function() return sp.pos.z + 1.5 - castRayStatic(vec3(sp.pos.x, sp.pos.y, sp.pos.z + 1.5), vec3(0, 0, -1), 4) end)
          if not okg or not hit or hit <= sp.pos.z + 0.25 then
            local d = sp.rot * vec3(0, 1, 0)
            out[#out + 1] = { x = sp.pos.x, y = sp.pos.y, z = sp.pos.z, dx = d.x, dy = d.y }
          else
            tell1(f, string.format(strings.t('career.a_parking_spot_at_0f'), sp.pos.x, sp.pos.y, hit - sp.pos.z))
          end
        end
      end
      if #out == 0 and ok then tell1(f, strings.t('career.no_parking_spots')) end
      return out
    end,
    door = function(f)
      local ok, c = pcall(fac.getAverageDoorPositionForFacility, f)
      if not (ok and c and (c.x ~= 0 or c.y ~= 0)) then return nil end
      -- the way the first door's area faces (best effort: else the place faces north)
      local dx, dy
      local obj = f.doors and f.doors[1] and scenetree and scenetree.findObject(f.doors[1][1])
      local okr, r = pcall(function() return obj and quat(obj:getRotation()) * vec3(0, 1, 0) end)
      if okr and r then dx, dy = r.x, r.y end
      return { x = c.x, y = c.y, z = c.z, dx = dx, dy = dy }
    end,
  }, tr
end

local placesSig                -- the ids of the places at the last load (to tell the markers when they change)
local lanesPending = false     -- the navgraph was not there yet at the last load of the places
local stockState = {}          -- stockLib.load's: whether the stock places are still to be had (retry), and how often it was tried
local stockTriedAt = -1e9

local function loadPlaces()
  places = {}
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier()
  if not level then return end
  local files = FS:findFiles(PLACES_DIR, '*.json', 0, false, false) or {}
  table.sort(files)
  local mine = {}           -- the map's own places
  for _, file in ipairs(files) do
    local data = FS:fileExists(file) and jsonReadFile(file)
    local here = type(data) == 'table' and data[level]
    for _, p in ipairs(type(here) == 'table' and type(here.places) == 'table' and here.places or {}) do mine[#mine + 1] = p end
  end
  if stockState.level ~= level then stockState = { level = level } end
  stockTriedAt = os.clock()
  local stock = stockLib.load(stockState, level, function() return stockApi(level) end)
  for _, p in ipairs(stockLib.merge(stock, mine)) do addPlace(p, 'places') end      -- (stock wins where it is the same dealer)
  local data = FS:fileExists(USER_PLACES) and jsonReadFile(USER_PLACES)       -- the player's own come last
  local here = type(data) == 'table' and data[level]
  for _, p in ipairs(type(here) == 'table' and type(here.places) == 'table' and here.places or {}) do addPlace(p, USER_PLACES) end
  -- the lots of a map with stock facilities stand where the game's data put them, not where a lane is: a lot whose
  -- nearest city lane is over 60 m away (the car leaves by it) is moved towards the lane, to 45 m (T15)
  lanesPending = baysMissing
  baysMissing = false
  if progression.has(level, 'stockFacilities') then
    local rs = require('sl/core/roadspot')
    local okm, nodes = pcall(function() return map.getMap().nodes end)
    local okr, roadRules = pcall(map.getRoadRules)
    local rhd = okr and roadRules and roadRules.rightHandDrive
    if not okm or type(nodes) ~= 'table' or next(nodes) == nil then
      lanesPending = true            -- (the navgraph is not there yet: getPlaces asks again)
    else
      for _, p in pairs(places) do
        -- the used lot and the scrap yard stand in the map's painted bays too, where there are enough (T37)
        if (p.kind == 'junkyard' or p.kind == 'scrapyard') and p.displays and #p.displays > 0 then
          local plain = {}
          for _, d in ipairs(p.displays) do plain[#plain + 1] = { x = d.pos.x, y = d.pos.y, z = d.pos.z, dx = d.dir.x, dy = d.dir.y } end
          local cands, roads = M.paintedBays(plain[1])
          local used = cands and stockLib.withBays(plain, cands, roads) or plain
          if #used > #plain then
            p.displays = {}
            for _, u in ipairs(used) do p.displays[#p.displays + 1] = { pos = vec3(u.x, u.y, u.z), dir = vec3(u.dx, u.dy, 0):normalized() } end
          end
        end
        if p.kind == 'dealer' or p.kind == 'junkyard' or p.kind == 'scrapyard' then
          local to = rs.towards(p.pos, rs.candidates(nodes, p.pos, not rhd)[1], rs.LOT_REACH, rs.LOT_TARGET)
          if to then p.pos = vec3(to.x, to.y, to.z) end
        end
      end
    end
  end
  -- the garages are Wrench Works' own sites
  local sites = garageModule('slrr/garageSites')
  for _, g in ipairs(progression.garages) do
    for _, site in ipairs(sites and sites.getSites() or {}) do
      if site.id == g.site and not places[g.site] then
        places[g.site] = { id = g.site, kind = 'garage', name = g.name, pos = site.spot + site.dir * 2, dir = -site.dir, level = g.level }
      end
    end
  end
  -- the markers and prompts of the places are drawn from this list: when it changes (the stock places came in late) they are made again
  local ids = {}
  for id in pairs(places) do ids[#ids + 1] = id end
  table.sort(ids)
  local sig = table.concat(ids, ',')
  if sig ~= placesSig then
    placesSig = sig
    extensions.hook('onStreetLegalPlacesChanged')
  end
end

-- EVERY place the player can go to or see on a map, one list for the phone's Map and Cab, the taxi, the routes and the big map's pins: the career's
-- places (getPlaces) plus Wrench Works' parts shops (kind 'shop') and the map's gas stations (kind 'gas'). id -> { id, kind, name, pos, at, dir }.
local gasCache = {}
local function gasStations(level)
  if gasCache.level == level and #gasCache > 0 then return gasCache end
  gasCache = { level = level }
  local gs, fac = freeroam_gasStations, freeroam_facilities
  local f = gs and gs.gasStationCenterRadius and fac and fac.getFacilities and fac.getFacilities(level)
  for _, g in ipairs(f and f.gasStations or {}) do
    local ok, c = pcall(gs.gasStationCenterRadius, g)
    if ok and c and (c.x ~= c.x or c:length() < 0.01) == false then
      local okn, name = pcall(translateLanguage, g.name, g.name, true)
      gasCache[#gasCache + 1] = { id = 'gas_' .. tostring(g.id), kind = 'gas', name = (okn and type(name) == 'string' and name ~= '' and name) or tostring(g.name or g.id), pos = c, at = c, dir = vec3(0, 1, 0) }
    end
  end
  return gasCache
end
function M.allPlaces()
  local out = {}
  for id, p in pairs(M.getPlaces() or {}) do out[id] = p end
  local sites = garageModule('slrr/garageSites')
  for _, sh in ipairs(sites and sites.getShops and sites.getShops() or {}) do
    local pos = sh.pos
    out['shop_' .. sh.id] = { id = 'shop_' .. sh.id, kind = 'shop', name = sh.name or sh.id, pos = pos, at = pos, dir = vec3(0, 1, 0), trade = sh.trade }
  end
  for _, g in ipairs(gasStations(getCurrentLevelIdentifier and getCurrentLevelIdentifier())) do out[g.id] = g end
  return require('sl/core/fasttravel').derive(out, sl_jobs and sl_jobs.pins and sl_jobs.pins() or {})
end

-- the tier of a lot (high / mid / low / junk) and its label, for the cab filter and the big-map card; nil for a place that is not a lot
function M.placeTier(placeId)
  local p = M.getPlaces()[placeId]
  if p and sl_lot and sl_lot.tier then return sl_lot.tier(p) end
  return nil
end

function M.getPlaces()
  -- the stock facilities were not there yet at the first load: ask again, every 3 s, a few times
  if not places or ((stockState.retry or (lanesPending and (stockState.tries or 0) < stockLib.MAX_TRIES)) and os.clock() - stockTriedAt > 3) then loadPlaces() end
  return places
end

-- stand where a place should be (the junkyard's gate, say) and run this in the console
function M.addPlaceHere(kind, name)
  local v = getPlayerVehicle(0)
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier()
  if not v or not level or type(kind) ~= 'string' then return strings.t('career.stand_where_the_place_should') end
  local pos, dir = v:getPosition(), vec3(v:getDirectionVector())
  local data = FS:fileExists(USER_PLACES) and jsonReadFile(USER_PLACES) or {}
  if type(data) ~= 'table' then data = {} end
  data[level] = type(data[level]) == 'table' and data[level] or {}
  local list = type(data[level].places) == 'table' and data[level].places or {}
  local id = kind
  for i = #list, 1, -1 do
    if list[i].id == id then table.remove(list, i) end
  end
  local r = function(x) return math.floor(x * 100 + 0.5) / 100 end
  list[#list + 1] = { id = id, kind = kind, name = name or kind, pos = { r(pos.x), r(pos.y), r(pos.z) }, dir = { r(dir.x), r(dir.y) } }
  data[level].places = list
  if not FS:directoryExists(SAVE_DIR) then FS:directoryCreate(SAVE_DIR, true) end
  jsonWriteFile(USER_PLACES, data, true)
  places = nil
  local text = string.format(strings.t('career.place_s_saved_in_s'), id, USER_PLACES)
  tell(text, 8)
  return text
end

----------------------------------------------------------------------------------------------
-- messages: the phone shows them; some come from the career itself

-- a text from somebody (thread = racer id or 'benny'), arriving after `delay` seconds
function M.sendText(thread, text, delay)
  replyQueue[#replyQueue + 1] = { at = os.clock() + (delay or 0), thread = thread, text = text }
end

local function deliverTexts()
  local i = 1
  while i <= #replyQueue do
    local m = replyQueue[i]
    if os.clock() >= m.at then
      table.remove(replyQueue, i)
      if s then
        stateLib.addMessage(s, m.thread, 'them', m.text, now())
        changed()
        extensions.hook('onStreetLegalText', m.thread, m.text)
      end
    else
      i = i + 1
    end
  end
end

-- new numbers in the phone, as the player becomes known
local function refreshContacts(quiet)
  local added = stateLib.refreshContacts(s)
  if #added > 0 then
    changed()
    if not quiet then
      M.sendText('benny', string.format(strings.t('career.people_are_talking_about_you'), #added), 2)
    end
  end
end

----------------------------------------------------------------------------------------------
-- starting and continuing

local function welcome()
  M.sendText('benny', strings.t('career.welcome_to_1_kid_this', (mapOf(M.LEVEL).name)), 3)
  M.sendText('benny', strings.t('career.street_racers_are_in_your'), 12)
  M.sendText('benny', strings.t('career.press_k_for_the_phone'), 20)
end

-- put the player on foot inside their garage, looking at the door
local function placeInGarage()
  local sites = garageModule('slrr/garageSites')
  local wanted = progression.garages[s.garageLevel] or progression.garages[1]
  local site
  for _, g in ipairs(sites and sites.getSites() or {}) do
    if g.id == wanted.site then site = g end
  end
  if not site then
    log('W', logTag, 'garage ' .. tostring(wanted.site) .. ' is not on this map; the career starts where the level puts you')
    return
  end
  local pos = sites.point(site, 1.5, 1.8, 0.3)
  local rot = quatFromDir(-site.dir, vec3(0, 0, 1))
  local v = getPlayerVehicle(0)
  if v and v:getJBeamFilename() == 'unicycle' then
    spawn.safeTeleport(v, pos, rot, true)                 -- already on foot: just walk in
  elseif gameplay_walk and gameplay_walk.setWalkingMode then
    gameplay_walk.setWalkingMode(true, pos, rot, true)    -- out of whatever car, or out of nothing
    -- the free-roam car the player was in stays where it stood (the default Vivace at its spawn) and overlaps cars delivered or teleported there: it goes (it is no car of the career)
    if v and not (sl_fleet and sl_fleet.carOfVehicle and sl_fleet.carOfVehicle(v:getID())) then v:delete() end
  end
end

-- Ambient traffic: the game spawns it only when ITS freeroam start does (and only with the options set before, see M.start). A level that was already
-- loaded when the career began (the player in freeroam, a scripted load) has none: seen, C5, an empty city with no taxis. Once the level is up (the
-- fade job in begin) and the game is not spawning any, the career asks for its own amount, parked cars too.
local trafficCover        -- the loading screen for the traffic spawn is up
local function ensureTraffic()
  local gt = gameplay_traffic
  if not (gt and gt.setupTrafficHelper and gt.getNumOfTraffic) then return end
  local info = core_levels and core_levels.getLevelByName and core_levels.getLevelByName(M.LEVEL)
  if info and info.supportsTraffic == false then return end
  if (gt.getNumOfTraffic() or 0) > 0 or (core_gamestate and core_gamestate.getLoadingStatus and core_gamestate.getLoadingStatus('traffic')) then return end
  log('I', logTag, 'no traffic in this level: spawning ' .. M.CITY_TRAFFIC .. ' cars driving and ' .. M.CITY_PARKED .. ' parked')
  -- (the game's parking and traffic spawn through core_multiSpawn, a preset extension of its own freeroam start: nil here, seen in game as an error that this pcall hid)
  for _, name in ipairs({ 'core_multiSpawn', 'gameplay_parking' }) do
    if not rawget(_G, name) and extensions and extensions.load then pcall(extensions.load, name) end
  end
  -- the spawn is a stall of 5-6 s with 220-245 ms frames whatever the amount (measured, 3 runs, none without it): hidden behind the game's own loading
  -- screen for traffic, as its freeroam start does; it goes when the game says the cars are in (onTrafficOrParkingReady) or after 40 s
  local cover = core_gamestate and core_gamestate.requestEnterLoadingScreen
  if cover then pcall(core_gamestate.requestEnterLoadingScreen, 'traffic') trafficCover = true end
  local ok, err = pcall(gt.setupTrafficHelper, M.CITY_TRAFFIC, { police = false }, M.CITY_PARKED, {})
  if not ok then log('E', logTag, 'traffic could not be spawned: ' .. tostring(err)) end
  if cover then
    core_jobsystem.create(function(job)
      job.sleep(ok and 40 or 0.1)
      M.onTrafficOrParkingReady()
    end)
  end
end
M.ensureTraffic = ensureTraffic
function M.onTrafficOrParkingReady()
  if not trafficCover then return end
  trafficCover = false
  if core_gamestate and core_gamestate.requestExitLoadingScreen then pcall(core_gamestate.requestExitLoadingScreen, 'traffic') end
end

-- on arrival the visit's cars stand in a row beside the player (the paddock); a car that already has a place (the game was restarted on the trip) keeps it. fleet.restore builds them.
local function visitArrive()
  local v = getPlayerVehicle(0)
  if not (v and s.visit) then return end
  local p, f = v:getPosition(), v:getDirectionVector()
  local slots = visitLib.paddock({ x = p.x, y = p.y, z = p.z }, { x = f.x, y = f.y }, #s.visit.cars)
  for i, id in ipairs(s.visit.cars) do
    for _, car in ipairs(s.cars) do
      if car.id == id and not car.where then
        local sl = slots[i]
        local q = quatFromDir(vec3(sl.face.x, sl.face.y, 0), vec3(0, 0, 1))
        car.where = { pos = { sl.pos.x, sl.pos.y, sl.pos.z }, rot = { q.x, q.y, q.z, q.w } }
      end
    end
  end
  if s.visit.cars[1] then s.activeCar = s.visit.cars[1] end
end

local function begin()
  pending = nil
  active = true
  connectWallet(true)
  places = nil
  local visiting = s.visit and s.visit.active == true
  if visiting then s.visit.arrived = true end          -- (the trip began: the fee is spent)
  if visiting then places = {} else loadPlaces() end          -- (no place of the home world exists on the visited map)
  ensureCelestial()
  ensureBigMap()
  local fresh = not s.begun
  if fresh then
    s.begun = true
    setHour(progression.START_HOUR)
    refreshContacts(true)
    welcome()
  else
    setHour(s.hour or progression.START_HOUR)
  end
  -- (D1) an old save has no phase (state.migrate guesses it from the hour); the clock is put inside it (a visit has no day and night halves)
  local fitted = visiting and hour() or phaseLib.fit(s.phase or 'day', hour())
  setHour(fitted)
  lastHour = hour()
  -- Night set while the level is still loading leaves the picture all white (seen in game: only a
  -- big jump of the clock brings it back, setting the same hour again does not). So once the
  -- loading screen is gone: midday for a moment behind a black fade, then the career's hour.
  local wanted = hour()
  core_jobsystem.create(function(job)
    job.sleep(3)
    if not active then return end
    if guihooks then guihooks.trigger('slFade', { on = true }) end
    job.sleep(0.6)
    pcall(ensureTraffic)
    setHour((wanted + 12) % 24)
    job.sleep(0.5)
    setHour(wanted)
    extensions.hook('onStreetLegalFade', 'start', job)       -- (the screen is black: cars may be built now; a listener that builds inside `job` holds the fade)
    job.sleep(0.3)
    skyReport(string.format(strings.t('career.career_start_clock_2f'), wanted))
    lastHour = hour()
    if guihooks then guihooks.trigger('slFade', { on = false }) end
    -- the level loaded with nobody in it, so the game left its free camera on: follow the player
    if getPlayerVehicle(0) and core_camera.getActiveCamName(0) == 'free' then core_camera.setByName(0, 'orbit') end
    -- started from the main menu's button, the UI stays on the menu screen over the game (seen in
    -- game: the main menu drawn over the garage, taking the keys): on to the play screen
    if ui_router and ui_router.navigate then ui_router.navigate('play') end
  end)
  if visiting then visitArrive() else placeInGarage() end
  changed()
  writeSave()
  extensions.hook('onStreetLegalStarted', fresh)
  if visitEnded then
    extensions.hook('onStreetLegalVisitEnded', visitEnded.was, visitEnded.how, visitEnded.loaners)
    visitEnded = nil
  end
  log('I', logTag, fresh and 'new career started' or 'career continued')
end

-- from the main menu: a new career (fresh = true, in the first free slot: never over another career, on the map
-- `level`: one of MAPS) or a saved one (n, or the one played last; its map is in the save)
local stop                                 -- (defined below)

-- BeamMP: the career is single-player (sl/core/multiplayer)
local mpLib = require('sl/core/multiplayer')
function M.inMultiplayer() return mpLib.inSession(rawget(_G, 'MPCoreNetwork'), rawget(_G, 'MPGameNetwork')) end

function M.start(fresh, n, level, choice)
  if M.inMultiplayer() then tell(mpLib.NOTE, 9) return false end
  if active then stop() end              -- (B26: the career being played is saved and stopped first, so nothing of it carries over)
  local m = slotsMeta()
  local qa = n == 'qa'
  n = not qa and tonumber(n) or nil
  if qa then
    n = 'qa'
  elseif fresh then
    n = nil
    for i = 1, M.SLOTS do if not n and not slotUsed(i) then n = i end end
    if not n then tell(string.format(strings.t('career.all_d_career_slots_are'), M.SLOTS), 6) return false end
  else
    n = n or (slotUsed(m.last) and m.last) or 1
  end
  -- a career that ended (Hardcore: the driver died) can be looked at, not played on
  if not fresh then
    local data = readSave(slotFile(n))
    if data and data.ended then tell(strings.t('career.that_career_is_over_it', (tostring(data.ended.day))), 6) return false end
    -- a saved visit (the game was quit or crashed on a trip): ask first, before any level loads, unless it is over or its map is gone (then it ends by itself below)
    if data and data.visit and data.visit.active and choice ~= 'resume' and choice ~= 'home' then
      if visitLib.recover(data.visit, data.day or 1, levelInstalled(data.visit.level)) == 'ask' then
        tell(strings.t('visit.choose', mapOf(data.visit.level).name, data.visit.round or 1, data.visit.rounds or 1), 9)
        return false, 'visit'
      end
    end
    -- a career on a map that is not here is not loaded (it would open on the wrong map): the slot list says which map it needs
    if data and not qa and not levelInstalled(progression.levelOf(data)) then
      tell(strings.t('career.this_career_is_on_1_map', mapOf(progression.levelOf(data)).name), 8)
      return false
    end
  end
  slot, SAVE_FILE = n, slotFile(n)
  if not qa then
    m.last = n
    writeMeta(m)
  end
  s = (not fresh) and readSave() or nil
  if not s then
    s = stateLib.new((os.time() % 1000000) * 31 + math.random(1, 997), now())
    require('sl/core/economy').mark(s)          -- (a career created now has the 0.8.0 economy; a save without the marker keeps playing as before until it opts in)
    s.level = progression.MAPS[level] and not progression.isVisit(level) and level or progression.DEFAULT_MAP
  end
  require('sl/core/features').setSaveOff(require('sl/core/economy').offFor(s))
  s.level = progression.levelOf(s)      -- (a save from before the maps has no level and is Valo City: it is written into the save the next time the game saves it)
  local target = s.level
  if s.visit and s.visit.active then
    local verdict = visitLib.recover(s.visit, s.day or 1, levelInstalled(s.visit.level))
    if verdict == 'home' or (verdict == 'ask' and choice == 'home') then
      local fee = (s.visit.arrived ~= true and tonumber(s.visit.fee) or 0)          -- (the trip never began: the fee comes back)
      if fee > 0 then stateLib.addMoney(s, fee, strings.t('visit.fee_back'), now()) end
      local was, loaners = visitLib.finish(s)
      visitEnded = { was = was, how = 'missed', loaners = loaners }          -- (the round that was running counts as missed; the cars are in the garage)
    else
      target = s.visit.level
    end
  end
  useMap(target)
  pending = 'start'
  if getCurrentLevelIdentifier and getCurrentLevelIdentifier() == M.LEVEL then
    begin()
  else
    if not freeroam_freeroam then extensions.load('freeroam_freeroam') end
  end
  if pending == 'start' and not (getCurrentLevelIdentifier and getCurrentLevelIdentifier() == M.LEVEL) and freeroam_freeroam and freeroam_freeroam.startFreeroamByName then
    -- the game starts a freeroam level with no traffic unless told (its default trafficMode "fromSetting" loads none): A3, the city was empty
    local sh = freeroam_freeroam.spawningOptionsHelper
    if sh then
      sh.trafficMode, sh.trafficParked = 'enabled', 'enabled'
      sh.trafficAmount, sh.trafficParkedAmount = M.CITY_TRAFFIC, M.CITY_PARKED
    end
    if not freeroam_freeroam.startFreeroamByName(M.LEVEL, nil, false, false) then
      pending = nil
      tell(string.format(strings.t('career.s_s_is_not_installed'), mapOf(M.LEVEL).name, M.LEVEL), 8)
    end
  end
end

-- the career is over (Hardcore: the driver died): saved as ended, and stopped
M.CITY_TRAFFIC, M.CITY_PARKED = 6, 6         -- cars driving and parked in the city (14 + 18 with 45 pedestrians cost about 13 ms a frame on the test machine: 27 ms against 14)
function M.endCareer() if active then stop() end end

stop = function()
  if not active then return end
  pcall(extensions.hook, 'onStreetLegalStopping')          -- (the career is still active and the save not yet written: a module settles what is pending into the save here, e.g. a refund)
  s.hour = hour()
  writeSave()
  connectWallet(false)
  active = false
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  extensions.hook('onStreetLegalStopped')
  require('sl/core/features').setSaveOff({})
  pcall(function() require('sl/racelog').flush() end)       -- (the race log writes at most once a second: what waits goes out now)
  M.onTrafficOrParkingReady()           -- (no loading screen left up)
end

----------------------------------------------------------------------------------------------
-- taxi: on foot, the phone takes you across town

function M.taxi(placeId)
  if not active then return false, strings.t('bank.no_career_running') end
  local place = M.allPlaces()[placeId]
  if not place then return false, strings.t('career.the_cab_does_not_know') end
  local v = getPlayerVehicle(0)
  if not v or v:getJBeamFilename() ~= 'unicycle' then return false, strings.t('career.cabs_are_for_people_on') end
  local fee = progression.taxiFee((v:getPosition() - place.pos):length())
  -- the floor: no car and no money for the fare (a pink slip lost, bets gone wrong): once a day a free
  -- ride, so the jobs that need no car (the junkyard's crushing run) are always in reach
  if s.money < fee and #s.cars == 0 and s.freeRideDay ~= s.day and not (sl_options and sl_options.get('slHardcore')) then
    s.freeRideDay = s.day
    fee = 0
    M.sendText('benny', strings.t('career.my_cousin_will_run_you'), 1)
  end
  if sl_cab and sl_cab.busy() then return false, strings.t('career.a_cab_is_already_waiting') end
  if fee > s.money then return false, string.format(strings.t('career.the_ride_is_d_you'), fee, s.money) end      -- (the fare is charged when the cab gets you there: sl_cab -> chargeFare)
  if sl_cab and sl_cab.call(place, fee) then return true end
  if fee > 0 then wallet.add(-fee, strings.t('career.cab_to_1', (place.name))) end
  -- no lane for a cab to pull up on here: the old way, straight there
  core_jobsystem.create(function(job)
    if guihooks then guihooks.trigger('slFade', { on = true }) end
    job.sleep(0.6)
    spawn.safeTeleport(getPlayerVehicle(0), place.pos + vec3(0, 0, 0.3), quatFromDir(place.dir, vec3(0, 0, 1)), true)
    extensions.hook('onStreetLegalFade', 'travel', job, place)
    job.sleep(0.6)
    if guihooks then guihooks.trigger('slFade', { on = false }) end
    tell(string.format(strings.t('cab.s_that_was_d'), place.name, fee), 4)
  end)
  return true
end

----------------------------------------------------------------------------------------------
-- races arranged on the phone. They are run by the map's night races (slrrValoRaces); see
-- docs/integration.md for the two calls that ties them together.

local raceList            -- the map's night races { id, name, start = vec3, finish = vec3 }
local trackList           -- its circuits and venues (from its mission list)
local listedAt

-- the map lists every race as a BeamNG mission (slrrValoRaces.listRaces): night races and drags
-- for the street, circuits and venues for the garage's Tracks list. Older maps: races.json.
local function missionRaces()
  local rm = raceMod()
  if not (rm and rm.listRaces and rm.launch) then return nil end
  if raceList and listedAt and os.clock() - listedAt < 10 then return raceList end
  local ok, list = pcall(rm.listRaces)
  if not ok or type(list) ~= 'table' then return nil end
  raceList, trackList, listedAt = {}, {}, os.clock()
  for _, r in ipairs(list) do
    local e = { id = r.id or r.missionId, missionId = r.missionId, name = r.name or tostring(r.id), start = v3(r.start), finish = v3(r.finish),
      kind = r.kind, ref = r.ref, laps = r.laps, drag = r.kind == 'drag' }
    if e.start and e.missionId then
      if r.kind == 'night' or r.kind == 'street' or r.kind == 'drag' then raceList[#raceList + 1] = e
      elseif r.ref ~= 'roc' then trackList[#trackList + 1] = e end        -- the ROC is the career's own, behind its rules
    end
  end
  return raceList
end

local function races()
  local listed = missionRaces()
  if listed then return listed end
  if raceList then return raceList end
  raceList = {}
  local data = jsonReadFile('/levels/' .. M.LEVEL .. '/races.json')
  for _, r in ipairs(type(data) == 'table' and data.nightRaces or {}) do
    if v3(r.start) then raceList[#raceList + 1] = { id = r.id, name = r.name or (strings.t('career.race_1', (tostring(r.id)))), start = v3(r.start), finish = v3(r.finish) } end
  end
  -- the drag strip at the test track: the same race menu runs them (races.json "dragRaces")
  for _, r in ipairs(type(data) == 'table' and data.dragRaces or {}) do
    if v3(r.start) then raceList[#raceList + 1] = { id = r.id, name = r.name or (strings.t('career.drag_1', (tostring(r.id)))), start = v3(r.start), finish = v3(r.finish), drag = true } end
  end
  return raceList
end

-- the start line nearest the player (the tutorial's first race)
function M.nearestRace(drag)
  local v = getPlayerVehicle(0)
  local here = v and v:getPosition() or vec3()
  local best, bd
  for _, r in ipairs(races()) do
    if (r.drag == true) == (drag == true) then
      local d = (r.start - here):squaredLength()
      if not bd or d < bd then best, bd = r, d end
    end
  end
  return best
end

-- a start line not too far from the player, picked a bit at random; drag: one of the strip's
local function pickRace(rng, drag)
  local list = {}
  for _, r in ipairs(races()) do if (r.drag == true) == (drag == true) then list[#list + 1] = r end end
  if #list == 0 then return nil end
  local v = getPlayerVehicle(0)
  local here = v and v:getPosition() or vec3()
  local sorted = {}
  for _, r in ipairs(list) do sorted[#sorted + 1] = r end
  table.sort(sorted, function(a, b) return (a.start - here):squaredLength() < (b.start - here):squaredLength() end)
  return sorted[rng:int(math.min(5, #sorted))]
end

-- the racer's answer to a challenge; arranges the race when they say yes
-- kind: 'race' | 'high' | 'pink' | 'drag' (their usual stake, down the test track's strip)
function M.challenge(racerId, kind)
  if not active then return { accept = false, text = strings.t('bank.no_career_running') } end
  local racer = stateLib.racer(s, racerId)
  if not racer or not s.known[racerId] then return { accept = false, text = strings.t('career.number_not_recognised') } end
  if sl_hospital and not sl_hospital.canDrive() then return { accept = false, text = strings.t('career.you_can_barely_walk_mate') } end
  local rng = rngLib.new(rngLib.hash(racerId .. kind .. tostring(now())))
  local drag = kind == 'drag'
  local answer = roster.respond(racer, drag and 'race' or kind, { rep = s.rep, money = s.money, hasCar = #s.cars > 0, pinkTonight = roster.pinkTonight(racer, s.day, s.seed) }, rng)
  if answer.accept and kind == 'pink' and not s.activeCar then
    answer = { accept = false, text = strings.t('career.pink_slips_for_which_car') }
  end
  if answer.accept then
    local race = pickRace(rng, drag)
    if not race then return { accept = false, text = drag and strings.t('career.there_s_no_drag_strip') or strings.t('career.there_s_nowhere_to_race') } end
    for i = #s.challenges, 1, -1 do
      if s.challenges[i].racer == racerId then table.remove(s.challenges, i) end      -- one date per racer
    end
    local c = { id = racerId .. ':' .. now(), racer = racerId, stake = answer.stake, bet = answer.bet, race = race.id, raceName = race.name,
      missionId = race.missionId, nightOnly = racer.nightOnly, at = now() }
    s.challenges[#s.challenges + 1] = c
    answer.challenge = c
    answer.text = strings.t('career.1_meet_at_2', (answer.text), (race.name))
    changed()
  end
  return answer
end

-- raise the stake of an arranged money race by a step, as far as their car makes them willing (and you can pay)
function M.raiseStake(id)
  if not active then return false, strings.t('bank.no_career_running') end
  for _, c in ipairs(s.challenges) do
    if c.id == id then
      local racer = stateLib.racer(s, c.racer)
      if c.stake ~= 'money' or not racer then return false, strings.t('career.nothing_to_raise') end
      c.baseBet = c.baseBet or c.bet
      local cap, bet = roster.maxStake(racer, c.baseBet), c.bet + roster.stakeStep(c.baseBet)
      if bet > cap then return false, string.format(strings.t('career.s_will_not_go_past'), roster.displayName(racer), cap) end
      if bet > s.money then return false, string.format(strings.t('career.d_you_have_d'), bet, s.money) end
      c.bet = bet
      changed()
      return true, string.format('%s: "$%d it is."', roster.displayName(racer), bet)
    end
  end
  return false, strings.t('career.that_race_is_off')
end

function M.cancelChallenge(id)
  for i = #s.challenges, 1, -1 do
    if s.challenges[i].id == id then table.remove(s.challenges, i) changed() return true end
  end
  return false
end

-- The map's night races hold one arranged race at a time: the newest one that can be raced now
-- (a racer who only comes out at night is not handed over in daylight). Kept in step every few seconds.
local registered = false
-- the racer's own car, built while the player drives to the start (when the map's race can take it:
-- slrrValoRaces.acceptsVehicleId); otherwise the map brings a stock car of their class
local ownCar             -- { challenge = id, vid, building }
local function dropOwnCar()
  if ownCar and ownCar.vid then
    local v, rm = getObjectByID(ownCar.vid), raceMod()
    local st = rm and rm.getState and rm.getState()
    if type(st) == 'table' then st = st.phase end      -- (sl_races; the map's returns a string)
    if v and st ~= 'countdown' and st ~= 'racing' then v:delete() end
  end
  ownCar = nil
end

local function updateOwnCar(pick)
  local rm = raceMod()
  if not (rm and rm.acceptsVehicleId) or not (sl_streets and sl_streets.buildRacerCar) then return end
  if not pick then if ownCar then dropOwnCar() end return end
  if ownCar and ownCar.challenge ~= pick.id then dropOwnCar() end
  local start
  for _, r in ipairs(races()) do if r.id == pick.race then start = r.start end end
  local v = getPlayerVehicle(0)
  if not start or not v then return end
  local d = (v:getPosition() - start):length()
  if not ownCar and d < 400 and d > 120 then
    ownCar = { challenge = pick.id, building = true }
    local mine = ownCar
    sl_streets.buildRacerCar(pick.racer, start + vec3(0, 0, 0.5), nil, function(veh)    -- waiting on the start line; the race lines it up
      if ownCar ~= mine then if veh then veh:delete() end return end
      mine.building, mine.vid = false, veh and veh:getID() or nil
      registered = nil                                     -- hand it over with the car
    end)
  elseif ownCar and not ownCar.building and d > 900 then
    dropOwnCar()
    registered = nil
  end
end

-- what the map's race needs to know about an arranged race (slrrValoRaces.launch's offer)
local function offerFor(c, vid)
  local racer = stateLib.racer(s, c.racer)
  if not racer then return nil end
  return { name = roster.displayName(racer), racerId = racer.id, class = racer.class, skill = racer.skill,
    aggression = sl_streets and sl_streets.aggression and sl_streets.aggression(racer.skill) or 0.6,
    stake = c.stake, bet = c.bet, car = racer.car and racer.car.name, vehicleId = vid, laps = c.laps }
end

local function syncChallenge()
  local rm = raceMod()
  if not (rm and (rm.startChallenge or rm.launch)) then return end
  local night = M.isNight()
  local pick
  for _, c in ipairs(s.challenges) do
    if not c.nightOnly or night then pick = c end
  end
  updateOwnCar(pick)
  if rm.launch and missionRaces() then return end           -- started from here, at the line (checkChallengeArrival)
  local key = pick and (pick.id .. ':' .. tostring(ownCar and ownCar.vid)) or false
  if key == registered then return end
  registered = key
  if not pick then
    rm.startChallenge(nil)
    return
  end
  local racer = stateLib.racer(s, pick.racer)
  rm.startChallenge(pick.race, { name = roster.displayName(racer), racerId = racer.id, class = racer.class,
    skill = racer.skill, aggression = sl_streets and sl_streets.aggression and sl_streets.aggression(racer.skill) or 0.6, stake = pick.stake, bet = pick.bet,
    car = racer.car and racer.car.name, vehicleId = ownCar and ownCar.vid or nil })
end

-- point the way to a race start (or a place) on the road
function M.waypoint(what)
  if not active or not core_groundMarkers then return end
  local target
  for _, c in ipairs(s.challenges) do
    if c.id == what then
      for _, r in ipairs(races()) do if r.id == c.race then target = r.start end end
    end
  end
  local place = not target and M.getPlaces()[what]
  if place then target = place.pos end
  if target then core_groundMarkers.setPath(target) end
end

-- The street racers waiting at one of the map's night races: the career's own crowd, the
-- ones whose reputation is near the player's (see docs/integration.md). Nil without a career.
-- Returns up to count of { racerId, name, class, skill, bet, pinkOK, tier }.
function M.racersForRace(raceId, count)
  if not active then return nil end
  count = count or 5
  local rng = rngLib.new(rngLib.hash(tostring(raceId) .. ':' .. s.day .. ':' .. math.floor(hour())))
  local pool = {}
  for _, r in ipairs(s.racers) do
    if math.abs(r.rep - s.rep) < 800 + s.rep * 0.6 then pool[#pool + 1] = r end
  end
  if #pool < count then pool = {} for _, r in ipairs(s.racers) do pool[#pool + 1] = r end end
  local out = {}
  while #out < count and #pool > 0 do
    local r = table.remove(pool, rng:int(#pool))
    out[#out + 1] = { racerId = r.id, name = roster.displayName(r), class = r.class, skill = r.skill,
      bet = math.floor(rng:range(r.betMin, r.betMax) / 50 + 0.5) * 50, pinkOK = r.pinkOK, tier = r.tier }
  end
  table.sort(out, function(a, b) return a.bet < b.bet end)
  return out
end

-- tonight's themed meet (Drivers & Pedestrians, X54): Benny passes it on
function M.onSlrrMeetTheme(t)
  if active and type(t) == 'table' and type(t.text) == 'string' then M.sendText('benny', t.text, 2) end
end

-- a pink slip won: the map hands the car over out of the player's sight; it is driven to your garage's
-- forecourt (as it is, dents and all), its driver gets out, and it is in My cars
function M.onSlrrPinkCarDelivered(vid)
  local veh = active and getObjectByID(vid)
  if not veh or not sl_fleet or sl_fleet.carOfVehicle(vid) then return end
  local won = M._pinkWon or {}
  M._pinkWon = nil
  if slrrDrivers and slrrDrivers.setDriver then slrrDrivers.setDriver(vid, nil) end
  veh:queueLuaCommand('ai.setMode("disabled")')
  local pos, rot = sl_fleet.freeForecourt(s, #s.cars % 6, vid)
  if not pos then pos, rot = sl_fleet.forecourt(s, #s.cars % 6) end
  if pos then spawn.safeTeleport(veh, pos, rot, true, nil, nil, nil, false) end     -- (8th: resetVehicle would repair it)
  sl_fleet.registerVehicle(vid, { name = won.name or veh:getJBeamFilename(), condition = 0.85, value = won.value })   -- (B32: a value, so resale and scrap price it)
  M.sendText('benny', string.format(strings.t('career.your_new_s_is_outside'), won.name or 'car'), 2)
end

-- the map's race code tells us how a race went (see docs/integration.md):
-- r = { won, stake = 'money'|'pink', bet, raceId, opponent = name }
function M.onSlrrRaceFinished(r)
  if not active or type(r) ~= 'table' then return end
  local challenge
  for i, c in ipairs(s.challenges) do
    if c.race == r.raceId or (r.missionId and c.missionId == r.missionId) then challenge = c table.remove(s.challenges, i) break end
  end
  -- the money has moved already: the map's races pay through the shared wallet. Without Wrench Works there is no
  -- shared wallet (the map keeps its own) so the bet is settled here (gate M1, B28)
  if r.stake == 'money' and tonumber(r.bet) and r.bet > 0 and not garageModule('slrr/garageParts') then
    wallet.add(r.won and r.bet or -r.bet, strings.t('career.1_a_street_race_2', (r.won and 'Won' or 'Lost'), (r.opponent and (' against ' .. tostring(r.opponent)) or '')))
  end
  local racer = (challenge and challenge.racer) or (type(r.racerId) == 'string' and stateLib.racer(s, r.racerId) and r.racerId) or nil
  local repBefore = s.rep
  local h = hour()
  local repDelta = progression.raceResult({ won = r.won, stake = r.stake, bet = r.bet, night = M.isNight(),
    opponentRep = racer and stateLib.racer(s, racer).rep or 300, playerRep = s.rep })
  if repDelta > 0 then repDelta = math.floor(repDelta * heatLib.repBoost(s.phase, sl_police and sl_police.level and sl_police.level() or 0) + 0.5) end     -- (D3) the hotter, the more it counts
  stateLib.addRep(s, repDelta)
  s.stats.races = s.stats.races + 1
  if r.won then s.stats.wins = s.stats.wins + 1 end
  if racer then
    local x = stateLib.racer(s, racer)
    if r.won then x.losses = x.losses + 1 else x.wins = x.wins + 1 end
    M.afterRace(racer, r.won, tonumber(r.margin))
    extensions.hook('onStreetLegalRaceResult', r.won, r.opponent, racer, r.stake)
  end
  -- an abandoned pink-slip race (false start, out of time, the opponent gone) costs no car: the map leaves it with you
  if r.stake == 'pink' and sl_fleet and not r.abandoned then
    if r.won then
      -- their car is yours: the map stops it and, once out of sight, hands it over (onSlrrPinkCarDelivered)
      M._pinkWon = { name = r.opponent and (r.opponent .. strings.t('career.s_car')) or nil, vid = r.opponentVid, value = tonumber(r.value) }
      s.stats.pinksWon = s.stats.pinksWon + 1
      extensions.hook('onStreetLegalPinkSlip', true, r.opponent)
    elseif not r.won then
      local gone = sl_fleet.lastGone
      if gone and os.clock() - gone.at < 5 then sl_fleet.lose(gone.carId) end
      s.stats.pinksLost = s.stats.pinksLost + 1
      extensions.hook('onStreetLegalPinkSlip', false, r.opponent)
      -- no free car to drive home in: you walk. The map swaps your car for a runabout only after
      -- this hook (seen in game: the player was left in a free Covet on the start line), so look
      -- again once it has
      core_jobsystem.create(function(job)
        job.sleep(1.5)
        local p = getPlayerVehicle(0)
        if p and not sl_fleet.carOfVehicle(p:getID()) and p:getJBeamFilename() ~= 'unicycle' then
          local id = p:getID()
          if gameplay_walk then gameplay_walk.setWalkingMode(true, nil, nil, true) end
          job.sleep(0.8)
          local x = getObjectByID(id)
          if x then x:delete() end
        end
      end)
    end
  end
  registered = nil
  tell(string.format(strings.t('career.s_d_reputation_s'), repDelta >= 0 and '+' or '', repDelta, (progression.titleFor(s.rep, M.LEVEL))), 5)
  if (progression.titleFor(s.rep)) ~= (progression.titleFor(repBefore)) then
    M.sendText('benny', strings.t('career.they_call_you_1_on', (progression.titleFor(s.rep, M.LEVEL))), 3)
  end
  refreshContacts(false)
  changed()
end

-- a race started from its marker on the map, with no offer from us: an arranged race there brings
-- its racer and stake; anything else is raced for nothing
function M.onSlrrRaceOffer(missionId, req)
  if not active or type(req) ~= 'table' then return end
  for _, c in ipairs(s.challenges) do
    if c.missionId == missionId then
      req.offer = offerFor(c, ownCar and ownCar.challenge == c.id and ownCar.vid or nil)
      return
    end
  end
end

-- the circuits and venues the map lists, for the garage's Tracks list (nil: an older map)
-- (only once the map's circuit missions put our racer's own car on the grid: slrrValoRaces.circuitOpponents;
-- before that the stock race brings its own cars, and Street Legal's own track race is used instead)
function M.tracksList()
  if not M.has('tracks') or not missionRaces() or not raceMod().circuitOpponents then return nil end
  return trackList
end

-- a race at one of them against a racer: their car is built at the start, then the mission takes over
function M.launchTrack(racerId, missionId)
  if not active then return false, strings.t('bank.no_career_running') end
  local racer = stateLib.racer(s, racerId)
  local track
  for _, t in ipairs(M.tracksList() or {}) do if t.missionId == missionId then track = t end end
  if not racer or not track then return false, strings.t('career.that_race_is_not_on') end
  if not (sl_streets and sl_streets.buildRacerCar) then return false, strings.t('career.not_now') end
  local bet = math.floor(((racer.betMin or 100) + (racer.betMax or 300)) / 2 / 50) * 50
  for i = #s.challenges, 1, -1 do if s.challenges[i].racer == racerId then table.remove(s.challenges, i) end end
  local c = { id = racerId .. ':track:' .. now(), racer = racerId, stake = 'money', bet = bet, race = track.id, raceName = track.name,
    missionId = missionId, laps = track.laps, at = now() }
  s.challenges[#s.challenges + 1] = c
  changed()
  sl_streets.buildRacerCar(racerId, track.start + vec3(0, 0, 0.5), nil, function(veh)
    raceMod().launch(missionId, offerFor(c, veh and veh:getID() or nil))
  end)
  return true, string.format(strings.t('career.s_against_s_for_d'), track.name, roster.displayName(racer), bet)
end

-- after a race against a contact (the map's races, sl_races and sl_streets all end up here): now and then a text
-- (a sore loser, or a winner's mockery), and a racer you beat will not race you again until they text for a
-- rematch some game hours later (roster.afterRace keeps the state in the racer's record)
function M.afterRace(racerId, won, margin)
  local x = active and type(racerId) == 'string' and stateLib.racer(s, racerId)
  if not x then return end
  local rng = rngLib.new(rngLib.hash(racerId .. ':after:' .. s.day .. ':' .. #s.ledger))
  local r = roster.afterRace(x, won, margin, rng)
  if r.taunt then M.sendText(racerId, r.taunt, 20 + rng:range(0, 40)) end
  -- game hours (the day turns at six: a rematch due across it comes at six, which is fine)
  if r.rematchIn then x.rematchAt = s.day * 24 + hour() + r.rematchIn end
  changed()
end
M.rematchMaybe = function(racerId) M.afterRace(racerId, true) end   -- (older callers)

local function dueRematches()
  local t = s.day * 24 + hour()
  for _, x in ipairs(s.racers) do
    if x.rematchAt and t >= x.rematchAt then
      x.rematchAt = nil
      s.known[x.id] = true
      M.sendText(x.id, roster.rematchText(x, rngLib.new(rngLib.hash(x.id .. ':rematch:' .. math.floor(t)))), 1)
      changed()
    end
  end
end

-- with a race arranged, arriving at its start brings the racer (when the map's races can be told)
local function checkChallengeArrival()
  local v = getPlayerVehicle(0)
  if not v or v:getJBeamFilename() == 'unicycle' or #s.challenges == 0 then return end
  local pos = v:getPosition()
  for _, c in ipairs(s.challenges) do
    for _, r in ipairs(races()) do
      if r.id == c.race and (pos - r.start):length() < 8 and v:getVelocity():length() < 1.5 and not c.notified then
        c.notified = true
        local racer = stateLib.racer(s, c.racer)
        if c.nightOnly and not M.isNight() then
          tell(strings.t('career.1_only_races_at_night', (roster.displayName(racer))), 6)
          c.notified = false
        elseif raceMod() and raceMod().launch and r.missionId then
          -- the race is a BeamNG mission now: start it with them in it
          raceMod().launch(r.missionId, offerFor(c, ownCar and ownCar.challenge == c.id and ownCar.vid or nil))
        elseif raceMod() and raceMod().startChallenge then
          -- handed over already (syncChallenge): the start marker brings them
        else
          tell(strings.t('career.1_is_here_pick_them', (roster.displayName(racer))), 6)
        end
      end
    end
  end
end

----------------------------------------------------------------------------------------------
-- moving up: a bigger garage, once the name and the money are there

-- the impound: pay what is owed and the car is back at your garage
function M.releaseCar(carId)
  if not active then return false, strings.t('bank.no_career_running') end
  for _, car in ipairs(s.cars) do
    if car.id == carId and car.impounded then
      if not M.addMoney(-car.impounded, strings.t('career.impound_1', (car.name))) then return false, string.format(strings.t('carcare.it_is_d_you_have'), car.impounded, s.money) end
      car.impounded = nil
      car.out, car.where = false, nil
      changed()
      return true, strings.t('career.the_1_is_back_in', (car.name))
    end
  end
  return false, strings.t('career.nothing_of_yours_is_impounded')
end

function M.moveGarage()
  if not active then return false, strings.t('bank.no_career_running') end
  local n = progression.nextGarage(s)
  if not n then return false, strings.t('career.this_is_the_best_garage') end
  if not n.canMove then return false, n.garage.name .. ' ' .. n.why .. '.' end
  if not M.addMoney(-n.garage.cost, strings.t('career.moved_to_1', (n.garage.name))) then return false, strings.t('career.not_enough_money') end
  local fromLevel = s.garageLevel
  s.garageLevel = n.garage.level
  places = nil
  extensions.hook('onStreetLegalGarageMoved', fromLevel, s.garageLevel, n.garage.cost)
  changed()
  M.sendText('benny', strings.t('career.welcome_to_1_your_cars', (n.garage.name)), 2)
  return true, strings.t('career.you_now_work_out_of', (n.garage.name))
end

----------------------------------------------------------------------------------------------
-- the police (the game's own pursuits, when traffic has police in it)

function M.onPursuitAction(id, action, pursuit)
  if not active then return end
  local v = getPlayerVehicle(0)
  if not v or v:getID() ~= id then return end
  if action == 'arrest' then
    if sl_justice and sl_justice.ticketInstead then                                     -- (P8: a pull-over at mode 1 is a ticket on the phone, not a bust; an error there is a bust as before)
      local okT, isT = pcall(sl_justice.ticketInstead, pursuit)
      if okT and isT then return end
    end
    local offences = type(pursuit) == 'table' and type(pursuit.offensesList) == 'table' and #pursuit.offensesList or 1
    local racing = sl_streets and sl_streets.isRacing()
    if racing then sl_streets.forfeit() end
    local ph = M.phase()
    local level = sl_police and sl_police.level and sl_police.level() or 0
    local owed = math.floor(heatLib.fine(progression.policeFine(offences, racing), ph, level) * (sl_perks and sl_perks.factor('fines') or 1) + 0.5)
    local fine = math.min(s.money, owed)
    if fine > 0 then M.addMoney(-fine, strings.t('career.police_fine')) end
    local lost = 0
    M.atRisk()                            -- (settles bankedRep first)
    if ph == 'night' then                 -- (D3) a bust at night: the unbanked reputation goes, and the heat goes up
      s.rep, lost = heatLib.afterBust(ph, s.rep, s.bankedRep)
      stateLib.addRep(s, progression.ARREST_REP)
      s.bankedRep = math.min(s.bankedRep or 0, s.rep)
      s.heat = heatLib.raised(s.heat, heatLib.BUST)
    end
    -- could not pay it all, or the heat is 4 or 5: the car goes to the impound until the rest is paid (as in SLRR)
    local impound = heatLib.impounds(ph, level)
    local why = sl_police and sl_police.bustCause and sl_police.bustCause(pursuit) or ''      -- (the cause, in words, in front of the message)
    local car = (owed > fine or impound) and sl_fleet and sl_fleet.currentCar()
    if car then
      car.impounded = math.max(0, owed - fine) + (impound and heatLib.impoundFee(level) or 500)
      car.out = false
      local veh = sl_fleet.vehicleOf(car.id)
      if gameplay_walk then gameplay_walk.setWalkingMode(true, nil, nil, true) end
      if veh then core_jobsystem.create(function(job) job.sleep(1) if veh then veh:delete() end end) end
      tell(why .. string.format(strings.t('career.busted_and_you_cannot_pay'), car.name, car.impounded), 9)
    else
      tell(why .. string.format(strings.t('career.busted_d_in_fines_s'), fine, racing and strings.t('career.and_the_race_is_lost') or '', lost > 0 and string.format(strings.t('career.and_the_d_reputation_you'), lost) or ''), 7)
    end
    extensions.hook('onStreetLegalBusted', fine, car and car.impounded or 0, car and car.name or nil)      -- (for the screen banners)
    changed()
  elseif action == 'evade' then
    -- the escape pays by heat, and for each roadblock passed and strip survived (core/chase)
    local rep = require('sl/core/chase').escapeRep(progression.EVADE_REP, M.phase(), sl_police and sl_police.level and sl_police.level() or 0,
      type(pursuit) == 'table' and pursuit.roadblocks or 0, sl_police and sl_police.stripsSurvived and sl_police.stripsSurvived() or 0)
    stateLib.addRep(s, rep)
    if M.phase() == 'night' then s.heat = heatLib.raised(s.heat, heatLib.ESCAPE) end        -- (D3) a chase is heat, even one you got out of
    tell(string.format(strings.t('career.you_lost_them_d_reputation'), rep), 5)
    changed()
  end
end

----------------------------------------------------------------------------------------------
-- the clock: a new day at six in the morning

-- dusk: Benny hears who is putting their car up for pink slips tonight (somebody you can call)
local function pinkTipOff()
  local names = {}
  for _, r in ipairs(s.racers) do
    if s.known[r.id] and roster.pinkTonight(r, s.day, s.seed) then
      names[#names + 1] = roster.displayName(r) .. (r.car and r.car.name and (' (' .. r.car.name .. ')') or '')
    end
  end
  if #names > 0 then
    M.sendText('benny', strings.t('career.word_is_1_2_putting', (table.concat(names, ' and ')), (#names == 1 and ' is' or ' are')), 1)
  end
end

-- (D1) the phase runs out: the clock stops at its end hour and stays there until the player switches (a new day starts only when the day is started)
local clockHeld = false
local switching = false          -- a phase switch is moving the clock behind a fade (the hold below must not touch it)
local function updateClock()
  local h = hour()
  if switching then lastHour = h return end
  if s.phase and not (s.visit and s.visit.active) and phaseLib.ended(s.phase, h) then
    if not clockHeld then
      clockHeld = true
      setHour(phaseLib.fit(s.phase, h))
      tell(strings.t(s.phase == 'night' and 'phase.nightOver' or 'phase.dayOver'), 8)
      extensions.hook('onStreetLegalPhaseEnded', s.phase)
    end
  else
    clockHeld = false
  end
  lastHour = h
end

----------------------------------------------------------------------------------------------
-- game hooks

local skyTimer = 0
local mpTimer = 0
local function onUpdate(dtReal)
  mpTimer = mpTimer + dtReal
  if mpTimer > 3 then
    mpTimer = 0
    if M.inMultiplayer() then
      if pending == 'start' then pending = nil tell(mpLib.NOTE, 9) end
      if active then stop() tell(mpLib.NOTE, 9) end                 -- (joined a server with a career running: saved and stopped)
    end
  end
  if pending == 'start' and getCurrentLevelIdentifier and getCurrentLevelIdentifier() == M.LEVEL and worldReadyState == 2 then
    begin()
  end
  if not active then return end
  deliverTexts()
  updateClock()
  skyTimer = skyTimer + dtReal
  if skyTimer > 1 then skyTimer = 0 skyFollow() ensureBigMap() end        -- (no core_celestial: the sun follows the running clock)
  checkChallengeArrival()
  syncTimer = syncTimer + dtReal
  if syncTimer > 2 then syncTimer = 0 syncChallenge() dueRematches() end
  saveTimer = saveTimer + dtReal
  if dirty and saveTimer > 3 then
    saveTimer = 0
    s.hour = hour()
    writeSave()
  end
end

local function onClientEndMission()
  stop()
  pcall(function() require('sl/racelog').flush() end)
  raceList, places = nil, nil
end

M.onUpdate = onUpdate
M.onClientEndMission = onClientEndMission
M.onExtensionUnloaded = stop

-- for the phone
M.hour = hour

-- wait: to the next morning or a few hours on (progression.skipPlan); the clock, the day counter and everything that follows
-- the clock (shop hours, deliveries, listings) move together. false and the reason when it cannot be done now.
-- a developer button on the phone's Settings: the money jumps to 99,999,999 (Connor's request, for testing)
function M.devMoney()
  if not s then return false, strings.t('bank.no_career_running') end
  local add = 99999999 - s.money
  if add > 0 then stateLib.addMoney(s, add, strings.t('career.developer_all_the_money'), now()) changed() end
  return true, strings.t('career.money_99_999_999')
end

local function busyState()
  return { racing = sl_streets and sl_streets.isRacing and sl_streets.isRacing(), job = s.jobs and s.jobs.active ~= nil,
    heat = (sl_police and sl_police.inPursuit and sl_police.inPursuit()) and 1 or 0 }      -- (D3: heat is a level that fades; only a chase on you stops the clock)
end

-- the trip: spec = { level (a visit map), cars = { carId }, event, entry (the fee of the event), untilDay, rounds, fits = function(car) -> bool }. The way out costs the entry and
-- VISIT.FEE_PER_CAR a car; the career is saved, stopped and started again on the other map. Returns ok, text.
function M.depart(spec)
  if not active then return false, strings.t('bank.no_career_running') end
  if s.visit and s.visit.active then return false, strings.t('visit.already') end
  if M.inMultiplayer() then return false, mpLib.NOTE end
  if not progression.isVisit(spec.level) or not levelInstalled(spec.level) then return false, strings.t('visit.map_missing') end
  local busy = busyState()
  if busy.racing or busy.job or (busy.heat or 0) > 0 then return false, strings.t('visit.not_now') end
  local ok, why = visitLib.validate(s, spec.cars, spec.fits)
  if not ok then return false, why end
  local fee = visitLib.fee(spec.entry, #spec.cars)
  if not stateLib.addMoney(s, -fee, strings.t('visit.fee_label', mapOf(spec.level).name), now()) then return false, strings.t('visit.cannot_afford', fee) end
  local visit = visitLib.new({ level = spec.level, event = spec.event, cars = spec.cars, day = s.day, untilDay = spec.untilDay or (s.day + 7), rounds = spec.rounds, round = 1, home = s.level, series = spec.series, firstDay = spec.firstDay, fee = fee })
  stop()                                   -- (the cars out at home are noted in the save first, then dropped below)
  visitLib.depart(s, visit)
  local h = (s.hour or 12) + visitLib.TRAVEL_HOURS                   -- the trip takes hours; the day hooks catch up by date (bills, reviews)
  if h >= 24 then s.day = s.day + 1 h = h - 24 end
  s.hour, s.phase = h, 'day'
  writeSave()
  M.start(false, slot, nil, 'resume')           -- (the player has chosen: no question about the visit)
  return true, strings.t('visit.departed', mapOf(spec.level).name)
end

-- the way home (always possible): the visit's cars go to the garage, the career starts again on the home map
function M.returnHome(how)
  if not active then return false, strings.t('bank.no_career_running') end
  if switching then return false, strings.t('career.one_moment') end          -- (the clock is moving: a moment)
  if not (s.visit and s.visit.active) then return false, strings.t('visit.not_on_a_trip') end
  if sl_series and sl_series.closeVisit and (sl_series.closeVisit() or 0) > 0 and (how == nil or how == 'done') then how = 'missed' end      -- (rounds left: the visit ends as missed)
  if how == 'forfeit' then how = 'missed' end
  stop()                                   -- (saves where the cars stand on the visited map; they are put in the garage now)
  local was, loaners = visitLib.finish(s)
  visitEnded = { was = was, how = how or 'done', loaners = loaners }
  writeSave()
  M.start(false, slot)
  return true, strings.t('visit.home')
end

function M.visit() return s and s.visit and s.visit.active and s.visit or nil end
function M.isBusy() if not s then return false end local b = busyState() return (b.racing or b.job or (b.heat or 0) > 0) and true or false end
function M.homeLevel() return s and progression.levelOf(s) or nil end
-- for the main menu: the visit a saved career holds, { level, name, round, rounds, untilDay, expired }, or nil
function M.slotVisit(n)
  local data = readSave(slotFile(n))
  local v = data and data.visit
  if not (v and v.active) then return nil end
  return { level = v.level, name = mapOf(v.level).name, round = v.round or 1, rounds = v.rounds or 1, untilDay = v.untilDay,
    verdict = visitLib.recover(v, data.day or 1, levelInstalled(v.level)) }
end

-- (D1) the phase API, for every module that depends on the time of the game:
--   sl_career.phase() -> 'day' | 'night' (nil with no career)      the hook onStreetLegalPhase(phase, day) when it is switched
--   onStreetLegalPhaseEnded(phase) when the clock has run out and stood still
function M.phase() return s and ((s.visit and s.visit.active) and 'day' or s.phase or 'day') or nil end
-- the night is a phase now, not a clock range (D2): everything that was 'after dark' asks this
function M.isNight() return M.phase() == 'night' end

-- is the player free to be taken into something that moves the car (a calendar race, a scene)? nil when free, else the reason: a race, a job,
-- a chase, a phase switch or a wait behind a fade, a cinematic, an open lot
function M.freeToStart()
  if not s then return strings.t('bank.no_career_running') end
  if switching or (sl_scenes and sl_scenes.isActive and sl_scenes.isActive()) then return strings.t('career.not_now') end
  if sl_lot and sl_lot.isOpen and sl_lot.isOpen() then return strings.t('career.not_now') end
  return progression.skipRefusal(busyState())
end

-- (D3) the night's reputation is at risk until it is banked: at a garage, or by switching phase
function M.atRisk()
  if not s then return 0 end
  s.bankedRep = math.min(s.bankedRep or 0, s.rep)          -- (reputation lost since the bank is not there to lose again)
  return heatLib.atRisk(M.phase(), s.rep, s.bankedRep)
end
function M.bankRep()
  if not s then return 0 end
  local n = M.atRisk()
  s.bankedRep = s.rep
  if n > 0 then changed() end
  return n
end

-- Moves the clock so that the SKY really follows. A small jump of the TimeOfDay value can leave the sun where it was (seen in game: hour 21, sun up),
-- so the clock goes by way of the opposite hour first, as the start of a career does. Then the sun is read back: at a night hour it should be below
-- the horizon; if not, one wider detour, and the elevations go to the log (sl_career) either way. Runs inside a job (it sleeps).
local function moveClock(h, job)
  ensureCelestial()
  skyReport(strings.t('career.before_the_jump_to_1', (string.format('%.2f', h))))
  setHour((h + 12) % 24)
  job.sleep(0.35)
  skyReport(strings.t('career.on_the_opposite_hour'))
  setHour(h)
  job.sleep(0.35)
  skyReport(strings.t('career.on_the_hour'))
  local el = sunElevation()
  log('I', 'sl_career', string.format('clock set to %.2f: sun elevation %s', h, el and string.format('%.1f deg', el) or 'unknown'))
  if el and phaseLib.isDarkHour(h) and el > 0 then
    setHour((h + 6) % 24)
    job.sleep(0.5)
    setHour(h)
    job.sleep(0.5)
    el = sunElevation()
    log('W', 'sl_career', string.format('the sun was up at night hour %.2f; after a wider detour: %s', h, el and string.format('%.1f deg', el) or 'unknown'))
  end
end

-- "Start the night" / "Start the day" (a garage computer, the phone's Wait app): the phase turns over, the clock jumps to its first hour behind a
-- short fade (the day counter goes up with a new day) and runs on. false and the reason when it cannot be done now.
-- on a visit the day is slept: the next morning at 07:00, the day counter up by one and the day hooks fired (bills, reviews, the next round of a series)
local function visitSleep()
  local why = progression.skipRefusal(busyState())
  if why then return false, why end
  s.day = s.day + 1
  extensions.hook('onStreetLegalNewDay', s.day)
  if core_jobsystem and core_jobsystem.create and guihooks then
    switching = true
    guihooks.trigger('slFade', { on = true })
    core_jobsystem.create(function(job)
      job.sleep(0.6)
      local ok, err = pcall(moveClock, 7, job)
      if not ok then log('E', logTag, 'the morning could not be set: ' .. tostring(err)) end
      lastHour = hour()
      switching = false                                 -- (released whatever happened: a lock left set would stop every later phase change)
      job.sleep(0.3)
      guihooks.trigger('slFade', { on = false })
    end)
  else
    setHour(7)
    lastHour = hour()
  end
  changed()
  return true, strings.t('phase.newDay', s.day)
end

function M.switchPhase()
  if not s then return false, strings.t('bank.no_career_running') end
  if switching then return false, strings.t('career.one_moment') end
  if s.visit and s.visit.active then return visitSleep() end
  local plan, why = phaseLib.switchPlan(s.phase or 'day', busyState())
  if not plan then return false, why end
  s.phase = plan.phase
  clockHeld = false
  s.bankedRep = s.rep                    -- (D3) switching banks what the night earned
  if plan.phase == 'day' then s.heat = 0 end        -- heat only exists at night
  if plan.day then
    s.day = s.day + 1
    extensions.hook('onStreetLegalNewDay', s.day)
  else
    pinkTipOff()
  end
  if core_jobsystem and core_jobsystem.create and guihooks then
    switching = true
    local function move(job) moveClock(plan.to, job) lastHour = hour() end
    -- a cinematic moment (sl_scenes, docs/TRANSITIONS.md) takes the place of the plain fade when it is on; false when there is no scene: the plain fade below, as before
    local scene = sl_scenes and sl_scenes.run and sl_scenes.run(plan.phase == 'day' and 'day' or 'night', { day = s.day }, move, function() switching = false end)
    if not scene then
      guihooks.trigger('slFade', { on = true })
      core_jobsystem.create(function(job)
        job.sleep(0.6)
        move(job)
        switching = false
        job.sleep(0.3)
        guihooks.trigger('slFade', { on = false })
      end)
    end
  else
    setHour(plan.to)
    lastHour = hour()
  end
  changed()
  extensions.hook('onStreetLegalPhase', s.phase, s.day)
  return true, plan.day and strings.t('phase.newDay', s.day) or strings.t('phase.nightBegins')
end

-- Whether skipTime(what) would be refused right now, and why (nil when it would go ahead). Changes nothing: a shop asks before it does the work, so an hour is never spent on a job that then fails.
function M.skipBlocked(what)
  if not s then return strings.t('bank.no_career_running') end
  what = tostring(what)
  if what == 'switch' or (s.visit and s.visit.active and what == 'morning') then return nil end
  local why = progression.skipRefusal(busyState())
  if why then return why end
  local plan, reason = phaseLib.waitPlan(s.phase or 'day', hour(), what)
  if not plan then return reason end
  return nil
end
function M.skipTime(what)
  if not s then return false, strings.t('bank.no_career_running') end
  what = tostring(what)
  if what == 'switch' or (s.visit and s.visit.active and what == 'morning') then return M.switchPhase() end
  local why = progression.skipRefusal(busyState())
  if why then return false, why end
  local plan, reason = phaseLib.waitPlan(s.phase or 'day', hour(), what)
  if not plan then return false, reason end
  lastHour = plan.to
  clockHeld = plan.ends or false
  if core_jobsystem and core_jobsystem.create and guihooks and not switching then
    switching = true
    guihooks.trigger('slFade', { on = true })
    core_jobsystem.create(function(job)
      job.sleep(0.5)
      moveClock(plan.to, job)
      switching = false
      job.sleep(0.3)
      guihooks.trigger('slFade', { on = false })
    end)
  else
    setHour(plan.to)
  end
  changed()
  local text = strings.t('wait.until', string.format('%02d:%02d', math.floor(plan.to), math.floor((plan.to % 1) * 60)))
  if plan.ends then text = text .. strings.t(s.phase == 'night' and 'wait.nightEnds' or 'wait.dayEnds') end
  return true, text
end

-- time that passes while the player does something that takes a while (WW fits parts at home): the clock moves on like a short wait, never past the end of the phase; the same refusals as
-- a wait (a race, a job, a chase), and none on a trip. Answers ok, text, minutes really spent. The hook onStreetLegalTimeSpent(minutes, reason) tells the rest.
function M.spendTime(minutes, reason)
  if not s then return false, strings.t('bank.no_career_running') end
  if switching then return false, strings.t('career.one_moment') end
  if s.visit and s.visit.active then return false, strings.t('career.no_time_on_a_trip') end
  local why = progression.skipRefusal(busyState())
  if why then return false, why end
  local plan, reason2 = phaseLib.spendPlan(s.phase or 'day', hour(), minutes)
  if not plan then return false, reason2 end
  lastHour = plan.to
  clockHeld = plan.ends or false
  if core_jobsystem and core_jobsystem.create and guihooks then
    switching = true
    core_jobsystem.create(function(job)
      local ok, err = pcall(function() moveClock(plan.to, job) lastHour = hour() end)
      switching = false                                 -- (released first, whatever happened: a lock left set would refuse every later wait)
      if not ok then log('E', logTag, 'the time could not be moved: ' .. tostring(err)) end
      pcall(extensions.hook, 'onStreetLegalTimeSpent', plan.minutes, tostring(reason or ''))          -- (after the move: a listener reading the hour sees the new time)
    end)
  else
    setHour(plan.to)
    extensions.hook('onStreetLegalTimeSpent', plan.minutes, tostring(reason or ''))
  end
  changed()
  return true, strings.t('career.time_spent', plan.minutes), plan.minutes
end

-- the Clock setting changed: the clock runs at the new speed at once
M.onStreetLegalOption = function(key) if s and key == 'slClock' then setHour(hour()) end end
M.racesList = races
M.markRead = function(thread) if s then stateLib.markRead(s, thread) changed() end end
M.logMessage = function(thread, text) if s then stateLib.addMessage(s, thread, 'me', text, now()) changed() end end

return M
