-- Street Legal: a lot's row built ahead of time (extension name: sl_lotpre; rules in sl/core/lotpre). Connor's point is frame rate: a lot car costs
-- about a second standing still inside the game's spawn call, so the row of the nearest lot is built while the screen is already black (the career
-- start, a fast travel, a cab ride: sl_career and sl_cab pass their job to onStreetLegalFade, so the fade waits) and kept INACTIVE at the lot's own
-- spots (veh:setActive(0): hidden, no physics, the way sl_streets pools racers). When the lot opens, sl_lot takes the row: setActive(1) and the cars
-- are there at once. Closing the lot gives the row back for the day; a new day, a career stop or a level change deletes it. One lot at a time.
-- Switch: Mods > Street Legal > World > Performance > "Build the nearest lot ahead" (on by default, on Active features).

local M = {}

local rules = require('sl/core/lotpre')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function on() return not sl_options or sl_options.get('slLotPrebuild') ~= false end
local function dentsOn() return not sl_options or sl_options.get('slLotDents') ~= false end

local store                 -- { placeId, day, ids, cars = { index -> vid }, partial }
local building = false
M.lastBuild = nil           -- { place, cars, seconds } for the log and the tester

local FREEZE = 'controller.setFreeze(1) input.event("parkingbrake", 1, FILTER_DIRECT)'

local function dropStore()
  if not store then return end
  for _, vid in pairs(store.cars) do
    local v = getObjectByID(vid)
    if v then v:delete() end
  end
  store = nil
end

-- build the row of `place` now, inside `job` (the fade's job: it waits for us)
local function build(job, s, place)
  local builder = require('sl/carBuilder')
  local offers = sl_lot.offersFor(place, s)
  if #offers == 0 then return end
  local spots = sl_lot.spotsFor(place, #offers)
  store = rules.newStore(place.id, s.day, offers)
  building = true
  local t0, built = os.clock(), 0
  for i, offer in ipairs(offers) do
    if os.clock() - t0 > rules.MAX_BUILD_S then store.partial = true break end
    local spot = spots[i]
    local veh = builder.buildOffer(job, offer, spot.pos + vec3(0, 0, 0.4), quatFromDir(spot.dir, vec3(0, 0, 1)), { deferDents = not dentsOn() })
    if veh then
      if slrrDrivers and slrrDrivers.setDriver then slrrDrivers.setDriver(veh:getID(), nil) end
      veh:queueLuaCommand(FREEZE)
      job.sleep(0.1)
      veh:setActive(0)
      store.cars[i] = veh:getID()
      built = built + 1
    end
  end
  building = false
  M.lastBuild = { place = place.id, cars = built, of = #offers, seconds = os.clock() - t0 }
  log('I', 'street_legal', string.format('lot row built ahead: %s, %d of %d cars in %.1f s%s', place.name or place.id, built, #offers, M.lastBuild.seconds, store.partial and ' (the rest at the lot)' or ''))
end

-- the fade: 'start' (career start), 'travel' (fast travel), 'cab' (a ride, `place` is where it goes). Without the job the fade would not wait: nothing is built.
function M.onStreetLegalFade(kind, job, place)
  local s = career()
  if not s or not on() or not job or type(job.sleep) ~= 'function' or building then return end
  if sl_lot and sl_lot.isOpen and sl_lot.isOpen() then return end
  local v = getPlayerVehicle(0)
  local pos = place and place.pos or (v and v:getPosition())
  local target = rules.pick(place, sl_career.getPlaces and sl_career.getPlaces() or {}, pos, rules.WITHIN)
  if not target then return end
  if store and rules.matches(store, target.id, s.day, sl_lot.offersFor(target, s)) then return end
  dropStore()
  build(job, s, target)
end

-- the lot opens: its cars from the store, active again (index -> vid), or nil. A partial store gives what it has; the lot builds the rest.
function M.take(place, offers, s)
  if not store or not rules.matches(store, place.id, s.day, offers) then dropStore() return nil end
  local out, n = {}, 0
  for i, vid in pairs(store.cars) do
    local v = getObjectByID(vid)
    if v then v:setActive(1) v:queueLuaCommand(FREEZE) out[i] = vid n = n + 1 end
  end
  store = nil
  if n == 0 then return nil end
  log('I', 'street_legal', 'lot row from the store: ' .. n .. ' cars')
  return out
end

-- the lot closes: its cars go back into the store for the day (hidden), except one just bought
function M.give(place, offers, cars, keepVid, s)
  if not on() or not s then return false end
  dropStore()
  store = rules.newStore(place.id, s.day, offers)
  local n = 0
  for i, vid in pairs(cars or {}) do
    if vid ~= keepVid then
      local v = getObjectByID(vid)
      if v then v:setActive(0) store.cars[i] = vid n = n + 1 end
    end
  end
  if n == 0 then store = nil return false end
  return true
end

function M.status()
  if not store then return 'no row in store' end
  local n = 0
  for _ in pairs(store.cars) do n = n + 1 end
  return string.format('row in store: lot %s day %d, %d cars%s', tostring(store.placeId), store.day, n, store.partial and ' (partial)' or '')
end

function M.onStreetLegalNewDay() dropStore() end
function M.onStreetLegalStopped() dropStore() building = false end
function M.onClientEndMission() store = nil building = false end

return M
