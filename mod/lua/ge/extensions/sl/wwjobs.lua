-- Wrench Works: Street Legal: the Wrench Works jobs on the job board (extension name: sl_wwjobs; Design 3 #7-9).
-- They are rows in sl_jobs' TYPES with settle = 'ww': the board offers them and the phone shows them as usual,
-- but they end when Wrench Works reports the work (a dyno run, a quarter mile, a car driven out, a part sold),
-- through sl_jobs.finishWith - the one money and rep path. Rules in sl/core/wwjobs.

local M = {}

local ww = require('sl/core/wwjobs')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) if ui_message then ui_message(text, 5, 'streetLegal') end end
local function active()
  local s = career()
  local js = s and s.jobs
  local j = js and js.active
  if j and j.settle == 'ww' then return s, js, j end
end
local function stop(p, name) return p and { id = p.id, name = name or p.name, x = p.x, y = p.y, z = p.z } end
local function fleetCar(vid) return sl_fleet and sl_fleet.carOfVehicle and sl_fleet.carOfVehicle(vid) end

-- #8 tune to spec: build it in your garage, prove it on the dyno (power) or the test track's quarter mile
local TUNE = { kind = 'tune', title = 'Tune to spec', unlock = ww.TIER_REP[1], settle = 'ww', offer = function(ctx, rng)
    local s = career()
    local spec = s and ctx.garage and ww.tuneSpec(rng, s.rep)
    if not spec then return nil end
    spec.settle, spec.spent, spec.seconds, spec.fragile = 'ww', 0, 0, false
    spec.legs = { stop(ctx.garage), stop(ctx.garage, spec.metric == 'power' and 'the dyno' or 'the test track quarter mile') }
    return spec
  end }

-- #7 repair tickets: the customer's car is waiting outside your garage with parts missing; drive it in, fit
-- them, drive it out
local REPAIR = { kind = 'repair', title = 'Repair ticket', unlock = 150, settle = 'ww', offer = function(ctx, rng)
    if not ctx.garage then return nil end
    local t = ww.repairTicket(rng)
    t.settle, t.spent, t.seconds, t.fragile = 'ww', 0, 1800, false
    t.car = { model = t.model, wear = 0.3 }
    t.legs = { stop(ctx.garage, 'the customer outside your garage'), stop(ctx.garage, 'your lift') }
    return t
  end }

local ROWS = { TUNE, REPAIR }     -- #9 scavenging joins once Wrench Works can run it

-- add our rows to the board (again after sl_jobs reloads, which makes a fresh TYPES)
local addedTo
local function register()
  if not (sl_jobs and sl_jobs.TYPES) or addedTo == sl_jobs.TYPES then return end
  for _, row in ipairs(ROWS) do table.insert(sl_jobs.TYPES, row) end
  addedTo = sl_jobs.TYPES
end
M.onExtensionLoaded = register

local function pay(s, js, j, amount, rep, text)
  amount = sl_jobs.bonusPay and sl_jobs.bonusPay(s, js, j, amount) or amount
  sl_jobs.finishWith(s, js, j, amount, rep, string.format(text, amount))
end

----------------------------------------------------------------------------------------------
-- #8: a measurement from one of your cars

local function measured(value, carKey)
  local s, js, j = active()
  if not j or j.kind ~= 'tune' then return end
  local r = ww.tuneMeasure(j, value, carKey)
  if r == 'already' then
    sl_jobs.finishWith(s, js, j, 0, 0, 'That car already beats the spec. The customer wanted it built, not bought: job off.')
  elseif r == 'baseline' then
    toast(string.format('Baseline noted. Now build it to %s.', j.item))
  elseif r == 'no parts' then
    toast('It makes the spec, but nothing was bought for it: the customer is paying for a build.')
  elseif r == 'met' then
    local amount, verdict = ww.tuneSettle(j, j.spent)
    pay(s, js, j, amount, verdict == 'over budget' and 5 or 20, 'Spec met (' .. j.item .. '), ' .. verdict .. ': $%d. The customer is happy.')
  end
end

function M.onWrenchWorksDyno(vid, data)
  local car = fleetCar(vid)
  if car and type(data) == 'table' then measured(tonumber(data.maxPower), car) end
end

function M.onSlrrRaceFinished(r)
  local _, _, j = active()
  if not j or j.metric ~= 'quarter' or type(r) ~= 'table' or r.abandoned or type(r.time) ~= 'number' then return end
  local v = getPlayerVehicle(0)
  local car = v and fleetCar(v:getID())
  if not car then return end
  for _, x in ipairs(sl_career.racesList and sl_career.racesList() or {}) do
    if x.drag and (x.id == r.raceId or (r.missionId and x.missionId == r.missionId)) and tostring(x.name):find('1/4', 1, true) then
      measured(r.time, car)
      return
    end
  end
end

----------------------------------------------------------------------------------------------
-- parts bought for the job: for a tune, any of your cars; for a repair, the customer's car

function M.onWrenchWorksPartBought(vid, slotPath, part, price)
  local _, _, j = active()
  if not j or not tonumber(price) then return end
  if (j.kind == 'tune' and fleetCar(vid)) or (j.kind == 'repair' and vid == j.carVid) then j.spent = (j.spent or 0) + tonumber(price) end
end

----------------------------------------------------------------------------------------------
-- #7: the customer's car loses the ticket's parts as soon as it is spawned; it is checked as it drives out

local leaving        -- a finished customer car, taken away once the garage is done with it

local function emptyTicketSlots(j)
  local veh = getObjectByID(j.carVid)
  local vd = veh and core_vehicle_manager.getVehicleData(j.carVid)
  if not vd or not vd.config or not vd.config.partsTree then return end
  local config = deepcopy(vd.config)
  j.removed = ww.emptySlots(config.partsTree, j.faults)
  veh:respawn(serialize(config))
  toast('The ticket: ' .. j.item .. '. Drive it into your garage.')
end

function M.onWrenchWorksDriveOut(vid, info)
  local s, js, j = active()
  if not j or j.kind ~= 'repair' or vid ~= j.carVid or not j.removed or type(info) ~= 'table' then return end
  local fixed = ww.fixedCount(info.partsTree, j.faults, j.removed)
  local amount, verdict = ww.repairSettle(j, fixed, j.spent)
  if verdict == 'unfinished' then
    toast(string.format('The ticket is not done yet: %d of %d. Bring it back in.', fixed, #j.faults))
    return
  end
  local late = j.startedAt and os.clock() - j.startedAt > j.seconds
  if late then amount = math.floor(amount / 20) * 10 end
  leaving = vid
  pay(s, js, j, amount, late and 4 or (verdict == 'over budget' and 6 or 15),
    'Ticket done' .. (late and ', late' or '') .. (verdict == 'over budget' and ', over budget' or '') .. ': $%d. The customer drives off.')
end

function M.onUpdate()
  register()
  local _, _, j = active()
  if j and j.kind == 'repair' and j.carVid and not j.removed then emptyTicketSlots(j) end
  if leaving and (not slrr_garage or not slrr_garage.getPhase or slrr_garage.getPhase() == 'idle') then
    local veh = getObjectByID(leaving)
    leaving = nil
    if veh then
      if gameplay_walk then gameplay_walk.setWalkingMode(true, nil, nil, true) end
      veh:delete()
    end
  end
end

return M
