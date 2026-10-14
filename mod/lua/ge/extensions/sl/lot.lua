-- Street Legal Racing: the car lots (extension name: sl_lot)
-- Walk up to the junkyard's used-car lot, the dealership or the scrap yard and you browse what
-- they have the SLRR way: one car at a time on the display spot, left and right through the
-- row, the camera round it with the mouse. Every car is built as its offer says - a tired
-- stock car, a modified one that needs work, a wreck. Take it for a test drive, buy it (it is
-- yours where it stands: drive it home or have it towed), or walk away. Arrive in one of your
-- own cars and they make you an offer for it instead.

local M = {}

local market = require('sl/core/market')
local builder = require('sl/carBuilder')

local KIND = { junkyard = 'used', dealer = 'dealer', scrapyard = 'scrap' }
local TITLES = { used = 'Used cars', dealer = 'New cars', scrap = 'Scrap yard' }
local TEST_SECONDS = 150

local lot                 -- the open lot: { place, kind, offers, index, veh, building, previousCamera, mode = 'browse'|'test'|'sell' }
local armedAt = {}        -- place id -> true once the player has walked away from it
local test                -- { timeLeft, started } during a test drive
local job                 -- the running build, so a second click does not start another

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

local function displaySpot(place)
  local pos = place.display or (place.pos + place.dir * 7)
  local dir = place.displayDir or place.dir
  return pos, dir
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
  guihooks.trigger('slLotData', {
    open = true, mode = lot.mode, name = lot.place.name, kindTitle = TITLES[lot.kind], kind = lot.kind,
    index = lot.index, count = #lot.offers, offer = offerForUi(lot.offers[lot.index]), building = lot.building,
    money = s.money, testLeft = test and math.ceil(test.timeLeft) or nil,
    sellCar = mine and { name = mine.name, price = lot.kind == 'scrap' and market.scrapValue(mine) or market.resaleValue(mine) } or nil,
  })
end

----------------------------------------------------------------------------------------------
-- the camera: Wrench Works' garage camera, round the display spot

local function cameraOn(pos, dir)
  local ok, camera = pcall(require, 'slrr/garageCamera')
  if not ok then return end
  local site = { spot = pos, dir = dir, halfWidth = 9, backDist = 9, doorDist = -9, ceiling = 8 }
  camera.setup(site, function()
    local veh = lot and lot.veh and getObjectByID(lot.veh)
    return veh and veh:getSpawnWorldOOBB():getCenter() or (pos + vec3(0, 0, 0.7))
  end, 4.6, false)
  camera.onPose = nil
  camera.startOrbit(false)
  core_camera.setByName(0, 'slrrGarage', false)
end

local function cameraOff()
  local ok, camera = pcall(require, 'slrr/garageCamera')
  if ok then camera.stop() end
  if core_camera.getActiveCamName(0) == 'slrrGarage' then
    core_camera.setByName(0, (lot and lot.previousCamera and lot.previousCamera ~= 'slrrGarage') and lot.previousCamera or 'orbit', false)
  end
end

function M.cameraDrag(dx, dy)
  local ok, camera = pcall(require, 'slrr/garageCamera')
  if ok and lot and lot.mode == 'browse' then camera.rotate(tonumber(dx) or 0, tonumber(dy) or 0) end
end

function M.cameraZoom(steps)
  local ok, camera = pcall(require, 'slrr/garageCamera')
  if ok and lot and lot.mode == 'browse' then camera.zoom(tonumber(steps) or 0) end
end

----------------------------------------------------------------------------------------------
-- showing one car of the row

local function dropCar()
  if lot and lot.veh and not lot.sold then
    local veh = getObjectByID(lot.veh)
    if veh then veh:delete() end
  end
  if lot then lot.veh = nil end
end

local function show(index)
  if not lot or lot.building then return end
  lot.index = ((index - 1) % #lot.offers) + 1
  lot.building = true
  send()
  local offer = lot.offers[lot.index]
  local pos, dir = displaySpot(lot.place)
  job = core_jobsystem.create(function(j)
    dropCar()
    local veh = builder.buildOffer(j, offer, pos + vec3(0, 0, 0.4), quatFromDir(dir, vec3(0, 0, 1)))
    if not lot then if veh then veh:delete() end return end
    lot.veh = veh and veh:getID() or nil
    lot.building = false
    if not veh then guihooks.trigger('slPhoneToast', { text = 'That one would not start. Try the next.' }) end
    send()
  end)
end

function M.next() if lot and lot.mode == 'browse' then show(lot.index + 1) end end
function M.prev() if lot and lot.mode == 'browse' then show(lot.index - 1) end end

----------------------------------------------------------------------------------------------
-- opening and closing

local function open(place, mode)
  local s = career()
  if not s or lot then return end
  local kind = KIND[place.kind]
  local offers = {}
  for _, o in ipairs(market.offers(builder.configs(), kind, s.seed, s.day, kind == 'scrap' and 6 or 8)) do
    if not (s.bought or {})[o.id] then offers[#offers + 1] = o end
  end
  lot = { place = place, kind = kind, offers = offers, index = 1, mode = mode or 'browse', previousCamera = core_camera.getActiveCamName(0) }
  armedAt[place.id] = false
  if lot.mode == 'browse' then
    if #offers == 0 then
      guihooks.trigger('slPhoneToast', { text = 'Nothing for sale here today. Come back tomorrow.' })
      lot = nil
      return
    end
    local pos, dir = displaySpot(place)
    cameraOn(pos, dir)
    show(1)
  end
  send()
end

function M.close()
  if not lot then return end
  if test then return end
  dropCar()
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
  if not s or not lot or lot.mode ~= 'browse' or lot.building or not lot.veh then return end
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
  lot.sold = true
  cameraOff()
  lot = nil
  send()
  if veh then
    if gameplay_walk and gameplay_walk.getInVehicle then gameplay_walk.getInVehicle(veh) else be:enterVehicle(0, veh) end
  end
  local broken = #(offer.faults or {}) > 0
  sl_career.sendText('benny', broken and string.format('You bought the %s? It has problems: %s. Drive it home if it goes, or call a tow, and we will sort it in the garage.', offer.name, table.concat(offer.faults, ', '))
    or string.format('Nice, the %s. Bring it to the garage and let us have a look at it.', offer.name), 4)
  return car
end

function M.testDrive()
  local s = career()
  if not s or not lot or lot.mode ~= 'browse' or lot.building or not lot.veh or lot.kind == 'scrap' then return end
  local veh = getObjectByID(lot.veh)
  if not veh then return end
  cameraOff()
  lot.mode = 'test'
  test = { timeLeft = TEST_SECONDS, driven = 0 }
  veh:queueLuaCommand('controller.setFreeze(0) input.event("parkingbrake", 0, FILTER_DIRECT)')
  if gameplay_walk and gameplay_walk.getInVehicle then gameplay_walk.getInVehicle(veh) else be:enterVehicle(0, veh) end
  if core_groundMarkers then core_groundMarkers.setPath(lot.place.pos) end
  send()
end

-- the test drive is over: the car goes back on its spot, the player back out of it
local function endTest()
  if not lot or not test then return end
  test = nil
  local veh = lot.veh and getObjectByID(lot.veh)
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  core_jobsystem.create(function(j)
    guihooks.trigger('slFade', { on = true })
    j.sleep(0.6)
    if gameplay_walk then gameplay_walk.setWalkingMode(true, lot and lot.place.pos + vec3(0, 0, 0.3) or nil, nil, true) end
    j.sleep(0.4)
    if veh and lot then
      local pos, dir = displaySpot(lot.place)
      spawn.safeTeleport(veh, pos + vec3(0, 0, 0.4), quatFromDir(dir, vec3(0, 0, 1)), true)
      veh:queueLuaCommand('input.event("parkingbrake", 1, FILTER_DIRECT) controller.setFreeze(1)')
    end
    if lot then
      lot.mode = 'browse'
      local pos, dir = displaySpot(lot.place)
      cameraOn(pos, dir)
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
    if back or test.timeLeft <= 0 then endTest() end
    return
  end
  if lot then return end
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

local sendTimer = 0
function M.onUpdate(dtReal)
  update(dtReal)
  if test then
    sendTimer = sendTimer + dtReal
    if sendTimer > 1 then sendTimer = 0 send() end
  end
end

function M.request() send() end
function M.onStreetLegalStopped() if lot then dropCar() cameraOff() end lot, test = nil, nil send() end
function M.onClientEndMission() lot, test = nil, nil end

return M
