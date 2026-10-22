-- Street Legal: my route (extension name: sl_myroute; campaign idea #14; Mods > Street Legal > Parts of the game > My route, off by default). Rules in sl/core/myroute.
-- The player drops 4 to 8 waypoints where the car is, saves the route and races it against the clock: the clock starts passing waypoint 1 and stops at the last. The
-- routes live in the career save (s.myroutes = { levels = { [level] = { list = { route } } } }, a route = { id, name, points, length, best, runs, last }). No money, no reputation.

local M = {}

local strings = require('sl/core/strings')
local rules = require('sl/core/myroute')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) if ui_message then ui_message(text, 5, 'streetLegal') end end
local function level() return getCurrentLevelIdentifier and getCurrentLevelIdentifier() or '' end
local function changed() extensions.hook('onStreetLegalChanged') end

-- the map's list (made on first use; a save without the key is read as no routes)
local function listOf(s)
  if type(s.myroutes) ~= 'table' then s.myroutes = {} end
  local t = s.myroutes
  if type(t.levels) ~= 'table' then t.levels = {} end
  local lv = level()
  if type(t.levels[lv]) ~= 'table' or type(t.levels[lv].list) ~= 'table' then t.levels[lv] = { list = {} } end
  return t.levels[lv].list
end

local draft = {}          -- the points dropped so far (not saved until Save)
local run, route, prev    -- the run now: its state, the route, the car's last sample
local ownFlares = false   -- the flares standing are this run's (the markers are shared: only these are put away)

local function here()
  local v = getPlayerVehicle(0)
  local p = v and v:getPosition()
  return p and { x = p.x, y = p.y, z = p.z } or nil
end

local function guide(p) if core_groundMarkers then core_groundMarkers.setPath(p and vec3(p.x, p.y, p.z) or nil) end end

local function flares()
  if not (sl_markers and sl_markers.flareCircuit and route) then return end
  local cps = {}
  for i, p in ipairs(route.points) do
    local q = route.points[i + 1] or route.points[i - 1] or p
    local d = vec3(q.x - p.x, q.y - p.y, 0)
    if i == #route.points then d = vec3(p.x - q.x, p.y - q.y, 0) end
    cps[i] = { pos = vec3(p.x, p.y, p.z), dir = d:length() > 0.01 and d:normalized() or vec3(0, 1, 0), half = 5 }
  end
  sl_markers.flareCircuit(cps)
  ownFlares = true
end

local function stopRun(quiet)
  if not run then return end
  run, route, prev = nil, nil, nil
  guide(nil)
  if ownFlares and sl_markers and sl_markers.clear then sl_markers.clear() end
  ownFlares = false
  if not quiet then changed() end
end

-- ---- the editor
function M.drop()
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  if run then return false, strings.t('myroute.in_run') end
  local p = here()
  if not p then return false, strings.t('career.not_now') end
  local ok, why = rules.canAdd(draft, p)
  if not ok then return false, strings.t(why) end
  draft[#draft + 1] = p
  changed()
  return true, strings.t('myroute.dropped', #draft)
end

function M.undo()
  if #draft == 0 then return false, strings.t('myroute.nothing_to_undo') end
  draft[#draft] = nil
  changed()
  return true
end

function M.discard() draft = {} changed() return true end

function M.save(name)
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  local list = listOf(s)
  local r, why = rules.make(draft, name, list)
  if not r then return false, strings.t(why) end
  list[#list + 1] = r
  draft = {}
  changed()
  return true, strings.t('myroute.saved', r.name)
end

function M.delete(id)
  local s = career()
  if not s then return false end
  local list = listOf(s)
  for i, r in ipairs(list) do
    if r.id == id then
      if route and route.id == id then stopRun() end
      table.remove(list, i)
      changed()
      return true
    end
  end
  return false
end

-- ---- the run
function M.race(id)
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  if run then return false, strings.t('myroute.in_run') end
  if (sl_gridrace and sl_gridrace.running and sl_gridrace.running()) or (sl_career.freeToStart and sl_career.freeToStart()) then return false, sl_career.freeToStart and sl_career.freeToStart() or strings.t('career.not_now') end
  for _, r in ipairs(listOf(s)) do
    if r.id == id then
      route, run, prev = r, rules.newRun(), nil
      flares()
      guide(r.points[1])
      toast(strings.t('myroute.go_to_the_start', r.name))
      changed()
      return true
    end
  end
  return false, strings.t('myroute.no_such_route')
end

function M.cancel() if run then stopRun() toast(strings.t('myroute.run_stopped')) end return true end

local timer = 0

-- a dropped waypoint: an orange post with its number (drawn every frame while the draft is open)
local function drawPost(p, i, pulse)
  local pos = vec3(p.x, p.y, p.z)
  debugDrawer:drawCylinder(pos, pos + vec3(0, 0, 4), 0.25, ColorF(1, 0.5, 0.1, 0.5 + 0.4 * pulse))
  debugDrawer:drawTextAdvanced(pos + vec3(0, 0, 4.4), String(tostring(i)), ColorF(1, 1, 1, 1), true, false, ColorI(25, 12, 0, 210))
end

local function update(dt)
  if debugDrawer and #draft > 0 then
    local pulse = 0.5 + 0.5 * math.sin(os.clock() * 3)
    for i, p in ipairs(draft) do drawPost(p, i, pulse) end
  end
  if not run then return end
  timer = timer + (dt or 0)
  if timer < 0.1 then return end
  local step = timer
  timer = 0
  local p = here()
  if not p then return end
  local ev
  run, ev = rules.step(run, route, prev, p, step)
  prev = p
  if ev == 'start' then
    toast(strings.t('myroute.clock_running'))
    guide(route.points[run.next])
  elseif ev == 'point' then
    guide(route.points[run.next])
  elseif ev == 'cancel' then
    toast(strings.t('myroute.run_cancelled'))
    stopRun()
  elseif ev == 'finish' then
    local rec, best = rules.record(route, run.t)
    route.best, route.runs, route.last = rec.best, rec.runs, rec.last
    toast(strings.t(best and 'myroute.finished_best' or 'myroute.finished', route.name, rules.clock(rec.last), rules.clock(rec.best)))
    stopRun()
  end
end

-- an error in a frame ends the run (and is logged once) instead of repeating every frame
function M.onUpdate(dt)
  local ok, err = pcall(update, dt)
  if ok then return end
  log('E', 'sl_myroute', 'update: ' .. tostring(err))
  draft = {}
  stopRun(true)
end

-- for the phone: nil with no career
function M.summary()
  local s = career()
  if not s then return nil end
  local out = { routes = {}, draft = #draft, draftMax = rules.MAX_POINTS, draftMin = rules.MIN_POINTS, maxRoutes = rules.MAX_ROUTES }
  for _, r in ipairs(listOf(s)) do
    out.routes[#out.routes + 1] = { id = r.id, name = r.name, points = #r.points, length = r.length, best = r.best, bestText = rules.clock(r.best), runs = r.runs, last = r.last, lastText = rules.clock(r.last) }
  end
  if run and route then out.run = { id = route.id, name = route.name, next = run.next, points = #route.points, started = run.started, t = run.t, clock = rules.clock(run.t) } end
  return out
end

function M.onStreetLegalStopped() stopRun(true) draft = {} timer = 0 end
function M.onClientEndMission() run, route, prev, draft, timer = nil, nil, nil, {}, 0 end
function M.onVehicleSwitched() if run then stopRun() end end

require('sl/core/features').gate('myroute', M, nil, nil, { 'summary', 'drop', 'undo', 'save', 'race' })

return M
