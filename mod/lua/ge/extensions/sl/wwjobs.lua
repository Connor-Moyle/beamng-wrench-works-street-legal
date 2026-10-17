-- Wrench Works: Street Legal: the Wrench Works jobs on the job board (extension name: sl_wwjobs; Design 3 #7-9).
-- They are rows in sl_jobs' TYPES with settle = 'ww': the board offers them and the phone shows them as usual,
-- but they end when Wrench Works reports the work (a dyno run, a quarter mile, a car driven out, a part sold),
-- through sl_jobs.finishWith - the one money and rep path. Rules in sl/core/wwjobs.

local M = {}

local strings = require('sl/core/strings')

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
local TUNE = { kind = 'tune', title = strings.t('wwjobs.tune_to_spec'), unlock = ww.TIER_REP[1], settle = 'ww', offer = function(ctx, rng)
    local s = career()
    local spec = s and ctx.garage and ww.tuneSpec(rng, s.rep)
    if not spec then return nil end
    spec.settle, spec.spent, spec.seconds, spec.fragile = 'ww', 0, 0, false
    spec.legs = { stop(ctx.garage), stop(ctx.garage, spec.metric == 'power' and 'the dyno' or 'the test track quarter mile') }
    return spec
  end }

-- #7 repair tickets: the customer's car is waiting outside your garage with parts missing; drive it in, fit
-- them, drive it out
local REPAIR = { kind = 'repair', title = strings.t('wwjobs.repair_ticket'), unlock = 150, settle = 'ww', offer = function(ctx, rng)
    if not ctx.garage then return nil end
    local t = ww.repairTicket(rng)
    t.settle, t.spent, t.seconds, t.fragile = 'ww', 0, 1800, false
    t.car = { model = t.model, wear = 0.3 }
    t.legs = { stop(ctx.garage, 'the customer outside your garage'), stop(ctx.garage, 'your lift') }
    return t
  end }

-- #9 scavenging: the scrapyard lets you have a wreck; take it to your garage, pull the parts on the list and
-- sell them over the counter (they're the yard's: Wrench Works pays nothing for parts off a job car), and the yard pays a finder's fee for the lot
local SCAVENGE = { kind = 'scavenge', title = 'Scavenging', unlock = 0, settle = 'ww', offer = function(ctx, rng)
    local yard = ctx.byId.scrapyard
    if not yard or not ctx.garage then return nil end
    local j = ww.scavengeList(rng)
    j.settle, j.fragile = 'ww', false
    j.car = { model = ww.MODELS[rng:int(#ww.MODELS)], wear = 0.9 }
    j.legs = { stop(yard, 'the wreck at the scrapyard'), stop(ctx.garage, 'your garage') }
    return j
  end }

local ROWS = { TUNE, REPAIR, SCAVENGE }

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
    local text = strings.t('wwjobs.that_car_already_beats_the')
    if sl_jobs.cancel then sl_jobs.cancel(s, js, j, text) else sl_jobs.finishWith(s, js, j, 0, 0, text) end
  elseif r == 'baseline' then
    toast(string.format(strings.t('wwjobs.baseline_noted_now_build_it'), j.item))
  elseif r == 'no parts' then
    toast(string.format(strings.t('wwjobs.it_makes_the_spec_but'), math.floor(ww.MIN_SPEND * j.budget), j.spent or 0))
  elseif r == 'met' then
    local amount, verdict = ww.tuneSettle(j, j.spent)
    pay(s, js, j, amount, verdict == 'over budget' and 5 or 20, strings.t('wwjobs.spec_met_1_2_d', (j.item), (verdict)))
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
      local best = (sl_career.getState().bests or {})[tostring(x.missionId or x.id)]   -- (a slow run on purpose is no baseline: your record counts; sl/core/achievements keys bests by mission or race id)
      measured(best and best.time and math.min(r.time, best.time) or r.time, car)
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
  toast(strings.t('wwjobs.the_ticket_1_drive_it', (j.item)))
end

function M.onWrenchWorksDriveOut(vid, info)
  local s, js, j = active()
  if not j or j.kind ~= 'repair' or vid ~= j.carVid or not j.removed or type(info) ~= 'table' then return end
  local fixed = ww.fixedCount(info.partsTree, j.faults, j.removed)
  local amount, verdict = ww.repairSettle(j, fixed, j.spent)
  if verdict == 'unfinished' then
    toast(string.format(strings.t('wwjobs.the_ticket_is_not_done'), fixed, #j.faults))
    return
  end
  local late = j.startedAt and os.clock() - j.startedAt > j.seconds
  if late then amount = math.floor(amount / 20) * 10 end
  leaving = vid
  pay(s, js, j, amount, late and 4 or (verdict == 'over budget' and 6 or 15),
    strings.t('wwjobs.ticket_done_1_2_d', (late and strings.t('jobs.late') or ''), (verdict == 'over budget' and strings.t('wwjobs.over_budget') or '')))
end

----------------------------------------------------------------------------------------------
-- #9: the wanted parts the wreck hasn't got are ticked off when it arrives; each sold part ticks one off

local function checkWreck(j)
  local vd = core_vehicle_manager.getVehicleData(j.carVid)
  if not vd or not vd.config or not vd.config.partsTree then return end
  ww.markMissing(j, vd.config.partsTree)
  j.checked = true
  local left = 0
  for i = 1, #j.parts do if not j.sold[i] then left = left + 1 end end
  if left == 0 then          -- (a wreck with nothing on the list: the yard calls it off, no harm done)
    local s, js = active()
    leaving = j.carVid
    local text = strings.t('wwjobs.that_wreck_has_nothing_the')
    if sl_jobs.cancel then sl_jobs.cancel(s, js, j, text) else sl_jobs.finishWith(s, js, j, 0, 0, text) end
    return
  end
  toast(strings.t('wwjobs.the_yard_wants_1_strip', (j.item)))
end

function M.onWrenchWorksPartSold(vid, slotPath, part, price)
  local s, js, j = active()
  if not j or j.kind ~= 'scavenge' or vid ~= j.carVid then return end
  if ww.scavengeSold(j, slotPath) then
    leaving = vid
    pay(s, js, j, j.pay, 10, strings.t('wwjobs.the_yard_has_all_it'))
  end
end

function M.onUpdate()
  register()
  local _, _, j = active()
  if j and j.carVid and not j.marked and slrr_garage and slrr_garage.markJobCar then
    slrr_garage.markJobCar(j.carVid)      -- not yours: its parts sell for nothing in Wrench Works
    j.marked = true
  end
  if j and j.kind == 'repair' and j.carVid and not j.removed then emptyTicketSlots(j) end
  if j and j.kind == 'scavenge' and j.carVid and not j.checked then checkWreck(j) end
  if leaving and (not slrr_garage or not slrr_garage.getPhase or slrr_garage.getPhase() == 'idle') then
    local veh = getObjectByID(leaving)
    leaving = nil
    if veh then
      local me = getPlayerVehicle(0)
      if gameplay_walk and me and me:getID() == veh:getID() then gameplay_walk.setWalkingMode(true, nil, nil, true) end   -- (out of it only if you sit in it)
      veh:delete()
    end
  end
end

return M
