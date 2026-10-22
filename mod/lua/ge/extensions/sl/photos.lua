-- Wrench Works: Street Legal: photos (extension name: sl_photos)
-- The phone's Camera app takes a picture of the scene without the UI and keeps it in screenshots/street_legal/ (yours to keep); a copy goes to
-- settings/street_legal/photos/, which the UI can read, for the Gallery app. A photo can be the phone's or the laptop's wallpaper (settings/street_legal/wallpapers.json).
-- A new car is photographed at the end of the purchase reveal (the option Photo of a new car).

local M = {}

local strings = require('sl/core/strings')
local pc = require('sl/core/photochallenge')
local weeklyRules = require('sl/core/weekly')
local stateLib = require('sl/core/state')

local SHOTS = 'screenshots/street_legal/'
local UIDIR = 'settings/street_legal/photos/'
local WALLS = 'settings/street_legal/wallpapers.json'
local SHOW = 24               -- photos in the gallery (the newest)
local KEEP = 60               -- copies kept for the UI (the originals in screenshots/ are never deleted)

local busy = false

local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end
local function slug(text) return (tostring(text or 'photo'):gsub('[^%w_%-]', '_')) end
local function stamp() return os.date('%Y%m%d_%H%M%S') end

local function ensureDir(dir) if FS and not FS:directoryExists(dir) then FS:directoryCreate(dir, true) end end

local function readWalls()
  local d = jsonReadFile and jsonReadFile(WALLS)
  return type(d) == 'table' and d or {}
end

-- only a photo of the gallery can be a wallpaper
local function valid(file)
  return type(file) == 'string' and file:match('^/' .. UIDIR:gsub('%-', '%%-') .. '[%w_%-]+%.png$') ~= nil and FS:fileExists(file)
end

-- { phone = '/settings/street_legal/photos/x.png' or nil, laptop = ... }; a photo that is gone does not count
function M.wallpapers()
  local d, out = readWalls(), {}
  if valid(d.phone) then out.phone = d.phone end
  if valid(d.laptop) then out.laptop = d.laptop end
  return out
end

function M.list()
  local files = FS:findFiles('/' .. UIDIR, '*.png', 0, false, true) or {}
  table.sort(files, function(a, b) return a > b end)         -- (the names start with the time: newest first)
  local photos = {}
  for i = 1, math.min(#files, SHOW) do
    local file = files[i]
    photos[#photos + 1] = { file = file, name = (file:match('([^/]+)%.png$') or file) }
  end
  for i = KEEP + 1, #files do FS:removeFile(files[i]) end
  local w = M.wallpapers()
  guihooks.trigger('slPhotos', { photos = photos, phone = w.phone, laptop = w.laptop })
  return #photos
end

function M.setWallpaper(which, file)
  if which ~= 'phone' and which ~= 'laptop' and which ~= 'both' then return false, strings.t('photos.unknown_wallpaper') end
  if file ~= false and not valid(file) then return false, strings.t('photos.that_photo_is_gone') end
  local d = readWalls()
  if which ~= 'laptop' then d.phone = file or nil end
  if which ~= 'phone' then d.laptop = file or nil end
  ensureDir('settings/street_legal/')
  jsonWriteFile(WALLS, d, true)
  if sl_phone and sl_phone.request then sl_phone.request() end
  M.list()
  local text = file and (which == 'phone' and strings.t('photos.phone_wallpaper_set') or strings.t('photos.laptop_wallpaper_set')) or strings.t('photos.wallpaper_back')
  toast(text)
  return true, text
end

-- the picture itself, inside a job j (the caller waits): the game's UI is hidden, the screenshot is taken, the UI comes back. Returns the name
-- (without .png) the file will have in screenshots/street_legal/, or nil when a photo is being taken
function M.shoot(j, label, before, after)
  if busy then return nil end
  busy = true
  ensureDir(SHOTS)
  ensureDir(UIDIR)
  local name = stamp() .. '_' .. slug(label)
  local was
  pcall(function() extensions.load('ui_visibility') was = ui_visibility.get() ui_visibility.set(false) end)
  j.sleep(before or 0.6)
  local ok = pcall(function() createScreenshot2({ filename = SHOTS .. name, writeJPG = false, superSampling = 2 }) end)
  j.sleep(after or 1.5)
  if was ~= nil then pcall(function() ui_visibility.set(was) end) end
  busy = false
  if not ok then return nil end
  -- the file is written a frame or two later: the copy for the UI waits for it
  core_jobsystem.create(function(job)
    for _ = 1, 40 do
      if FS:fileExists(SHOTS .. name .. '.png') then break end
      job.sleep(0.1)
    end
    if FS:fileExists(SHOTS .. name .. '.png') then
      FS:copyFile(SHOTS .. name .. '.png', UIDIR .. name .. '.png')
      M.list()
    end
  end)
  return name
end

-- ---- photo challenges (campaign idea #3; rules in sl/core/photochallenge, design in the control repo: docs/PHOTO_CHALLENGES.md). The option Photo challenges is off by default.
local function enabled() return sl_options and sl_options.get and sl_options.get('slPhotoChallenges') == true end
local function limits()      -- the three rows of the camera page: challenges a week, the radius of "at a place", the pay
  local get = sl_options and sl_options.get
  if get then pc.configure(get('slPhotoPerWeek'), get('slPhotoRadius'), get('slPhotoPay')) end
end
local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

-- the paint of a car as r, g, b in 0..1, from its part config (the same place Wrench Works reads paints); nil when unreadable (unverified for every car)
local function paintOf(veh)
  local ok, rgb = pcall(function()
    local c = core_vehicle_manager.getVehicleData(veh:getID()).config.paints[1].baseColor
    return { tonumber(c[1]) or 0, tonumber(c[2]) or 0, tonumber(c[3]) or 0 }
  end)
  return ok and rgb or nil
end

-- the power in hp from the game's config list (unverified: the field name Power and its unit); nil when not found
local function powerOf(veh)
  local ok, hp = pcall(function()
    local key = tostring(veh.partConfig or ''):match('([^/]+)%.pc$')
    return tonumber(core_vehicles.getModel(veh:getJBeamFilename()).model.configs[key].Power)
  end)
  return ok and hp or nil
end

local function vecArr(v) return { v.x, v.y, v.z } end

-- everything the rules need about the picture the player is about to take: the camera, the player car (box corners, rays, paint, power), the places, the hour
function M.snapshot()
  local veh = getPlayerVehicle(0)
  local q, pos = core_camera.getQuat(), core_camera.getPosition()
  if not veh or not q or not pos then return nil end
  local tanY = math.tan(math.rad(core_camera.getFovDeg() or 60) * 0.5)
  local mode = GFXDevice.getVideoMode()
  local aspect = (mode and mode.height and mode.height > 0) and (mode.width / mode.height) or (16 / 9)
  local cam = { pos = vecArr(pos), fwd = vecArr(q * vec3(0, 1, 0)), right = vecArr(q * vec3(1, 0, 0)), up = vecArr(q * vec3(0, 0, 1)), tanY = tanY, tanX = tanY * aspect }
  local box = veh:getSpawnWorldOOBB()
  local centre = box:getCenter()
  local corners, clear = {}, {}
  for i = 0, 7 do
    local c = box:getPoint(i)
    corners[i + 1] = vecArr(c)
    local aim = c + (centre - c) * 0.12                                  -- (a little inside the box, off the ground)
    local to = aim - pos
    local len = to:length()
    local ok, hit = pcall(castRayStatic, pos, to / math.max(len, 0.01), len)
    clear[i + 1] = ok and type(hit) == 'number' and hit >= len - 0.4
  end
  local places = {}
  for id, p in pairs(sl_career and sl_career.getPlaces and sl_career.getPlaces() or {}) do
    local at = p.at or p.pos
    if at then places[id] = { at.x or at[1], at.y or at[2], at.z or at[3] } end
  end
  local tod = core_environment and core_environment.getTimeOfDay and core_environment.getTimeOfDay()
  local hour = (type(tod) == 'table' and tod.time) and ((tod.time * 24 + 12) % 24) or 12
  return { cam = cam, hour = hour, places = places,
    cars = { { own = true, corners = corners, rayClear = clear, rgb = paintOf(veh), hp = powerOf(veh), pos = vecArr(veh:getPosition()), model = veh:getJBeamFilename() } } }
end

-- the week's challenges, drawn once for the week (the car driven then is the one the colour and power are asked of) and kept in the save with what is done
local function weekList(s)
  local week = weeklyRules.week(s.day)
  local st = s.photoChallenges
  if st and st.week == week then return st end
  local veh = getPlayerVehicle(0)
  local ctx = { ownColours = {}, ownHp = {}, places = {} }
  local rgb = veh and paintOf(veh)
  if rgb then
    local fam = pc.colourFamily(rgb[1], rgb[2], rgb[3])
    if fam ~= 'other' then ctx.ownColours[1] = fam end
  end
  local hp = veh and powerOf(veh)
  if hp then ctx.ownHp[1] = hp end
  local all, ids = sl_career.getPlaces() or {}, {}
  for id, p in pairs(all) do if p.name then ids[#ids + 1] = id end end
  table.sort(ids)
  for _, id in ipairs(ids) do ctx.places[#ctx.places + 1] = { id = id, name = all[id].name } end
  limits()
  s.photoChallenges = { week = week, list = pc.pool(s.seed, week, ctx), done = {} }
  return s.photoChallenges
end

-- to the phone: the challenges of the week, open and done
function M.challenges()
  local s = career()
  if not enabled() or not s then guihooks.trigger('slPhotoChallenges', { on = false }) return end
  local st = weekList(s)
  local out = {}
  for _, c in ipairs(st.list) do
    out[#out + 1] = { id = c.id, text = pc.describe(c), pays = strings.t('photoch.pays', c.money, c.rep), done = st.done[c.id] == true }
  end
  guihooks.trigger('slPhotoChallenges', { on = true, title = strings.t('photoch.title'), list = out })
end

-- judge the shot taken at the shutter against the week's open challenges and pay what passes. Returns the text for the toast, or nil when nothing is asked
local function claim(shot)
  local s = career()
  if not enabled() or not s or not shot then return nil end
  local st = weekList(s)
  limits()
  local texts, bestMiss = {}, nil
  for _, c in ipairs(st.list) do
    if not st.done[c.id] then
      local r = pc.check(c, shot)
      if r.ok then
        st.done[c.id] = true
        sl_career.payOut(c.money, strings.t('photoch.title'))
        stateLib.addRep(s, c.rep)
        texts[#texts + 1] = strings.t('photoch.done', c.money, c.rep)
      elseif not bestMiss or #r.reasons < #bestMiss then
        bestMiss = r.reasons
      end
    end
  end
  if #texts > 0 then extensions.hook('onStreetLegalChanged') M.challenges() return table.concat(texts, ' ') end
  if bestMiss and #bestMiss > 0 then return strings.t('photoch.missed', strings.t(bestMiss[1])) end
  return nil
end

-- for 80: what the rules would see of the car in the picture (paint, power, corners in frame and reached by a ray, the hour); written to the log and shown on the phone
function M.probe()
  local shot = M.snapshot()
  if not shot then toast('photo probe: no camera or car') return nil end
  local car = shot.cars[1]
  local vis = pc.visible(shot.cam, car.corners, car.rayClear)
  local nclear = 0
  for _, c in ipairs(car.rayClear) do if c then nclear = nclear + 1 end end
  local text = string.format('photo probe: %s colour %s (%s) hp %s hour %.1f, in frame %s clear %s big %s height %.2f, rays reaching %d of 8',
    tostring(car.model), car.rgb and string.format('%.2f %.2f %.2f', car.rgb[1], car.rgb[2], car.rgb[3]) or 'unreadable', car.rgb and pc.colourFamily(car.rgb[1], car.rgb[2], car.rgb[3]) or '-',
    tostring(car.hp or 'unreadable'), shot.hour, tostring(vis.seen), tostring(vis.clear), tostring(vis.big), vis.height, nclear)
  log('I', 'sl_photos', text)
  toast(text)
  return text
end

-- the Camera app's button
function M.take()
  if busy then return false, strings.t('photos.one_moment') end
  core_jobsystem.create(function(j)
    local v = getPlayerVehicle(0)
    local okS, shot = false, nil
    if enabled() then okS, shot = pcall(M.snapshot) if not okS then shot = nil end end          -- (before the screen is cleared: it is the picture at the shutter)
    local name = M.shoot(j, v and v:getJBeamFilename() or 'photo')
    local said
    if name and shot then
      local okC, res = pcall(claim, shot)          -- (a throw in the claim must not cost the saved toast)
      if okC then said = res else pcall(log, 'E', 'sl_photos', 'photo challenge claim failed: ' .. tostring(res)) end
    end
    toast(said or (name and strings.t('photos.photo_saved') or strings.t('photos.photo_failed')))
  end)
  return true, strings.t('photos.taking')
end

-- the end of a purchase reveal (inside the reveal's job): a picture of the new car
function M.newCar(j, carName)
  if sl_options and sl_options.get and sl_options.get('slAutoPhoto') == false then return end
  local name = M.shoot(j, 'new_' .. slug(carName), 0.15, 0.5)
  if name then toast(strings.t('photos.new_car_photo')) end
end

M.onExtensionLoaded = function() ensureDir(UIDIR) end

return M
