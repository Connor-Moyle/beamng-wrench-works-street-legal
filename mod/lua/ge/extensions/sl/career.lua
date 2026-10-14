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
M.LEVEL = 'slrr_valo_city'
local SAVE_DIR = '/settings/street_legal/'
local SAVE_FILE = SAVE_DIR .. 'career.json'
local PLACES_DIR = '/street_legal/places/'          -- any mod (the map) can bring its places here
local USER_PLACES = SAVE_DIR .. 'places.json'       -- and the player can add their own

local s                   -- the save, while a career is played
local active = false
local pending             -- 'start' while the level loads for a career
local dirty, saveTimer = false, 0
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
end

local function v3(t) return type(t) == 'table' and vec3(tonumber(t[1] or t.x) or 0, tonumber(t[2] or t.y) or 0, tonumber(t[3] or t.z) or 0) or nil end

----------------------------------------------------------------------------------------------
-- the save

local function writeSave()
  if not s then return end
  extensions.hook('onStreetLegalBeforeSave')      -- the cars out in the world note where they are first
  if not FS:directoryExists(SAVE_DIR) then FS:directoryCreate(SAVE_DIR, true) end
  jsonWriteFile(SAVE_FILE, s, true)
  dirty = false
end

local function readSave()
  local data = FS:fileExists(SAVE_FILE) and jsonReadFile(SAVE_FILE) or nil
  return stateLib.migrate(data)
end

function M.hasSave() return FS:fileExists(SAVE_FILE) end

-- a line for the menu: "Day 4 - $12,300 - Street kid"
function M.saveSummary()
  local data = readSave()
  if not data then return nil end
  return string.format('Day %d, $%d, %s', data.day or 1, data.money or 0, (progression.titleFor(data.rep or 0)))
end

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
    return ok
  end,
  walkIn = false,       -- no body shells over the counter: cars come from the lots
}

local function connectWallet(on)
  local parts = garageModule('slrr/garageParts')
  if parts and parts.setMoneyProvider then parts.setMoneyProvider(on and wallet or nil) end
end

-- money in and out, from anywhere in the career (negative = paid). Returns ok.
function M.addMoney(amount, label)
  return wallet.add(amount, label)
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
        places[p.id] = { id = p.id, kind = tostring(p.kind or p.id), name = tostring(p.name or p.id), pos = pos,
          dir = flat(p.dir) or vec3(0, 1, 0), display = v3(p.display), displayDir = flat(p.displayDir) }
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
  M.sendText('benny', "Welcome to Valo City, kid. This is Benny - I keep the garage. You've got a bit of money and no car, so first stop is the junkyard. Call a cab from your phone.", 3)
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
  placeInGarage()
  changed()
  writeSave()
  extensions.hook('onStreetLegalStarted', fresh)
  log('I', logTag, fresh and 'new career started' or 'career continued')
end

-- from the main menu: a new career (fresh = true) or the saved one
function M.start(fresh)
  s = (not fresh) and readSave() or nil
  if not s then
    s = stateLib.new((os.time() % 1000000) * 31 + math.random(1, 997), now())
  end
  pending = 'start'
  if getCurrentLevelIdentifier and getCurrentLevelIdentifier() == M.LEVEL then
    begin()
  elseif freeroam_freeroam and freeroam_freeroam.startFreeroamByName then
    if not freeroam_freeroam.startFreeroamByName(M.LEVEL, nil, false, false) then
      pending = nil
      tell('Valo City (slrr_valo_city) is not installed: Street Legal Racing is played on that map.', 8)
    end
  end
end

local function stop()
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
  if not wallet.add(-fee, 'Cab to ' .. place.name) then return false, string.format('The ride is $%d. You have $%d.', fee, s.money) end
  core_jobsystem.create(function(job)
    if guihooks then guihooks.trigger('slFade', { on = true }) end
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
local function races()
  if raceList then return raceList end
  raceList = {}
  local data = jsonReadFile('/levels/' .. M.LEVEL .. '/races.json')
  for _, r in ipairs(type(data) == 'table' and data.nightRaces or {}) do
    if v3(r.start) then raceList[#raceList + 1] = { id = r.id, name = r.name or ('Race ' .. tostring(r.id)), start = v3(r.start), finish = v3(r.finish) } end
  end
  return raceList
end

-- a start line not too far from the player, picked a bit at random
local function pickRace(rng)
  local list = races()
  if #list == 0 then return nil end
  local v = getPlayerVehicle(0)
  local here = v and v:getPosition() or vec3()
  local sorted = {}
  for _, r in ipairs(list) do sorted[#sorted + 1] = r end
  table.sort(sorted, function(a, b) return (a.start - here):squaredLength() < (b.start - here):squaredLength() end)
  return sorted[rng:int(math.min(5, #sorted))]
end

-- the racer's answer to a challenge; arranges the race when they say yes
-- kind: 'race' | 'high' | 'pink'
function M.challenge(racerId, kind)
  if not active then return { accept = false, text = 'No career running.' } end
  local racer = stateLib.racer(s, racerId)
  if not racer or not s.known[racerId] then return { accept = false, text = 'Number not recognised.' } end
  local rng = rngLib.new(rngLib.hash(racerId .. kind .. tostring(now())))
  local answer = roster.respond(racer, kind, { rep = s.rep, money = s.money, hasCar = #s.cars > 0 }, rng)
  if answer.accept and kind == 'pink' and not s.activeCar then
    answer = { accept = false, text = 'Pink slips for which car? Get one out of the garage first.' }
  end
  if answer.accept then
    local race = pickRace(rng)
    if not race then return { accept = false, text = "There's nowhere to race on this map." } end
    for i = #s.challenges, 1, -1 do
      if s.challenges[i].racer == racerId then table.remove(s.challenges, i) end      -- one date per racer
    end
    local c = { id = racerId .. ':' .. now(), racer = racerId, stake = answer.stake, bet = answer.bet, race = race.id, raceName = race.name,
      nightOnly = racer.nightOnly, at = now() }
    s.challenges[#s.challenges + 1] = c
    answer.challenge = c
    answer.text = answer.text .. ' Meet at ' .. race.name .. '.'
    changed()
  end
  return answer
end

function M.cancelChallenge(id)
  for i = #s.challenges, 1, -1 do
    if s.challenges[i].id == id then table.remove(s.challenges, i) changed() return true end
  end
  return false
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

-- the map's race code tells us how a race went (see docs/integration.md):
-- r = { won, stake = 'money'|'pink', bet, raceId, opponent = name }
function M.onSlrrRaceFinished(r)
  if not active or type(r) ~= 'table' then return end
  local challenge
  for i, c in ipairs(s.challenges) do
    if c.race == r.raceId then challenge = c table.remove(s.challenges, i) break end
  end
  -- the money has moved already: the map's races pay through the shared wallet
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
  end
  tell(string.format('%s %d reputation (%s)', repDelta >= 0 and '+' or '', repDelta, (progression.titleFor(s.rep))), 5)
  if (progression.titleFor(s.rep)) ~= (progression.titleFor(repBefore)) then
    M.sendText('benny', 'They call you "' .. (progression.titleFor(s.rep)) .. '" on the street now. Not bad.', 3)
  end
  refreshContacts(false)
  changed()
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
        elseif slrrValoRaces and slrrValoRaces.startChallenge then
          slrrValoRaces.startChallenge(c.race, { name = roster.displayName(racer), racerId = racer.id, class = racer.class,
            skill = racer.skill, stake = c.stake, bet = c.bet })
        else
          tell(roster.displayName(racer) .. ' is here. Pick them from the race menu.', 6)
        end
      end
    end
  end
end

----------------------------------------------------------------------------------------------
-- moving up: a bigger garage, once the name and the money are there

function M.moveGarage()
  if not active then return false, 'No career running.' end
  local n = progression.nextGarage(s)
  if not n then return false, 'This is the best garage in town.' end
  if not n.canMove then return false, n.garage.name .. ' ' .. n.why .. '.' end
  if not M.addMoney(-n.garage.cost, 'Moved to ' .. n.garage.name) then return false, 'Not enough money.' end
  s.garageLevel = n.garage.level
  places = nil
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
    local fine = math.min(s.money, progression.policeFine(offences, racing))
    if fine > 0 then M.addMoney(-fine, 'Police fine') end
    stateLib.addRep(s, progression.ARREST_REP)
    tell(string.format('Busted. $%d in fines%s.', fine, racing and ', and the race is lost' or ''), 7)
    changed()
  elseif action == 'evade' then
    stateLib.addRep(s, progression.EVADE_REP)
    tell(string.format('You lost them. +%d reputation.', progression.EVADE_REP), 5)
    changed()
  end
end

----------------------------------------------------------------------------------------------
-- the clock: a new day at six in the morning

local function updateClock()
  local h = hour()
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
