-- Street Legal Racing: the SLRR dashboard (extension name: sl_hud)
-- Speedometer and rev counter, a map that turns with the car, and a damage diagram - each one
-- can be switched off, and the whole thing too (phone > Street cred > Dashboard). Shown while
-- driving in the career; in freeroam as well if that is switched on. The drawing is the UI
-- module ui/modModules/slHud; this side gathers what it shows.

local M = {}

local SETTINGS_FILE = '/settings/street_legal/hud.json'
local DEFAULTS = { enabled = false, speedo = true, tacho = true, map = true, damage = true, units = 'kmh', freeroam = false, enabledChosen = false }

-- #33 the game's own UI is the default in the career. The SLRR dashboard is an option (the Settings app: 'SLRR dashboard', sl_options slDashboard,
-- off until the player turns it on; also phone > Street cred > Dashboard and the bindable 'dashboard' key). Its parts and units are kept in hud.json.
local settings
local function load()
  settings = {}
  local saved = jsonReadFile(SETTINGS_FILE)
  for k, v in pairs(DEFAULTS) do
    if type(saved) == 'table' and type(saved[k]) == type(v) then settings[k] = saved[k] else settings[k] = v end
  end
  settings.enabledChosen = true
end

local function dashboardOn() return sl_options ~= nil and sl_options.get ~= nil and sl_options.get('slDashboard') == true end

function M.getSettings()
  if not settings then load() end
  settings.enabled = dashboardOn()          -- (the option decides: an old hud.json 'enabled' no longer does)
  settings.textScale = require('sl/core/strings').textScale(sl_options and sl_options.get and sl_options.get('slTextScale'))      -- (#51)
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
  elseif key == 'enabled' then
    if sl_options and sl_options.set then sl_options.set('slDashboard', not dashboardOn()) end
    s.enabled = dashboardOn()
  elseif type(DEFAULTS[key]) == 'boolean' and key ~= 'enabledChosen' then
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
  -- the map may bring SLRR's own navigator picture: /street_legal/minimap/<name>.json
  -- { image, x0, y0, x1, y1 } (world x/y at the image's left/top and right/bottom), <name> part of the level id,
  -- and optionally "tiles": a list of such pictures, drawn in order (the whole level, then the city on top)
  local pictures
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier() or ''
  for _, f in ipairs(FS:findFiles('/street_legal/minimap/', '*.json', 0, false, false) or {}) do
    local name = f:match('([^/]+)%.json$')
    local d = name and level:find(name, 1, true) and jsonReadFile(f)
    if type(d) == 'table' then
      local list = {}
      for _, t in ipairs(type(d.tiles) == 'table' and #d.tiles > 0 and d.tiles or { d }) do
        if type(t) == 'table' and t.image and tonumber(t.x0) and tonumber(t.x1) and tonumber(t.y0) and tonumber(t.y1) then
          list[#list + 1] = { url = '/street_legal/minimap/' .. t.image, x0 = t.x0, y0 = t.y0, x1 = t.x1, y1 = t.y1 }
        end
      end
      if #list > 0 then pictures = list end
    end
  end
  guihooks.trigger('slHudMap', { segs = segs, places = places, pictures = pictures })
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
  -- a mission that ended before the career started can leave its layout behind (timeTrialMission...)
  local mm = gameplay_missions_missionManager
  if career and type(current) == 'string' and current:find('Mission$') and not (mm and mm.getForegroundMissionId and mm.getForegroundMissionId()) then
    current = 'freeroam'
    core_gamestate.setGameState('freeroam', 'freeroam')
  end
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
  if sl_lot and sl_lot.uiHidden and sl_lot.uiHidden() then return nil end           -- (a lot is open: only its own menu shows)
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
    atRisk = sl_career and sl_career.atRisk and sl_career.atRisk() or 0,
    labels = (function() local S = require('sl/core/strings') return { day = S.t('phase.day'), night = S.t('phase.night'), engine = S.t('status.engine'), atRisk = S.TEXT['hud.atRisk'], heat = S.TEXT['hud.heat'], rpm = S.TEXT['hud.rpm'], mph = S.TEXT['hud.mph'], kmh = S.TEXT['hud.kmh'], atRiskTip = S.TEXT['hud.atRiskTip'] } end)(),
    phase = sl_career and sl_career.phase and sl_career.phase() or nil, heat = require('sl/core/phase').heatLevel(sl_police and sl_police.heat and sl_police.heat() or 0),
    speed = car.speed or v:getVelocity():length(), rpm = car.rpm or 0, maxRpm = car.maxRpm or 0, gear = car.gear,
    x = pos.x, y = pos.y, heading = math.atan2(dir.x, dir.y),
    body = car.body, engine = car.engine, tyres = car.tyres,
    target = h and core_groundMarkers and core_groundMarkers.endWP and core_groundMarkers.endWP[1] and
      (function() local t = core_groundMarkers.endWP[1] return type(t) == 'cdata' and { x = t.x, y = t.y } or nil end)() or nil,
  })
end

function M.request() mapSent = false sendSettings() end
function M.onStreetLegalOption(key) if key == 'slDashboard' then sendSettings() end end
-- the career stops: the game's own layout comes back (the career's was a layout of its own, nothing of the stock one was touched)
function M.onStreetLegalStopped()
  if layoutSet and core_gamestate and core_gamestate.state and core_gamestate.state.appLayout == 'streetLegal' then
    core_gamestate.setGameState('freeroam', 'freeroam')
  end
  layoutSet = nil
end
function M.onClientEndMission() mapSent, shown, carId, car, layoutSet = false, false, nil, {}, nil end
function M.onClientPostStartMission() mapSent = false end
M.onStreetLegalStarted = function() mapSent = false end

return M
