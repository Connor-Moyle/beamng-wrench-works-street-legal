-- Street Legal: tickets and court, wanted posters, the impound lot (extension name: sl_justice; police batch 2, P8-P10; each its own switch on
-- Mods > Street Legal > Police chase). Rules in sl/core/chase (the P8-P10 block). The career's bust (sl_career.onPursuitAction) asks
-- ticketInstead(pursuit) first: a pull-over at mode 1 is a ticket on the phone, not a bust. From heat level 4 the car carries a wanted record
-- that outlives the day; patrols recognise it. The impounded car stands at the police station: pay at the window by day, or cut the fence at
-- night for a chase from the gate. The phone reads summary() and calls payTicket, contestTicket, informant.

local M = {}

local rules = require('sl/core/chase')
local heatLib = require('sl/core/heat')
local strings = require('sl/core/strings')
local stateLib = require('sl/core/state')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function opt(key) return not (sl_options and sl_options.get) or sl_options.get(key) ~= false end
local function night() return sl_career and sl_career.isNight and sl_career.isNight() == true end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end
local function level() return sl_police and sl_police.level and sl_police.level() or 0 end
local function playerVid() local v = getPlayerVehicle(0) return v and v:getID() or nil end
local function store(s)
  s.tickets = type(s.tickets) == 'table' and s.tickets or {}
  s.licence = type(s.licence) == 'table' and s.licence or {}
  return s
end

-- ---- P8: the chase watch (was it a pull-over?), the tickets, the court, the suspension
local chase = nil        -- { t0, maxMode, stoppedAt } while the player is in a chase
local watchT = 0
local function watchChase()
  local s = career()
  if not s or not chase then return end
  local vid = playerVid()
  local pur = vid and gameplay_police and gameplay_police.getPursuitData and gameplay_police.getPursuitData(vid)
  if pur and (pur.mode or 0) > chase.maxMode then chase.maxMode = pur.mode end
  local v = getPlayerVehicle(0)
  if v and not chase.stoppedAt and v:getVelocity():length() < rules.STOPPED_MS then chase.stoppedAt = os.clock() - chase.t0 end
end

-- the career asks at an arrest: true when this arrest is a ticket (recorded, told) and not a bust
function M.ticketInstead(pursuit)
  local s = career()
  if not s or not opt('slPoliceTickets') or not chase then return false end
  local c = chase
  chase = nil
  if not rules.isTicket(c.maxMode, c.stoppedAt) then return false end
  store(s)
  local offences = type(pursuit) == 'table' and type(pursuit.offensesList) == 'table' and #pursuit.offensesList or 1
  local t = rules.newTicket(#s.tickets + 1 + (s.ticketSeq or 0), s.day, offences)
  s.ticketSeq = (s.ticketSeq or 0) + 1
  s.tickets[#s.tickets + 1] = t
  if ui_message then ui_message(strings.t('justice.pulled_over_ticket_1_due_day_2', t.amount, t.due), 8, 'streetLegal') end
  sl_career.sendText('benny', strings.t('justice.benny_ticket_1', t.amount), 2)
  extensions.hook('onStreetLegalChanged')
  return true
end

local function ticketById(s, id)
  for _, t in ipairs(store(s).tickets) do if t.id == tonumber(id) or t.id == id then return t end end
  return nil
end
function M.payTicket(id)
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  local t = ticketById(s, id)
  if not t then return false, strings.t('justice.no_such_ticket') end
  if t.paid then return false, strings.t('justice.already_paid') end
  if not sl_career.addMoney(-t.amount, strings.t('justice.ticket')) then return false, strings.t('carcare.it_is_d_you_have', t.amount, s.money) end
  t.paid = true
  t.paidDay = s.day
  if s.licence.suspended and not rules.suspended(s.tickets, s.day) then s.licence.suspended = nil toast(strings.t('justice.licence_back')) end
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('justice.paid_1', t.amount)
end
function M.contestTicket(id)
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  local t = ticketById(s, id)
  if not t then return false, strings.t('justice.no_such_ticket') end
  if t.paid or t.contested then return false, strings.t('justice.cannot_contest') end
  if not sl_career.addMoney(-rules.LAWYER_FEE, strings.t('justice.lawyer')) then return false, strings.t('carcare.it_is_d_you_have', rules.LAWYER_FEE, s.money) end
  local rp = rawget(_G, 'sl_replay')
  local rec = rp and rp.summary and rp.summary()
  local evidence = type(rec) == 'table' and rec.saved == true
  local okc, won = pcall(rules.contest, t, evidence, math.random())
  if not okc then sl_career.addMoney(rules.LAWYER_FEE, strings.t('justice.lawyer')) log('E', 'sl_justice', 'contest: ' .. tostring(won)) return false, strings.t('career.not_now') end
  extensions.hook('onStreetLegalChanged')
  return true, won and strings.t('justice.contest_won') or strings.t('justice.contest_lost_1_due_2', t.amount, t.due)
end
function M.suspended() local s = career() return s ~= nil and opt('slPoliceTickets') and store(s).licence.suspended == true end

local function newDay(s)
  store(s)
  local over = rules.overdue(s.tickets, s.day)
  for _, t in ipairs(over) do
    if not t.toldOverdue then t.toldOverdue = true sl_career.sendText('benny', strings.t('justice.benny_overdue_1', t.amount), 3) end
  end
  if rules.suspended(s.tickets, s.day) and not s.licence.suspended then
    s.licence.suspended = true
    sl_career.sendText('benny', strings.t('justice.benny_suspended'), 4)
  elseif s.licence.suspended and not rules.suspended(s.tickets, s.day) then
    s.licence.suspended = nil
  end
  rules.sweepTickets(s.tickets, s.day)
end

-- ---- P9: the wanted record
local lastRecognised = -1e9
local function wantedOn() return opt('slPoliceWanted') end
local function markWanted(s, lvl)
  if not wantedOn() or s.wanted then return end
  local car = sl_fleet and sl_fleet.currentCar and sl_fleet.currentCar()
  if not car then return end
  s.wanted = rules.wantedRecord(car, s.day, lvl)
  sl_career.sendText('benny', strings.t('justice.benny_wanted_1_2', car.name, s.wanted.bounty), 3)
  extensions.hook('onStreetLegalChanged')
end
local function clearWanted(s, why)
  if not s.wanted then return end
  s.wanted = nil
  toast(why)
  extensions.hook('onStreetLegalChanged')
end
local function recogniseTick()
  local s = career()
  if not (s and s.wanted and wantedOn() and gameplay_police and gameplay_police.getPoliceVehicles and gameplay_police.setPursuitMode) then return end
  if sl_police and sl_police.inPursuit and sl_police.inPursuit() then return end
  local car = sl_fleet and sl_fleet.currentCar and sl_fleet.currentCar()
  local v = getPlayerVehicle(0)
  if not (car and v and car.id == s.wanted.carId) then return end
  local p, speed = v:getPosition(), v:getVelocity():length()
  for cid in pairs(gameplay_police.getPoliceVehicles() or {}) do
    local c = getObjectByID(cid)
    if c and cid ~= v:getID() and rules.recognised((c:getPosition() - p):length(), speed, os.clock() - lastRecognised) then
      lastRecognised = os.clock()
      gameplay_police.setPursuitMode(1, v:getID(), { cid })
      if ui_message then ui_message(strings.t('justice.recognised_1', car.name), 5, 'streetLegal') end
      return
    end
  end
end
function M.onWrenchWorksPainted(vid)
  local s = career()
  if not (s and s.wanted and sl_fleet and sl_fleet.carOfVehicle) then return end
  if sl_fleet.carOfVehicle(vid) == s.wanted.carId then clearWanted(s, strings.t('justice.repainted_cleared')) end
end
-- the informant: a crew perk (a district you hold) clears the record for half the bounty
function M.informant()
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  if not s.wanted then return false, strings.t('justice.not_wanted') end
  local perks = sl_crews and sl_crews.perksHere and sl_crews.perksHere()
  if not (type(perks) == 'table' and perks.informant) then return false, strings.t('justice.no_informant_here') end
  local price = rules.informantPrice(s.wanted.bounty)
  if not sl_career.addMoney(-price, strings.t('justice.informant')) then return false, strings.t('carcare.it_is_d_you_have', price, s.money) end
  clearWanted(s, strings.t('justice.informant_cleared_1', price))
  return true, strings.t('justice.informant_cleared_1', price)
end

-- the game's pursuit events: the chase watch and the wanted record
function M.onPursuitAction(id, action, pursuit)
  local s = career()
  if not s or id ~= playerVid() then return end
  if action == 'start' then
    chase = { t0 = os.clock(), maxMode = type(pursuit) == 'table' and tonumber(pursuit.mode) or 1, stoppedAt = nil }
    if level() >= rules.WANTED_LEVEL then markWanted(s, level()) end
  elseif action == 'evade' then
    if level() >= rules.WANTED_LEVEL then markWanted(s, level()) end
    chase = nil
  elseif action == 'arrest' then
    -- (ticketInstead ran from the career first when it was a pull-over; a bust clears the watch here)
    chase = nil
  end
end

-- ---- P10: the impound lot
local lot = nil          -- { carId, vid } the impounded car standing at the station
local lotBusy = false
local function lotPlace()
  for _, p in pairs(sl_career.getPlaces and sl_career.getPlaces() or {}) do if p.kind == 'impound' then return p end end
  return nil
end
local function impoundedCar(s)
  for _, c in ipairs(s.cars or {}) do if c.impounded then return c end end
  return nil
end
local function dropLot()
  if lot then local v = getObjectByID(lot.vid) if v then pcall(v.delete, v) end end
  lot = nil
end
local function lotTick()
  local s = career()
  if not (s and opt('slPoliceImpoundLot') and sl_fleet) then return end
  local car = impoundedCar(s)
  if lot and (not car or car.id ~= lot.carId or not getObjectByID(lot.vid)) then dropLot() end
  if not car or lot or lotBusy then return end
  local place = lotPlace()
  local v = getPlayerVehicle(0)
  if not (place and place.pos and v) or (v:getPosition() - place.pos):length() > rules.LOT_BUILD_WITHIN then return end
  local spot = place.displays and place.displays[1] or { pos = place.pos, dir = place.dir }
  lotBusy = true
  core_jobsystem.create(function(job)
    local okb, err = pcall(function()
      local builder = require('sl/carBuilder')
      local pos = vec3(spot.pos.x or spot.pos[1], spot.pos.y or spot.pos[2], (spot.pos.z or spot.pos[3]) + 0.4)
      local d = spot.dir or { 1, 0 }
      local rot = quatFromDir(vec3(d.x or d[1] or 1, d.y or d[2] or 0, 0), vec3(0, 0, 1))
      local veh = builder.spawnOwned(job, car, pos, rot)
      if veh then
        veh:queueLuaCommand('controller.setFreeze(1) input.event("parkingbrake", 1, FILTER_DIRECT)')
        lot = { carId = car.id, vid = veh:getID() }
      end
    end)
    if not okb then log('E', 'sl_justice', 'the impound lot could not build the car: ' .. tostring(err)) end
    lotBusy = false
  end)
end
-- the window and the fence: the game's prompt at the lot
function M.onGetRawPoiListForLevel(lvl, elements)
  local s = career()
  local place = s and opt('slPoliceImpoundLot') and lotPlace()
  if not place or lvl ~= sl_career.LEVEL then return end
  local pos = vec3(place.pos.x, place.pos.y, place.pos.z)
  elements[#elements + 1] = {
    id = 'slImpoundLot', data = { type = 'other', id = 'slImpoundLot', impoundLot = true, name = place.name, date = 0 }, clusterType = 'missionMarker', clusterInBigMap = false,
    clusterInPlayMode = true, interactableInPlayMode = true, quickTravelAvailable = false,
    markerInfo = { missionMarker = { pos = pos, rot = quat(0, 0, 0, 1), icon = 'mission_arrival_triangle' } },
  }
end
local function handOver(s, car)
  local veh = lot and getObjectByID(lot.vid)
  if not veh then return end
  veh:setActive(1)
  veh:queueLuaCommand('controller.setFreeze(0) input.event("parkingbrake", 0, FILTER_DIRECT)')
  sl_fleet.adopt(car.id, veh:getID())
  lot = nil
  if sl_fleet.setActive then pcall(sl_fleet.setActive, car.id) end
end
local function lotCarOf(car) return lot ~= nil and lot.carId == car.id and getObjectByID(lot.vid) ~= nil end
function M.payAtWindow()
  local s = career()
  local car = s and impoundedCar(s)
  if not car then return false, strings.t('justice.nothing_impounded') end
  if night() then return false, strings.t('justice.window_closed') end
  local standing = lotCarOf(car)
  local ok, text = sl_career.releaseCar(car.id)
  if not ok then return false, text end
  if not standing then return true, text end          -- (the car was not in the yard yet: it went home to the garage, as the release says)
  handOver(s, car)
  return true, strings.t('justice.took_the_1', car.name)
end
function M.cutTheFence()
  local s = career()
  local car = s and impoundedCar(s)
  if not car then return false, strings.t('justice.nothing_impounded') end
  if not night() then return false, strings.t('justice.fence_by_day') end
  if not lotCarOf(car) then return false, strings.t('justice.not_in_the_yard_yet') end      -- (the state changes only once the car stands there: no free car, no chase with no car)
  local owed = car.impounded or 0
  car.impounded = nil
  car.out, car.where = false, nil
  s.heat = math.max(s.heat or 0, rules.FENCE_HEAT)
  s.wanted = rules.wantedRecord(car, s.day, rules.WANTED_LEVEL)
  s.wanted.bounty = rules.fenceBounty(owed, rules.WANTED_LEVEL)
  handOver(s, car)
  if sl_police and sl_police.chaseFromHere then pcall(sl_police.chaseFromHere) end
  if ui_message then ui_message(strings.t('justice.fence_cut_1', car.name), 7, 'streetLegal') end
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('justice.fence_cut_1', car.name)
end
function M.onActivityAcceptGatherData(elemData, activityData)
  local s = career()
  if not s or not opt('slPoliceImpoundLot') then return end
  for _, elem in ipairs(elemData or {}) do
    if elem.impoundLot then
      local car = impoundedCar(s)
      if car then
        local atNight = night()
        table.insert(activityData, {
          icon = 'poi_arrival_round', heading = strings.t('justice.police_impound'), preheadings = { car.name },
          sorting = { type = 'slImpound', id = 'lot' },
          buttonLabel = atNight and strings.t('justice.cut_the_fence_1', car.name) or strings.t('justice.pay_1_take_2', car.impounded or 0, car.name),
          buttonFun = function() local ok, text = atNight and M.cutTheFence() or M.payAtWindow() if text then toast(text) end end,
          buttonSoundClass = 'bng_hover_generic',
        })
      end
    end
  end
end

-- ---- the phone and the garage computer
function M.summary()
  local s = career()
  if not s then return nil end
  store(s)
  local tickets = {}
  for _, t in ipairs(s.tickets) do
    tickets[#tickets + 1] = { id = t.id, day = t.day, amount = t.amount, due = t.due, paid = t.paid == true, contested = t.contested == true, overdue = (not t.paid) and t.due < s.day }
  end
  local car = impoundedCar(s)
  local perks = sl_crews and sl_crews.perksHere and sl_crews.perksHere()
  return {
    tickets = tickets, suspended = s.licence.suspended == true, lawyerFee = rules.LAWYER_FEE,
    wanted = s.wanted and { car = s.wanted.name, model = s.wanted.model, bounty = s.wanted.bounty, since = s.wanted.day, days = s.day - (s.wanted.day or s.day),
      informant = type(perks) == 'table' and perks.informant ~= nil, informantPrice = rules.informantPrice(s.wanted.bounty) } or nil,
    impound = car and { car = car.name, carId = car.id, owed = car.impounded, place = (lotPlace() or {}).name, standing = lot ~= nil } or nil,
  }
end

local tickT = 0
function M.onUpdate(dtReal)
  tickT = tickT + dtReal
  if tickT < 0.25 then return end
  tickT = 0
  local ok, err = pcall(function() watchChase() recogniseTick() lotTick() end)
  if not ok then log('E', 'sl_justice', tostring(err)) end
end
function M.onStreetLegalNewDay() local s = career() if s then pcall(newDay, s) end end
function M.onStreetLegalStopped() chase = nil dropLot() lastRecognised = -1e9 end
function M.onClientEndMission() chase = nil lot = nil lotBusy = false end
function M.status()
  local s = career()
  if not s then return 'no career' end
  local sum = M.summary()
  return string.format('tickets %d (suspended %s); wanted %s; impound %s; chase watch %s', #sum.tickets, tostring(sum.suspended), sum.wanted and (sum.wanted.car .. ' $' .. sum.wanted.bounty) or 'none',
    sum.impound and (sum.impound.car .. (sum.impound.standing and ' standing' or ' not built')) or 'none', chase and string.format('mode %d stopped %s', chase.maxMode, tostring(chase.stoppedAt)) or 'none')
end
-- for the tester: a ticket and a wanted record without a chase
function M.debugTicket() local s = career() if not s then return 'no career' end chase = { t0 = os.clock(), maxMode = 1, stoppedAt = 1 } return tostring(M.ticketInstead({ offensesList = { 'speeding' } })) end
function M.debugWanted() local s = career() if not s then return 'no career' end markWanted(s, 4) return M.status() end

return M
