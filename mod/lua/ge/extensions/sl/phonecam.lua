-- Street Legal: the phone's camera as a camera (extension name: sl_phonecam). Opening the Camera app on the phone puts the view into first person (the driver's camera in a car) and the phone's UI
-- draws a full-screen sideways phone over it (bezel, shutter, zoom, flash, grid: slPhone.js); leaving the app (Back, Home, Esc, closing the phone) puts the previous camera and its field of view back
-- exactly. The zoom is the camera's field of view. The picture itself is the Camera app's own (sl_photos.take: the UI is hidden for it, so the frame is the plain view: the photo challenges read the
-- same picture). Settings (Mods > Street Legal > Screens and texts > Phone camera): the first-person view on/off, the hand sway, the grid, the bezel, the highest zoom. On foot the view is left as it
-- is (the walking camera is Drivers' to say). Not seen in the game.

local M = {}

local prev = nil        -- { cam = the camera name before, fov = its field of view, switched = whether we changed the camera, base = the field of view the zoom divides }

local function opt(key, default)
  local v = sl_options and sl_options.get and sl_options.get(key)
  if v == nil then return default end
  return v
end

function M.active() return prev ~= nil end

function M.enter()
  if prev then return true end
  if not core_camera then return false end
  local okCam, name = pcall(core_camera.getActiveCamName, 0)
  local okFov, fov = pcall(core_camera.getFovDeg)
  prev = { cam = okCam and name or nil, fov = okFov and tonumber(fov) or nil, switched = false }
  prev.base = prev.fov
  local v = getPlayerVehicle and getPlayerVehicle(0)
  local walking = gameplay_walk and gameplay_walk.isWalking and gameplay_walk.isWalking()
  if opt('slCamFirstPerson', true) and v and not walking and prev.cam ~= 'driver' then
    if pcall(core_camera.setByName, 0, 'driver', false) then
      prev.switched = true
      -- the new camera has its own field of view: that is the one the zoom divides
      local ok2, fov2 = pcall(core_camera.getFovDeg)
      prev.base = ok2 and tonumber(fov2) or prev.base
    end
  end
  return true
end

-- the zoom 1..zoomMax as a field of view (the camera's own divided by the zoom)
function M.zoom(z)
  if not prev or not prev.base then return false end
  local max = math.max(1, math.min(8, tonumber(opt('slCamZoomMax', 4)) or 4))
  z = math.max(1, math.min(max, tonumber(z) or 1))
  pcall(core_camera.setFOV, 0, prev.base / z)
  return true
end

function M.leave()
  if not prev then return false end
  local p = prev
  prev = nil
  if core_camera then
    if p.switched and p.cam then pcall(core_camera.setByName, 0, p.cam, false) end
    if p.fov then pcall(core_camera.setFOV, 0, p.fov) end
  end
  return true
end

-- the player left the car or the level ended in the middle of it: the camera is the game's again
function M.onVehicleSwitched() if prev then M.leave() end end
function M.onClientEndMission() prev = nil end
function M.onExtensionUnloaded() if prev then M.leave() end end

return M
