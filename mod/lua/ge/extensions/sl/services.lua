-- Street Legal Racing: what the garage does for you (extension name: sl_services)
-- Wrench Works' garage has a Services drawer that other mods fill; the career offers, as SLRR's
-- garage did: fluids and a battery, an oil change, a nitrous refill, an engine rebuild (just the
-- engine, for when the whole car is more than you can pay for), your other cars (swap the one on
-- the lift), and a race selector (pick an event: your opponent waits at the start, you are taken there).

local M = {}

local rules = require('sl_carcare')
local roster = require('sl/core/roster')
local rngLib = require('sl/core/rng')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

local PRICES = { coolant = 30, battery = 120, n2o = 150 }

local function engineRebuildCost(car)
  local c = sl_carcare.careOf(car)
  return math.floor((900 + (car.value or 5000) * 0.12 + (c.engineKm or 0) * 0.004) / 10) * 10
end

local function toast(text) if text then guihooks.trigger('slPhoneToast', { text = text }) end if ui_message then ui_message(text, 4, 'streetLegal') end end

-- the drawer's entries
function M.onWrenchWorksServices(list, vid)
  local s = career()
  if not s then return end
  local car = sl_fleet.currentCar()
  if car then
    local c = sl_carcare.careOf(car)
    local add = function(t) t.group = 'Your ' .. (car.name or 'car') list[#list + 1] = t end
    add({ id = 'oil', label = 'Oil change', price = rules.oilChangeCost(4), desc = string.format('fresh oil: it is %s km old, %d%% full', tostring(math.floor(c.oilKm or 0)), math.floor((c.oilLevel or 1) * 100)) })
    add({ id = 'coolant', label = 'Top up the coolant', price = PRICES.coolant, desc = string.format('%d%% full', math.floor((c.coolantLevel or 1) * 100)) })
    add({ id = 'battery', label = 'New battery', price = PRICES.battery, desc = string.format('this one is at %d%%', math.floor((c.battery or 1) * 100)) })
    if c.n2o then add({ id = 'n2o', label = 'Refill the nitrous', price = PRICES.n2o, desc = string.format('the bottle is at %d%%', math.floor(c.n2o * 100)) }) end
    add({ id = 'engine', label = 'Rebuild the engine', price = engineRebuildCost(car), desc = string.format('only the engine, like new: %s km of wear and any internal damage gone', tostring(math.floor(c.engineKm or 0))) })
  end
  for _, other in ipairs(s.cars) do
    if not car or other.id ~= car.id then
      list[#list + 1] = { id = 'swap:' .. other.id, group = 'Your other cars', label = other.name,
        desc = other.impounded and 'in the police impound' or 'put this one away and bring that one in', disabled = other.impounded ~= nil }
    end
  end
  if car then
    for _, r in ipairs(sl_career.racesList() or {}) do
      list[#list + 1] = { id = 'race:' .. r.id, group = 'Races', label = r.name, desc = r.drag and 'drag strip, test track: a racer of your level waits' or 'a racer of your level waits at the start' }
    end
    -- the race tracks: the map's own missions when it lists them, else its venue file
    local missionTracks = sl_career.tracksList and sl_career.tracksList()
    for _, t in ipairs(missionTracks or {}) do
      list[#list + 1] = { id = 'mtrack:' .. t.missionId, group = 'Tracks', label = t.name,
        desc = (t.laps and t.laps > 1 and t.laps .. ' laps' or 'start to finish') .. ': a racer of your level on the grid with you' }
    end
    for _, t in ipairs(not missionTracks and sl_streets and sl_streets.tracks and sl_streets.tracks() or {}) do
      list[#list + 1] = { id = 'track:' .. t.id, group = 'Tracks', label = t.name,
        desc = (t.sprint and 'a stage, start to finish' or t.laps .. ' laps') .. (t.kind == 'offroad' and ', off road' or '') .. ': a racer of your level on the grid with you' }
    end
  end
end

-- a racer for an event: one of about your level, by tier
local function racerForEvent(s, raceId)
  local mine = 1
  for t, def in ipairs(roster.TIERS) do if (s.rep or 0) >= def.rep[1] then mine = t end end
  local list = {}
  for _, r in ipairs(s.racers) do if math.abs(r.tier - mine) <= 1 then list[#list + 1] = r end end
  if #list == 0 then list = s.racers end
  return list[rngLib.new(rngLib.hash(tostring(raceId) .. ':' .. s.day)):int(#list)]
end

local function doRace(s, raceId)
  local race
  for _, r in ipairs(sl_career.racesList() or {}) do if tostring(r.id) == tostring(raceId) then race = r end end
  local racer = race and racerForEvent(s, raceId)
  if not race or not racer then return toast('That race is not on.') end
  s.known[racer.id] = true
  -- the event: their usual stake, at that start line
  local bet = math.floor(((racer.betMin or 100) + (racer.betMax or 300)) / 2 / 50) * 50
  for i = #s.challenges, 1, -1 do if s.challenges[i].racer == racer.id then table.remove(s.challenges, i) end end
  s.challenges[#s.challenges + 1] = { id = racer.id .. ':event:' .. os.time(), racer = racer.id, stake = 'money', bet = bet,
    race = race.id, raceName = race.name, missionId = race.missionId, nightOnly = racer.nightOnly, at = os.time() }
  core_jobsystem.create(function(job)
    if slrr_garage and slrr_garage.leave then slrr_garage.leave() end
    job.sleep(4)
    local v = getPlayerVehicle(0)
    if not v then return end
    guihooks.trigger('slFade', { on = true })
    job.sleep(0.8)
    local dir = race.finish and (race.finish - race.start) or vec3(0, 1, 0)
    dir.z = 0
    dir = dir:length() > 1 and dir:normalized() or vec3(0, 1, 0)
    spawn.safeTeleport(v, race.start - dir * 25 + vec3(0, 0, 0.4), quatFromDir(dir, vec3(0, 0, 1)), true, nil, nil, nil, false)   -- just short of the line (not repaired)
    job.sleep(1)
    guihooks.trigger('slFade', { on = false })
    toast(string.format('%s is waiting at %s. $%d. Roll up to the line.', roster.displayName(racer), race.name, bet))
  end)
end

local function doSwap(id)
  core_jobsystem.create(function(job)
    if slrr_garage and slrr_garage.leave then slrr_garage.leave() end
    job.sleep(4)
    local ok, text = sl_fleet.setActive(id)
    toast(text)
    if not ok then return end
    job.sleep(5)
    local car = sl_fleet.currentCar()
    local veh = car and sl_fleet.vehicleOf(car.id)
    if veh and gameplay_walk and gameplay_walk.getInVehicle then gameplay_walk.getInVehicle(veh) end
    job.sleep(1)
    if slrr_garage and slrr_garage.enter then slrr_garage.enter() end
  end)
end

-- a click in the drawer
function M.onWrenchWorksService(id, vid)
  local s = career()
  if not s then return end
  local car = sl_fleet.currentCar()
  local swap = id:match('^swap:(%d+)$')
  if swap then return doSwap(tonumber(swap)) end
  local race = id:match('^race:(.+)$')
  if race then return doRace(s, race) end
  local mtrack = id:match('^mtrack:(.+)$')
  if mtrack then
    local racer = racerForEvent(s, mtrack)
    if not racer then return toast('Nobody to race.') end
    s.known[racer.id] = true
    core_jobsystem.create(function(job)
      if slrr_garage and slrr_garage.leave then slrr_garage.leave() end
      job.sleep(4)
      local _, text = sl_career.launchTrack(racer.id, mtrack)
      toast(text)
    end)
    return
  end
  local track = id:match('^track:(.+)$')
  if track then
    local racer = racerForEvent(s, track)
    if not racer then return toast('Nobody to race.') end
    s.known[racer.id] = true
    core_jobsystem.create(function(job)
      if slrr_garage and slrr_garage.leave then slrr_garage.leave() end
      job.sleep(4)
      local _, text = sl_streets.trackRace(racer.id, track)
      toast(text)
    end)
    return
  end
  if not car then return end
  local c = sl_carcare.careOf(car)
  if id == 'oil' then
    if not sl_career.addMoney(-rules.oilChangeCost(4), 'Oil change: ' .. car.name) then return toast('Not enough money.') end
    c.oilKm, c.oilLevel = 0, 1
    local veh = sl_fleet.vehicleOf(car.id)
    if veh then veh:queueLuaCommand('if slCar then slCar.setState({ oilKm = 0, oilLevel = 1 }) end') end
    toast('Fresh oil in.')
  elseif PRICES[id] then
    if id == 'n2o' and not c.n2o then return end
    if not sl_career.addMoney(-PRICES[id], ({ coolant = 'Coolant', battery = 'Battery', n2o = 'Nitrous refill' })[id] .. ': ' .. car.name) then return toast('Not enough money.') end
    sl_carcare.refill(car.id, id, id == 'coolant' and 10 or 0)
    toast(({ coolant = 'Coolant topped up.', battery = 'New battery in.', n2o = 'Nitrous bottle full.' })[id])
  elseif id == 'engine' then
    local cost = engineRebuildCost(car)
    if not sl_career.addMoney(-cost, 'Engine rebuild: ' .. car.name) then return toast(string.format('The rebuild is $%d.', cost)) end
    c.engineKm, c.oilKm, c.oilLevel, c.coolantLevel = 0, 0, 1, 1
    sl_carcare.note(car, 'Engine rebuilt')
    local veh = sl_fleet.vehicleOf(car.id)
    if veh then veh:queueLuaCommand('if slCar then slCar.rebuildEngine() end') end
    toast('The engine is rebuilt. Like new.')
  end
  extensions.hook('onStreetLegalChanged')
end

return M
