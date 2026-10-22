-- Street Legal: fuel siphoning (extension name: sl_siphon; docs/FUEL_SIPHON.md). On foot, with a jerry can and a siphon tube in the boot, hold the siphon key at a car to move fuel from its tank into the
-- can, or hold the pour key at your own car to pour the can in. The tank is read and written through the game's gameplay interface (core_vehicleBridge: 'energyStorage' and
-- 'setEnergyStorageEnergy'). Taking fuel from a car that is not yours can be noticed. The rules are in sl/core/siphon; the can and the tube are 19's inventory items. OFF by default (part `siphon`).

local M = {}

local rules = require('sl/core/siphon')
local invRules = require('sl/core/inventory')
local heat = require('sl/core/heat')
local strings = require('sl/core/strings')
local features = require('sl/core/features')

local function career() return sl_career and sl_career.isActive and sl_career.isActive() and sl_career.getState() or nil end
local function opt(key, d) local v = sl_options and sl_options.get and sl_options.get(key) if v == nil then return d end return v end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end
local function hint(text) if guihooks and guihooks.message then pcall(guihooks.message, text, 1.5, 'slSiphon') end end

local near                    -- { vid, dist, own, tank } the car in reach of the walking player, refreshed four times a second
local session                 -- the siphon or pour running: { mode = 'take'|'pour', vid, can (a record of s.inventory.cans), own, acc, busy, noticeT }
local held = { take = false, pour = false }
local tickT, hintT, tankT = 0, 0, 0
local fails, dead = 0, false      -- (errors in the tick: after FAIL_MAX the part stops until the career restarts)
local FAIL_MAX = 5

local function vehOf(vid) return be and be.getObjectByID and be:getObjectByID(vid) end

-- the walking player's position, or nil (driving: nothing to siphon from a seat)
local function walker()
  if not (gameplay_walk and gameplay_walk.isWalking and gameplay_walk.isWalking()) then return nil end
  local p = getPlayerVehicle and getPlayerVehicle(0)
  return p and p:getPosition() or nil, p
end

-- the distance from a point to a car: to the middle minus the longer half of its box (a flat estimate of its edge)
local function distTo(veh, pos)
  local ok, d = pcall(function()
    local box = veh:getSpawnWorldOOBB()
    local h = box:getHalfExtents()
    return (box:getCenter() - pos):length() - math.max(h.x, h.y)
  end)
  return ok and d or math.huge
end

-- is the car one of the player's own cars?
local function isOwn(s, vid)
  for _, c in ipairs(s.cars or {}) do
    local v = sl_fleet and sl_fleet.vehicleOf and sl_fleet.vehicleOf(c.id)
    if v and v:getID() == vid then return true end
  end
  return false
end

-- ab's theft rules (sl_theft, the Car theft part), when they answer: fairGame(vid) -> ok, reason ('own' a car that is not for taking, 'running' a moving one) and exposure(vid, noise) -> { witness, alarm }
-- with the heat and the alarm applied by them. nil (no theft part, an error) means: use the rules here.
local function theftCall(name, ...)
  local f = rawget(_G, 'sl_theft') and sl_theft[name]
  if type(f) ~= 'function' then return nil end
  local ok, a, b = pcall(f, ...)
  if not ok then return nil end
  return a, b
end

local function tubeCount() return sl_inventory and sl_inventory.count and sl_inventory.count('siphontube') or 0 end

-- the first can that can take from this tank (partly filled of the same fuel first), the first with fuel that can be poured into it
local function canFor(s, mode, tank)
  local cans = invRules.ensure(s).cans
  local best
  for i, c in ipairs(cans) do
    local ok = mode == 'take' and rules.canTake(c, tank) or (mode == 'pour' and tank and rules.canPour(c, tank))
    if ok and (not best or (c.litres or 0) > (cans[best].litres or 0)) then best = i end
  end
  return best and cans[best] or nil
end

local function requestTank(vid, cb)
  local veh = vehOf(vid)
  if not (veh and core_vehicleBridge and core_vehicleBridge.requestValue) then return false end
  local ok = pcall(core_vehicleBridge.requestValue, veh, function(ret) cb(rules.pick(type(ret) == 'table' and ret[1] or nil)) end, 'energyStorage')
  return ok
end

local function writeTank(vid, tank, litres)
  local veh = vehOf(vid)
  if not (veh and core_vehicleBridge and core_vehicleBridge.executeAction) then return false end
  return pcall(core_vehicleBridge.executeAction, veh, 'setEnergyStorageEnergy', tank.name, rules.joules(tank.fuel, litres))
end

-- the nearest other car within reach of the walking player
local function findNear(s)
  local pos, me = walker()
  if not pos then return nil end
  local best
  for _, veh in ipairs(getAllVehicles and getAllVehicles() or {}) do
    if veh:getID() ~= (me and me:getID()) and (veh:getPosition() - pos):length() < 30 then      -- (a car further than 30 m is never in reach: its box is not read)
      local d = distTo(veh, pos)
      if d <= rules.REACH and (not best or d < best.dist) then best = { vid = veh:getID(), dist = d } end
    end
  end
  if best then best.own = isOwn(s, best.vid) end
  return best
end

local function stop(text)
  if session and text then toast(text) end
  session = nil
end

-- ---- the held keys
function M.hold(mode, down)
  held[mode] = down == true
  if not down then
    if session and session.mode == mode then stop() end
    return
  end
  local s = career()
  if not s or session then return end
  if not near then toast(strings.t('siphon.no_car_near')) return end
  if mode == 'take' then
    if tubeCount() < 1 then toast(strings.t('siphon.need_tube')) return end
    if not near.tank then toast(strings.t('siphon.no_fuel_tank')) return end
    if near.own and opt('slSiphonOwn', true) == false then toast(strings.t('siphon.own_off')) return end
    local fair, why = nil, nil
    if not near.own then fair, why = theftCall('fairGame', near.vid) end
    if fair == false then toast(strings.t(why == 'running' and 'siphon.car_running' or 'siphon.not_fair_game')) return end
    near.theft = fair == true
    local can = canFor(s, 'take', near.tank)
    if not can then
      local any = #invRules.ensure(s).cans > 0
      toast(strings.t(any and 'siphon.can_wrong_or_full' or 'siphon.need_can'))
      return
    end
    session = { mode = 'take', vid = near.vid, can = can, own = near.own, acc = 0, noticeT = 0, theft = near.theft, exposeT = 0 }
    toast(strings.t('siphon.started'))
  else
    if not near.own then toast(strings.t('siphon.pour_own_only')) return end
    if not near.tank then toast(strings.t('siphon.no_fuel_tank')) return end
    local can = canFor(s, 'pour', near.tank)
    if not can then toast(strings.t('siphon.nothing_to_pour')) return end
    session = { mode = 'pour', vid = near.vid, can = can, own = true, acc = 0, noticeT = 0 }
  end
end
function M.holdSiphon(down) M.hold('take', down) end
function M.holdPour(down) M.hold('pour', down) end

-- how risky it is right now: passing cars within 25 m count as witnesses (scaled by the noise setting)
local function witnesses(pos, vid)
  local n = 0
  for _, veh in ipairs(getAllVehicles and getAllVehicles() or {}) do
    if veh:getID() ~= vid then
      local ok, moving, d = pcall(function() return veh:getVelocity():length() > 1, (veh:getPosition() - pos):length() end)
      if ok and moving and d < 25 then n = n + 1 end
    end
  end
  return n * math.max(0, math.min(1, tonumber(opt('slSiphonNoise', 0.5)) or 0.5)) * 2
end

local function notice(s, applied)
  toast(strings.t('siphon.seen'))
  if not applied and sl_career.isNight and sl_career.isNight() then s.heat = heat.raised(s.heat, 0.08) end      -- (heat is a night thing; the theft rules apply their own)
  extensions.hook('onStreetLegalFuelTheft', session and session.vid)
  stop()
end

-- one step of the running siphon or pour: read the tank, move the litres, write the tank
local function step(s, dt)
  local ses = session
  ses.busy = true
  local ok = requestTank(ses.vid, function(tank)
    ses.busy = false
    if session ~= ses then return end
    if not tank then stop(strings.t('siphon.no_fuel_tank')) return end
    if ses.mode == 'take' then
      local moved = rules.take(ses.can, tank, dt, tonumber(opt('slSiphonRate', rules.RATE)) or rules.RATE)
      if moved <= 0 then stop(strings.t(tank.litres - rules.FLOOR * tank.capacity <= 1e-6 and 'siphon.tank_dry' or 'siphon.can_full')) return end
      if not writeTank(ses.vid, tank, tank.litres - moved) then stop(strings.t('siphon.no_fuel_tank')) return end
      ses.can.fuel = tank.fuel
      ses.can.litres = (ses.can.litres or 0) + moved
    else
      local moved = rules.pour(ses.can, tank, dt, rules.RATE * 4)
      if moved <= 0 then stop(strings.t(ses.can.litres <= 1e-6 and 'siphon.can_empty' or 'siphon.tank_full')) return end
      if not writeTank(ses.vid, tank, tank.litres + moved) then stop(strings.t('siphon.no_fuel_tank')) return end
      ses.can.litres = math.max(0, ses.can.litres - moved)
      if ses.can.litres <= 1e-9 then ses.can.fuel = nil end
    end
    extensions.hook('onStreetLegalChanged')
  end)
  if not ok then ses.busy = false stop(strings.t('siphon.no_fuel_tank')) end
end

local function tick(dt)
  dt = tonumber(dt) or 0
  local s = career()
  if not s then session, near = nil, nil return end
  tickT = tickT + dt
  if session then
    local veh = vehOf(session.vid)
    local pos = walker()
    local d = veh and pos and distTo(veh, pos) or math.huge
    local speed = veh and veh:getVelocity():length() or 0
    if rules.interrupted({ held = held[session.mode], dist = d, inCar = pos == nil, carSpeed = speed }) then stop(d > rules.LET_GO and strings.t('siphon.too_far') or nil) return end
    session.acc = session.acc + dt
    if session.acc >= 1 and not session.busy then
      local a = session.acc
      session.acc = 0
      if not session.own and session.mode == 'take' and session.theft then      -- the theft rules decide every ten seconds (witnesses and the car alarm, their heat)
        session.exposeT = (session.exposeT or 0) + a
        if session.exposeT >= 10 then
          session.exposeT = 0
          local ex = theftCall('exposure', session.vid, tonumber(opt('slSiphonNoise', 0.5)) or 0.5)
          if type(ex) == 'table' and (ex.witness or ex.alarm) then notice(s, true) return end
        end
      elseif not session.own and session.mode == 'take' then                  -- somebody else car: the risk of being noticed
        local night = sl_career.isNight and sl_career.isNight() or false
        local r = rules.risk(night, witnesses(pos, session.vid), false, tonumber(opt('slSiphonRisk', 1)) or 1)
        if math.random() < rules.noticed(r, a) then notice(s) return end
      end
      step(s, a)
    end
    return
  end
  if tickT < 0.25 then return end
  tickT = 0
  local was = near
  near = findNear(s)
  if near then
    local vid = near.vid
    if was and was.vid == vid then near.tank = was.tank end                  -- (the same car: its tank stays, read again about once a second)
    tankT = tankT + 0.25
    if not near.tank or tankT >= 1 then
      tankT = 0
      requestTank(vid, function(tank) if near and near.vid == vid then near.tank = tank end end)
    end
    hintT = hintT + 0.25
    if hintT >= 1 then
      hintT = 0
      hint(strings.t(near.own and 'siphon.prompt_own' or 'siphon.prompt'))
    end
  end
end

function M.onUpdate(dt)
  if dead then return end
  local ok, err = pcall(tick, dt)
  if not ok then
    fails = fails + 1
    session, near = nil, nil
    if log then log('E', 'sl_siphon', 'tick failed (' .. fails .. '): ' .. tostring(err)) end
    if fails >= FAIL_MAX then dead = true end
  end
end

function M.status()
  return string.format('near %s, session %s, tube %d', near and (near.vid .. (near.own and ' (own)' or '')) or 'none', session and session.mode or 'none', tubeCount())
end
function M.onStreetLegalStopped() session, near, held.take, held.pour, fails, dead = nil, nil, false, false, 0, false end
function M.onClientEndMission() session, near = nil, nil end

features.gate('siphon', M, nil, nil, { 'hold', 'holdSiphon', 'holdPour', 'status' })

return M
