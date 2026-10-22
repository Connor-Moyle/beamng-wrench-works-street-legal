-- Street Legal: the career's tyres (extension name: sl_tyrecare), the game side of sl/core/tyres. The physics is Car Surface FX's (carSurfaceFx_tyres: wear, temperature, grip); this keeps the compound
-- and the wear of each of the player's cars with the car, sells tyre changes in the garage drawer (and at a track or meet, through changeNow), and tells the player about a blow-out.
-- Everything is guarded: while carSurfaceFx_tyres is absent or switched off in its Mods page, every call does nothing and the garage and the phone show no tyres.
-- API used (carSurfaceFx_tyres): getTyres(vid) -> { compound, wheels = { { idx, stage, frac, tread, compound, axle, side, flat, blown } } }, setCompound(vid, axle, name), setTread(vid, wheelIdx, frac), snapshot(vid), restore(vid, blob), attach(vid), getConfig().
-- The tread state lives in the car's own VM and is lost on a reset or a respawn: so it is snapshotted every few seconds into car.tyres.blob (the career save) and put back when a car comes out.

local M = {}

local strings = require('sl/core/strings')
local T = require('sl/core/tyres')
local B = require('sl_basictyres')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function api() return rawget(_G, 'carSurfaceFx_tyres') end
local function has(name) local a = api() return a ~= nil and type(a[name]) == 'function' end
local function toast(text) if text then guihooks.trigger('slPhoneToast', { text = text }) end if ui_message then ui_message(text, 4, 'streetLegal') end end

-- the career's own simple tyre wear (docs/CAREER_EXPANSION.md #10): on by its switch Simple tyre wear, and ONLY while Car Surface FX's tyre system is not there at all, so the two never stack.
-- It keeps a set of four treads with the car (car.tyres.set), wears it by the km the car reports (slCar, weighted by how hard it was driven) and tells the car the grip of each tyre.
function M.basic()
  if not career() or api() ~= nil then return false end
  return sl_options ~= nil and sl_options.get ~= nil and sl_options.get('slBasicTyres') == true
end
local WEAR_RATE = { half = 0.5, normal = 1, double = 2, quad = 4 }       -- the Wear rate setting
local layouts, sentKey = {}, {}                                          -- vehicle id -> its wheels as the car named them / the grip last sent to it

-- the tyre module is there and switched on (or the career's own wear is)
function M.available()
  if M.basic() then return true end
  if not (career() and has('getTyres') and has('setCompound')) then return false end
  local ok, cfg = pcall(function() return has('getConfig') and api().getConfig() or nil end)
  if ok and type(cfg) == 'table' and cfg.enabled == false then return false end
  return true
end

local function carById(s, id) for _, c in ipairs(s.cars) do if c.id == id then return c end end end

-- the player's car and its world vehicle id
local function current()
  local car = sl_fleet and sl_fleet.currentCar()
  local veh = car and sl_fleet.vehicleOf(car.id)
  return car, veh and veh:getID()
end

local function compoundOf(car) return car and car.tyres and car.tyres.compound or 'road' end

-- the tyre module is on but the car has no tyres to report (a starter car is sold on bare rims): no tyre rows and no swap until a tyre part is fitted and the car respawns
function M.noTyres(vid)
  if not (vid and M.available()) or M.basic() then return false end
  local ok, raw = pcall(api().getTyres, vid)
  return ok and type(raw) == 'table' and (type(raw.wheels) ~= 'table' or #raw.wheels == 0)
end

-- what the garage and the phone show for a car: T.carRows plus the compound we know ({ compound, rows, worst, replace } or nil)
-- the set of a car under the career's own wear (made new the first time it is looked at)
local function setOf(car, vid)
  car.tyres = car.tyres or {}
  if type(car.tyres.set) ~= 'table' or type(car.tyres.set.treads) ~= 'table' or #car.tyres.set.treads == 0 then
    car.tyres.set = B.newSet(layouts[vid] and #layouts[vid] or 4)
  end
  return car.tyres.set
end

-- tell the car the grip of each worn tyre; only when it changed since the last time
local function applyBasic(vid, car)
  local v = getObjectByID and getObjectByID(vid)
  if not (v and car and car.tyres) then return end
  local f = B.factors(setOf(car, vid), compoundOf(car))
  local text = serialize(f)
  if sentKey[vid] == text then return end
  sentKey[vid] = text
  v:queueLuaCommand(string.format('if slCar and slCar.setTyreGrip then slCar.setTyreGrip(%s) end', text))
end

function M.info(car, vid)
  if not (M.available() and car and vid) then return nil end
  if M.basic() then
    local raw = B.raw(setOf(car, vid), compoundOf(car), layouts[vid])
    return T.carRows(raw)
  end
  local ok, raw = pcall(api().getTyres, vid)
  if not (ok and type(raw) == 'table') then return nil end
  raw.compound = raw.compound or compoundOf(car)
  return T.carRows(raw)
end

-- the tread now, as the trade-in sees it: { compound, frac of the worst tyre }
local function setNow(car, info)
  return { compound = compoundOf(car), frac = info and info.worst and info.worst.frac or 1 }
end

-- a place where the crew changes tyres: a car meet (a place of the map), or the start of a track or a drag strip (the race missions: sl_career.racesList / tracksList).
-- The name of the one the car stands at, or nil.
M.SWAP_KINDS = { meet = true }
M.SWAP_REACH = 80            -- m: a meet place
M.START_REACH = 150          -- m: a race start (the grid is long)
local function swapPlace(vid)
  local v = getObjectByID and getObjectByID(vid)
  local ok, pos = pcall(function() return v:getPosition() end)
  if not (ok and pos) then return nil end
  for _, p in pairs(sl_career and sl_career.getPlaces and sl_career.getPlaces() or {}) do
    if M.SWAP_KINDS[p.kind] and p.pos then
      local dx, dy = pos.x - p.pos.x, pos.y - p.pos.y
      if dx * dx + dy * dy <= M.SWAP_REACH * M.SWAP_REACH then return p.name or p.id end
    end
  end
  for _, list in ipairs({ sl_career and sl_career.racesList and sl_career.racesList() or {}, sl_career and sl_career.tracksList and sl_career.tracksList() or {} }) do
    for _, r in ipairs(list) do
      if r.start then
        local dx, dy = pos.x - r.start.x, pos.y - r.start.y
        if dx * dx + dy * dy <= M.START_REACH * M.START_REACH then return r.name end
      end
    end
  end
end

-- what the phone shows for a car: the tyres (a diagram and the axles) and, for the car you sit in, what a swap costs where you are (a track or a meet: the crew comes to you)
-- { compound, rows, axles, replace, worst = { frac, stage }, offers = { { id, price, current } } } or nil (no tyre module, or it is switched off)
function M.card(car, vid, withOffers)
  local info = M.info(car, vid)
  if not info then return M.noTyres(vid) and { tracked = false, reason = 'no_tyres' } or nil end      -- (a car on bare rims says so)
  local out = { compound = info.compound, rows = info.rows, axles = info.axles, replace = info.replace,
    worst = info.worst and { frac = info.worst.frac, stage = info.worst.stage } or nil }
  if withOffers then
    out.swapAt = swapPlace(vid)               -- (nil elsewhere: the phone says tyre changes are at a garage or a track)
    local now = setNow(car, info)
    out.offers = {}
    for _, id in ipairs(T.ORDER) do
      local price = T.quote(id, nil, 'track', now)
      if price then out.offers[#out.offers + 1] = { id = id, price = price, current = id == now.compound and not info.replace } end
    end
  end
  return out
end

-- what a set of each compound costs on the player's car, where `where` is 'garage' (default) or 'track', the trade-in of the old set counted: id -> price. nil when there is no car or no tyres to report
function M.quotes(where)
  if not career() then return nil end
  local car, vid = current()
  if not (car and vid and M.available() and not M.noTyres(vid)) then return nil end
  local now = setNow(car, M.info(car, vid))
  local out = {}
  for _, id in ipairs(T.ORDER) do out[id] = T.quote(id, nil, where or 'garage', now) end
  return out
end

local function moving(vid)
  local v = getObjectByID and getObjectByID(vid)
  if not v then return false end
  local ok, speed = pcall(function() return v:getVelocity():length() end)
  return ok and (speed or 0) > 1
end

-- fit a set of `compound` on the player's car; where = 'garage' | 'track' (the crew comes to the track and charges more). Returns ok, text.
function M.changeNow(compound, where)
  local s = career()
  if not s then return false, strings.t('tyres.not_here') end
  local car, vid = current()
  if not (car and vid) then return false, strings.t('tyres.get_in_car') end
  if not (M.available() and T.known(compound)) then return false, strings.t('tyres.not_here') end
  if M.noTyres(vid) then return false, strings.t('tyres.no_tyres') end
  local info = M.info(car, vid)
  local plan = T.plan(compound, where or 'garage', setNow(car, info), s.money or 0, moving(vid))
  if not plan.ok then return false, plan.why end
  if plan.price > 0 and not sl_career.addMoney(-plan.price, strings.t('tyres.fitted', T.name(compound))) then return false, strings.t('tyres.you_cannot_afford_that') end
  if M.basic() then
    car.tyres = { compound = compound, sig = car.tyres and car.tyres.sig, set = B.newSet(layouts[vid] and #layouts[vid] or 4) }          -- (a new set)
    sentKey[vid] = nil
    applyBasic(vid, car)
    extensions.hook('onStreetLegalChanged')
    return true, strings.t('tyres.fitted', T.name(compound))
  end
  if not pcall(api().setCompound, vid, nil, compound) then return false, strings.t('tyres.not_here') end
  pcall(api().setTread, vid, nil, 1)                    -- (a new set, however the module treats a compound it already had)
  car.tyres = { compound = compound }                   -- (no blob: the new set is new)
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('tyres.fitted', T.name(compound))
end

-- the phone's Swap tyres button (a track or a meet)
function M.swap(compound)
  local car, vid = current()
  if not (car and vid and swapPlace(vid)) then toast(strings.t('ui.tyre_changes_where')) return end       -- (a stale card must not pay the track fee anywhere)
  local _, text = M.changeNow(tostring(compound), 'track')
  toast(text)
end

-- what the garage's drawer offers for the car on the lift
function M.onWrenchWorksServices(list)
  local s = career()
  if not (s and M.available()) then return end
  local car, vid = current()
  if not (car and vid) then return end
  local group = strings.t('tyres.group')
  local info = M.info(car, vid)
  if not info and M.noTyres(vid) then
    list[#list + 1] = { id = 'tyres:none', group = group, label = strings.t('tyres.no_tyres'), desc = strings.t('tyres.fit_from_catalog'), disabled = true }
    return
  end
  local now = setNow(car, info)
  if info and info.worst then
    local line = strings.t('tyres.fitted_line', T.name(info.compound or now.compound), strings.t('tyres.word_' .. info.worst.stage))
    list[#list + 1] = { id = 'tyres:info', group = group, label = line, desc = info.replace and strings.t('tyres.old_set_credit') or '', disabled = true }
  end
  for _, r in ipairs(info and info.rows or {}) do                       -- one line per tyre
    local flat = r.flat and (' - ' .. strings.t('ui.tyre_flat_spot')) or ''
    local named = (r.axle == 'front' or r.axle == 'rear') and (r.side == 'left' or r.side == 'right')
    local what = named and (strings.t('tyres.axle_' .. r.axle) .. ' ' .. strings.t('ui.tyre_' .. r.side)) or strings.t('tyres.tyre_n', (tonumber(r.idx) or 0) + 1)
    list[#list + 1] = { id = 'tyres:w' .. tostring(r.idx), group = group, disabled = true, desc = '',
      label = strings.t('tyres.tyre_line2', what, math.floor((r.frac or 0) * 100 + 0.5), strings.t('tyres.word_' .. tostring(r.stage))) .. flat }
  end
  for _, id in ipairs(T.ORDER) do
    if id ~= now.compound or (info and info.replace) then
      local price, parts = T.quote(id, nil, 'garage', now)
      local c = T.COMPOUNDS[id]
      list[#list + 1] = { id = 'tyre:' .. id, group = group, label = T.name(id), price = price,
        desc = strings.t('tyres.change_desc', T.name(id), parts.credit > 0 and (' · ' .. strings.t('tyres.old_set_credit')) or '') .. ' (' .. strings.t('tyres.family_' .. c.family) .. ')' }
    end
  end
end

function M.onWrenchWorksService(id)
  local compound = type(id) == 'string' and id:match('^tyre:(.+)$')
  if not compound then return end
  local _, text = M.changeNow(compound, 'garage')
  toast(text)
end

-- the tyre module reports a blow-out
function M.onCsfxTyreBlown(vid)
  if not career() then return end
  local car = sl_fleet and sl_fleet.carOfVehicle(vid)
  if car then toast(strings.t('tyres.blown_toast')) end
end

-- ---- keeping the wear with the car (called by sl_fleet: snapshot() every minute and before a save, and when a car comes out)
function M.save(vid, car)
  if not (vid and car and has('snapshot')) or M.noTyres(vid) then return nil end             -- (a car on bare rims has no wear to keep)
  local ok, blob = pcall(api().snapshot, vid)
  if ok and type(blob) == 'table' and next(blob) then
    car.tyres = car.tyres or {}
    car.tyres.blob = blob
    return true
  end
end

-- the blob is sent twice, the second time M.RETRY seconds later: the first can reach a car whose tyre module is not loaded yet (it is dropped) or arrive before the car's own reset has
-- renewed the tyres (the reset wipes it); the same blob twice sets the same state (the module holds one that arrives before the tyres are built)
M.RETRY = 2
local retries = {}                   -- vehicle id -> { car, left }
local function send(vid, car)
  if M.basic() then sentKey[vid] = nil applyBasic(vid, car) return end
  local a = api()
  if has('attach') then pcall(a.attach, vid) end
  if type(car.tyres.blob) == 'table' and has('restore') then pcall(a.restore, vid, car.tyres.blob)         -- (the blob keeps the compound of every wheel)
  elseif car.tyres.compound and car.tyres.compound ~= 'road' then pcall(a.setCompound, vid, nil, car.tyres.compound) end
  -- Car Surface FX is here now and the car was on the career's own wear: the treads it had go to the new tyres, the grip we set is taken off, and the own set is dropped (the hand-over)
  if type(car.tyres.set) == 'table' and has('setTread') then
    if type(car.tyres.blob) ~= 'table' then
      local layout = layouts[vid]
      for i, t in ipairs(car.tyres.set.treads or {}) do pcall(a.setTread, vid, (layout and layout[i] and layout[i].idx) or (i - 1), t) end
    end
    car.tyres.set = nil
    local v = getObjectByID and getObjectByID(vid)
    if v then v:queueLuaCommand('if slCar and slCar.setTyreGrip then slCar.setTyreGrip({}) end') end
    sentKey[vid] = nil
  end
end

function M.restore(vid, car)
  if not (vid and car and M.available()) then return nil end
  if not car.tyres and not M.basic() then return nil end
  car.tyres = car.tyres or {}
  send(vid, car)
  retries[vid] = { car = car, left = M.RETRY }
  return true
end

-- the car's report (slCar through sl_carcare.onReport, every 2 s): its wheel names, and under the career's own wear the km driven since the last one, weighted by how hard
function M.onReport(vid, t)
  if type(t) ~= 'table' then return end
  if type(t.wheelNames) == 'table' then
    local n = 0
    for k in pairs(t.wheelNames) do n = math.max(n, (tonumber(k) or 0) + 1) end
    if n > 0 then layouts[vid] = B.layout(t.wheelNames, n) end
  end
  if not M.basic() then return end
  local s = career()
  local carId = sl_fleet and sl_fleet.carOfVehicle and sl_fleet.carOfVehicle(vid)
  local car = s and carId and carById(s, carId)
  if not car then return end
  local set = setOf(car, vid)
  local km = tonumber(t.tyreKm)
  if km and km > 0 then
    local rate = WEAR_RATE[sl_options.get('slWearRate') or 'normal'] or 1
    B.wear(set, compoundOf(car), km * rate)
    local rows = T.carRows(B.raw(set, compoundOf(car), layouts[vid]))
    if rows and rows.replace and not car.tyres.told then
      car.tyres.told = true
      toast(strings.t('tyres.worn_toast'))
    end
  end
  applyBasic(vid, car)
end

-- the car leaves the garage: if its tyre parts are not the ones its wear was saved for, the tyres are a new set (no old blob, no old compound); the parts now fitted are remembered
function M.onWrenchWorksDriveOut(vid, info)
  local s = career()
  local car = s and carById(s, sl_fleet and sl_fleet.carOfVehicle(vid))
  if not (car and type(info) == 'table' and type(info.partsTree) == 'table') then return end
  local sig = T.signature(info.partsTree)
  if car.tyres and car.tyres.sig ~= nil and car.tyres.sig ~= sig then car.tyres = nil sentKey[vid] = nil end      -- (a save from before this has no signature: kept, not guessed)
  car.tyres = car.tyres or {}
  car.tyres.sig = sig
end

-- a test aid (console: sl_tyrecare.devRegister()): the car the player sits in becomes one of the career's cars, so a QA career with no cars can test the tyres' record, restore after a reset
-- or a respawn, and save and load. Returns ok, text.
function M.devRegister()
  local s = career()
  if not (s and sl_fleet and sl_fleet.registerVehicle) then return false, 'no career running' end
  local veh = getPlayerVehicle and getPlayerVehicle(0)
  if not veh then return false, 'no car under the player' end
  if sl_fleet.carOfVehicle(veh:getID()) then return false, 'already a career car' end
  local car = sl_fleet.registerVehicle(veh:getID(), { name = 'QA tyre car', value = 1000, condition = 1 })
  if not car then return false, 'the car could not be registered' end
  return true, 'registered as career car ' .. tostring(car.id)
end

-- a tyre part bought in Wrench Works is a new set, even the same part as the worn one (like for like): the wear saved for the old set is dropped
function M.onWrenchWorksPartBought(vid, slotPath)
  local path = tostring(slotPath or ''):lower()
  if not (path:find('tire', 1, true) or path:find('tyre', 1, true)) then return end
  local s = career()
  local car = s and carById(s, sl_fleet and sl_fleet.carOfVehicle(vid))
  if car then car.tyres = nil end
end

-- a vehicle reset (R) gives the tyres new in the tyre module; the career does not: the wear is put back from the last snapshot
function M.onVehicleResetted(vid)
  local s = career()
  local carId = s and sl_fleet and sl_fleet.carOfVehicle(vid)
  local car = carId and carById(s, carId)
  if car then M.restore(vid, car) end
end

-- the player's current car gets its tyres snapshotted every few seconds (a blob up to that old is what a respawn gets back)
local timer = 0
function M.onUpdate(dtReal)
  for vid, r in pairs(retries) do
    r.left = r.left - (dtReal or 0)
    if r.left <= 0 then
      retries[vid] = nil
      if r.car.tyres and M.available() then send(vid, r.car) end
    end
  end
  timer = timer + (dtReal or 0)
  if timer < 5 then return end
  timer = 0
  if not M.available() then return end
  local car, vid = current()
  if car and vid then M.save(vid, car) end
end

return M
