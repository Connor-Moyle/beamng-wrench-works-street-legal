-- Street Legal: what a wheel does in a puddle (vehicle extension slPuddles; loaded into the player's car by the game side, sl/puddlefx.lua, for ANY car: the career's own
-- car extension slCar only exists in fleet cars). The game side sends the puddles near the car, their size as they are now, how wet the road is and which parts are on.
-- A wheel inside one gets drag and, above about 80 km/h, aquaplanes (little grip); the spray, the mist of a wet road and a wet trail are asked of the game side as
-- particles. The rules are in lua/common/sl_puddles.lua (tested offline).

local M = {}

local rules = require('sl_puddles')

local puddleList, puddleWet, puddleFlags = {}, 0, {}
local wheelMult = {}                 -- wheel id -> grip factor of that wheel in water (absent = 1)
local puddleTimer, fxTimer, fxSentEmpty = 0, 0, true
local wheelInAt = {}

function M.wheelFactor(wid) return wheelMult[wid] or 1 end

-- the grip of the tread nodes: with the career's slCar present it multiplies this in (and applies the weather's grip as well); without it we scale the jbeam's friction ourselves
local function applyGrip()
  if slCar and slCar.reapplyGrip then slCar.reapplyGrip() return end
  for wid, wheel in pairs(wheels and wheels.wheels or {}) do
    if wheel.treadNodes and not wheel.isTireDeflated then
      local f = wheelMult[wid] or 1
      for _, cid in pairs(wheel.treadNodes) do
        local n = v.data.nodes[cid]
        local fc = n and n.frictionCoef
        if fc then obj:setNodeFrictionSlidingCoefs(cid, fc * f, (n.slidingFrictionCoef or fc) * f) end
      end
    end
  end
end

-- the tyre module of Car Surface FX, when it tracks this car's tyres, owns the water's grip loss (a slick aquaplanes, a wet tyre copes): it is told the depth and this file stops scaling the friction
local function tyreWater(wid, depth)
  local ok, set = pcall(function()
    local t = rawget(_G, 'carSurfaceFxTyres')
    if t and t.active and t.active() and t.setWheelWater then return t.setWheelWater(wid, depth) end
  end)
  return ok and set == true
end

function M.setPuddles(list, wet, flags)
  puddleList, puddleWet, puddleFlags = list or {}, tonumber(wet) or 0, flags or {}
  if not puddleFlags.physics and next(wheelMult) then wheelMult = {} applyGrip() end
end

local function update(dt)
  puddleTimer = puddleTimer + dt
  if puddleTimer < 0.05 then return end                          -- 20 times a second is plenty
  local step = puddleTimer
  puddleTimer = 0
  if #puddleList == 0 and puddleWet < 0.3 and not next(wheelMult) then return end
  local vel = obj:getVelocity()
  local speed = vel:length()
  local dirx, diry = 0, 0
  if speed > 0.5 then dirx, diry = vel.x / speed, vel.y / speed end
  local base = obj:getPosition()
  local changed, fx = false, {}
  for wid, wheel in pairs(wheels and wheels.wheels or {}) do
    if wheel.node1 and not wheel.isTireDeflated then
      local p = base + obj:getNodePosition(wheel.node1)
      local depth = rules.deepest(puddleList, p.x, p.y)
      if puddleFlags.physics then
        local target = tyreWater(wid, depth) and 1 or rules.wheelGrip(speed * 3.6, depth)
        if math.abs(target - (wheelMult[wid] or 1)) > 0.03 or (target == 1 and wheelMult[wid]) then
          wheelMult[wid] = target ~= 1 and target or nil
          changed = true
        end
        local drag = rules.drag(speed, depth)
        if drag > 0 then pcall(function() obj:applyForceVectorTime(wheel.node1, vec3(-dirx * drag, -diry * drag, 0), step * 1.5) end) end
      end
      if depth > 0 and os.clock() - (wheelInAt[wid] or 0) > 2 then
        wheelInAt[wid] = os.clock()
        obj:queueGameEngineLua(string.format('if sl_puddlefx and sl_puddlefx.wheelIn then sl_puddlefx.wheelIn(%d, %q, %.2f, %.0f) end', obj:getId(), tostring(wid), depth, speed * 3.6))
      end
      local splash = puddleFlags.splash and rules.splash(speed, depth) or 0
      local mist = puddleFlags.mist and rules.mist(puddleWet, speed) or 0
      if splash > 0.02 or mist > 0.02 then
        fx[#fx + 1] = string.format('{%.2f,%.2f,%.2f,%.2f,%.2f}', p.x - dirx * 0.3, p.y - diry * 0.3, p.z - (wheel.radius or 0.3), splash, mist)
      end
    end
  end
  if changed then applyGrip() end
  fxTimer = fxTimer + step
  if fxTimer >= 0.1 and (#fx > 0 or not fxSentEmpty) then
    fxTimer = 0
    fxSentEmpty = #fx == 0
    obj:queueGameEngineLua(string.format('if sl_puddlefx and sl_puddlefx.wheelFx then sl_puddlefx.wheelFx(%d, {%s}, %.2f, %.2f) end', obj:getId(), table.concat(fx, ','), dirx, diry))
  end
end

function M.updateGFX(dt) pcall(update, dt) end
function M.onReset() wheelMult = {} end

return M
