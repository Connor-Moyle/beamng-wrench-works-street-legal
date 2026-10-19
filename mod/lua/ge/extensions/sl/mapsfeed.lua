-- Street Legal: feeds the Maps HUD app (ui/modules/apps/slMaps): the road tiles from the navgraph, the player's pose, the route and the places.
-- The app tells us it is on screen (sl_mapsfeed.active(true)) and asks for tiles (sl_mapsfeed.tiles({ "0,0", ... })); nothing is built or sent while it is not.
-- The road tiles are built a few nodes at a time (2 ms a frame at most, the same rule as the puddles).

local M = {}

local feed = require('sl/core/mapfeed')

local BUDGET = 0.002          -- s of tile building per frame
local POSE_EVERY = 0.1        -- s: the pose goes to the app at 10 Hz
local wanted = {}             -- tile keys the app asked for and has not got yet
local builder, level
local isActive = false
local failed = false          -- an error was logged since the app last turned us on
local poseTimer, routeKey, placesSent = 0, nil, false

local function push(name, data, opts)
  if sl_uipush and sl_uipush.push then return sl_uipush.push(name, data, opts) end
  guihooks.trigger(name, data)
end

local function reset() builder, wanted, routeKey, placesSent = nil, {}, nil, false end

local function sendWanted()
  if not builder then return end
  local out, any = {}, false
  for key in pairs(wanted) do
    if builder.done or builder.tiles[key] then out[key] = builder.tiles[key] or {} any = true wanted[key] = nil end
  end
  if any then guihooks.trigger('slMapsTiles', { tiles = out }) end
end

function M.active(on)
  isActive = on and true or false
  if isActive then failed = false end
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
    if type(p) == 'table' and p.pos and type(p.pos.x) == 'number' then list[#list + 1] = { id = id, kind = p.kind, name = p.name, x = math.floor(p.pos.x), y = math.floor(p.pos.y) } end
  end
  return list
end

local function tick(dtReal)
  local lv = getCurrentLevelIdentifier and getCurrentLevelIdentifier() or ''
  if lv ~= level then level = lv reset() end
  if builder and not builder.done then builder:step(os.clock, BUDGET) end
  if next(wanted) then sendWanted() end
  poseTimer = poseTimer + (dtReal or 0)
  if poseTimer < POSE_EVERY then return end
  poseTimer = 0
  local v = getPlayerVehicle and getPlayerVehicle(0)
  if v then
    local p, d = v:getPosition(), v:getDirectionVector()
    push('slMapsPose', { x = p.x, y = p.y, heading = math.atan2(d.x, d.y) }, { minInterval = POSE_EVERY })
  end
  if not placesSent then placesSent = true guihooks.trigger('slMapsPlaces', { places = places() }) end
  local gm = core_groundMarkers
  local path = gm and gm.routePlanner and gm.routePlanner.path
  local last = path and path[#path] and path[#path].pos
  local key = last and type(last.x) == 'number' and (#path .. ':' .. math.floor(last.x) .. ':' .. math.floor(last.y)) or ''
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
    reset()
  end
end

function M.onClientEndMission() reset() end

return M
