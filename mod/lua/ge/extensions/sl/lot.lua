-- Street Legal Racing: the car lots (extension name: sl_lot)
-- Walk up to the junkyard's used-car lot, the dealership or the scrap yard and you browse what
-- they have the SLRR way: one car at a time on the display spot, left and right through the
-- row, the camera round it with the mouse. Every car is built as its offer says - a tired
-- stock car, a modified one that needs work, a wreck. Take it for a test drive, buy it (it is
-- yours where it stands: drive it home or have it towed), or walk away. Arrive in one of your
-- own cars and they make you an offer for it instead.

local M = {}

local strings = require('sl/core/strings')

local market = require('sl/core/market')
local rngLib = require('sl/core/rng')
local builder = require('sl/carBuilder')
local hours = require('sl/core/hours')
local splitphase = require('sl/core/splitphase')
local carreport = require('sl/core/carreport')
local tiers = require('sl/core/tiers')
local stockLib = require('sl/core/stockdealers')
local lotcam = require('sl/core/lotcam')
local lotfx = require('sl/core/lotfx')
local lotbuild = require('sl/core/lotbuild')
local lotaudio = require('sl/core/lotaudio')

local lotprompt = require('sl/core/lotprompt')
local factoryLib = require('sl/core/factory')
local KIND = { junkyard = 'used', dealer = 'dealer', scrapyard = 'scrap' }
local TITLES = { used = strings.t('pois.used_cars'), dealer = strings.t('pois.new_cars'), scrap = strings.t('pois.scrap_yard') }
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
    faults = o.faults, mods = o.mods, price = o.price, value = o.value, report = carreport.build(o) }
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
    open = true, mode = lot.mode, name = lot.place.name, kindTitle = lot.private and strings.t('lot.private_sale') or TITLES[lot.kind], kind = lot.kind,
    index = lot.index, count = #lot.offers, offer = offerForUi(lot.offers[lot.index]), auction = lot.mode == 'auction' and lot.auction or nil, building = (lot.mode == 'browse' or lot.mode == 'auction') and lot.building == true, progress = lot.progress,
    canFactory = lot.mode == 'browse' and not lot.private and lot.kind == 'dealer' and M.tier(lot.place) == 'high' or nil, factory = lot.factory and M.factoryView() or nil,
    money = s.money, testLeft = test and math.ceil(test.timeLeft) or nil,
    sellCar = mine and { name = mine.name, price = lot.kind == 'scrap' and market.scrapValue(mine, parts) or market.resaleValue(mine, parts) } or nil,
  })
end

----------------------------------------------------------------------------------------------
-- the camera: SLRR's way, a three-quarter view of the car on show from the side the row faces,
-- gliding over to the next one; drag to go round it, the wheel to come closer. (Wrench Works'
-- garage camera was made for a room: on an open lot a fence behind the car pulled it inside the car.)

local cam             -- { yaw, pitch, dist, pos, look, previous }

-- The cinematic touches (each behind a flag, all restored by fxStop): letterbox bars (the UI slides them), the game's depth of field focused on
-- the car, the car's lights on, a slow field-of-view drift. What to show for the camera chain's state is in sl/core/lotfx.
M.FX = { bars = true, dof = true, lights = true, fov = true, dofDebug = false }      -- (dofDebug: the effect's own debug view, red = far blur, blue = near blur, green line = the focus plane)
local DOF_FIELDS = { 'debugModeEnabled', 'autoFocusEnabled', 'focalDist', 'minRange', 'maxRange', 'nearBlurMax', 'farBlurMax', 'nearSlope', 'farSlope' }
local function setBars(on)
  on = (M.FX.bars and on) or false
  if cam and cam.bars == on then return end
  if cam then cam.bars = on end
  guihooks.trigger('slLotBars', { on = on })
end
local function setLit(vid, on)
  local v = vid and getObjectByID(vid)
  if v then v:queueLuaCommand('electrics.setLightsState(' .. (on and 1 or 0) .. ')') end
end
local function dofRestore()
  if not (cam and cam.dofSaved) then return end
  local dof = scenetree and scenetree.findObject('DOFPostEffect')
  if dof then
    for _, k in ipairs(DOF_FIELDS) do if cam.dofSaved[k] ~= nil then pcall(function() dof[k] = cam.dofSaved[k] end) end end
    if not cam.dofSaved.enabled then pcall(function() dof:disable() end) end
  end
  cam.dofSaved = nil
end
local function dofOn(eye, look, c, w)
  local dof = scenetree and scenetree.findObject('DOFPostEffect')
  if not dof then return end
  if not cam.dofSaved then
    local okEn, en = pcall(function() return dof:isEnabled() ~= false end)
    local saved = { enabled = okEn and en }
    for _, k in ipairs(DOF_FIELDS) do saved[k] = dof[k] end
    cam.dofSaved = saved
    pcall(function() dof.autoFocusEnabled = false if not saved.enabled then dof:enable() end end)
  end
  local far = tonumber(VariableRegistry and VariableRegistry.get('$Param::FarDist')) or 2000
  local params = lotfx.dofParams(eye, look, c, cam.L or 4.5, cam.W or 1.9, cam.H or 1.5, far, w)
  for k, v in pairs(params) do pcall(function() dof[k] = v end) end
  pcall(function() dof.debugModeEnabled = M.FX.dofDebug == true end)
end
-- back to the player's own settings: depth of field, field of view, the car's lights, the bars
local function fxStop()
  if not cam then return end
  dofRestore()
  if cam.baseFov then
    local sf = core_camera.getGlobalCameras and core_camera.getGlobalCameras().scriptedFree
    if sf and sf.setFOV then pcall(sf.setFOV, sf, cam.baseFov) end
    cam.baseFov = nil
  end
  if cam.lit then setLit(cam.lit, false) cam.lit = nil end
  setBars(false)
  cam.chain = nil
end

local function cameraOn()
  if cam or M.NO_CAMERA then return end
  cam = { yaw = math.rad(lotcam.YAWS[1]), pitch = lotcam.PITCH, dist = lotcam.DIST, previous = lot and lot.previousCamera }
  -- the script-driven camera (it takes its pose from us every frame and shows no free-camera help); the free camera as a fallback
  local ok = core_camera and core_camera.setByName and pcall(core_camera.setByName, 0, 'scriptedFree', false, { locked = true, driveRot = true })
  if not ok and commands and commands.setFreeCamera then commands.setFreeCamera() end
end

local function cameraOff()
  if not cam then return end
  fxStop()
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

-- The engine shots (C6) open the car's own hood (or engine lid) through its latch controller, as the game does, and shut it again before the next
-- shot: slrrGarageVeh.shutLatches pushes every lid shut and retries while the release's force dies down. A car on show is frozen, so it is let go
-- (parking brake on) while a lid is open and frozen again once it has latched. A car's latch controllers are asked once, when it comes on show.
local latches = {}             -- vehicle id -> the names of its latch controllers
local hoods = {}              -- vehicle id -> { state = 'open' | 'closing', t }
local HOOD_SHUT = 4           -- s from the shut command until the car is frozen again (the latch retries take up to this long)
function M.onLatches(vid, names) latches[vid] = names end
local function askLatches(veh)
  veh:queueLuaCommand([[local n = {} for k, c in pairs(controller.getAllControllers and controller.getAllControllers() or {}) do if type(c) == 'table' and c.detachGroup and c.getGroupState then n[#n + 1] = "'" .. tostring(k):gsub("'", "") .. "'" end end obj:queueGameEngineLua('if sl_lot then sl_lot.onLatches(' .. obj:getID() .. ',{' .. table.concat(n, ',') .. '}) end')]])
end
-- 'front' (a hood), 'rear' (an engine lid) or nil for a car whose lid we cannot open (or do not know yet)
local function lidOf(vid)
  local rear
  for _, name in ipairs(latches[vid] or {}) do
    local n = name:lower()
    if n:find('hood', 1, true) then return 'front' end
    if n:find('enginelid', 1, true) or n:find('enginecover', 1, true) or (n:find('engine', 1, true) and n:find('latch', 1, true)) then rear = true end
  end
  return rear and 'rear' or nil
end
local function openLid(veh, side)
  hoods[veh:getID()] = { state = 'open', t = 0 }
  local pat = side == 'front' and "'hood'" or "'engine'"
  veh:queueLuaCommand('controller.setFreeze(0) input.event("parkingbrake", 1, FILTER_DIRECT) for k, c in pairs(controller.getAllControllers and controller.getAllControllers() or {}) do if type(c) == "table" and c.detachGroup and tostring(k):lower():find(' .. pat .. ', 1, true) then c.detachGroup() end end')
end
local function shutLids()
  for vid, h in pairs(hoods) do
    if h.state == 'open' then
      local v = getObjectByID(vid)
      if v then v:queueLuaCommand('extensions.load("slrrGarageVeh") if slrrGarageVeh and slrrGarageVeh.shutLatches then slrrGarageVeh.shutLatches() end') end
      h.state, h.t = 'closing', 0
    end
  end
end
local function tickLids(dt)
  for vid, h in pairs(hoods) do
    if h.state == 'closing' then
      h.t = h.t + dt
      if h.t >= HOOD_SHUT then
        local v = getObjectByID(vid)
        if v then v:queueLuaCommand('controller.setFreeze(1)') end
        hoods[vid] = nil
      end
    end
  end
end
-- how long a purchase has to wait for the lid of this car to be shut
local function lidWait(vid) local h = hoods[vid] return h and (h.state == 'open' and HOOD_SHUT or math.max(0, HOOD_SHUT - h.t)) or 0 end

-- where the game's own driver camera sits in this car (its 'onboard.driver' camera node): the cabin shot turns its head from there and never moves,
-- so it cannot clip through a seat or the roof. nil when the car has none (the shot then uses a guess).
function M.driverEye(veh)
  local ok, p = pcall(function()
    local node = core_camera.getDriverData(veh)
    return node and (veh:getPosition() + veh:getNodePosition(node))
  end)
  return ok and p and { x = p.x, y = p.y, z = p.z } or nil
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
    cam.L, cam.W = ok and he and 2 * math.max(he.x, he.y) or 4.5, ok and he and 2 * math.min(he.x, he.y) or 1.9
    cam.H, cam.eye = ok and he and 2 * he.z or 1.5, veh and M.driverEye(veh)
    cam.yaw = lotcam.choose(t, dir, cam.pitch, cam.dist, wallRay)
    -- another car of the row: the camera glides there along the lot (0.8 s), it does not jump
    if not first and cam.pos and cam.look then
      local fp, fl = cam.shown and cam.shown.pos or cam.pos, cam.shown and cam.shown.look or cam.look      -- (from what the player sees, also in a detail shot)
      cam.glide = { t = 0, fp = { x = fp.x, y = fp.y, z = fp.z }, fl = { x = fl.x, y = fl.y, z = fl.z } }
    end
    cam.idle, cam.chain = 0, nil
    shutLids()
    if veh and not latches[veh:getID()] then askLatches(veh) end
  end
  cam.t = (cam.t or 0) + math.min(dt, 0.1)
  local eye = lotcam.pull(t, lotcam.eyeAt(t, dir, cam.yaw + lotcam.sway(cam.t), cam.pitch, cam.dist), wallRay)       -- (never inside a building)
  local want = vec3(eye.x, eye.y, eye.z)
  local k = 1 - math.exp(-4 * math.min(dt, 0.1))
  local aim = target                  -- (the car is centred; the card shrinks to a bar while the shots play)
  if cam.glide then
    cam.glide.t = cam.glide.t + math.min(dt, 0.1)
    local p, l, done = lotcam.glide(cam.glide.fp, { x = want.x, y = want.y, z = want.z }, cam.glide.fl, { x = aim.x, y = aim.y, z = aim.z }, cam.glide.t)
    cam.pos, cam.look = vec3(p.x, p.y, p.z), vec3(l.x, l.y, l.z)
    if done then cam.glide = nil end
  else
    cam.pos = cam.pos and (cam.pos + (want - cam.pos) * k) or want
    cam.look = cam.look and (cam.look + (aim - cam.look) * k) or aim
  end
  -- C6: left alone for IDLE seconds, the camera eases into preset detail shots one after another, each eased in from and out to the normal
  -- orbit (never a cut); the player's drag, zoom or another car eases it back at once and the shots wait for the next idle time
  local ds = math.min(dt, 0.1)
  cam.idle = (cam.idle or 0) + ds
  local auto = cam.idle > lotcam.IDLE and not cam.glide and not M.NO_SHOTS and not lot.factory
  -- the next shot, in shuffled order, whose whole drift has a clear view of the car (not through or inside a wall or pillar) and which the car
  -- can do (the engine shots need a lid we can open)
  local vid = lot.veh
  local function pick()
    cam.bag = cam.bag or { bag = {} }
    if cam.force and #cam.force > 0 then return table.remove(cam.force, 1) end      -- (sl_lot.debugShot)
    return lotcam.draw(cam.bag, math.random, function(kind)
      if kind == 'engine' and lidOf(vid) ~= 'front' then return false end
      if kind == 'engine_rear' and lidOf(vid) ~= 'rear' then return false end
      return lotcam.shotClear(kind, t, dir, cam.L or 4.5, cam.W or 1.9, wallRay, cam.eye)
    end)
  end
  local failed, sp2, sl2, e
  cam.chain, sp2, sl2, e, failed = lotcam.chain(cam.chain, ds, auto, { pos = cam.pos, look = cam.look }, { c = t, f = dir, L = cam.L or 4.5, W = cam.W or 1.9, H = cam.H or 1.5, eye = cam.eye }, pick)
  -- the lid is open exactly while an engine shot is on or arriving; shut as soon as it is not (also when the player moves the camera)
  local ch, wantLid = cam.chain, nil
  if ch and (((ch.phase == 'in' or ch.phase == 'shot') and (ch.kind == 'engine' or ch.kind == 'engine_rear')) or (ch.phase == 'trans' and (ch.nextKind == 'engine' or ch.nextKind == 'engine_rear'))) then
    wantLid = (ch.phase == 'trans' and ch.nextKind or ch.kind) == 'engine' and 'front' or 'rear'
  end
  if wantLid and veh and not hoods[vid] then openLid(veh, wantLid) elseif not wantLid then shutLids() end
  if failed then cam.idle = 0 end             -- (none usable: try again after another idle time)
  local pos, look = cam.pos, cam.look
  if sp2 then pos, look = vec3(sp2.x, sp2.y, sp2.z), vec3(sl2.x, sl2.y, sl2.z) end
  e = e or 0
  cam.shown = { pos = pos, look = look }
  -- the touches for this state of the chain
  local kind = ch and (ch.phase == 'trans' and ch.nextKind or ch.kind)
  setBars(lotfx.barsOn(ch))
  local litWant = M.FX.lights and ch and ch.phase ~= 'out' and vid or nil
  if cam.lit ~= litWant then
    if cam.lit then setLit(cam.lit, false) end
    if litWant then setLit(litWant, true) end
    cam.lit = litWant
  end
  if M.FX.dof and ch and e > 0.01 and not lotfx.isCabin(kind) then dofOn(pos, look, t, e) else dofRestore() end
  local sf0 = core_camera.getGlobalCameras and core_camera.getGlobalCameras().scriptedFree
  if M.FX.fov and sf0 and sf0.setFOV then
    if not cam.baseFov and sf0.fov then
      cam.baseFov = sf0.fov
      -- the side shot sizes itself from the real field of view and window shape (logged once, to check them against the picture)
      local okC, fovNow = pcall(function() return core_camera.getFovDeg(0) end)
      local fovDeg = okC and tonumber(fovNow) or sf0.fov
      local canvas = scenetree and scenetree.findObject('Canvas')
      local okW, w, h = pcall(function() return canvas:getWindowClientSizeXY() end)
      local aspect = okW and w and h and h > 0 and w / h or 16 / 9
      lotcam.setView(fovDeg, aspect)
      local L = cam.L or 4.5
      log('I', 'street_legal', string.format('lot camera: scriptedFree fov %s, camera fov %s, window %sx%s (aspect %.2f), half-width tangent %.3f: the side shot stands %.2f m from the centre line of a %.2f m car', tostring(sf0.fov), okC and tostring(fovNow) or 'not read yet', tostring(w), tostring(h), aspect, lotcam.viewTan, math.max((cam.W or 1.9) / 2 + 1.2, L / (2 * lotcam.SIDE_FILL * lotcam.viewTan)), L))
    end
    local drift = lotfx.fovDrift(ch, lotcam.SHOT_TIME)
    if cam.baseFov and (drift ~= 0 or cam.fovDrifted) then pcall(sf0.setFOV, sf0, cam.baseFov - drift) end
    cam.fovDrifted = drift ~= 0
  end
  -- the script-driven camera takes yaw and pitch (pitch positive = looking down): given in its own terms
  local sf = core_camera.getGlobalCameras and core_camera.getGlobalCameras().scriptedFree
  if sf and sf.setPose and core_camera.getActiveCamName(0) == 'scriptedFree' then
    local yawDeg, pitchDeg = lotcam.angles(look.x - pos.x, look.y - pos.y, look.z - pos.z)
    sf:setPose(pos, yawDeg, pitchDeg, 0)
  else
    core_camera.setPosition(0, pos)
    core_camera.setRotation(0, quatFromDir((look - pos):normalized(), vec3(0, 0, 1)))
  end
end

function M.cameraDrag(dx, dy)
  if not cam then return end
  cam.idle = 0
  cam.yaw = cam.yaw - (tonumber(dx) or 0) * 0.008
  cam.pitch = math.max(math.rad(2), math.min(math.rad(60), cam.pitch + (tonumber(dy) or 0) * 0.006))
end

-- for testing: runs this shot now (run_lua: sl_lot.debugShot('engine')) with the lot open on a car; the shots of M.BROWSE_SHOTS (see lotcam)
-- a cabin shot is reached through a side shot first (the chain never starts inside the car)
function M.debugShot(kind)
  if not cam then return false end
  local isCabin = kind == 'cabin' or kind == 'cabin_pass'
  cam.force, cam.chain, cam.idle = isCabin and { 'side', kind } or { kind }, nil, lotcam.IDLE + 1
  return true
end

-- for the in-game suite: what the lot is showing now ({ mode, veh (the shown car's id), index, count, factory (the step), L, W, H })
function M.debugState()
  if not lot then return nil end
  return { mode = lot.mode, veh = lot.veh, index = lot.index, count = #lot.offers, factory = lot.factory and lot.factory.step or nil,
    building = lot.building == true, L = cam and cam.L, W = cam and cam.W, H = cam and cam.H, kind = lot.kind, tier = M.tier(lot.place) }
end

function M.cameraZoom(steps)
  if cam then cam.idle = 0 end
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
  if M.NO_MUTE then return end
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
        if not M.NO_DRIVER_CALL and slrrDrivers and slrrDrivers.setDriver then slrrDrivers.setDriver(veh:getID(), nil) end   -- a car for sale: nobody in it
        mine.cars[i] = veh:getID()
        if dents and #dents > 0 and not M.NO_DENTS then pending[i] = dents end
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
      guihooks.trigger('slPhoneToast', { text = strings.t('lot.nothing_to_see_here_today') })
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
M.NO_DENTS = false      -- true: the cars of a lot are not dented (bisect switch; the plain-beam dents of WW f00078e passed 3 lot runs, 30 builds, no crash)
M.NO_MUTE = false       -- true: the game's sound is not turned down while the row is built
M.NO_DRIVER_CALL = false -- true: slrrDrivers.setDriver is not called for the lot's cars
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

-- the cars a lot can offer: every car for sale, or a stock dealer's by its filter
function M.poolOf(place, given)
  local stock = place.stock
  local pool = builder.forSale()
  if stock and not given then
    if extensions and extensions.load then pcall(extensions.load, 'util_configListGenerator') end      -- (only its filter test; no career module)
    pool = stockLib.pool(pool, stock.filter, util_configListGenerator and function(c, f) return util_configListGenerator.doesVehiclePassFilter(c.raw, f) end)
  end
  return pool
end

-- the tier of a lot (#22): id ('high' | 'mid' | 'low' | 'junk'), label, from the median price of its pool; nil for a place that is not a lot
-- or while its pool is not there yet (not kept then). Kept per place: the pool does not change in a session.
local tierOfPlace = {}
function M.tier(place)
  if type(place) ~= 'table' or not (place.stock or KIND[place.kind]) then return nil end
  local hit = tierOfPlace[place.id]
  if hit then return hit[1], hit[2] end
  local kind = place.stock and place.stock.kind or KIND[place.kind] or 'used'
  local values = {}
  for _, c in ipairs(M.poolOf(place) or {}) do values[#values + 1] = c.value end
  local id, label = tiers.forPool(values, kind)
  if id then tierOfPlace[place.id] = { id, label } end
  return id, label
end

-- what stands on a lot today (the lot and the laptop's Dealers list the same cars): its offers, in order, and their kind.
-- `given`: a private seller's own offers. An offer already bought (at the lot or on the laptop) is not offered again.
function M.offersFor(place, s, given)
  local stock = place.stock      -- a stock dealer (the map's own): new or used by its filter, its own cars
  local kind = stock and stock.kind or KIND[place.kind] or 'used'
  -- how many stand on the lot today: 2 to 6, the same all day
  local count = rngLib.new(rngLib.hash(place.id .. ':' .. s.day .. ':' .. s.seed)):int(M.MIN_CARS, M.MAX_CARS)
  if stock and place.displays then count = math.min(math.max(count, 4), #place.displays) end      -- (a stock dealer's cars stand on its parking spots and the slots beside them (sl/core/stockdealers): 4 to 6 where there is room)
  local offers = given or {}
  local pool = M.poolOf(place, given)
  -- (A2: a dealer shows cars of its own tier. Not the used lots and the scrap yard: their tier is set by the median of a price scaled down, and
  -- cutting their pools to it left the scrap yard with expensive cars that market.offers then refuses: one car on the lot)
  if not given and kind == 'dealer' then pool = tiers.within(pool, M.tier(place), kind) end
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
  local closed = splitphase.closedText('places', place.kind, sl_career.phase(), hours.opensAt(place.kind)) or (type(tod) == 'table' and tod.time and hours.closedText(place.kind, tod.time))
  if closed then
    armedAt[place.id] = false      -- (said once; it prompts again after you have left)
    guihooks.trigger('slPhoneToast', { text = closed })
    return
  end
  local offers, kind = M.offersFor(place, s, given)
  lot = { place = place, kind = kind, offers = offers, index = 1, cars = {}, mode = mode or 'browse', previousCamera = core_camera.getActiveCamName(0),
    private = place.private }
  armedAt[place.id] = false
  if lot.mode == 'browse' or lot.mode == 'auction' then
    if #offers == 0 then
      guihooks.trigger('slPhoneToast', { text = strings.t('lot.nothing_for_sale_here_today') })
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
  open({ id = 'private:' .. tostring(offer.listingId), kind = 'private', name = (sellerName or strings.t('lot.a_private_seller')) .. strings.t('career.s_car'),
    pos = pos, dir = dir, displays = { { pos = at, dir = dir } }, private = offer.listingId or true }, 'browse', { offer })
  return lot ~= nil
end

-- the weekly car auction at the junkyard (sl_carauctions): the six lot cars stand in the yard's bays (the same row build as a dealer's: one car at a time, the
-- dents on the safe path afterwards), the camera is on the lot being bid on; the screen's bar is the bidding bar (state: sl_carauctions' card of the live lot)
function M.openAuction(place, offers)
  if not career() or lot or type(offers) ~= 'table' or #offers == 0 then return false end
  open(place, 'auction', offers)
  return lot ~= nil and lot.mode == 'auction'
end
function M.auctionOpen() return lot ~= nil and lot.mode == 'auction' end
function M.auctionReady() return lot ~= nil and lot.mode == 'auction' and not lot.building end
function M.auctionView(state, index)
  if not lot or lot.mode ~= 'auction' then return end
  lot.auction = state
  if index and index ~= lot.index and not lot.building then show(index) return end      -- (show sends)
  send()
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

-- a car just bought: a short reveal of jump cuts on the car's details (front quarter, wheel, inside, rear), then a smooth move to where the
-- game's chase camera stands, then the player is put in the car WHERE IT STANDS (the row beside it is gone, so it can drive straight out).
-- M.skip() (the Skip button, B on the pad) goes straight to the smooth move: never a cut to the driver's seat.
local CUT_TIME, MOVE_TIME = 1.3, 1.4
local reveal
function M.skip() if reveal then reveal.skip = true end end
-- The lot's display car was spawned without driver props (a lot car has no driver); the car the player owns has them, drawn by the car itself
-- (carBuilder.PLAYER_DRIVER_PROPS). So the bought car is rebuilt from its record at the same spot: damage captured, the car deleted, a new one
-- spawned (never respawned in place: heap corruption). Returns the new vehicle's id, or the old one if it could not be done.
local function withDriverProps(j, veh, car, wait)
  local id, pos, rot = veh:getID(), veh:getPosition(), veh:getRotation()
  if wait > 0 then j.sleep(wait) end            -- (an open hood is shut and latched first: its latch state is part of the saved damage)
  hoods[id] = nil
  car.damage = nil
  veh:queueLuaCommand('extensions.load("slrrGarageVeh") if slrrGarageVeh then slrrGarageVeh.capture() end')
  for _ = 1, 40 do                                -- (sl_fleet.onWrenchWorksDamage answers within a few frames)
    if car.damage then break end
    j.sleep(0.05)
  end
  veh:delete()
  j.sleep(0.5)
  local new = builder.spawnOwned(j, car, pos, rot) or (j.sleep(1) or builder.spawnOwned(j, car, pos, rot))
  if not new then
    car.out, car.where = false, nil               -- (it waits in the garage: nothing lost)
    guihooks.trigger('slPhoneToast', { text = strings.t('lot.bought_car_at_garage') })
    return nil
  end
  sl_fleet.adopt(car.id, new:getID())
  new:queueLuaCommand('controller.setFreeze(0) extensions.load("slrrGarageVeh")')
  return new:getID()
end

local function getInWhereItStands(veh, car, wait)
  local id = veh:getID()
  veh:queueLuaCommand('controller.setFreeze(0) input.event("parkingbrake", 0, FILTER_DIRECT)')
  reveal = {}
  guihooks.trigger('slLotData', { open = true, mode = 'reveal' })
  setBars(true)
  local function revealJob(j)
    if car then id = withDriverProps(j, veh, car, wait or 0) end
    local v = id and getObjectByID(id)
    local from = cam and cam.shown or (cam and cam.pos and cam.look and { pos = cam.pos, look = cam.look })
    local function put(p, l)
      local sf = core_camera.getGlobalCameras and core_camera.getGlobalCameras().scriptedFree
      if sf and sf.setPose and core_camera.getActiveCamName(0) == 'scriptedFree' then
        local yawDeg, pitchDeg = lotcam.angles(l.x - p.x, l.y - p.y, l.z - p.z)
        sf:setPose(vec3(p.x, p.y, p.z), yawDeg, pitchDeg, 0)
      end
    end
    -- runs frame(t) for `dur` seconds (the real clock, so a slow frame does not stretch it); stops early when skipped
    local function run(dur, frame)
      local t, last = 0, os.clock()
      repeat
        j.sleep(0.016)
        local now = os.clock()
        t, last = t + math.min(now - last, 0.1), now
        frame(math.min(t, dur))
      until t >= dur or reveal.skip
    end
    if v and from then
      local c, f = v:getSpawnWorldOOBB():getCenter(), vec3(v:getDirectionVector())
      f = vec3(f.x, f.y, 0):normalized()
      local he = v:getSpawnWorldOOBB():getHalfExtents()
      local L, W = 2 * math.max(he.x, he.y), 2 * math.min(he.x, he.y)
      local cc, ff = { x = c.x, y = c.y, z = c.z }, { x = f.x, y = f.y }
      local pos = { x = from.pos.x, y = from.pos.y, z = from.pos.z }
      local look = { x = from.look.x, y = from.look.y, z = from.look.z }
      local eye = M.driverEye(v)
      for _, kind in ipairs(lotcam.REVEAL_SHOTS) do
        if reveal.skip then break end
        if not lotcam.shotClear(kind, cc, ff, L, W, wallRay, eye) then goto next end      -- (a shot through or inside a pillar is left out)
        setBars(not lotfx.isCabin(kind))
        run(CUT_TIME, function(t) local p, l = lotcam.shot(kind, cc, ff, L, W, t / CUT_TIME, eye); pos, look = p, l; put(p, l) end)      -- (a cut to each: no move in between)
        ::next::
      end
      reveal.skip = false
      setBars(true)
      local p1, l1 = lotcam.chase(cc, ff)
      local sp, sl = pos, look
      run(MOVE_TIME, function(t)
        local _, l = lotcam.glide(sp, p1, sl, l1, t, MOVE_TIME, 0)
        local u = t / MOVE_TIME
        put(lotcam.arc(cc, sp, p1, u * u * (3 - 2 * u)), l)       -- (round the car to the chase pose, not through it)
      end)
      if car and sl_photos and not reveal.skip then sl_photos.newCar(j, car.name) end      -- (a photo of the new car, in the gallery)
    end
  end
  -- whatever happens in the reveal (an error included), the screen, the camera and the game's UI come back
  core_jobsystem.create(function(j)
    local t0 = os.clock()
    local ok, err = pcall(revealJob, j)
    if not ok then log('E', 'street_legal', 'the purchase reveal failed: ' .. tostring(err)) end
    reveal = nil
    setBars(false)
    guihooks.trigger('slLotData', { open = false })
    local v = id and getObjectByID(id)
    log('I', 'street_legal', string.format('purchase: the reveal took %.1f s, the player gets into %s', os.clock() - t0, v and tostring(v:getJBeamFilename()) or 'nothing (the car is gone)'))
    if v then
      pcall(function() if gameplay_walk and gameplay_walk.getInVehicle then gameplay_walk.getInVehicle(v) else be:enterVehicle(0, v) end end)
    end
    j.sleep(0.2)
    cameraOff()                                  -- (a no-op once the game has put its own camera on the car)
  end)
end

function M.buy()
  local s = career()
  if not s or not lot or lot.mode ~= 'browse' or not lot.veh then return end
  local offer = lot.offers[lot.index]
  if s.money < offer.price then
    guihooks.trigger('slPhoneToast', { text = string.format(strings.t('carcare.it_is_d_you_have'), offer.price, s.money) })
    return
  end
  sl_career.addMoney(-offer.price, strings.t('carcare.bought_1', (offer.name)))
  s.bought = s.bought or {}
  s.bought[offer.id] = true
  local car = sl_fleet.registerVehicle(lot.veh, { name = offer.name, brand = offer.brand, value = offer.value, condition = offer.condition,
    faults = offer.faults, mileage = offer.mileage, price = offer.price })
  local veh = getObjectByID(lot.veh)
  if lot.private and sl_classifieds and sl_classifieds.onPrivateSold then sl_classifieds.onPrivateSold(lot.private, car and car.id) end
  lot.soldVeh = lot.veh
  fxStop()
  shutLids()
  local wait = lidWait(lot.soldVeh)
  dropCars()                                    -- the rest of the row goes away; the camera stays and glides to the car (no cut)
  lightsOff()
  lot = nil
  send()
  if veh then getInWhereItStands(veh, car, wait) else cameraOff() end
  local broken = #(offer.faults or {}) > 0
  sl_career.sendText('benny', broken and string.format(strings.t('lot.you_bought_the_s_it'), offer.name, table.concat(offer.faults, ', '))
    or string.format(strings.t('lot.nice_the_s_bring_it'), offer.name), 4)
  return car
end

function M.testDrive()
  shutLids()
  hoods = {}                       -- (the car is driven now: it must not be frozen again when the countdown ends)
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
-- factory orders (docs/FACTORY_ORDER.md): a high-end dealer's catalogue of models and trims, the factory's own options only

local cfgLib = require('sl/factorycfg')
local modelInfo = function(key) return (cfgLib.modelInfo(key)) end

local function catalogue()
  lot.catalogue = lot.catalogue or factoryLib.withSpecial(M.poolOf(lot.place), builder.specialOrder())
  return lot.catalogue
end

-- a model's factory configurator data, read once per lot visit
local function configurator(mi)
  lot.cfgs = lot.cfgs or {}
  lot.cfgs[mi] = lot.cfgs[mi] or cfgLib.configurator(catalogue()[mi])
  return lot.cfgs[mi]
end

-- what the screen shows for the step the player is on: the catalogue (model cards), a model's trims, the configurator
function M.factoryView()
  local f, cat = lot and lot.factory, lot and catalogue()
  if not f then return nil end
  local out = { step = f.step, money = career() and career().money }
  if f.step == 'models' then
    out.models = {}
    for i, m in ipairs(cat) do out.models[i] = cfgLib.modelCard(m, i) end
    return out
  end
  local m = cat[f.mi]
  if not m then return out end
  local card = cfgLib.modelCard(m, f.mi)
  out.model = card.name
  if f.step == 'trims' then
    out.trims = {}
    for i, t in ipairs(m.trims) do out.trims[i] = cfgLib.trimCard(m, t, i) end
  else
    local t = m.trims[f.ti]
    local groups, deltas = cfgLib.groups(configurator(f.mi), f.ti, f.picks)
    out.trim, out.base, out.groups, out.paint = t.name, t.value, groups, f.paint
    out.picture = cfgLib.picture(m.model, t.config)
    out.total = factoryLib.total(t.value, deltas)
    out.swatches = {}
    for _, name in ipairs(f.paints) do out.swatches[#out.swatches + 1] = { name = name, css = factoryLib.css(((modelInfo(m.model).paints or {})[name] or {}).baseColor), on = name == f.paint } end
    out.hours = factoryLib.DELIVERY_HOURS
  end
  return out
end

local function factoryOk() return lot and lot.mode == 'browse' and lot.kind == 'dealer' and not lot.private and M.tier(lot.place) == 'high' end
function M.factoryOpen() if factoryOk() then lot.factory = { step = 'models' } send() end end
function M.factoryBack()
  local f = lot and lot.factory
  if not f then return end
  lot.factory = ({ config = { step = 'trims', mi = f.mi }, trims = { step = 'models' } })[f.step]
  send()
end
function M.factoryModel(i) local f = lot and lot.factory if f and f.step == 'models' and catalogue()[i] then lot.factory = { step = 'trims', mi = i } send() end end
function M.factoryTrim(i)
  local f = lot and lot.factory
  local m = f and f.step == 'trims' and catalogue()[f.mi]
  if m and m.trims[i] then
    local names = {}
    for name in pairs(modelInfo(m.model).paints or {}) do names[#names + 1] = name end
    table.sort(names)
    lot.factory = { step = 'config', mi = f.mi, ti = i, picks = {}, paints = names, paint = names[1] }
    send()
  end
end
function M.factoryPaint(i)
  local f = lot and lot.factory
  if f and f.step == 'config' then f.paint = f.paints[i] or f.paint send() end
end
-- n * 1000 + j: option j of slot number n on the screen
function M.factoryPick(code)
  local f = lot and lot.factory
  if not (f and f.step == 'config') then return end
  local n, j = math.floor(code / 1000), code % 1000
  local groups = cfgLib.groups(configurator(f.mi), f.ti, f.picks)
  for _, g in ipairs(groups) do
    for _, sl in ipairs(g.slots) do
      if sl.n == n and sl.options[j] then f.picks[sl.slot] = sl.options[j].part send() return end
    end
  end
end

function M.factoryBuy()
  local s, f = career(), lot and lot.factory
  local m = f and f.step == 'config' and catalogue()[f.mi]
  if not s or not m then return end
  local trim = m.trims[f.ti]
  local _, deltas = cfgLib.groups(configurator(f.mi), f.ti, f.picks)
  local price = factoryLib.total(trim.value, deltas)
  if s.money < price then
    guihooks.trigger('slPhoneToast', { text = string.format(strings.t('carcare.it_is_d_you_have'), price, s.money) })
    return
  end
  local hour = (s.day or 0) * 24 + math.floor(sl_career.hour and sl_career.hour() or 12)
  if not sl_career.addMoney(-price, strings.t('carcare.bought_1', trim.name)) then return end
  local o = factoryLib.order(m.model, trim, f.paint, hour)
  o.price, o.picks = price, f.picks
  o.brand, o.dealer = m.brand, lot.place.name
  s.factoryOrders = s.factoryOrders or {}
  s.factoryOrders[#s.factoryOrders + 1] = o
  lot.factory = nil
  send()
  sl_career.sendText('benny', string.format(strings.t('lot.factory_ordered'), trim.name, factoryLib.DELIVERY_HOURS), 4)
end

-- the orders still to arrive, for the phone's and the laptop's My cars: { name, dealer, day, hour }
function M.ordersList()
  local s, out = career(), {}
  for _, o in ipairs(s and s.factoryOrders or {}) do
    local day, hour = factoryLib.arrives(o)
    out[#out + 1] = { name = o.name, dealer = o.dealer, day = day, hour = hour }
  end
  return out
end

-- an order that is due is built at the garage forecourt (beside the first place) and becomes one of the player's cars
local delivering, deliverAfter = false, 0
local function deliverOrders(s)
  if delivering or os.clock() < deliverAfter or not s.factoryOrders or #s.factoryOrders == 0 then return end
  deliverAfter = os.clock() + 5
  local pv = getPlayerVehicle(0)
  if pv and pv:getVelocity():length() > 6 then return end         -- (a spawn freezes the game for about a second: not while the player drives fast; tried again in 5 s)
  local o = s.factoryOrders[factoryLib.nextDue(s.factoryOrders, (s.day or 0) * 24 + math.floor(sl_career.hour and sl_career.hour() or 12)) or 0]
  local pos, rot
  if o then pos, rot = sl_fleet.forecourt(s, 1) end
  if not pos then return end
  delivering = true
  core_jobsystem.create(function(j)
    local veh = builder.spawn(j, o.model, cfgLib.pcFor(o.config, o.picks, o.paint and modelInfo(o.model).paints and modelInfo(o.model).paints[o.paint]), pos, rot, true)
    if veh then
      local paint = o.paint and modelInfo(o.model).paints and modelInfo(o.model).paints[o.paint]
      if paint and core_vehicle_colors and core_vehicle_colors.setVehiclePaint then pcall(core_vehicle_colors.setVehiclePaint, 1, paint, veh:getID()) end
      for i, x in ipairs(s.factoryOrders) do if x == o then table.remove(s.factoryOrders, i) break end end
      local active = s.activeCar
      local car = sl_fleet.registerVehicle(veh:getID(), { name = o.name, brand = o.brand, value = o.price, condition = 1, faults = {}, mileage = 0, price = o.price })
      s.activeCar = active            -- (the player keeps the car they are in)
      if car and paint then car.config = car.config or {} car.config.paints = factoryLib.withPaint(car.config.paints, paint) end      -- (saved with the car: it survives a reload and a respawn)
      guihooks.trigger('slPhoneToast', { text = string.format(strings.t('lot.factory_delivered'), o.name) })
      sl_career.sendText('benny', string.format(strings.t('lot.factory_delivered_text'), o.name, o.dealer or ''), 1)
    end
    delivering = false
  end)
end

----------------------------------------------------------------------------------------------
-- walking or driving up to a lot

local walkT = 0
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
    local away = (v:getPosition() - lot.place.pos):length()
    if away > 30 then log('I', 'sl_lot', string.format('the lot closed: the player is %.0f m from it (the limit is 30 m)', away)) M.close() end
    return
  end
  -- the map marks the lots with the game's own markers: then they open from its prompt (below)
  if slrrValoPois then return end
  walkT = walkT + dt                                -- (a few times a second is enough for a walk-up; every frame built a vector for every lot)
  if walkT < 0.25 then return end
  walkT = 0
  local pos = v:getPosition()
  local px, py, pz = pos.x, pos.y, pos.z
  local onFoot = v:getJBeamFilename() == 'unicycle'
  for id, place in pairs(sl_career.getPlaces() or {}) do
    if KIND[place.kind] then
      local pp = place.pos
      local d = math.sqrt((px - pp.x) ^ 2 + (py - pp.y) ^ 2 + (pz - pp.z) ^ 2)
      if d > 15 then armedAt[id] = true end
      if armedAt[id] ~= false and d < 5 and v:getVelocity():length() < 1 then
        open(place, lotprompt.driveUp(KIND[place.kind], onFoot, sl_fleet.currentCar() ~= nil))      -- (no markers, so no prompt to choose in: see lotprompt)
        return
      end
    end
  end
end

-- standing in a lot's marker: the game's prompt gets our button (as its gas stations do)
local HEADINGS = { used = strings.t('pois.used_cars'), dealer = strings.t('pois.new_cars'), scrap = strings.t('pois.scrap_yard') }
function M.onActivityAcceptGatherData(elemData, activityData)
  if not career() or lot then return end
  for _, elem in ipairs(elemData or {}) do
    local place = type(elem.placeId) == 'string' and (sl_career.getPlaces() or {})[elem.placeId]      -- (sl_pois' markers carry the place)
    local kind = place and KIND[place.kind]
    if kind then
      local v = getPlayerVehicle(0)
      local onFoot = not v or v:getJBeamFilename() == 'unicycle'
      local tod = core_environment and core_environment.getTimeOfDay and core_environment.getTimeOfDay()
      local closed = splitphase.closedText('places', place.kind, sl_career.phase(), hours.opensAt(place.kind)) or (type(tod) == 'table' and tod.time and hours.closedText(place.kind, tod.time))      -- 'Closed. Opens at 09:00'
      if place.kind == 'junkyard' and not closed and sl_carauctions and sl_carauctions.yardOpen and sl_carauctions.yardOpen() then      -- the weekly car auction at the yard (sl_carauctions)
        table.insert(activityData, {
          icon = 'poi_arrival_round', heading = place.name, preheadings = { HEADINGS[kind] },
          sorting = { type = 'slrrPlace', id = place.id },
          buttonLabel = strings.t('carauction.join_the_auction'),
          buttonFun = function() pcall(function() sl_carauctions.join() end) end,
          buttonSoundClass = 'bng_hover_generic',
        })
      end
      for _, mode in ipairs(lotprompt.modes(kind, onFoot, sl_fleet.currentCar() ~= nil)) do      -- (a lot that shows cars always lets a driver look: Connor drove to Jefferson Motors and had nothing to press, T33)
        local selling = mode == 'sell'
        table.insert(activityData, {
          icon = 'poi_arrival_round', heading = place.name, preheadings = { HEADINGS[kind] },
          sorting = { type = 'slrrPlace', id = place.id },
          buttonLabel = closed or (selling and (kind == 'scrap' and strings.t('lot.scrap_your_car') or strings.t('lot.sell_your_car')) or strings.t('lot.look_at_the_cars')),
          buttonFun = function() open(place, mode) end,      -- (shut: open() says so and closes the prompt)
          buttonSoundClass = 'bng_hover_generic',
        })
      end
    end
  end
end

local sendTimer = 0
-- The game's own UI (the HUD apps: dials, minimap, messages and tips) is out of the way while a lot is open, the purchase reveal plays and so on,
-- through the game's own app switch (guihooks 'ShowApps', as its observer camera and flowgraph do), so our card, the shop, the Skip button and
-- the letterbox stay. It is shown again the moment the lot is gone, a test drive starts, the career stops or the level unloads.
M.HIDE_GAME_UI = true
local uiHidden = false
function M.uiHidden() return uiHidden end
local function gameUi(show)
  if show == not uiHidden then return end
  uiHidden = not show
  guihooks.trigger('ShowApps', show)
end

function M.onUpdate(dtReal)
  update(dtReal)
  gameUi(not (M.HIDE_GAME_UI and ((lot and lot.mode ~= 'test') or reveal)))
  tickLids(dtReal)
  local cs = career()
  if cs then deliverOrders(cs) end
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
function M.onStreetLegalStopped() reveal = nil gameUi(true) fxStop() setBars(false) if lot then dropCars() lightsOff() cameraOff() end lot, test = nil, nil unmuteCars() send() end
function M.onClientEndMission() reveal = nil gameUi(true) fxStop() setBars(false) guihooks.trigger('slLotData', { open = false }) lot, test, lights, cam = nil, nil, {}, nil unmuteCars() end

return M
