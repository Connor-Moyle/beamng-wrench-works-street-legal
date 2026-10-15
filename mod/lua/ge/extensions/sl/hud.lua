-- Street Legal Racing: the SLRR dashboard (extension name: sl_hud)
-- Speedometer and rev counter, a map that turns with the car, and a damage diagram - each one
-- can be switched off, and the whole thing too (phone > Street cred > Dashboard). Shown while
-- driving in the career; in freeroam as well if that is switched on. The drawing is the UI
-- module ui/modModules/slHud; this side gathers what it shows.

local M = {}

local SETTINGS_FILE = '/settings/street_legal/hud.json'
local DEFAULTS = { enabled = true, speedo = true, tacho = true, map = true, damage = true, units = 'kmh', freeroam = false }

local settings
local function load()
  settings = {}
  local saved = jsonReadFile(SETTINGS_FILE)
  for k, v in pairs(DEFAULTS) do
    if type(saved) == 'table' and type(saved[k]) == type(v) then settings[k] = saved[k] else settings[k] = v end
  end
end

function M.getSettings()
  if not settings then load() end
  return settings
end

local function sendSettings()
  guihooks.trigger('slHudSettings', M.getSettings())
end

-- phone buttons: toggle a part ('enabled', 'speedo', 'tacho', 'map', 'damage', 'freeroam') or the units
function M.toggle(key)
  local s = M.getSettings()
  if key == 'units' then
    s.units = s.units == 'kmh' and 'mph' or 'kmh'
  elseif type(DEFAULTS[key]) == 'boolean' then
    s[key] = not s[key]
  else
    return
  end
  jsonWriteFile(SETTINGS_FILE, s, true)
  sendSettings()
  extensions.hook('onStreetLegalChanged')
end

----------------------------------------------------------------------------------------------
-- what the car says (asked for from its own Lua a few times a second)

local car = {}              -- { rpm, maxRpm, gear, speed, body = { FL.. }, engine = 0|1|2, tyres = { FL.. } }
local carId

function M.onVehicleData(id, data)
  if id ~= carId or type(data) ~= 'table' then return end
  for k, v in pairs(data) do car[k] = v end
end

local ASK_FAST = [[obj:queueGameEngineLua(string.format("sl_hud.onVehicleData(%d,%s)", obj:getId(), serialize({
  rpm = electrics.values.rpm or 0, maxRpm = electrics.values.maxrpm or 0, gear = electrics.values.gear,
  speed = electrics.values.wheelspeed or electrics.values.airspeed or 0 })))]]

-- body: six zones, how much of each is bent (0..1); engine: 0 fine, 1 trouble, 2 dead; tyres: burst or not
local ASK_DAMAGE = [[
local d = damageTracker and damageTracker.getDamage or function() return false end
local body = {}
for _, z in ipairs({ 'FL', 'FR', 'ML', 'MR', 'RL', 'RR' }) do local v = d('body', z) body[z] = type(v) == 'number' and v or 0 end
local dead, trouble = false, false
for _, k in ipairs({ 'engineDisabled', 'engineLockedUp', 'engineHydrolocked', 'blockMelted', 'cylinderWallsMelted', 'catastrophicOverrevDamage', 'catastrophicOverTorqueDamage' }) do if d('engine', k) then dead = true end end
for _, k in ipairs({ 'headGasketDamaged', 'pistonRingsDamaged', 'rodBearingsDamaged', 'radiatorLeak', 'oilpanLeak', 'oilRadiatorLeak', 'impactDamage', 'engineReducedTorque', 'coolantOverheating', 'oilOverheating', 'exhaustBroken', 'turbochargerDamaged', 'superchargerDamaged', 'inductionSystemDamaged' }) do if d('engine', k) then trouble = true end end
local tyres = {}
for _, w in ipairs({ 'FL', 'FR', 'RL', 'RR' }) do tyres[w] = d('wheels', w) == true end
obj:queueGameEngineLua(string.format("sl_hud.onVehicleData(%d,%s)", obj:getId(), serialize({ body = body, engine = dead and 2 or (trouble and 1 or 0), tyres = tyres })))
]]

----------------------------------------------------------------------------------------------
-- the road map, sent once a level: every navgraph road as line segments, plus the places

local mapSent
local function sendMap()
  local ok, m = pcall(function() return map.getMap() end)
  if not ok or type(m) ~= 'table' or not m.nodes then return end
  local segs, seen = {}, {}
  for name, n in pairs(m.nodes) do
    for other in pairs(n.links or {}) do
      local o = m.nodes[other]
      local key = name < other and (name .. '|' .. other) or (other .. '|' .. name)
      if o and not seen[key] then
        seen[key] = true
        segs[#segs + 1] = math.floor(n.pos.x + 0.5)
        segs[#segs + 1] = math.floor(n.pos.y + 0.5)
        segs[#segs + 1] = math.floor(o.pos.x + 0.5)
        segs[#segs + 1] = math.floor(o.pos.y + 0.5)
      end
    end
  end
  local places = {}
  for id, p in pairs(sl_career and sl_career.getPlaces and sl_career.getPlaces() or {}) do
    places[#places + 1] = { id = id, kind = p.kind, name = p.name, x = math.floor(p.pos.x), y = math.floor(p.pos.y) }
  end
  guihooks.trigger('slHudMap', { segs = segs, places = places })
  mapSent = true
end

----------------------------------------------------------------------------------------------
-- every frame: whether to show, and what

local fastTimer, damageTimer, sendTimer = 0, 0, 0
local shown = false

-- with the dashboard on, the game's own rev counter and damage app make way for it: the career
-- uses the 'streetLegal' app layout (settings/ui_apps/originalLayouts/default/streetLegal.uilayout.json)
-- (checked against the layout in use, as walking and the garage set their own and hand back 'freeroam')
local layoutSet, layoutTimer = nil, 0
local function useLayout(dt)
  layoutTimer = layoutTimer + dt
  if layoutTimer < 0.5 or not core_gamestate or not core_gamestate.setGameState then return end
  layoutTimer = 0
  local current = core_gamestate.state and core_gamestate.state.appLayout
  local career = sl_career and sl_career.isActive and sl_career.isActive()
  if career and M.getSettings().enabled then
    if current == 'freeroam' then core_gamestate.setGameState('freeroam', 'streetLegal') layoutSet = true end
  elseif layoutSet and current == 'streetLegal' then
    core_gamestate.setGameState('freeroam', 'freeroam')
    layoutSet = nil
  end
end

local function wanted()
  local s = M.getSettings()
  if not s.enabled then return nil end
  local v = getPlayerVehicle(0)
  if not v or v:getJBeamFilename() == 'unicycle' then return nil end
  local career = sl_career and sl_career.isActive and sl_career.isActive()
  if not career and not s.freeroam then return nil end
  local cam = core_camera and core_camera.getActiveCamName and core_camera.getActiveCamName(0)
  if cam == 'slrrGarage' or cam == 'free' then return nil end           -- in the garage or looking round a lot
  if freeroam_bigMapMode and freeroam_bigMapMode.bigMapActive and freeroam_bigMapMode.bigMapActive() then return nil end
  return v
end

function M.onUpdate(dtReal)
  useLayout(dtReal)
  local v = wanted()
  if not v then
    if shown then shown = false guihooks.trigger('slHud', { show = false }) end
    return
  end
  if v:getID() ~= carId then carId, car = v:getID(), {} end
  if not mapSent then sendMap() end
  fastTimer, damageTimer, sendTimer = fastTimer + dtReal, damageTimer + dtReal, sendTimer + dtReal
  if fastTimer > 0.06 then fastTimer = 0 v:queueLuaCommand(ASK_FAST) end
  if damageTimer > 0.5 then damageTimer = 0 v:queueLuaCommand(ASK_DAMAGE) end
  if sendTimer < 0.06 then return end
  sendTimer = 0
  local pos, dir = v:getPosition(), v:getDirectionVector()
  local h = sl_career and sl_career.getState and sl_career.isActive() and sl_career.getState() or nil
  shown = true
  guihooks.trigger('slHud', {
    show = true, settings = M.getSettings(),
    speed = car.speed or v:getVelocity():length(), rpm = car.rpm or 0, maxRpm = car.maxRpm or 0, gear = car.gear,
    x = pos.x, y = pos.y, heading = math.atan2(dir.x, dir.y),
    body = car.body, engine = car.engine, tyres = car.tyres,
    target = h and core_groundMarkers and core_groundMarkers.endWP and core_groundMarkers.endWP[1] and
      (function() local t = core_groundMarkers.endWP[1] return type(t) == 'cdata' and { x = t.x, y = t.y } or nil end)() or nil,
  })
end

function M.request() mapSent = false sendSettings() end
function M.onClientEndMission() mapSent, shown, carId, car, layoutSet = false, false, nil, {}, nil end
function M.onClientPostStartMission() mapSent = false end
M.onStreetLegalStarted = function() mapSent = false end

return M
