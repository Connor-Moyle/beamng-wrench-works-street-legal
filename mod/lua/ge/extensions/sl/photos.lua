-- Wrench Works: Street Legal: photos (extension name: sl_photos)
-- The phone's Camera app takes a picture of the scene without the UI and keeps it in screenshots/street_legal/ (yours to keep); a copy goes to
-- settings/street_legal/photos/, which the UI can read, for the Gallery app. A photo can be the phone's or the laptop's wallpaper (settings/street_legal/wallpapers.json).
-- A new car is photographed at the end of the purchase reveal (the option Photo of a new car).

local M = {}

local strings = require('sl/core/strings')

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

-- the Camera app's button
function M.take()
  if busy then return false, strings.t('photos.one_moment') end
  core_jobsystem.create(function(j)
    local v = getPlayerVehicle(0)
    local name = M.shoot(j, v and v:getJBeamFilename() or 'photo')
    toast(name and strings.t('photos.photo_saved') or strings.t('photos.photo_failed'))
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
