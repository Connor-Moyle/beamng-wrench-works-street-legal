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

local logTag = 'street_legal'
M.MAPS = progression.MAPS         -- the maps a career is played on (W1)
M.LEVEL = progression.DEFAULT_MAP -- the map of the career being played (a new career picks one; the save keeps it)
local SAVE_DIR = '/settings/street_legal/'
-- save slots (X52): slot 1 is the original career.json (so the career from before slots is slot 1, untouched),
-- slot n is careerN.json; their names and the last one played are in slots.json
M.SLOTS = 6
local SLOTS_FILE = SAVE_DIR .. 'slots.json'
local function slotFile(n) return SAVE_DIR .. (n == 1 and 'career.json' or ('career' .. n .. '.json')) end
local slot = 1
local SAVE_FILE = slotFile(1)          -- the slot being played; set by M.start
local PLACES_DIR = '/street_legal/places/'          -- any mod (the map) can bring its places here
local USER_PLACES = SAVE_DIR .. 'places.json'       -- and the player can add their own

local s                   -- the save, while a career is played
local active = false
local pending             -- 'start' while the level loads for a career
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

local function setHour(h)
  local tod = core_environment and core_environment.getTimeOfDay and core_environment.getTimeOfDay()
  if type(tod) ~= 'table' then return end
  tod.time = ((h - 12) % 24) / 24
  tod.play = true                 -- the clock runs: races are at night
  core_environment.setTimeOfDay(tod)
  -- the setter leaves "play" off on this level (seen in game: the clock stood at 20:30 all night),
  -- so start it on the TimeOfDay object itself
  local names = scenetree.findClassObjects and scenetree.findClassObjects('TimeOfDay') or {}
  local obj = names[1] and scenetree.findObject(names[1])
  if obj then
    obj:setField('play', 0, '1')
    obj:setField('animate', 0, '1')
  end
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

local function summaryOf(data)
  return data and string.format('Day %d, $%d, %s, %s%s', data.day or 1, data.money or 0, (progression.titleFor(data.rep or 0)),
    mapOf(data.level).name, data.ended and ' (ended)' or '') or nil
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
      out[#out + 1] = { slot = n, name = m.names[tostring(n)] or ('Career ' .. n), summary = summaryOf(data), last = m.last == n, ended = data and data.ended ~= nil }
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
}

local function connectWallet(on)
  local parts = garageModule('slrr/garageParts')
  if parts and parts.setMoneyProvider then parts.setMoneyProvider(on and wallet or nil) end
end

-- money in and out, from anywhere in the career (negative = paid). Returns ok.
function M.addMoney(amount, label)
  return wallet.add(amount, label)
end

-- money earned (jobs, purses, prizes, sponsors): as much as the career's Pay setting says (sl_options; not
-- sales, refunds or bets, which stay as they are)
function M.payOut(amount, label)
  local k = sl_options and sl_options.get('slEconomy') or 1
  return wallet.add(math.floor((amount or 0) * k / 10 + 0.5) * 10, label)
end

----------------------------------------------------------------------------------------------
-- places on the map: the junkyard, the dealer, the scrap yard, the garages. Read from
-- /street_legal/places/*.json (the map brings them) and the player's own places.json:
-- { "slrr_valo_city": { "places": [ { "id": "junkyard", "kind": "junkyard", "name": "...", "pos": [x, y, z], "dir": [x, y] } ] } }

local function loadPlaces()
  places = {}
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier()
  if not level then return end
  local files = FS:findFiles(PLACES_DIR, '*.json', 0, false, false) or {}
  table.sort(files)
  files[#files + 1] = USER_PLACES
  for _, file in ipairs(files) do
    local data = FS:fileExists(file) and jsonReadFile(file)
    local here = type(data) == 'table' and data[level]
    for _, p in ipairs(type(here) == 'table' and type(here.places) == 'table' and here.places or {}) do
      local pos = v3(p.pos)
      if type(p.id) == 'string' and pos then
        local function flat(t)
          local d = v3(t)
          if not d then return nil end
          d.z = 0
          return d:length() > 0.01 and d:normalized() or nil
        end
        local place = { id = p.id, kind = tostring(p.kind or p.id), name = tostring(p.name or p.id), pos = pos,
          dir = flat(p.dir) or vec3(0, 1, 0), display = v3(p.display), displayDir = flat(p.displayDir) }
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
        places[p.id] = place
      else
        log('W', logTag, file .. ': a place without "id" or "pos" was left out')
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
end

function M.getPlaces()
  if not places then loadPlaces() end
  return places
end

-- stand where a place should be (the junkyard's gate, say) and run this in the console
function M.addPlaceHere(kind, name)
  local v = getPlayerVehicle(0)
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier()
  if not v or not level or type(kind) ~= 'string' then return 'Stand where the place should be, with a level loaded: sl_career.addPlaceHere("junkyard", "Name")' end
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
  local text = string.format('Place "%s" saved in %s', id, USER_PLACES)
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
      M.sendText('benny', string.format('People are talking about you. %d more racers will pick up when you call now: they are in your contacts.', #added), 2)
    end
  end
end

----------------------------------------------------------------------------------------------
-- starting and continuing

local function welcome()
  M.sendText('benny', "Welcome to " .. mapOf(M.LEVEL).name .. ", kid. This is Benny - I keep the garage. You've got a bit of money and no car, so first stop is the junkyard. Call a cab from your phone.", 3)
  M.sendText('benny', 'Street racers are in your contacts. Most of them will laugh at you until you have a car and a name. Races are at night, and night races are what people remember.', 12)
  M.sendText('benny', 'Press K for the phone. Bills, messages, calls, a cab: all in there.', 20)
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
  end
end

local function begin()
  pending = nil
  active = true
  connectWallet(true)
  places = nil
  loadPlaces()
  local fresh = not s.begun
  if fresh then
    s.begun = true
    setHour(progression.START_HOUR)
    refreshContacts(true)
    welcome()
  else
    setHour(s.hour or progression.START_HOUR)
  end
  lastHour = hour()
  -- Night set while the level is still loading leaves the picture all white (seen in game: only a
  -- big jump of the clock brings it back, setting the same hour again does not). So once the
  -- loading screen is gone: midday for a moment behind a black fade, then the career's hour.
  local wanted = hour()
  core_jobsystem.create(function(job)
    job.sleep(3)
    if not active then return end
    if guihooks then guihooks.trigger('slFade', { on = true, pic = 'loading_garage_blue_cheetah.png' }) end
    job.sleep(0.6)
    setHour((wanted + 12) % 24)
    job.sleep(0.5)
    setHour(wanted)
    lastHour = hour()
    if guihooks then guihooks.trigger('slFade', { on = false }) end
    -- the level loaded with nobody in it, so the game left its free camera on: follow the player
    if getPlayerVehicle(0) and core_camera.getActiveCamName(0) == 'free' then core_camera.setByName(0, 'orbit') end
    -- started from the main menu's button, the UI stays on the menu screen over the game (seen in
    -- game: the main menu drawn over the garage, taking the keys): on to the play screen
    if ui_router and ui_router.navigate then ui_router.navigate('play') end
  end)
  placeInGarage()
  changed()
  writeSave()
  extensions.hook('onStreetLegalStarted', fresh)
  log('I', logTag, fresh and 'new career started' or 'career continued')
end

-- from the main menu: a new career (fresh = true, in the first free slot: never over another career, on the map
-- `level`: one of MAPS) or a saved one (n, or the one played last; its map is in the save)
local stop                                 -- (defined below)

function M.start(fresh, n, level)
  if active then stop() end              -- (B26: the career being played is saved and stopped first, so nothing of it carries over)
  local m = slotsMeta()
  n = tonumber(n)
  if fresh then
    n = nil
    for i = 1, M.SLOTS do if not n and not slotUsed(i) then n = i end end
    if not n then tell(string.format('All %d career slots are taken: delete one first.', M.SLOTS), 6) return false end
  else
    n = n or (slotUsed(m.last) and m.last) or 1
  end
  -- a career that ended (Hardcore: the driver died) can be looked at, not played on
  if not fresh then
    local data = readSave(slotFile(n))
    if data and data.ended then tell('That career is over: it ended on day ' .. tostring(data.ended.day) .. '. Start a new one.', 6) return false end
  end
  slot, SAVE_FILE = n, slotFile(n)
  m.last = n
  writeMeta(m)
  s = (not fresh) and readSave() or nil
  if not s then
    s = stateLib.new((os.time() % 1000000) * 31 + math.random(1, 997), now())
    s.level = progression.MAPS[level] and level or progression.DEFAULT_MAP
  end
  useMap(progression.MAPS[s.level] and s.level or progression.DEFAULT_MAP)   -- (a save from before W1 has no level: Valo City)
  pending = 'start'
  if getCurrentLevelIdentifier and getCurrentLevelIdentifier() == M.LEVEL then
    begin()
  else
    if not freeroam_freeroam then extensions.load('freeroam_freeroam') end
  end
  if pending == 'start' and not (getCurrentLevelIdentifier and getCurrentLevelIdentifier() == M.LEVEL) and freeroam_freeroam and freeroam_freeroam.startFreeroamByName then
    if not freeroam_freeroam.startFreeroamByName(M.LEVEL, nil, false, false) then
      pending = nil
      tell(string.format('%s (%s) is not installed: this career is played on that map.', mapOf(M.LEVEL).name, M.LEVEL), 8)
    end
  end
end

-- the career is over (Hardcore: the driver died): saved as ended, and stopped
function M.endCareer() if active then stop() end end

stop = function()
  if not active then return end
  s.hour = hour()
  writeSave()
  connectWallet(false)
  active = false
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  extensions.hook('onStreetLegalStopped')
end

----------------------------------------------------------------------------------------------
-- taxi: on foot, the phone takes you across town

function M.taxi(placeId)
  if not active then return false, 'No career running.' end
  local place = M.getPlaces()[placeId]
  if not place then return false, 'The cab does not know that place.' end
  local v = getPlayerVehicle(0)
  if not v or v:getJBeamFilename() ~= 'unicycle' then return false, 'Cabs are for people on foot. Park the car and get out first.' end
  local fee = progression.taxiFee((v:getPosition() - place.pos):length())
  -- the floor: no car and no money for the fare (a pink slip lost, bets gone wrong): once a day a free
  -- ride, so the jobs that need no car (the junkyard's crushing run) are always in reach
  if s.money < fee and #s.cars == 0 and s.freeRideDay ~= s.day and not (sl_options and sl_options.get('slHardcore')) then
    s.freeRideDay = s.day
    fee = 0
    M.sendText('benny', "My cousin will run you over there. Don't make a habit of it. The junkyard always has a wreck that needs driving to the crusher.", 1)
  end
  if sl_cab and sl_cab.busy() then return false, 'A cab is already waiting for you.' end
  if fee > 0 and not wallet.add(-fee, 'Cab to ' .. place.name) then return false, string.format('The ride is $%d. You have $%d.', fee, s.money) end
  if sl_cab and sl_cab.call(place, fee) then return true end
  -- no lane for a cab to pull up on here: the old way, straight there
  core_jobsystem.create(function(job)
    if guihooks then guihooks.trigger('slFade', { on = true, pic = 'loading_city.png' }) end
    job.sleep(0.6)
    spawn.safeTeleport(getPlayerVehicle(0), place.pos + vec3(0, 0, 0.3), quatFromDir(place.dir, vec3(0, 0, 1)), true)
    job.sleep(0.6)
    if guihooks then guihooks.trigger('slFade', { on = false }) end
    tell(string.format('%s. That was $%d.', place.name, fee), 4)
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
    if v3(r.start) then raceList[#raceList + 1] = { id = r.id, name = r.name or ('Race ' .. tostring(r.id)), start = v3(r.start), finish = v3(r.finish) } end
  end
  -- the drag strip at the test track: the same race menu runs them (races.json "dragRaces")
  for _, r in ipairs(type(data) == 'table' and data.dragRaces or {}) do
    if v3(r.start) then raceList[#raceList + 1] = { id = r.id, name = r.name or ('Drag ' .. tostring(r.id)), start = v3(r.start), finish = v3(r.finish), drag = true } end
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
  if not active then return { accept = false, text = 'No career running.' } end
  local racer = stateLib.racer(s, racerId)
  if not racer or not s.known[racerId] then return { accept = false, text = 'Number not recognised.' } end
  if sl_hospital and not sl_hospital.canDrive() then return { accept = false, text = 'You can barely walk, mate. Call me when you are healed.' } end
  local rng = rngLib.new(rngLib.hash(racerId .. kind .. tostring(now())))
  local drag = kind == 'drag'
  local answer = roster.respond(racer, drag and 'race' or kind, { rep = s.rep, money = s.money, hasCar = #s.cars > 0, pinkTonight = roster.pinkTonight(racer, s.day, s.seed) }, rng)
  if answer.accept and kind == 'pink' and not s.activeCar then
    answer = { accept = false, text = 'Pink slips for which car? Get one out of the garage first.' }
  end
  if answer.accept then
    local race = pickRace(rng, drag)
    if not race then return { accept = false, text = drag and "There's no drag strip on this map." or "There's nowhere to race on this map yet. Call me when there is." } end
    for i = #s.challenges, 1, -1 do
      if s.challenges[i].racer == racerId then table.remove(s.challenges, i) end      -- one date per racer
    end
    local c = { id = racerId .. ':' .. now(), racer = racerId, stake = answer.stake, bet = answer.bet, race = race.id, raceName = race.name,
      missionId = race.missionId, nightOnly = racer.nightOnly, at = now() }
    s.challenges[#s.challenges + 1] = c
    answer.challenge = c
    answer.text = answer.text .. ' Meet at ' .. race.name .. '.'
    changed()
  end
  return answer
end

-- raise the stake of an arranged money race by a step, as far as their car makes them willing (and you can pay)
function M.raiseStake(id)
  if not active then return false, 'No career running.' end
  for _, c in ipairs(s.challenges) do
    if c.id == id then
      local racer = stateLib.racer(s, c.racer)
      if c.stake ~= 'money' or not racer then return false, 'Nothing to raise.' end
      c.baseBet = c.baseBet or c.bet
      local cap, bet = roster.maxStake(racer, c.baseBet), c.bet + roster.stakeStep(c.baseBet)
      if bet > cap then return false, string.format('%s will not go past $%d.', roster.displayName(racer), cap) end
      if bet > s.money then return false, string.format('$%d? You have $%d.', bet, s.money) end
      c.bet = bet
      changed()
      return true, string.format('%s: "$%d it is."', roster.displayName(racer), bet)
    end
  end
  return false, 'That race is off.'
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
  local night = progression.isNight(hour())
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
  local pos, rot = sl_fleet.forecourt(s, #s.cars % 6)
  if pos then spawn.safeTeleport(veh, pos, rot, true, nil, nil, nil, false) end     -- (8th: resetVehicle would repair it)
  sl_fleet.registerVehicle(vid, { name = won.name or veh:getJBeamFilename(), condition = 0.85, value = won.value })   -- (B32: a value, so resale and scrap price it)
  M.sendText('benny', string.format('Your new %s is outside the garage. Won fair and square.', won.name or 'car'), 2)
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
    wallet.add(r.won and r.bet or -r.bet, (r.won and 'Won' or 'Lost') .. ' a street race' .. (r.opponent and (' against ' .. tostring(r.opponent)) or ''))
  end
  local racer = (challenge and challenge.racer) or (type(r.racerId) == 'string' and stateLib.racer(s, r.racerId) and r.racerId) or nil
  local repBefore = s.rep
  local h = hour()
  local repDelta = progression.raceResult({ won = r.won, stake = r.stake, bet = r.bet, night = progression.isNight(h),
    opponentRep = racer and stateLib.racer(s, racer).rep or 300, playerRep = s.rep })
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
      M._pinkWon = { name = r.opponent and (r.opponent .. "'s car") or nil, vid = r.opponentVid, value = tonumber(r.value) }
      s.stats.pinksWon = s.stats.pinksWon + 1
    elseif not r.won then
      local gone = sl_fleet.lastGone
      if gone and os.clock() - gone.at < 5 then sl_fleet.lose(gone.carId) end
      s.stats.pinksLost = s.stats.pinksLost + 1
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
  tell(string.format('%s %d reputation (%s)', repDelta >= 0 and '+' or '', repDelta, (progression.titleFor(s.rep))), 5)
  if (progression.titleFor(s.rep)) ~= (progression.titleFor(repBefore)) then
    M.sendText('benny', 'They call you "' .. (progression.titleFor(s.rep)) .. '" on the street now. Not bad.', 3)
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
  if not missionRaces() or not raceMod().circuitOpponents then return nil end
  return trackList
end

-- a race at one of them against a racer: their car is built at the start, then the mission takes over
function M.launchTrack(racerId, missionId)
  if not active then return false, 'No career running.' end
  local racer = stateLib.racer(s, racerId)
  local track
  for _, t in ipairs(M.tracksList() or {}) do if t.missionId == missionId then track = t end end
  if not racer or not track then return false, 'That race is not on.' end
  if not (sl_streets and sl_streets.buildRacerCar) then return false, 'Not now.' end
  local bet = math.floor(((racer.betMin or 100) + (racer.betMax or 300)) / 2 / 50) * 50
  for i = #s.challenges, 1, -1 do if s.challenges[i].racer == racerId then table.remove(s.challenges, i) end end
  local c = { id = racerId .. ':track:' .. now(), racer = racerId, stake = 'money', bet = bet, race = track.id, raceName = track.name,
    missionId = missionId, laps = track.laps, at = now() }
  s.challenges[#s.challenges + 1] = c
  changed()
  sl_streets.buildRacerCar(racerId, track.start + vec3(0, 0, 0.5), nil, function(veh)
    raceMod().launch(missionId, offerFor(c, veh and veh:getID() or nil))
  end)
  return true, string.format('%s, against %s for $%d.', track.name, roster.displayName(racer), bet)
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
        if c.nightOnly and not progression.isNight(hour()) then
          tell(roster.displayName(racer) .. ' only races at night. Come back after dark.', 6)
          c.notified = false
        elseif raceMod() and raceMod().launch and r.missionId then
          -- the race is a BeamNG mission now: start it with them in it
          raceMod().launch(r.missionId, offerFor(c, ownCar and ownCar.challenge == c.id and ownCar.vid or nil))
        elseif raceMod() and raceMod().startChallenge then
          -- handed over already (syncChallenge): the start marker brings them
        else
          tell(roster.displayName(racer) .. ' is here. Pick them from the race menu.', 6)
        end
      end
    end
  end
end

----------------------------------------------------------------------------------------------
-- moving up: a bigger garage, once the name and the money are there

-- the impound: pay what is owed and the car is back at your garage
function M.releaseCar(carId)
  if not active then return false, 'No career running.' end
  for _, car in ipairs(s.cars) do
    if car.id == carId and car.impounded then
      if not M.addMoney(-car.impounded, 'Impound: ' .. car.name) then return false, string.format('It is $%d. You have $%d.', car.impounded, s.money) end
      car.impounded = nil
      car.out, car.where = false, nil
      changed()
      return true, 'The ' .. car.name .. ' is back in your garage.'
    end
  end
  return false, 'Nothing of yours is impounded.'
end

function M.moveGarage()
  if not active then return false, 'No career running.' end
  local n = progression.nextGarage(s)
  if not n then return false, 'This is the best garage in town.' end
  if not n.canMove then return false, n.garage.name .. ' ' .. n.why .. '.' end
  if not M.addMoney(-n.garage.cost, 'Moved to ' .. n.garage.name) then return false, 'Not enough money.' end
  local fromLevel = s.garageLevel
  s.garageLevel = n.garage.level
  places = nil
  extensions.hook('onStreetLegalGarageMoved', fromLevel, s.garageLevel, n.garage.cost)
  changed()
  M.sendText('benny', 'Welcome to ' .. n.garage.name .. '. Your cars are where you left them; drive them over or have them towed.', 2)
  return true, 'You now work out of ' .. n.garage.name .. '.'
end

----------------------------------------------------------------------------------------------
-- the police (the game's own pursuits, when traffic has police in it)

function M.onPursuitAction(id, action, pursuit)
  if not active then return end
  local v = getPlayerVehicle(0)
  if not v or v:getID() ~= id then return end
  if action == 'arrest' then
    local offences = type(pursuit) == 'table' and type(pursuit.offensesList) == 'table' and #pursuit.offensesList or 1
    local racing = sl_streets and sl_streets.isRacing()
    if racing then sl_streets.forfeit() end
    local owed = progression.policeFine(offences, racing)
    local fine = math.min(s.money, owed)
    if fine > 0 then M.addMoney(-fine, 'Police fine') end
    stateLib.addRep(s, progression.ARREST_REP)
    s.heat = math.min(1, (s.heat or 0) + 0.2)
    -- could not pay it all: the car goes to the impound until the rest is paid (as in SLRR)
    local car = owed > fine and sl_fleet and sl_fleet.currentCar()
    if car then
      car.impounded = (owed - fine) + 500
      car.out = false
      local veh = sl_fleet.vehicleOf(car.id)
      if gameplay_walk then gameplay_walk.setWalkingMode(true, nil, nil, true) end
      if veh then core_jobsystem.create(function(job) job.sleep(1) if veh then veh:delete() end end) end
      tell(string.format('Busted, and you cannot pay. The %s is impounded: $%d to get it back (phone, My cars).', car.name, car.impounded), 9)
    else
      tell(string.format('Busted. $%d in fines%s.', fine, racing and ', and the race is lost' or ''), 7)
    end
    changed()
  elseif action == 'evade' then
    stateLib.addRep(s, progression.EVADE_REP)
    tell(string.format('You lost them. +%d reputation.', progression.EVADE_REP), 5)
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
    M.sendText('benny', 'Word is ' .. table.concat(names, ' and ') .. (#names == 1 and ' is' or ' are') ..
      ' putting their car up for pink slips tonight. Call them if you fancy it - and if you can afford to lose yours.', 1)
  end
end

local function updateClock()
  local h = hour()
  if lastHour and lastHour < 20 and h >= 20 then pinkTipOff() end
  if lastHour and lastHour < 6 and h >= 6 then
    s.day = s.day + 1
    changed()
    extensions.hook('onStreetLegalNewDay', s.day)
  end
  lastHour = h
end

----------------------------------------------------------------------------------------------
-- game hooks

local function onUpdate(dtReal)
  if pending == 'start' and getCurrentLevelIdentifier and getCurrentLevelIdentifier() == M.LEVEL and worldReadyState == 2 then
    begin()
  end
  if not active then return end
  deliverTexts()
  updateClock()
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
  raceList, places = nil, nil
end

M.onUpdate = onUpdate
M.onClientEndMission = onClientEndMission
M.onExtensionUnloaded = stop

-- for the phone
M.hour = hour
M.racesList = races
M.markRead = function(thread) if s then stateLib.markRead(s, thread) changed() end end
M.logMessage = function(thread, text) if s then stateLib.addMessage(s, thread, 'me', text, now()) changed() end end

return M
