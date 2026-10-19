-- Street Legal: the career's tyres (extension name: sl_tyrecare), the game side of sl/core/tyres. The physics is Car Surface FX's (carSurfaceFx_tyres: wear, temperature, grip); this keeps the compound
-- and the wear of each of the player's cars with the car, sells tyre changes in the garage drawer (and at a track or meet, through changeNow), and tells the player about a blow-out.
-- Everything is guarded: while carSurfaceFx_tyres is absent or switched off in its Mods page, every call does nothing and the garage and the phone show no tyres.
-- API used (carSurfaceFx_tyres): getTyres(vid) -> { compound, wheels = { { idx, stage, frac, tread, compound, axle, side, flat, blown } } }, setCompound(vid, axle, name), setTread(vid, wheelIdx, frac), snapshot(vid), restore(vid, blob), attach(vid), getConfig().
-- The tread state lives in the car's own VM and is lost on a reset or a respawn: so it is snapshotted every few seconds into car.tyres.blob (the career save) and put back when a car comes out.

local M = {}

local strings = require('sl/core/strings')
local T = require('sl/core/tyres')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function api() return rawget(_G, 'carSurfaceFx_tyres') end
local function has(name) local a = api() return a ~= nil and type(a[name]) == 'function' end
local function toast(text) if text then guihooks.trigger('slPhoneToast', { text = text }) end if ui_message then ui_message(text, 4, 'streetLegal') end end

-- the tyre module is there and switched on
function M.available()
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

-- what the garage and the phone show for a car: T.carRows plus the compound we know ({ compound, rows, worst, replace } or nil)
function M.info(car, vid)
  if not (M.available() and car and vid) then return nil end
  local ok, raw = pcall(api().getTyres, vid)
  if not (ok and type(raw) == 'table') then return nil end
  raw.compound = raw.compound or compoundOf(car)
  return T.carRows(raw)
end

-- the tread now, as the trade-in sees it: { compound, frac of the worst tyre }
local function setNow(car, info)
  return { compound = compoundOf(car), frac = info and info.worst and info.worst.frac or 1 }
end

-- what the phone shows for a car: the tyres (a diagram and the axles) and, for the car you sit in, what a swap costs where you are (a track or a meet: the crew comes to you)
-- { compound, rows, axles, replace, worst = { frac, stage }, offers = { { id, price, current } } } or nil (no tyre module, or it is switched off)
function M.card(car, vid, withOffers)
  local info = M.info(car, vid)
  if not info then return nil end
  local out = { compound = info.compound, rows = info.rows, axles = info.axles, replace = info.replace,
    worst = info.worst and { frac = info.worst.frac, stage = info.worst.stage } or nil }
  if withOffers then
    local now = setNow(car, info)
    out.offers = {}
    for _, id in ipairs(T.ORDER) do
      local price = T.quote(id, nil, 'track', now)
      if price then out.offers[#out.offers + 1] = { id = id, price = price, current = id == now.compound and not info.replace } end
    end
  end
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
  local info = M.info(car, vid)
  local plan = T.plan(compound, where or 'garage', setNow(car, info), s.money or 0, moving(vid))
  if not plan.ok then return false, plan.why end
  if plan.price > 0 and not sl_career.addMoney(-plan.price, strings.t('tyres.fitted', T.name(compound))) then return false, strings.t('tyres.you_cannot_afford_that') end
  if not pcall(api().setCompound, vid, nil, compound) then return false, strings.t('tyres.not_here') end
  pcall(api().setTread, vid, nil, 1)                    -- (a new set, however the module treats a compound it already had)
  car.tyres = { compound = compound }                   -- (no blob: the new set is new)
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('tyres.fitted', T.name(compound))
end

-- the phone's Swap tyres button (a track or a meet)
function M.swap(compound)
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
  local now = setNow(car, info)
  if info and info.worst then
    local line = strings.t('tyres.fitted_line', T.name(info.compound or now.compound), strings.t('tyres.word_' .. info.worst.stage))
    list[#list + 1] = { id = 'tyres:info', group = group, label = line, desc = info.replace and strings.t('tyres.old_set_credit') or '', disabled = true }
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
  if not (vid and car and has('snapshot')) then return nil end
  local ok, blob = pcall(api().snapshot, vid)
  if ok and type(blob) == 'table' and next(blob) then
    car.tyres = car.tyres or {}
    car.tyres.blob = blob
    return true
  end
end

function M.restore(vid, car)
  if not (vid and car and car.tyres and M.available()) then return nil end
  local a = api()
  if has('attach') then pcall(a.attach, vid) end
  if type(car.tyres.blob) == 'table' and has('restore') then pcall(a.restore, vid, car.tyres.blob)         -- (the blob keeps the compound of every wheel)
  elseif car.tyres.compound and car.tyres.compound ~= 'road' then pcall(a.setCompound, vid, nil, car.tyres.compound) end
  return true
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
  timer = timer + (dtReal or 0)
  if timer < 5 then return end
  timer = 0
  if not M.available() then return end
  local car, vid = current()
  if car and vid then M.save(vid, car) end
end

return M
