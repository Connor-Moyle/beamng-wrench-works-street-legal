-- Street Legal Racing: the phone (extension name: sl_phone)
-- The Lua side of the phone in ui/modModules/slPhone: it hands the screen everything it shows
-- (contacts, messages, calls, the bank, the cab) and does what its buttons ask. All the
-- career's state lives in sl_career; this only translates.

local M = {}

local strings = require('sl/core/strings')

local progression = require('sl/core/progression')
local phaseLib = require('sl/core/phase')
local roster = require('sl/core/roster')
local rngLib = require('sl/core/rng')

local BENNY = { id = 'benny', name = strings.t('phone.benny_garage'), phone = '555-0100', system = true }

local sendTimer, wantSend = 0, true

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

-- free roam (sl_mode: the master switch and the 'phone' switch, no career): a small phone of the apps that need no career. Nothing of a career is in it (no money, rep, cars, contacts,
-- messages or jobs), and an app that is not in the list cannot be opened.
M.FREE_KINDS = { garage = true, shop = true, carwash = true, meet = true }       -- (the places the Cab and the Map list there)
local function freeRoam() return career() == nil and sl_mode ~= nil and sl_mode.enabled('phone') end
local function freeApps()
  local out = {}      -- (no Settings app: the settings live in ESC > Mods)
  if sl_mode.enabled('maps') then out[#out + 1] = 'map' end
  if sl_mode.enabled('cab') then out[#out + 1] = 'cab' end
  return out
end
-- the app to open: in free roam only the free apps, else the home screen
function M.freeAppOpens(app)
  for _, id in ipairs(freeApps()) do if id == app then return app end end
  return 'home'
end
local function freeSnapshot()
  local sb = sl_mode.state('phone') or {}
  local h = sb.hour or 12
  local placesOut = {}
  for id, p in pairs(sl_career and (sl_career.freeRoamPlaces or sl_career.allPlaces) and (sl_career.freeRoamPlaces or sl_career.allPlaces)() or {}) do
    if M.FREE_KINDS[p.kind] then placesOut[#placesOut + 1] = { id = id, name = p.name, kind = p.kind } end
  end
  table.sort(placesOut, function(a, b) return a.name < b.name end)
  return {
    active = true, freeroam = true, apps = freeApps(), hour = math.floor(h), minute = math.floor((h % 1) * 60), night = sb.phase == 'night', phase = sb.phase,
    weather = sl_mode.enabled('weather') and sl_weather and sl_weather.forecast and sl_weather.forecast() or nil,
    textScale = require('sl/core/strings').textScale(sl_options and sl_options.get and sl_options.get('slTextScale')),
    colorBlind = sl_options ~= nil and sl_options.get ~= nil and sl_options.get('slColorBlind') == true,
    has = { clubs = false, crews = false, classifieds = false, races = false, jobs = false, market = false, bank = false, maps = sl_mode.enabled('maps'), hudpill = false },
    places = placesOut, contacts = {}, threads = {}, fleet = {}, cars = 0,
    mapName = (function() local lvl = getCurrentLevelIdentifier and getCurrentLevelIdentifier() local m = lvl and progression.MAPS and progression.MAPS[lvl] return m and m.name or lvl end)(),
  }
end
M.freeSnapshot = freeSnapshot

----------------------------------------------------------------------------------------------
-- what the screen shows

local travelPick = nil

local function snapshot()
  local s = career()
  if not s then if freeRoam() then return freeSnapshot() end return { active = false } end
  local title, nextRep, titleRep = progression.titleFor(s.rep, sl_career.LEVEL)
  local h = sl_career.hour()
  local contacts = { { id = BENNY.id, name = BENNY.name, phone = BENNY.phone, system = true } }
  for _, r in ipairs(s.racers) do
    if s.known[r.id] then
      contacts[#contacts + 1] = {
        id = r.id, name = roster.displayName(r), short = r.name, phone = r.phone, tier = r.tier, class = r.class,
        nightOnly = r.nightOnly, wins = r.wins, losses = r.losses, pinkTonight = roster.pinkTonight(r, s.day, s.seed),
      }
    end
  end
  table.sort(contacts, function(a, b)
    if a.system ~= b.system then return a.system == true end
    return a.short and b.short and a.short < b.short or false
  end)
  local challenges = {}
  for _, c in ipairs(s.challenges) do
    local r
    for _, x in ipairs(s.racers) do if x.id == c.racer then r = x end end
    challenges[#challenges + 1] = { id = c.id, racer = c.racer, name = r and roster.displayName(r) or '?', stake = c.stake, bet = c.bet,
      raceName = c.raceName, nightOnly = c.nightOnly,
      preview = c.race and sl_races and sl_races.preview and sl_races.preview(c.race) or nil }       -- (the route as a small map: #18)
  end
  local placesOut = {}
  for id, p in pairs(sl_career.allPlaces() or {}) do
    local tier, tierLabel = nil, nil
    if sl_career.placeTier then tier, tierLabel = sl_career.placeTier(id) end        -- (a lot's price tier: high | mid | low | junk; nil is asked again next time)
    placesOut[#placesOut + 1] = { id = id, name = p.name, kind = p.kind, tier = tier, tierLabel = tierLabel }
  end
  table.sort(placesOut, function(a, b) return a.name < b.name end)
  local ledger = {}
  for i = 1, math.min(30, #s.ledger) do ledger[i] = s.ledger[i] end
  local nextGarage = progression.nextGarage(s)
  return {
    active = true,
    money = s.money, rep = s.rep, title = title, nextRep = nextRep, titleRep = titleRep,
    day = s.day, hour = math.floor(h), minute = math.floor((h % 1) * 60), night = sl_career.isNight(),
    atRisk = sl_career.atRisk and sl_career.atRisk() or 0,
    textScale = require('sl/core/strings').textScale(sl_options and sl_options.get and sl_options.get('slTextScale')),
    colorBlind = sl_options ~= nil and sl_options.get ~= nil and sl_options.get('slColorBlind') == true,      -- (#51)
    reduceMotion = sl_options ~= nil and sl_options.get ~= nil and sl_options.get('slReduceMotion') == true,      -- (UI style kit: no movement, only instant changes)
    wall = sl_photos and sl_photos.wallpapers and sl_photos.wallpapers().phone or nil,      -- (a photo as the home screen's wallpaper)
    heat = phaseLib.heatLevel(sl_police and sl_police.heat and sl_police.heat() or 0),
    phase = sl_career.phase and sl_career.phase() or nil, phaseSwitch = phaseLib.switchLabel(sl_career.phase and sl_career.phase() or nil),
    garage = (progression.garages[s.garageLevel] or {}).name,
    weather = sl_weather and sl_weather.forecast and sl_weather.forecast() or nil,
    nextGarage = nextGarage and { name = nextGarage.garage.name, canMove = nextGarage.canMove, why = nextGarage.why } or nil,
    roc = progression.rocOpen(s) and sl_career.has('roc'), hasRoc = sl_career.has('roc'), mapName = sl_career.mapName(),
    art = sl_hud ~= nil and sl_hud.slrrArt ~= nil and sl_hud.slrrArt() or false,
    has = { clubs = sl_career.has('clubs'), crews = sl_career.has('crews'), classifieds = sl_career.has('classifieds'),
      races = require('sl/core/features').on('races'), jobs = require('sl/core/features').on('jobs'), market = require('sl/core/features').on('market'),
      bank = require('sl/core/features').on('bank'), maps = require('sl/core/features').on('maps'), hudpill = require('sl/core/features').on('hudpill'), weekly = require('sl/core/features').on('weekly'), service = require('sl/core/features').on('service'), perks = require('sl/core/features').on('perks'), traps = require('sl/core/features').on('traps'), danger = require('sl/core/features').on('danger'), calendar = require('sl/core/features').on('calendar'), sponsors = require('sl/core/features').on('sponsors') },      -- (the parts that are switched off lose their apps)
    contacts = contacts, threads = s.threads, unread = s.unread,
    challenges = challenges, ledger = ledger, places = placesOut,
    cars = #s.cars, stats = s.stats,
    perks = sl_perks and sl_perks.perks and sl_perks.perks() or nil,
    calendar = sl_calendar and sl_calendar.summary and sl_calendar.summary() or nil,      -- (the Calendar app: nil with the part off or no career)
    visit = sl_career.visit and sl_career.visit() and { name = sl_career.visit().name or sl_career.mapName(), round = sl_career.visit().round, rounds = sl_career.visit().rounds, untilDay = sl_career.visit().untilDay } or nil,      -- (on a trip: the phone shows the Event hub)
    hub = sl_career.visit and sl_career.visit() and sl_series and sl_series.hub and sl_series.hub() or nil,      -- (the paddock: standings, the next round, the cars brought)
    travelPick = travelPick,      -- (the pick-cars screen: sl_series.options(eventId) while one is open)
    danger = sl_danger and sl_danger.summary and sl_danger.summary() or nil,      -- (jumps and drift zones, on the Speed traps page)
    traps = sl_traps and sl_traps.summary and sl_traps.summary() or nil,      -- (the Speed traps page: nil with the part off or no career)
    fleet = (function()      -- each car with its service card (sl_service.serviceOf: nil with the part off or for an unknown car)
      local list = sl_fleet and sl_fleet.list() or {}
      if sl_service and sl_service.serviceOf then for _, c in ipairs(list) do c.service = sl_service.serviceOf(c.id) end end
      return list
    end)(),
    onOrder = (function()      -- the factory orders of the high-end dealers, then the stock dealers' and private sellers' cars on their way
      local out = sl_lot and sl_lot.ordersList and sl_lot.ordersList() or {}
      for _, o in ipairs(sl_dealers and sl_dealers.ordersList and sl_dealers.ordersList() or {}) do out[#out + 1] = o end
      return out
    end)(),
    rocRound = (s.roc or {}).round or 0, rocChampion = (s.roc or {}).champion == true,
    rocEntry = progression.ROC.entry,
    jobs = sl_jobs and sl_jobs.summary and sl_jobs.summary() or nil,
    market = sl_classifieds and sl_classifieds.summary and sl_classifieds.summary() or nil,
    tutorial = sl_tutorial and sl_tutorial.summary and sl_tutorial.summary() or nil,
    achievements = sl_achievements and sl_achievements.summary and sl_achievements.summary() or nil,
    bank = sl_bank and sl_bank.summary and sl_bank.summary() or nil,
    weekly = sl_weekly and sl_weekly.summary and sl_weekly.summary() or nil,
    sponsors = sl_sponsor and sl_sponsor.summary and sl_sponsor.summary() or nil,
    club = sl_clubs and sl_clubs.summary and sl_clubs.summary() or nil,
    replay = sl_replay and sl_replay.summary and sl_replay.summary() or nil,
    turf = sl_crews and sl_crews.summary and sl_crews.summary() or nil,
    upgrades = sl_upgrades and sl_upgrades.summary and sl_upgrades.summary() or nil,
  }
end

-- the phone's data goes through sl_uipush (counted; the same snapshot again is not sent) and faster only while the phone or a laptop is open (the screens tell us: uiOpen)
local screensOpen = {}
local function anyOpen() return next(screensOpen) ~= nil end
function M.uiOpen(name, open) screensOpen[tostring(name)] = open and true or nil wantSend = true end
local function send()
  local data = snapshot()
  if sl_uipush and sl_uipush.push then sl_uipush.push('slPhoneData', data, { dedupe = true }) else guihooks.trigger('slPhoneData', data) end
end

----------------------------------------------------------------------------------------------
-- calls

-- the first thing they say when they pick up
local GREETINGS = {
  easy = strings.t('phone.yeah_who_is_this'),
  trash = strings.t('phone.make_it_quick_i_ve'),
  roller = strings.t('phone.talk_time_is_money'),
  careful = 'Hello?',
}

local function bennyAdvice(s)
  if #s.cars == 0 then return strings.t('phone.you_still_haven_t_got') end
  local n = progression.nextGarage(s)
  if n and n.canMove then return strings.t('phone.you_could_move_up_to', (n.garage.name)) end
  if not sl_career.isNight() then return strings.t('phone.nothing_much_happens_in_the') end
  return strings.t('phone.call_a_few_of_the')
end

function M.call(id)
  local s = career()
  if not s then return end
  if id == BENNY.id then
    guihooks.trigger('slPhoneCall', { id = id, answered = true, greeting = strings.t('phone.benny_here'), text = bennyAdvice(s), options = {} })
    return
  end
  local racer
  for _, r in ipairs(s.racers) do if r.id == id and s.known[id] then racer = r end end
  if not racer then
    guihooks.trigger('slPhoneCall', { id = id, answered = false, text = strings.t('phone.the_number_you_have_dialled') })
    return
  end
  -- most pick up; the same hour gives the same answer
  local rng = rngLib.new(rngLib.hash(id .. ':' .. s.day .. ':' .. math.floor(sl_career.hour())))
  local answered = rng:chance(racer.nightOnly and sl_career.isNight() and 0.95 or 0.8)
  s.calls[#s.calls + 1] = { racer = id, at = os.time(), outgoing = true, missed = not answered }
  while #s.calls > 30 do table.remove(s.calls, 1) end
  guihooks.trigger('slPhoneCall', {
    id = id, answered = answered,
    greeting = answered and (GREETINGS[racer.style] or GREETINGS.easy) or nil,
    text = not answered and strings.t('phone.no_answer') or nil,
    options = answered and (roster.pinkTonight(racer, s.day, s.seed) and { 'race', 'high', 'drag', 'pink' } or { 'race', 'high', 'drag' }) or {},
  })
end

-- on a call: race for money, high stakes or pink slips
function M.challenge(id, kind)
  if not career() then return end
  local answer = sl_career.challenge(id, kind)
  guihooks.trigger('slPhoneCallReply', { id = id, accept = answer.accept, text = answer.text, challenge = answer.challenge })
  wantSend = true
end

-- the same by text message: they write back after a moment
local ASK = {
  race = strings.t('phone.up_for_a_race'),
  high = strings.t('phone.race_me_high_stakes'),
  pink = strings.t('phone.pink_slips_you_and_me'),
  drag = strings.t('phone.drag_race_at_the_test'),
}

function M.text(id, kind)
  if not career() or not ASK[kind] then return end
  sl_career.logMessage(id, ASK[kind])
  local answer = sl_career.challenge(id, kind)
  sl_career.sendText(id, answer.text, 3 + math.random() * 5)
  wantSend = true
end

----------------------------------------------------------------------------------------------
-- the rest of the buttons

-- the phone skin chosen in the Mods menu (sl/phoneskins): sent when the UI asks and when the choice changes. Classic (or a skin that is gone) is sent as { id = 'classic' }
function M.sendSkin()
  local id = sl_options and sl_options.get and sl_options.get('slPhoneSkin') or 'classic'
  local ok, skin = pcall(function() return require('sl/phoneskins').payload(id) end)
  guihooks.trigger('slPhoneSkin', ok and skin or { id = 'classic' })
end
function M.onStreetLegalOption(key) if key == 'slPhoneSkin' then M.sendSkin() end end
function M.request() wantSend = true M.sendSkin() end
-- the help pages (sl/core/help), for the phone's Help app and the laptop's Help window
-- all the player-facing text (sl/core/strings), once, for the UI's T()
function M.requestStrings()
  local out = {}
  for k, v in pairs(require('sl/core/strings').TEXT) do      -- (only what the screens use: the rest is for the Lua side)
    if k:find('^ui%.') or k:find('^app%.') or k:find('^laptop%.') or k:find('^status%.') or k:find('^phase%.') or k:find('^wait%.') or k:find('^hud%.') or k:find('^settings%.') then out[k] = v end
  end
  guihooks.trigger('slStrings', { text = out })
end
function M.requestHelp() guihooks.trigger('slHelp', { pages = require('sl/core/help').PAGES }) end
function M.markRead(thread) if career() then sl_career.markRead(thread) end end
function M.waypoint(id) if career() then sl_career.waypoint(id) end end
function M.cancel(challengeId) if career() then sl_career.cancelChallenge(challengeId) end end

local function answer(ok, text)
  guihooks.trigger('slPhoneToast', { text = text })
  wantSend = true
end

----------------------------------------------------------------------------------------------
-- the Map app: the career's places by kind with their distance, and a route on the road (the game's ground markers) to one of them, cleared on arrival
local mapLib = require('sl/core/mapapp')
local route                      -- { id, name, x, y } while a route set here is on

local function playerAt()
  local v = getPlayerVehicle(0)
  local p = v and v:getPosition()
  return p and { x = p.x, y = p.y } or nil
end

-- the Map's route, if it is still the one on the road; another path (a job's, a race's) set since drops it quietly and is left alone
local function liveRoute()
  if route and not mapLib.stillActive(core_groundMarkers and core_groundMarkers.endWP, route) then route = nil end
  return route
end

function M.mapPlaces()
  local inCareer = career() ~= nil
  if not inCareer and not freeRoam() then return end
  liveRoute()
  local list = {}
  for id, p in pairs((inCareer and sl_career.allPlaces or sl_career.freeRoamPlaces or sl_career.allPlaces)() or {}) do
    if p.pos and (inCareer or M.FREE_KINDS[p.kind]) then list[#list + 1] = { id = id, name = p.name, kind = p.kind, x = p.pos.x, y = p.pos.y } end
  end
  guihooks.trigger('slMap', { groups = mapLib.groups(list, playerAt()), route = route and { id = route.id, name = route.name } or nil })
end

-- the Contacts app's people: rivals (sl_rivals), the crews' leaders you know, the dealers on the map
function M.people()
  local s = career()
  if not s then return end
  local rivals = sl_rivals and sl_rivals.met and sl_rivals.met() or {}
  local crews = {}
  local cs = sl_crews and sl_crews.ensure and sl_crews.ensure(s)
  for _, cr in ipairs(require('sl/core/crews').CREWS) do
    local id = cs and cs.leader and cs.leader[cr.id]
    local racer = id and s.known[id] and require('sl/core/state').racer(s, id)
    if racer then crews[#crews + 1] = { id = id, name = roster.displayName(racer), kind = 'crew', line = strings.t('phone.leader_of_1', cr.name) } end
  end
  local dealers = {}
  for id, p in pairs(sl_career.getPlaces() or {}) do
    if p.kind == 'dealer' or p.stock then
      local _, tierLabel = nil, nil
      if sl_career.placeTier then _, tierLabel = sl_career.placeTier(id) end
      dealers[#dealers + 1] = { id = 'dealer:' .. id, name = p.name, kind = 'dealer', line = tierLabel and strings.t('phone.dealer_1', tierLabel) or strings.t('phone.dealer'), placeId = id }
    end
  end
  table.sort(dealers, function(a, b) return tostring(a.name) < tostring(b.name) end)
  guihooks.trigger('slPeople', { people = mapLib.people(rivals, crews, dealers) })
end

function M.routeTo(id)
  local p = (career() or freeRoam()) and core_groundMarkers and (career() and sl_career.allPlaces or sl_career.freeRoamPlaces or sl_career.allPlaces)()[tostring(id)]
  if not p or (not career() and not M.FREE_KINDS[p.kind]) then return end
  core_groundMarkers.setPath(p.pos)
  route = { id = tostring(id), name = p.name, x = p.pos.x, y = p.pos.y }
  answer(true, strings.t('phone.route_set', p.name))
  M.mapPlaces()
end

function M.routeGarage()
  local s = career()
  if not s then return end
  local g = progression.garages[s.garageLevel or 1] or progression.garages[1]
  M.routeTo(g.site)
end

function M.clearRoute()
  if liveRoute() and core_groundMarkers then core_groundMarkers.setPath(nil) end
  route = nil
  M.mapPlaces()
end

local routeTimer = 0
local function routeStep(dtReal)
  if not route then return end
  routeTimer = routeTimer + dtReal
  if routeTimer < 0.5 then return end
  routeTimer = 0
  if not liveRoute() then return end
  if mapLib.arrived(playerAt(), route) then
    local name = route.name
    M.clearRoute()
    guihooks.trigger('slPhoneToast', { text = strings.t('phone.you_have_arrived', name) })
  end
end

function M.photos() if sl_photos then sl_photos.list() end end
function M.takePhoto() if sl_photos then answer(sl_photos.take()) end end
function M.setWallpaper(which, file) if sl_photos then answer(sl_photos.setWallpaper(tostring(which), file ~= '' and tostring(file) or false)) end end
function M.upgrade(id) if career() and sl_upgrades then answer(sl_upgrades.buy(tostring(id))) end end
function M.raise(challengeId) if career() then answer(sl_career.raiseStake(challengeId)) end end
function M.tow(carId) if career() then answer(sl_fleet.tow(tonumber(carId))) end end
function M.release(carId) if career() then answer(sl_career.releaseCar(tonumber(carId))) end end
function M.useItem(carId, itemId) if career() and sl_carcare then answer(sl_carcare.useItem(tonumber(carId), tostring(itemId))) end end
function M.useCar(carId) if career() then answer(sl_fleet.setActive(tonumber(carId))) end end
function M.moveGarage() if career() then answer(sl_career.moveGarage()) end end
-- the Wrench Works catalog from the market: the car you drive (else the one you last used) goes into the garage it stands at, catalog open
function M.catalog()
  local s = career()
  if not s then return end
  local car = sl_fleet.currentCar() or (s.activeCar and (function() for _, c in ipairs(s.cars) do if c.id == s.activeCar then return c end end end)())
  local veh = car and sl_fleet.vehicleOf(car.id)
  if not veh then return answer(false, strings.t('phone.bring_a_car_of_yours')) end
  if not (slrr_garage and slrr_garage.enterWith) then return answer(false, strings.t('career.not_now')) end
  local ok, why = slrr_garage.enterWith(veh:getID(), 'catalog')
  if not ok then answer(false, why or strings.t('career.not_now')) end
end
function M.despawn(carId) if career() then answer(sl_fleet.despawn(tonumber(carId))) end end
function M.workOn(carId) if career() then answer(sl_fleet.workOn(tonumber(carId))) end end
-- on foot in a garage's doorway: the cars panel (take out, work on, put away); true when it opened. The cars come in the phone's own data.
function M.openGarage(siteId)
  local s = career()
  if not s or #s.cars == 0 then return false end
  local name = siteId
  for _, g in ipairs(progression.garages) do if g.site == siteId then name = g.name end end
  guihooks.trigger('slGarage', { open = true, name = name })
  wantSend = true
  return true
end
function M.closeGarage() guihooks.trigger('slGarage', { open = false }) end
function M.wait(what) if career() then answer(sl_career.skipTime(tostring(what))) end end
function M.enterRoc() if career() then answer(sl_streets.enterRoc()) end end
function M.watchReplay() if career() and sl_replay then answer(sl_replay.watch()) end end
function M.saveClip() if career() and sl_replay then answer(sl_replay.save()) end end
function M.enterLeague(kind) if career() and sl_clubs then answer(sl_clubs.enter(tostring(kind))) end end
function M.borrow(amount) if career() and sl_bank then answer(sl_bank.borrow(tonumber(amount))) end end
-- the Calendar's actions (sl_calendar answers ok, text: the toast is the phone's own)
function M.calendarEnter(eventId, carIds) if career() and sl_calendar and sl_calendar.enter then answer(sl_calendar.enter(tostring(eventId), type(carIds) == 'table' and carIds or nil)) end end
function M.calendarDecline(eventId) if career() and sl_calendar and sl_calendar.decline then answer(sl_calendar.decline(tostring(eventId))) end end
function M.calendarRemind(eventId, on) if career() and sl_calendar and sl_calendar.remind then answer(sl_calendar.remind(tostring(eventId), on == true or on == 'true')) end end
-- the trip: open the pick-cars screen for an event, confirm it (sl_series answers ok, text), close it; the paddock's two buttons. With sl_series missing the player is told, never left with nothing
local function tripAway() answer(false, strings.t('phone.trip_unavailable')) end
function M.travelPick(eventId)
  if not career() then return end
  if not (sl_series and sl_series.options) then tripAway() return end
  local o, why = sl_series.options(tostring(eventId))
  if not o then answer(false, why) return end
  travelPick = o
  wantSend = true
end
function M.travelClose() travelPick = nil wantSend = true end
function M.travelConfirm(eventId, carIds, useLoaner)
  if not career() then return end
  if not (sl_series and sl_series.confirm) then tripAway() return end
  -- the phone sends ids as text: hand sl_series the ids as the options listed them (numbers stay numbers)
  local want, ids = {}, {}
  for _, id in ipairs(type(carIds) == 'table' and carIds or {}) do want[tostring(id)] = true end
  for _, c in ipairs(travelPick and travelPick.cars or {}) do if want[tostring(c.id)] then ids[#ids + 1] = c.id end end
  local ok, text = sl_series.confirm(tostring(eventId), ids, useLoaner == true)
  if ok then travelPick = nil end
  answer(ok, text)
end
function M.hubStart()
  if not career() then return end
  if not (sl_series and sl_series.startNext) then tripAway() return end
  answer(sl_series.startNext())
end
function M.hubHome()
  if not career() then return end
  if not sl_career.returnHome then tripAway() return end
  answer(sl_career.returnHome())      -- (the core closes the series: the rounds left count as missed)
end

function M.calendarTravel(eventId) if career() and sl_calendar and sl_calendar.travel then answer(sl_calendar.travel(tostring(eventId))) end end
function M.service(carId, optionId) if career() and sl_service then answer(sl_service.service(tonumber(carId), tostring(optionId))) end end
function M.sponsorAccept() if career() and sl_sponsor then answer(sl_sponsor.accept()) end end
function M.sponsorDecline() if career() and sl_sponsor then answer(sl_sponsor.decline()) end end
function M.sponsorQuit() if career() and sl_sponsor then answer(sl_sponsor.quit()) end end
function M.payDebt(amount) if career() and sl_weekly then answer(sl_weekly.payDebt(tonumber(amount))) end end
function M.repay(amount) if career() and sl_bank then answer(sl_bank.repay(tonumber(amount))) end end
function M.insure(on) if career() and sl_bank then answer(sl_bank.insure(on == true or on == 'true')) end end
function M.takeJob(id) if career() and sl_jobs then answer(sl_jobs.take(tostring(id))) end end
function M.marketOffer(id, amount) if career() and sl_classifieds then answer(sl_classifieds.offer(tostring(id), tonumber(amount))) end end
function M.marketCheck(id) if career() and sl_classifieds then answer(sl_classifieds.check(tostring(id))) end end
function M.marketBuy(id, how) if career() and sl_classifieds then answer(sl_classifieds.buy(tostring(id), tostring(how))) end end
function M.marketBid(id) if career() and sl_classifieds then answer(sl_classifieds.bid(tostring(id))) end end
function M.buyPaper() if career() and sl_classifieds then answer(sl_classifieds.buyPaper()) end end
function M.buyAtMeet(id) if career() and sl_classifieds then answer(sl_classifieds.buyAtMeet(tostring(id))) end end
function M.listPart(model, id, channel) if career() and sl_classifieds then answer(sl_classifieds.listPart(tostring(model), tonumber(id), tostring(channel))) end end
function M.acceptOffer(id, index) if career() and sl_classifieds then answer(sl_classifieds.acceptOffer(tostring(id), tonumber(index))) end end
function M.listCar(id) if career() and sl_classifieds then answer(sl_classifieds.listCar(tonumber(id) or id)) end end
function M.withdrawListing(id) if career() and sl_classifieds then answer(sl_classifieds.withdraw(tostring(id))) end end
function M.giveUpJob() if career() and sl_jobs then answer(sl_jobs.giveUp()) end end
function M.jobWay() if career() and sl_jobs then sl_jobs.showWay() end end

function M.taxi(placeId)
  if not career() then
    if sl_cab and sl_cab.callFree then local ok, text = sl_cab.callFree(placeId) guihooks.trigger('slPhoneToast', { text = text }) end      -- (free roam: free; sl_cab checks the switch)
    return
  end
  local ok, why = sl_career.taxi(placeId)
  guihooks.trigger('slPhoneToast', { text = ok and strings.t('phone.your_cab_is_on_its') or why })
end

-- for a game test: open the phone on this app ('home', 'races', 'garage', 'bank', 'me', 'jobs', 'wait', 'help', 'settings', 'club', 'turf', 'carmarket', 'partmarket', 'phone', 'messages', 'contacts', 'cab')
function M.go(app)
  if not career() and not freeRoam() then return end
  if not career() then app = M.freeAppOpens(tostring(app or 'home')) end
  guihooks.trigger('slPhoneGo', { app = tostring(app or 'home') })
  wantSend = true
end

-- the K key (rebindable in Options > Controls)
function M.toggle()
  if not career() and not freeRoam() then return end
  guihooks.trigger('slPhoneToggle', {})
  wantSend = true
end

----------------------------------------------------------------------------------------------
-- hooks

M.onStreetLegalChanged = function() wantSend = true end
M.onStreetLegalStopped = function() guihooks.trigger('slPhoneData', { active = false }) end
-- the Wrench Works garage screen has no access to our settings: it is told the text size and the colour-blind palette (event slAccess) when they change and every 5 s
local lastAccess = 0
local function sendAccess()
  if not career() then return end
  guihooks.trigger('slAccess', { textScale = require('sl/core/strings').textScale(sl_options and sl_options.get and sl_options.get('slTextScale')),
    colorBlind = sl_options ~= nil and sl_options.get ~= nil and sl_options.get('slColorBlind') == true })
end
M.sendAccess = sendAccess
M.onStreetLegalOption = function(key) if key == 'slTextScale' or key == 'slColorBlind' then sendAccess() end end
M.onStreetLegalStarted = function() wantSend = true sendAccess() end

M.onStreetLegalText = function(thread, text)
  local s = career()
  if not s then return end
  local name = BENNY.name
  for _, r in ipairs(s.racers) do if r.id == thread then name = roster.displayName(r) end end
  -- the pop-up as the settings say (sl_options): every text, only the racers', or none (all land in Messages)
  local level = sl_options and sl_options.get('slNotify') or 'all'
  if level == 'off' or (level == 'important' and thread == 'benny') then return end
  guihooks.trigger('slPhoneNotify', { thread = thread, name = name, text = text })
end

local freeWas = false
M.onUpdate = function(dtReal)
  routeStep(dtReal)
  sendTimer = sendTimer + dtReal
  -- the clock on the screen moves too: a refresh every few seconds, sooner when something changed
  local free = freeRoam()
  if freeWas and not free then wantSend = true end      -- (the free-roam switch went off: the phone is told)
  freeWas = free
  if (wantSend and sendTimer > (anyOpen() and 0.25 or 1)) or (sendTimer > 5 and (career() or free)) then
    sendTimer, wantSend = 0, false
    send()
    if os.clock() - lastAccess > 5 then lastAccess = os.clock() sendAccess() end
  end
end

return M
