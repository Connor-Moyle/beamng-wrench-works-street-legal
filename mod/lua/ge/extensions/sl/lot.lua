-- Street Legal Racing: the car lots (extension name: sl_lot)
-- Walk up to the junkyard's used-car lot, the dealership or the scrap yard and you browse what
-- they have the SLRR way: one car at a time on the display spot, left and right through the
-- row, the camera round it with the mouse. Every car is built as its offer says - a tired
-- stock car, a modified one that needs work, a wreck. Take it for a test drive, buy it (it is
-- yours where it stands: drive it home or have it towed), or walk away. Arrive in one of your
-- own cars and they make you an offer for it instead.

local M = {}

local market = require('sl/core/market')
local rngLib = require('sl/core/rng')
local builder = require('sl/carBuilder')
local hours = require('sl/core/hours')
local splitphase = require('sl/core/splitphase')
local stockLib = require('sl/core/stockdealers')
local lotcam = require('sl/core/lotcam')
local lotbuild = require('sl/core/lotbuild')
local lotaudio = require('sl/core/lotaudio')

local KIND = { junkyard = 'used', dealer = 'dealer', scrapyard = 'scrap' }
local TITLES = { used = 'Used cars', dealer = 'New cars', scrap = 'Scrap yard' }
local TEST_SECONDS = 150

-- the open lot: { place, kind, offers, spots, cars (index -> vehicle id), index, veh (the one looked at),
--   building, previousCamera, mode = 'browse'|'test'|'sell' }
local lot
local armedAt = {}        -- place id -> true once the player has walked away from it
local test                -- { timeLeft, started } during a test drive
local job                 -- the running build, so a second click does not start another

local SPACING = 4.6       -- metres between cars standing in a row
M.MIN_CARS, M.MAX_CARS = 2, 6

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

-- out to the street: the display spots are boxed in, so a car you drive away (bought or on a test drive) waits on
-- the nearest city lane, in the lane, facing along it, where no other car stands
local roadspot = require('sl/core/roadspot')
function M.toRoad(veh, from)
  local others = {}
  for _, v in ipairs(getAllVehicles()) do if v:getID() ~= veh:getID() then others[#others + 1] = v:getPosition() end end
  local c = roadspot.pick(roadspot.candidates(map.getMap().nodes, from, not map.getRoadRules().rightHandDrive), others)
  if not c then return false end
  veh:queueLuaCommand('controller.setFreeze(0) input.event("parkingbrake", 0, FILTER_DIRECT)')
  spawn.safeTeleport(veh, vec3(c.x, c.y, c.z + 0.4), quatFromDir(vec3(c.dx, c.dy, 0), vec3(0, 0, 1)), true, nil, nil, nil, false)   -- (not repaired)
  return true
end

-- where a car leaves a lot from: a showroom's way out ends on the street (map: "exit"), a yard is the street
local function leaveFrom(place) return place.exit and place.exit[#place.exit] or place.pos end

-- fade out, the car to the road, the player in it, fade in
local function driveAwayFromRoad(veh, from)
  core_jobsystem.create(function(j)
    guihooks.trigger('slFade', { on = true })
    j.sleep(0.6)
    if not M.toRoad(veh, from) then veh:queueLuaCommand('controller.setFreeze(0) input.event("parkingbrake", 0, FILTER_DIRECT)') end
    j.sleep(0.3)
    if gameplay_walk and gameplay_walk.getInVehicle then gameplay_walk.getInVehicle(veh) else be:enterVehicle(0, veh) end
    j.sleep(0.3)
    guihooks.trigger('slFade', { on = false })
  end)
end

local function displaySpot(place)
  local pos = place.display or (place.pos + place.dir * 7)
  local dir = place.displayDir or place.dir
  return pos, dir
end

-- where the cars stand: the map's own spots for this lot, or a row side by side through the
-- display spot, all facing the same way. Returns { { pos, dir } } with n entries.
local function spots(place, n)
  if place.displays and #place.displays >= n then
    local out = {}
    for i = 1, n do out[i] = place.displays[i] end
    return out
  end
  local base, dir = displaySpot(place)
  local side = vec3(dir.y, -dir.x, 0)
  local out = {}
  for i = 1, n do out[i] = { pos = base + side * ((i - (n + 1) / 2) * SPACING), dir = dir } end
  return out
end

----------------------------------------------------------------------------------------------
-- the screen

local function offerForUi(o)
  if not o then return nil end
  return { name = o.name, brand = o.brand, title = o.title, condition = o.condition, damage = o.damage, mileage = o.mileage,
    faults = o.faults, mods = o.mods, price = o.price, value = o.value }
end

local function send()
  local s = career()
  if not lot or not s then
    guihooks.trigger('slLotData', { open = false })
    return
  end
  local mine = sl_fleet.currentCar()
  local mineVeh = mine and sl_fleet.vehicleOf(mine.id)
  local parts = mineVeh and builder.partsValue(mineVeh:getID())       -- (what was fitted since counts, as at the sale)
  guihooks.trigger('slLotData', {
    open = true, mode = lot.mode, name = lot.place.name, kindTitle = lot.private and 'Private sale' or TITLES[lot.kind], kind = lot.kind,
    index = lot.index, count = #lot.offers, offer = offerForUi(lot.offers[lot.index]), building = lot.mode == 'browse' and lot.building == true, progress = lot.progress,
    money = s.money, testLeft = test and math.ceil(test.timeLeft) or nil,
    sellCar = mine and { name = mine.name, price = lot.kind == 'scrap' and market.scrapValue(mine, parts) or market.resaleValue(mine, parts) } or nil,
  })
end

----------------------------------------------------------------------------------------------
-- the camera: SLRR's way, a three-quarter view of the car on show from the side the row faces,
-- gliding over to the next one; drag to go round it, the wheel to come closer. (Wrench Works'
-- garage camera was made for a room: on an open lot a fence behind the car pulled it inside the car.)

local cam             -- { yaw, pitch, dist, pos, look, previous }

local function cameraOn()
  if cam or M.NO_CAMERA then return end
  cam = { yaw = math.rad(lotcam.YAWS[1]), pitch = lotcam.PITCH, dist = lotcam.DIST, previous = lot and lot.previousCamera }
  -- the script-driven camera (it takes its pose from us every frame and shows no free-camera help); the free camera as a fallback
  local ok = core_camera and core_camera.setByName and pcall(core_camera.setByName, 0, 'scriptedFree', false, { locked = true, driveRot = true })
  if not ok and commands and commands.setFreeCamera then commands.setFreeCamera() end
end

local function cameraOff()
  if not cam then return end
  local previous = cam.previous
  cam = nil
  local active = core_camera.getActiveCamName(0)
  if active == 'free' or active == 'scriptedFree' then
    local bad = previous == 'free' or previous == 'scriptedFree' or previous == 'slrrGarage'
    core_camera.setByName(0, (previous and not bad) and previous or 'orbit', false)
  end
end

-- the game's walls for the camera: the distance from a to the first static thing on the way to b, or nil
local function wallRay(a, b)
  local d = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2 + (b.z - a.z) ^ 2)
  if d <= 0 then return nil end
  local ok, h = pcall(castRayStatic, vec3(a.x, a.y, a.z), vec3((b.x - a.x) / d, (b.y - a.y) / d, (b.z - a.z) / d), d)
  return ok and h and h < d - 0.01 and h or nil
end

local function updateCamera(dt)
  if not cam or not lot or lot.mode ~= 'browse' then return end
  local sp = lot.spots and lot.spots[lot.index or 1]
  if not sp then return end
  local veh = lot.veh and getObjectByID(lot.veh)
  local target = veh and veh:getSpawnWorldOOBB():getCenter() or (sp.pos + vec3(0, 0, 0.7))
  local t = { x = target.x, y = target.y, z = target.z }
  local dir = { x = sp.dir.x, y = sp.dir.y }
  -- the car in front of the camera changed: stand on the side with room (a rear quarter, away from the wall)
  local key = tostring(lot.index) .. ':' .. tostring(lot.veh)
  if cam.chosenFor ~= key then
    local first = cam.chosenFor == nil
    cam.chosenFor = key
    -- the car's size sets the distance and the downward look; the quarter with room sets the side
    local ok, he = pcall(function() return veh and veh:getSpawnWorldOOBB():getHalfExtents() end)
    local diag = ok and he and (2 * he:length()) or 5.5
    cam.dist, cam.pitch = lotcam.frame(diag)
    cam.yaw = lotcam.choose(t, dir, cam.pitch, cam.dist, wallRay)
    -- another car of the row: the camera glides there along the lot (0.8 s), it does not jump
    if not first and cam.pos and cam.look then
      cam.glide = { t = 0, fp = { x = cam.pos.x, y = cam.pos.y, z = cam.pos.z }, fl = { x = cam.look.x, y = cam.look.y, z = cam.look.z } }
    end
  end
  local eye = lotcam.pull(t, lotcam.eyeAt(t, dir, cam.yaw, cam.pitch, cam.dist), wallRay)       -- (never inside a building)
  local want = vec3(eye.x, eye.y, eye.z)
  local k = 1 - math.exp(-4 * math.min(dt, 0.1))
  local aim = target - vec3(0, 0, lotcam.DROP * cam.dist)       -- (aimed below the car: it stands in the upper part of the screen, above the info card)
  if cam.glide then
    cam.glide.t = cam.glide.t + math.min(dt, 0.1)
    local p, l, done = lotcam.glide(cam.glide.fp, { x = want.x, y = want.y, z = want.z }, cam.glide.fl, { x = aim.x, y = aim.y, z = aim.z }, cam.glide.t)
    cam.pos, cam.look = vec3(p.x, p.y, p.z), vec3(l.x, l.y, l.z)
    if done then cam.glide = nil end
  else
    cam.pos = cam.pos and (cam.pos + (want - cam.pos) * k) or want
    cam.look = cam.look and (cam.look + (aim - cam.look) * k) or aim
  end
  -- the script-driven camera takes yaw and pitch (pitch positive = looking down): given in its own terms
  local sf = core_camera.getGlobalCameras and core_camera.getGlobalCameras().scriptedFree
  if sf and sf.setPose and core_camera.getActiveCamName(0) == 'scriptedFree' then
    local yawDeg, pitchDeg = lotcam.angles(cam.look.x - cam.pos.x, cam.look.y - cam.pos.y, cam.look.z - cam.pos.z)
    sf:setPose(cam.pos, yawDeg, pitchDeg, 0)
  else
    core_camera.setPosition(0, cam.pos)
    core_camera.setRotation(0, quatFromDir((cam.look - cam.pos):normalized(), vec3(0, 0, 1)))
  end
end

function M.cameraDrag(dx, dy)
  if not cam then return end
  cam.yaw = cam.yaw - (tonumber(dx) or 0) * 0.008
  cam.pitch = math.max(math.rad(2), math.min(math.rad(60), cam.pitch + (tonumber(dy) or 0) * 0.006))
end

function M.cameraZoom(steps)
  if cam then cam.dist = math.max(4, math.min(14, cam.dist - (tonumber(steps) or 0) * 0.6)) end
end

----------------------------------------------------------------------------------------------
-- showing one car of the row

-- every car of the lot goes, except one just bought
local function dropCars()
  if not lot then return end
  for _, vid in pairs(lot.cars or {}) do
    if vid ~= lot.soldVeh then
      local veh = getObjectByID(vid)
      if veh then veh:delete() end
    end
  end
  lot.cars, lot.veh = {}, nil
end

-- look at another car of the row: the camera glides over to it
local function show(index)
  if not lot then return end
  lot.index = ((index - 1) % #lot.offers) + 1
  lot.veh = lot.cars[lot.index]
  send()
end

function M.next() if lot and lot.mode == 'browse' then show(lot.index + 1) end end
function M.prev() if lot and lot.mode == 'browse' then show(lot.index - 1) end end

-- the cars' sound is off while the row is made (spawning, rebuilding and denting are loud); restored from the player's own settings
local audioMuted = false
local gameAudio = {
  get = function(ch) return Engine.Audio.getChannelVolume(ch, false) end,
  set = function(ch, v) Engine.Audio.setChannelVolume(ch, v, true) end,
}
local function muteCars()
  if audioMuted or not (Engine and Engine.Audio) then return end
  audioMuted = true
  lotaudio.mute(gameAudio)
end
local function unmuteCars()
  if not audioMuted then return end
  audioMuted = false
  lotaudio.restore(gameAudio)
end

-- The whole row is made before the lot shows (the screen says so while it is): first every car is spawned and rebuilt, one at a time
-- (no dents yet), THEN the dents go on one car at a time, each waited for until the car says they are on, with nothing spawning or
-- rebuilding meanwhile (T43: dents applied while the next car spawned beside it killed the game).
-- One lot builds its row at a time: the next lot's build waits for the one still running (or 30 s of its silence), so two lots never
-- spawn and rebuild cars side by side (T29). A build that makes no progress for BUILD_STUCK seconds is given up by onUpdate.
local buildingNow                  -- os.clock() of the last sign of life of the running build
local BUILD_STUCK = 60
local function buildRow()
  local mine = lot
  lot.building = true
  mine.buildAlive = os.clock()
  mine.progress = { phase = 'cars', done = 0, total = #mine.offers }
  muteCars()
  send()
  job = core_jobsystem.create(function(j)
    local gate = os.clock()
    while buildingNow and os.clock() - buildingNow < 30 and os.clock() - gate < 45 and lot == mine do j.sleep(0.2) end
    if lot ~= mine or mine.abandoned then unmuteCars() return end
    buildingNow = os.clock()
    local function alive() mine.buildAlive, buildingNow = os.clock(), os.clock() return lot == mine and not mine.abandoned end
    local pending = {}                    -- car index -> its dents, to go on in the second round
    for i, offer in ipairs(mine.offers) do
      local spot = mine.spots[i]
      local veh, _, dents = builder.buildOffer(j, offer, spot.pos + vec3(0, 0, 0.4), quatFromDir(spot.dir, vec3(0, 0, 1)), { deferDents = true })
      if not alive() then if veh then veh:delete() end buildingNow = nil unmuteCars() return end
      if veh then
        if slrrDrivers and slrrDrivers.setDriver then slrrDrivers.setDriver(veh:getID(), nil) end   -- a car for sale: nobody in it
        mine.cars[i] = veh:getID()
        if dents and #dents > 0 then pending[i] = dents end
      else
        log('W', 'street_legal', 'lot car ' .. tostring(offer.id) .. ' could not be built: left out of the row')
      end
      mine.progress.done = i
      send()
    end
    local order = lotbuild.plan(#mine.offers, pending).dent
    mine.progress = { phase = 'bodywork', done = 0, total = #order }
    send()
    for k, i in ipairs(order) do
      local veh = mine.cars[i] and getObjectByID(mine.cars[i])
      if veh then builder.dentCar(j, veh, pending[i], mine.offers[i]) end
      mine.progress.done = k
      if not alive() then buildingNow = nil unmuteCars() return end
      send()
    end
    buildingNow = nil
    -- the car to show: the one asked for, else the first that was made
    mine.index = lotbuild.shown(#mine.offers, mine.index, function(i) return mine.cars[i] and getObjectByID(mine.cars[i]) end)
    if not mine.index then
      mine.building = false
      unmuteCars()
      guihooks.trigger('slPhoneToast', { text = 'Nothing to see here today. Come back tomorrow.' })
      M.close()
      return
    end
    mine.veh = mine.cars[mine.index]
    mine.building = false
    mine.progress = nil
    unmuteCars()
    send()
  end)
end

----------------------------------------------------------------------------------------------
-- floodlights over the row while you look round (a lot after dark was too dark to see a car)

local lights = {}
local function lightsOff()
  for _, l in ipairs(lights) do pcall(function() l:delete() end) end
  lights = {}
end

M.NO_LIGHTS = false     -- true: no lights over the row (to find out whether they crash the game: T29)
M.NO_CAMERA = false     -- true: the lot does not move the camera
local function lightsOn(row)
  lightsOff()
  if M.NO_LIGHTS then return end
  for i, sp in ipairs(row) do
    local stale = scenetree and scenetree.findObject('slLotLight' .. i)         -- (one left from the last lot would make the name clash)
    if stale then pcall(function() stale:delete() end) end
    local l = createObject('PointLight')
    l.canSave = false
    l.radius = 9
    l:setField('color', 0, '1 0.95 0.85 1')
    l:setField('brightness', 0, '2')
    l:setField('castShadows', 0, '0')
    l:registerObject('slLotLight' .. i)
    local m = MatrixF(true)
    m:setPosition(sp.pos + vec3(0, 0, 4.5))
    l:setTransform(m)
    lights[#lights + 1] = l
  end
end

----------------------------------------------------------------------------------------------
-- opening and closing

-- what stands on a lot today (the lot and the laptop's Dealers list the same cars): its offers, in order, and their kind.
-- `given`: a private seller's own offers. An offer already bought (at the lot or on the laptop) is not offered again.
function M.offersFor(place, s, given)
  local stock = place.stock      -- a stock dealer (the map's own): new or used by its filter, its own cars
  local kind = stock and stock.kind or KIND[place.kind] or 'used'
  -- how many stand on the lot today: 2 to 6, the same all day
  local count = rngLib.new(rngLib.hash(place.id .. ':' .. s.day .. ':' .. s.seed)):int(M.MIN_CARS, M.MAX_CARS)
  if stock and place.displays then count = math.min(math.max(count, 4), #place.displays) end      -- (a stock dealer's cars stand on its parking spots and the slots beside them (sl/core/stockdealers): 4 to 6 where there is room)
  local offers = given or {}
  local pool = builder.forSale()
  if stock and not given then
    if extensions and extensions.load then pcall(extensions.load, 'util_configListGenerator') end      -- (only its filter test; no career module)
    pool = stockLib.pool(pool, stock.filter, util_configListGenerator and function(c, f) return util_configListGenerator.doesVehiclePassFilter(c.raw, f) end)
  end
  for _, o in ipairs(given and {} or market.offers(pool, kind, stock and (s.seed .. ':' .. place.id) or s.seed, s.day, count + 4)) do
    if stock then o.id = place.id .. ':' .. o.id end      -- (an offer is bought once: a stock dealer's ids are its own)
    if not (s.bought or {})[o.id] and #offers < count then offers[#offers + 1] = o end
  end
  return offers, kind
end

local function open(place, mode, given)
  -- the game's prompt that was pressed to get here ("Look at the cars") closes with it, also when the lot is shut or empty
  if ui_missionInfo and ui_missionInfo.closeDialogue then pcall(ui_missionInfo.closeDialogue) end
  local s = career()
  if not s or lot then return end
  local tod = core_environment and core_environment.getTimeOfDay and core_environment.getTimeOfDay()
  local closed = splitphase.closedText('places', place.kind, sl_career.phase()) or (type(tod) == 'table' and tod.time and hours.closedText(place.kind, tod.time))
  if closed then
    armedAt[place.id] = false      -- (said once; it prompts again after you have left)
    guihooks.trigger('slPhoneToast', { text = closed })
    return
  end
  local offers, kind = M.offersFor(place, s, given)
  lot = { place = place, kind = kind, offers = offers, index = 1, cars = {}, mode = mode or 'browse', previousCamera = core_camera.getActiveCamName(0),
    private = place.private }
  armedAt[place.id] = false
  if lot.mode == 'browse' then
    if #offers == 0 then
      guihooks.trigger('slPhoneToast', { text = 'Nothing for sale here today. Come back tomorrow.' })
      lot = nil
      return
    end
    lot.spots = spots(place, #offers)
    lightsOn(lot.spots)
    cameraOn(lot.spots)
    buildRow()
  end
  send()
end

-- a private seller's car (the used-car ads, sl_classifieds): offer as the lots make them ({ name, model, config,
-- condition, faults, mileage, price, value } + listingId), standing on the street by the seller's kerb at pos.
-- Looked round, test driven and bought as at a lot; a sale calls sl_classifieds.onPrivateSold(listingId, carId)
function M.privateOffers(seed, count) return market.offers(builder.forSale(), 'used', seed or 1, 0, count or 6, true) end      -- (no starter car: a seller's ad is not the lot's cheap tired one)
function M.openPrivate(offer, pos, sellerName)
  if not career() or lot or type(offer) ~= 'table' or not pos then return false end
  pos = vec3(pos.x, pos.y, pos.z or 0)
  local others = {}
  for _, v in ipairs(getAllVehicles()) do others[#others + 1] = v:getPosition() end
  local c = roadspot.pick(roadspot.candidates(map.getMap().nodes, pos, not map.getRoadRules().rightHandDrive, 120), others)
  local at, dir = c and vec3(c.x, c.y, c.z) or pos, c and vec3(c.dx, c.dy, 0) or vec3(0, 1, 0)
  open({ id = 'private:' .. tostring(offer.listingId), kind = 'private', name = (sellerName or 'A private seller') .. "'s car",
    pos = pos, dir = dir, displays = { { pos = at, dir = dir } }, private = offer.listingId or true }, 'browse', { offer })
  return lot ~= nil
end

function M.close()
  if not lot then unmuteCars() return end
  if test then return end
  dropCars()
  lightsOff()
  cameraOff()
  lot = nil
  send()
end

-- from "sell" (arrived in your own car) to browsing
function M.browse()
  if not lot or lot.mode ~= 'sell' then return end
  local place = lot.place
  lot = nil
  open(place, 'browse')
end

----------------------------------------------------------------------------------------------
-- buying, test driving, selling

function M.buy()
  local s = career()
  if not s or not lot or lot.mode ~= 'browse' or not lot.veh then return end
  local offer = lot.offers[lot.index]
  if s.money < offer.price then
    guihooks.trigger('slPhoneToast', { text = string.format('It is $%d. You have $%d.', offer.price, s.money) })
    return
  end
  sl_career.addMoney(-offer.price, 'Bought: ' .. offer.name)
  s.bought = s.bought or {}
  s.bought[offer.id] = true
  local car = sl_fleet.registerVehicle(lot.veh, { name = offer.name, brand = offer.brand, value = offer.value, condition = offer.condition,
    faults = offer.faults, mileage = offer.mileage, price = offer.price })
  local veh = getObjectByID(lot.veh)
  local from = leaveFrom(lot.place)
  if lot.private and sl_classifieds and sl_classifieds.onPrivateSold then sl_classifieds.onPrivateSold(lot.private, car and car.id) end
  lot.soldVeh = lot.veh
  cameraOff()
  dropCars()                                    -- the rest of the row goes back inside
  lightsOff()
  lot = nil
  send()
  if veh then driveAwayFromRoad(veh, from) end
  local broken = #(offer.faults or {}) > 0
  sl_career.sendText('benny', broken and string.format('You bought the %s? It has problems: %s. Drive it home if it goes, or call a tow, and we will sort it in the garage.', offer.name, table.concat(offer.faults, ', '))
    or string.format('Nice, the %s. Bring it to the garage and let us have a look at it.', offer.name), 4)
  return car
end

function M.testDrive()
  local s = career()
  if not s or not lot or lot.mode ~= 'browse' or not lot.veh or lot.kind == 'scrap' then return end
  local veh = getObjectByID(lot.veh)
  if not veh then return end
  cameraOff()
  lot.mode = 'test'
  test = { timeLeft = TEST_SECONDS, driven = 0 }
  if slrrDrivers and slrrDrivers.setDriver then slrrDrivers.setDriver(veh:getID(), slrrDrivers.getDefaultDriver and slrrDrivers.getDefaultDriver() or nil) end   -- you, at the wheel
  driveAwayFromRoad(veh, leaveFrom(lot.place))
  if core_groundMarkers then core_groundMarkers.setPath(lot.place.pos) end
  send()
end

-- the test drive is over: the car goes back on its spot, the player back out of it
local function endTest()
  if not lot or not test or test.ending then return end
  test.ending = true                     -- (test stays set until you are back: the 30 m rule would close the lot under you)
  local veh = lot.veh and getObjectByID(lot.veh)
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  core_jobsystem.create(function(j)
    guihooks.trigger('slFade', { on = true })
    j.sleep(0.6)
    if gameplay_walk then gameplay_walk.setWalkingMode(true, lot and lot.place.pos + vec3(0, 0, 0.3) or nil, nil, true) end
    test = nil
    j.sleep(0.4)
    if veh and lot then
      local spot = lot.spots[lot.index]
      spawn.safeTeleport(veh, spot.pos + vec3(0, 0, 0.4), quatFromDir(spot.dir, vec3(0, 0, 1)), true, nil, nil, nil, false)   -- (back as you left it: a teleport never repairs)
      veh:queueLuaCommand('input.event("parkingbrake", 1, FILTER_DIRECT) controller.setFreeze(1)')
    end
    if lot then
      lot.mode = 'browse'
      cameraOn(lot.spots)
    end
    j.sleep(0.3)
    guihooks.trigger('slFade', { on = false })
    send()
  end)
end

function M.endTest() endTest() end

function M.sell()
  if not lot or lot.mode ~= 'sell' then return end
  local car = sl_fleet.currentCar()
  if not car then return end
  local ok, text = sl_fleet.sell(car.id, lot.kind == 'scrap' and 'scrap' or 'lot')
  guihooks.trigger('slPhoneToast', { text = text })
  if ok then lot = nil send() end
end

----------------------------------------------------------------------------------------------
-- walking or driving up to a lot

local function update(dt)
  local s = career()
  if not s then
    if lot then lot = nil end
    return
  end
  local v = getPlayerVehicle(0)
  if not v then return end
  if test then
    test.timeLeft = test.timeLeft - dt
    test.driven = test.driven + dt
    local back = (v:getPosition() - lot.place.pos):length() < 12 and v:getVelocity():length() < 1 and test.driven > 15
    if not test.ending and (back or test.timeLeft <= 0) then endTest() end
    return
  end
  -- walked or driven off (or taken a cab) while the lot was open: it closes
  if lot then
    if (v:getPosition() - lot.place.pos):length() > 30 then M.close() end
    return
  end
  -- the map marks the lots with the game's own markers: then they open from its prompt (below)
  if slrrValoPois then return end
  local pos = v:getPosition()
  local onFoot = v:getJBeamFilename() == 'unicycle'
  for id, place in pairs(sl_career.getPlaces() or {}) do
    if KIND[place.kind] then
      local d = (pos - place.pos):length()
      if d > 15 then armedAt[id] = true end
      if armedAt[id] ~= false and d < 5 and v:getVelocity():length() < 1 then
        if onFoot then
          open(place, 'browse')
        elseif sl_fleet.currentCar() and KIND[place.kind] ~= 'dealer' then
          open(place, 'sell')
        end
        return
      end
    end
  end
end

-- standing in a lot's marker: the game's prompt gets our button (as its gas stations do)
local HEADINGS = { used = 'Used cars', dealer = 'New cars', scrap = 'Scrap yard' }
function M.onActivityAcceptGatherData(elemData, activityData)
  if not career() or lot then return end
  for _, elem in ipairs(elemData or {}) do
    local place = type(elem.placeId) == 'string' and (sl_career.getPlaces() or {})[elem.placeId]      -- (sl_pois' markers carry the place)
    local kind = place and KIND[place.kind]
    if kind then
      local v = getPlayerVehicle(0)
      local onFoot = not v or v:getJBeamFilename() == 'unicycle'
      local selling = not onFoot and sl_fleet.currentCar() and kind ~= 'dealer'
      -- a dealer shows its cars to a driver too: Connor drove to Jefferson Motors and had nothing to press (T33)
      if onFoot or selling or kind == 'dealer' then
        local tod = core_environment and core_environment.getTimeOfDay and core_environment.getTimeOfDay()
        local closed = splitphase.closedText('places', place.kind, sl_career.phase()) or (type(tod) == 'table' and tod.time and hours.closedText(place.kind, tod.time))      -- 'Closed. Opens at 09:00'
        table.insert(activityData, {
          icon = 'poi_arrival_round', heading = place.name, preheadings = { HEADINGS[kind] },
          sorting = { type = 'slrrPlace', id = place.id },
          buttonLabel = closed or (selling and (kind == 'scrap' and 'Scrap your car' or 'Sell your car') or 'Look at the cars'),
          buttonFun = function() open(place, selling and 'sell' or 'browse') end,      -- (shut: open() says so and closes the prompt)
          buttonSoundClass = 'bng_hover_generic',
        })
      end
    end
  end
end

local sendTimer = 0
function M.onUpdate(dtReal)
  update(dtReal)
  if lot and lot.building and lot.buildAlive and os.clock() - lot.buildAlive > BUILD_STUCK then
    log('W', 'street_legal', 'the lot build made no progress for ' .. BUILD_STUCK .. ' s: the row stays as it is')
    lot.building, lot.abandoned = false, true
    buildingNow = nil
    unmuteCars()
    send()
  end
  if audioMuted and not (lot and lot.building) then unmuteCars() end        -- (whatever ended the build: the sound comes back)
  updateCamera(dtReal)
  if test then
    sendTimer = sendTimer + dtReal
    if sendTimer > 1 then sendTimer = 0 send() end
  end
end

function M.request() send() end
function M.onStreetLegalStopped() if lot then dropCars() lightsOff() cameraOff() end lot, test = nil, nil unmuteCars() send() end
function M.onClientEndMission() lot, test, lights, cam = nil, nil, {}, nil unmuteCars() end

return M
