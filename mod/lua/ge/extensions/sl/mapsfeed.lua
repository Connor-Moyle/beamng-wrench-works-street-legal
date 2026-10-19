-- Street Legal: feeds the Maps HUD app (ui/modules/apps/slMaps): the road tiles from the navgraph, the player's pose, the route and the places.
-- The app tells us it is on screen (sl_mapsfeed.use(name, true): the HUD app and the phone's Map tab each count as a consumer) and asks for tiles (sl_mapsfeed.tiles({ "0,0", ... })); nothing is built or sent while it is not.
-- The road tiles are built a few nodes at a time (2 ms a frame at most, the same rule as the puddles).

local M = {}

local feed = require('sl/core/mapfeed')

local BUDGET = 0.002          -- s of tile building per frame
local POSE_EVERY = 0.1        -- s: the pose goes to the app at 10 Hz
local wanted = {}             -- tile keys the app asked for and has not got yet
local builder, level
local users = feed.consumers()
local isActive = false
local failed = false          -- an error was logged since the app last turned us on
local poseTimer, routeKey, placesSent, optsKey = 0, nil, false, nil

local function push(name, data, opts)
  if sl_uipush and sl_uipush.push then return sl_uipush.push(name, data, opts) end
  guihooks.trigger(name, data)
end

local function reset() builder, wanted, routeKey, placesSent, optsKey = nil, {}, nil, false, nil end

local function sendWanted()
  if not builder then return end
  local out, any = {}, false
  for key in pairs(wanted) do
    if builder.done then out[key] = builder.tiles[key] or {} any = true wanted[key] = nil end      -- (only a finished tile: one sent half-built would never be completed)
  end
  if any then guihooks.trigger('slMapsTiles', { tiles = out }) end
end

-- a consumer (the HUD app 'hud', the phone's Map tab 'phone') turns the feed on or off for itself; it runs while any of them needs it
function M.use(name, on)
  local added = users.use(tostring(name), on)
  isActive = users.any()
  if isActive then failed = false end
  if added then routeKey, placesSent, optsKey = nil, false, nil end        -- (a new consumer has not got the route and the places yet)
  if not isActive then reset() end
end

function M.tiles(list)
  if type(list) ~= 'table' then return end
  for _, key in ipairs(list) do if type(key) == 'string' then wanted[key] = true end end
  if not builder then
    local ok, m = pcall(function() return map.getMap() end)
    if ok and type(m) == 'table' and m.nodes then builder = feed.builder(m.nodes) end
  end
end

local function places()
  local list = {}
  for id, p in pairs(sl_career and sl_career.getPlaces and sl_career.getPlaces() or {}) do
    local x, y = feed.xy(type(p) == 'table' and p.pos or nil)
    if x then list[#list + 1] = { id = id, kind = p.kind, name = p.name, x = math.floor(x), y = math.floor(y) } end
  end
  return list
end

local function tick(dtReal)
  local lv = getCurrentLevelIdentifier and getCurrentLevelIdentifier() or ''
  if lv ~= level then level = lv reset() end
  if builder and not builder.done then builder:step(os.clock, BUDGET) end
  if builder and builder.done and not builder.reported then
    builder.reported = true
    local n = 0 for _ in pairs(builder.tiles) do n = n + 1 end
    log('I', 'sl_mapsfeed', 'road tiles built: ' .. builder.count .. ' segments in ' .. n .. ' tiles')
  end
  if next(wanted) then sendWanted() end
  poseTimer = poseTimer + (dtReal or 0)
  if poseTimer < POSE_EVERY then return end
  poseTimer = 0
  local v = getPlayerVehicle and getPlayerVehicle(0)
  if v then
    local p, d = v:getPosition(), v:getDirectionVector()
    local pose = { x = p.x, y = p.y, heading = math.atan2(d.x, d.y) }
    local okv, vel = pcall(function() return v:getVelocity() end)
    pose.speed = okv and vel and vel:length() or 0
    local okr, n1, n2, dist = pcall(function() return map.findClosestRoad(p, 25) end)                 -- (the road under the car, within 25 m)
    if okr and n1 and n2 and (dist or 99) <= 25 then
      local okm, m = pcall(function() return map.getMap() end)
      pose.limit = okm and m and feed.limitOf(m.nodes, n1, n2) or nil
    end
    pose.mph = settings and settings.getValue and settings.getValue('uiUnitLength') == 'imperial' or false
    push('slMapsPose', pose, { minInterval = POSE_EVERY })
  end
  if not placesSent then placesSent = true guihooks.trigger('slMapsPlaces', { places = places() }) end
  local o = feed.mapOptions(function(k) return sl_options and sl_options.get and sl_options.get(k) or nil end)           -- (the Mods menu's Maps rows)
  local ok = o.style .. ':' .. tostring(o.headingUp) .. ':' .. tostring(o.speed) .. ':' .. tostring(o.slide) .. ':' .. o.zoom
  if ok ~= optsKey then optsKey = ok guihooks.trigger('slMapsOptions', o) end
  local gm = core_groundMarkers
  local path = gm and gm.routePlanner and gm.routePlanner.path
  local lx, ly = feed.xy(path and path[#path] and path[#path].pos or nil)
  local key = lx and (#path .. ':' .. math.floor(lx) .. ':' .. math.floor(ly)) or ''
  if key ~= routeKey then
    routeKey = key
    guihooks.trigger('slMapsRoute', { route = path and path[1] and feed.routePoints(path, 6) or {} })
  end
end

-- one error switches the feed off (logged once) rather than erroring every frame until the app closes; the app's next active(true) turns it on again
function M.onUpdate(dtReal)
  if not isActive then return end
  local ok, err = pcall(tick, dtReal)
  if not ok then
    if not failed then failed = true log('E', 'sl_mapsfeed', 'switched off after an error: ' .. tostring(err)) end
    isActive = false
    users.clear()
    reset()
  end
end

-- for a game test: what the feed has built
function M.status()
  local n = 0
  if builder then for _ in pairs(builder.tiles) do n = n + 1 end end
  return { active = isActive, built = builder and builder.done or false, segments = builder and builder.count or 0, tiles = n, waiting = next(wanted) ~= nil }
end

function M.onClientEndMission() reset() end

return M
