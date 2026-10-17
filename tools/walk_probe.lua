-- Makes the on-foot player (BeamNG's walking unicycle) WALK, the way a player does, so a doorway or a marker can be tested by walking into it
-- instead of teleporting. Runs in the game's GE Lua (node bng.js run_lua @tools/walk_probe.lua, or the console).
--   WALK_TO = { x = , y = , z = }   where to walk (set it first; z is only for the log)
--   WALK_FROM = { x = , y = , z = } optional: the walker is put there first (a teleport, then it walks)
--   WALK_SECONDS = 40               optional: give up after this long (default 40)
--   WALK_EXIT = true                optional: the player is in a car: get out first, the way the game's own key does with the career's
--                                   action filters up: gameplay_walk.setWalkingMode(true, nil, nil, true) (force: toggleWalkingMode refuses
--                                   a car that is not at parking speed or while toggling is off, which is how a bought car stays 'roamer')
-- It does what the walking controls do (lua/vehicle/controller/playerController.lua): the walker goes where the walking camera looks, so the
-- camera is turned to the target (unicycle camera setCustomData, as gameplay_walk does) and the forward axis is held (walkUpDownRaw 1),
-- at normal walking speed (the controller's speed coefficient 0). Every second it logs the distance (log tag walk_probe) and WALK_STATUS is
-- 'walking', 'arrived' (within 0.5 m) or 'stuck' (no progress for 4 s, or WALK_SECONDS up). Stop it early with WALK_STATUS = 'stop'.
--   return WALK_STATUS      read it from run_lua afterwards; the last line of the log has the distance and speed

local TAG = 'walk_probe'
local target = rawget(_G, 'WALK_TO')
if type(target) ~= 'table' or not tonumber(target.x) or not tonumber(target.y) then
  rawset(_G, 'WALK_STATUS', 'stuck')
  return 'set WALK_TO = { x = , y = , z = } first'
end
local goal = vec3(tonumber(target.x), tonumber(target.y), tonumber(target.z) or 0)
local seconds = tonumber(rawget(_G, 'WALK_SECONDS')) or 40

local function walker() local v = getPlayerVehicle(0) return v and v:getJBeamFilename() == 'unicycle' and v or nil end
local function control(v, value)
  v:queueLuaCommand('local c = controller.getControllerSafe("playerController") if c then c.walkUpDownRaw(' .. value .. ') c.walkLeftRightRaw(0) end')
end
local function faceTo(v, toward)
  local d = toward - v:getPosition()
  d.z = 0
  if d:length() < 0.05 then return end
  local cam = core_camera.getCameraDataById(v:getId())
  if cam and cam.unicycle and cam.unicycle.setCustomData then
    cam.unicycle:setCustomData({ front = d:normalized(), up = vec3(0, 0, 1) })
  end
end

local exit = rawget(_G, 'WALK_EXIT') == true
if not walker() and not exit then
  rawset(_G, 'WALK_STATUS', 'stuck')
  log('W', TAG, 'the player is not on foot (no walking unicycle); set WALK_EXIT = true to get out of the car first')
  return 'the player is not on foot'
end

rawset(_G, 'WALK_STATUS', 'walking')
core_jobsystem.create(function(job)
  if exit and not walker() then
    local ok = gameplay_walk and gameplay_walk.setWalkingMode and gameplay_walk.setWalkingMode(true, nil, nil, true)
    local waited = 0
    while not walker() and waited < 6 do job.sleep(0.2) waited = waited + 0.2 end
    if not walker() then
      rawset(_G, 'WALK_STATUS', 'stuck')
      log('W', TAG, 'could not get out of the car (setWalkingMode returned ' .. tostring(ok) .. ')')
      return
    end
    log('I', TAG, 'out of the car: the player is the walking unicycle now')
    job.sleep(1)
  end
  local v0 = walker()
  local from = rawget(_G, 'WALK_FROM')
  if type(from) == 'table' and tonumber(from.x) and tonumber(from.y) then
    local face = goal - vec3(tonumber(from.x), tonumber(from.y), 0)
    face.z = 0
    spawn.safeTeleport(v0, vec3(tonumber(from.x), tonumber(from.y), tonumber(from.z) or v0:getPosition().z), quatFromDir(face:normalized(), vec3(0, 0, 1)), true, nil, nil, nil, false)
    job.sleep(1.5)                                  -- settle on the ground before walking
  end
  local t, lastLog, best, bestAt = 0, 0, math.huge, 0
  while rawget(_G, 'WALK_STATUS') == 'walking' do
    local v = walker()
    if not v then rawset(_G, 'WALK_STATUS', 'stuck') log('W', TAG, 'the walker is gone') break end
    local d = vec3(goal.x - v:getPosition().x, goal.y - v:getPosition().y, 0):length()
    if d < 0.5 then rawset(_G, 'WALK_STATUS', 'arrived') break end
    faceTo(v, goal)
    control(v, 1)
    if t - lastLog >= 1 then
      lastLog = t
      local p = v:getPosition()
      log('I', TAG, string.format('%.1fs  %.2f m to go  at %.1f, %.1f, %.1f  %.2f m/s', t, d, p.x, p.y, p.z, v:getVelocity():length()))
    end
    if d < best - 0.3 then best, bestAt = d, t end
    if t - bestAt > 4 or t > seconds then rawset(_G, 'WALK_STATUS', 'stuck') log('W', TAG, string.format('stuck %.2f m from the target after %.1f s', d, t)) break end
    job.sleep(0.1)
    t = t + 0.1
  end
  if rawget(_G, 'WALK_STATUS') == 'stop' then rawset(_G, 'WALK_STATUS', 'stuck') end
  local v = walker()
  if v then control(v, 0) end
  log('I', TAG, 'finished: ' .. tostring(rawget(_G, 'WALK_STATUS')))
end)
return 'walking to ' .. string.format('%.1f, %.1f', goal.x, goal.y)
