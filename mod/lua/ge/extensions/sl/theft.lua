-- Street Legal: car theft (extension name: sl_theft; the Car theft part, OFF by default: Mods > Street Legal > Parts of the game > Car theft).
-- Rules in sl/core/theft (Graph docs/CAR_THEFT.md). On foot near a fair-game car (the game's parked cars, a traffic car that stopped and emptied)
-- the walk-up prompt offers a break-in: the era from the car's years decides the stages (the lock and the wires; the bypass box first on a mid car;
-- the fob on a modern one) and the tool it needs. The stages are 9e's screens (docs/THEFT_CONTRACT.md: guihooks 'slTheftGame' in,
-- sl_theft.gameResult out); with the Developer switch "Theft screens: autoplay" the stages resolve by a roll after their time, for the tester.
-- Noise draws witnesses and the alarm (heat, a patrol); a stolen car is a hot record, wanted (sl_justice) once reported, impounded on a bust,
-- maybe tracked (the police come to it until the tracker is out); sold, stripped, plated or titled at the fence, or bought hot at the black
-- market (19's shops call the functions at the end). Plates: every career car keeps its plate text and a new one is bought.
-- The save: s.theft = { tools, stolen, deliveries, busts, fenceKnown }. Vehicle ids never survive a restart: the hot cars are rebuilt at
-- their last place on career start, and every delete or register checks the vehicle is the record's car.

local M = {}

local rules = require('sl/core/theft')
local heatLib = require('sl/core/heat')
local chaseLib = require('sl/core/chase')
local strings = require('sl/core/strings')
local features = require('sl/core/features')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function opt(key, default) if not (sl_options and sl_options.get) then return default end local v = sl_options.get(key) if v == nil then return default end return v end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end
local function say(text, s) if ui_message then ui_message(text, s or 5, 'streetLegal') end end
local function night() return sl_career and sl_career.isNight and sl_career.isNight() == true end
local function store(s)
  s.theft = type(s.theft) == 'table' and s.theft or {}
  local t = s.theft
  t.tools, t.stolen, t.deliveries, t.busts = t.tools or {}, t.stolen or {}, t.deliveries or { done = 0 }, t.busts or 0
  return t
end
local function onFoot() local v = getPlayerVehicle(0) return v ~= nil and v:getJBeamFilename() == 'unicycle' end
local function playerVid() local v = getPlayerVehicle(0) return v and v:getID() or nil end
local function fleetCar(vid) return sl_fleet and sl_fleet.carOfVehicle and sl_fleet.carOfVehicle(vid) or nil end
local function changed() extensions.hook('onStreetLegalChanged') end
-- the record's own car, or nil: the id must point at a vehicle of the record's model that is nobody's fleet car (ids are reused by the game)
local function carOf(rec)
  local v = rec.vid and getObjectByID(rec.vid)
  if not v or v:getJBeamFilename() ~= rec.model or fleetCar(rec.vid) then return nil end
  return v
end
local function recordOf(s, vid) for i, r in ipairs(store(s).stolen) do if r.vid == vid then return r, i end end return nil end

-- ---- what a car is: its era, class and name from the game's own files
local function describe(vid)
  local ok, d = pcall(function() return core_vehicles.getVehicleDetails(vid) end)
  if not ok or type(d) ~= 'table' then return nil end
  local cfg, model = type(d.configs) == 'table' and d.configs or {}, type(d.model) == 'table' and d.model or {}
  local key = tostring(d.key or '')
  local year = rules.year(cfg.Years, model.Years, key)
  local prestige = cfg.InsuranceClass == 'prestige' or model.InsuranceClass == 'prestige'
  local value = tonumber(cfg.Value) or tonumber(model.Value) or 8000
  local name = (model.Brand and (model.Brand .. ' ') or '') .. tostring(model.Name or key)
  if cfg.Configuration then name = name .. ' ' .. tostring(cfg.Configuration) end
  return { vid = vid, model = key, config = d.pc_file, name = name, year = year, era = rules.era(year, prestige), prestige = prestige, value = value }
end

-- ---- fair game: the game's parked cars, and traffic cars that have stood still (the driver stepped out) for a while
local stoodSince = {}
local function fairGame(vid, s)
  if fleetCar(vid) then return false, 'own' end
  if recordOf(s, vid) then return false, 'own' end
  local t = gameplay_traffic and gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData()[vid]
  if t and t.role and t.role.name == 'police' then return false, 'own' end
  if sl_lot and sl_lot.owns and sl_lot.owns(vid) then return false, 'own' end
  if sl_streets and sl_streets.isMeetCar and sl_streets.isMeetCar(vid) then return false, 'own' end
  if t and (tonumber(t.speed) or 0) > 0.5 then return false, 'running' end
  return true
end
-- for ba's siphoning and anyone else: may this car be touched? ok, reason ('own' | 'running')
function M.fairGame(vid)
  local s = career()
  if not s or not vid or vid == playerVid() then return false, 'own' end
  local ok, res, why = pcall(fairGame, vid, s)
  if not ok then return false, 'own' end
  return res == true, why
end
local function candidates(s)
  local out = {}
  local v = getPlayerVehicle(0)
  if not v then return out end
  local p, now = v:getPosition(), os.clock()
  local seen = {}
  local okp, parked = pcall(function() return gameplay_parking.getParkedCarsList() end)
  for _, vid in ipairs(okp and type(parked) == 'table' and parked or {}) do seen[vid] = 'parked' end
  for vid, t in pairs(gameplay_traffic and gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {}) do
    if not seen[vid] and vid ~= v:getID() and (tonumber(t.speed) or 1) < 0.5 and not (t.pursuit and (t.pursuit.mode or 0) > 0) then
      stoodSince[vid] = stoodSince[vid] or now
      if now - stoodSince[vid] >= rules.STOOD_S then seen[vid] = 'traffic' end
    elseif not seen[vid] then stoodSince[vid] = nil end
  end
  for vid, kind in pairs(seen) do
    local o = getObjectByID(vid)
    if o and (o:getPosition() - p):length() <= rules.REACH_M and fairGame(vid, s) then
      out[#out + 1] = { vid = vid, kind = kind, pos = o:getPosition() }
      if kind == 'traffic' and opt('slTheftLockTraffic', true) == true then pcall(function() o.playerUsable = false end) end      -- (the break-in is the way in, per car; never the game's traffic setting)
    end
  end
  return out
end

-- ---- the prompt
local marks, markSig = {}, ''
function M.onGetRawPoiListForLevel(level, elements)
  local s = career()
  if not s or level ~= sl_career.LEVEL then return end
  for _, m in ipairs(marks) do
    local ok, err = pcall(function()
      local pos = vec3(m.pos.x, m.pos.y, m.pos.z)
      elements[#elements + 1] = {
        id = 'slTheft:' .. m.vid, data = { type = 'other', id = 'slTheft:' .. m.vid, theftVid = m.vid, name = strings.t('theft.break_in'), date = 0 }, clusterType = 'missionMarker',
        clusterInBigMap = false, clusterInPlayMode = false, interactableInPlayMode = true, quickTravelAvailable = false,
        markerInfo = { missionMarker = { pos = pos, rot = quat(0, 0, 0, 1), icon = 'mission_arrival_triangle' } },
      }
    end)
    if not ok then log('E', 'sl_theft', 'poi: ' .. tostring(err)) end
  end
end
local session = nil        -- the break-in in progress: { vid, car, d, stage, noise, t0, witnessAt, tool, alarmed }
local tried = {}           -- [vid] = os.clock() of the last failed try (this session only: a saved clock means nothing after a restart)
local function promptFor(s, vid)
  local car = describe(vid)
  if not car then return nil end
  local tool = rules.toolFor(car.era, store(s).tools)
  local need = rules.needs(car.era)
  local label = strings.t('theft.break_in_1_2', car.name, strings.t('theft.era_' .. car.era))
  if need and not tool then label = strings.t('theft.needs_1', rules.tool(need[1]).title) end
  return car, label
end
function M.onActivityAcceptGatherData(elemData, activityData)
  local s = career()
  if not s or session then return end
  for _, elem in ipairs(elemData or {}) do
    local vid = tonumber(elem.theftVid)
    if vid then
      local ok, car, label = pcall(promptFor, s, vid)
      if not ok then log('E', 'sl_theft', 'prompt: ' .. tostring(car))
      elseif car then
        table.insert(activityData, {
          icon = 'poi_arrival_round', heading = car.name, preheadings = { strings.t('theft.break_in') },
          sorting = { type = 'slTheft', id = vid },
          buttonLabel = label,
          buttonFun = function() local okb, _, text = pcall(M.begin, vid) if not okb then log('E', 'sl_theft', 'begin: ' .. tostring(_)) elseif text then toast(text) end end,
          buttonSoundClass = 'bng_hover_generic',
        })
      end
    end
  end
end

-- ---- the alarm, the witnesses, the heat
local function raiseHeat(s, amount)
  s.heat = heatLib.raised(s.heat or 0, amount or heatLib.BUST)
  changed()
end
local function patrolNear(pos, within)
  if not (gameplay_police and gameplay_police.getPoliceVehicles) then return false end
  for cid in pairs(gameplay_police.getPoliceVehicles() or {}) do
    local c = getObjectByID(cid)
    if c and (c:getPosition() - pos):length() <= within then return true end
  end
  return false
end
local function alarm(s, vid)
  local o = getObjectByID(vid)
  if o then
    core_jobsystem.create(function(job)
      local on = false
      for i = 1, rules.ALARM_S * 2 do
        local v = getObjectByID(vid)
        if not v then break end
        on = not on
        v:queueLuaCommand(string.format('electrics.set_warn_signal(%d) if electrics.horn then electrics.horn(%s) end', on and 1 or 0, on and 'true' or 'false'))
        job.sleep(0.5)
      end
      local v = getObjectByID(vid)
      if v then v:queueLuaCommand('electrics.set_warn_signal(0) if electrics.horn then electrics.horn(false) end') end
    end)
  end
  say(strings.t('theft.alarm'), 5)
  raiseHeat(s, heatLib.BUST)
  if o and patrolNear(o:getPosition(), rules.PATROL_M) and sl_police and sl_police.chaseFromHere then pcall(sl_police.chaseFromHere) end
end
local function peopleAbout() local p = rawget(_G, 'slrrPedestrians') return p ~= nil and p.getCount ~= nil and (p.getCount() or 0) > 0 end
-- for ba's siphoning: this much noise at this car: a witness (the heat, if the switch says) and the alarm; answers { witness, alarm }
function M.exposure(vid, noise)
  local s = career()
  if not s then return { witness = false, alarm = false } end
  local e = rules.exposure(noise, peopleAbout(), not night())
  if e.witness and opt('slTheftWitnesses', true) ~= false then say(strings.t('theft.witness'), 5) raiseHeat(s, heatLib.BUST) end
  if e.alarm and vid then alarm(s, vid) end
  return e
end

-- ---- the tracker: the police come to the car until it is out
local function trackedOn(rec)
  rec.lastTrack = os.clock() - rules.TRACK_RESEND_S + rules.TRACK_S      -- (the first call comes TRACK_S after the wheels turn)
  say(strings.t('theft.tracked_radio_1', rec.name), 6)
  guihooks.trigger('slTheftTracked', { on = true, name = rec.name })
end
local function trackedOff(rec, text)
  rec.tracked, rec.jammedUntil = false, nil
  guihooks.trigger('slTheftTracked', { on = false, name = rec.name })
  if text then toast(text) end
  changed()
end
local function trackTick(s, rec, v)
  local now = os.clock()
  if not rules.trackerDue(rec, now) then return end
  local okv, speed = pcall(function() return v:getVelocity():length() end)
  if not okv or (speed or 0) < 2 then return end      -- (the clock runs from driving off)
  rec.lastTrack = now
  if sl_police and sl_police.chaseFromHere then pcall(sl_police.chaseFromHere) end
  say(strings.t('theft.tracked_again'), 4)
end
-- the search for the tracker: in the car, standing still, PULL_S (less with the finder); the car moving ends it
local pulling = nil
function M.pullTracker()
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  local rec = recordOf(s, playerVid())
  if not rec or not rec.tracked then return false, strings.t('theft.not_tracked') end
  if pulling then return false, strings.t('career.not_now') end
  local t = store(s)
  local finder = rules.has(t.tools, 'finder')
  local secs = rules.pullSeconds(finder)
  pulling = rec
  core_jobsystem.create(function(job)
    local left = secs
    while left > 0 do
      job.sleep(0.5)
      left = left - 0.5
      local v = getPlayerVehicle(0)
      local okv, speed = pcall(function() return v:getVelocity():length() end)
      if pulling ~= rec or not v or v:getID() ~= rec.vid or not okv or speed > 1 then pulling = nil toast(strings.t('theft.pull_stopped')) return end
    end
    pulling = nil
    if finder then rules.useTool(t.tools, 'finder') end
    trackedOff(rec, strings.t('theft.pulled'))
  end)
  return true, strings.t('theft.pulling_1', math.floor(secs))
end
-- the jammer: the tracker is silent for JAM_S
function M.jam()
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  local rec = recordOf(s, playerVid())
  if not rec or not rec.tracked then return false, strings.t('theft.not_tracked') end
  local t = store(s)
  if not rules.has(t.tools, 'jammer') then return false, strings.t('theft.needs_1', rules.tool('jammer').title) end
  rules.useTool(t.tools, 'jammer')
  rec.jammedUntil = os.clock() + rules.JAM_S
  changed()
  return true, strings.t('theft.jammed_1', math.floor(rules.JAM_S))
end

-- ---- plates: the career's cars keep their plate text; a change made outside the career comes back; a new plate is bought
local function applyPlate(vid, text)
  if not (core_vehicles and core_vehicles.setPlateText) then return end
  pcall(core_vehicles.setPlateText, text, vid)
end
local function plateNow(v)
  local ok, txt = pcall(function() return core_vehicles.getVehicleLicenseText(v) end)
  return ok and type(txt) == 'string' and txt or nil
end
-- the record (a fleet car's or a hot car's) the player's vehicle belongs to
local function plateHolder(s, v)
  local vid = v:getID()
  local carId = fleetCar(vid)
  if carId then for _, c in ipairs(s.cars or {}) do if c.id == carId then return c end end end
  return recordOf(s, vid)
end
local function plateTick(s, v)
  local holder = plateHolder(s, v)
  if not holder then return end
  local now = plateNow(v)
  if holder.plate == nil then holder.plate = now return end      -- (an existing car: its plate is recorded as it is, never changed)
  if now ~= nil and now ~= holder.plate then applyPlate(v:getID(), holder.plate) toast(strings.t('theft.plate_put_back')) end
end
function M.plateOf(carId)
  local s = career()
  if not s then return nil end
  for _, c in ipairs(s.cars or {}) do if c.id == carId then return c.plate end end
  return nil
end
-- a new plate for one of the player's cars: $300 (paid = the shop took the money)
function M.newPlate(carId, paid)
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  local car
  for _, c in ipairs(s.cars or {}) do if c.id == carId then car = c end end
  if not car then return false, strings.t('theft.no_such_car') end
  local price = rules.platePrice(false)
  if not paid and not sl_career.addMoney(-price, strings.t('theft.plates')) then return false, strings.t('carcare.it_is_d_you_have', price, s.money) end
  car.plate = rules.plateText((s.seed or 0) .. ':' .. carId .. ':' .. s.day .. ':' .. os.clock())
  local vid = sl_fleet and sl_fleet.vehicleOf and sl_fleet.vehicleOf(carId)
  if vid then applyPlate(vid, car.plate) end
  if s.wanted and s.wanted.carId == carId and not s.wanted.stolen then s.wanted = nil toast(strings.t('theft.plate_cleared')) end      -- (P9: a normal wanted car: a repaint or a plate change)
  changed()
  return true, strings.t('theft.new_plate_1', car.plate)
end

-- ---- the break-in
local function endSession() local vid = session and session.vid session = nil if vid then guihooks.trigger('slTheftEnd', { vid = vid }) end end      -- (9e's screen closes on slTheftEnd)
local function startStage()
  local st = session
  local stage = st.d.stages[st.stage]
  if opt('slTheftAutoplay', false) == true then
    core_jobsystem.create(function(job)
      job.sleep(st.d.seconds / #st.d.stages)
      if session ~= st then return end
      local ok, noise = rules.autoplay(st.d, math.random())
      M.gameResult(st.vid, stage, ok, noise)
    end)
  else
    guihooks.trigger('slTheftGame', { vid = st.vid, stage = stage, stages = st.d.stages, difficulty = st.d, era = st.car.era, tool = st.tool, model = st.car.model, name = st.car.name, noise = st.noise })
  end
end
function M.begin(vid)
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  if session then return false, strings.t('career.not_now') end
  if not onFoot() then return false, strings.t('theft.on_foot') end
  local car = describe(vid)
  if not car or not fairGame(vid, s) then return false, strings.t('theft.not_that_one') end
  local t = store(s)
  local need, tool = rules.needs(car.era), rules.toolFor(car.era, t.tools)
  if need and not tool then return false, strings.t('theft.needs_1', rules.tool(need[1]).title) end
  if not tool and rules.has(t.tools, 'slimjim') then tool = 'slimjim' end
  local retry = tried[vid] ~= nil and (os.clock() - tried[vid]) < rules.RETRY_S
  session = { vid = vid, car = car, d = rules.difficulty(car.era, car.value, car.prestige, retry), stage = 1, noise = 0, t0 = os.clock(), tool = tool }
  startStage()
  return true, nil
end
-- the wanted record of a hot car (sl_justice recognises the vehicle by its id)
function M.wantIt(s, rec)
  if s.wanted or not rec.vid then return end
  s.wanted = { vid = rec.vid, name = rec.name, model = rec.model, day = s.day, level = 4, bounty = chaseLib.bounty(4), stolen = true }
  rec.reported = true
end
-- a car becomes a hot record of the player's: the record, the tracker roll, the wanted state, the player in it
local function takeCar(s, o, car, reported, f, tracked)
  local t = store(s)
  pcall(function() o.playerUsable = true end)
  pcall(function() gameplay_parking.removeVehicle(o:getID()) end)
  pcall(function() gameplay_traffic.removeTraffic(o:getID()) end)
  local rec = rules.stolenRecord(car, car.era, s.day, reported)
  rec.vid = o:getID()
  rec.plate = plateNow(o)
  if tracked == nil then tracked = rules.tracked(car.era, car.prestige, f, math.random()) end
  rec.tracked = tracked
  t.stolen[#t.stolen + 1] = rec
  if reported then M.wantIt(s, rec) end
  pcall(function() if gameplay_walk and gameplay_walk.getInVehicle then gameplay_walk.getInVehicle(o) else be:enterVehicle(0, o) end end)
  if tracked then trackedOn(rec) end
  changed()
  return rec
end
local function steal(s)
  local st = session
  local t = store(s)
  local o = getObjectByID(st.vid)
  if not o then endSession() return end
  local reported = st.witnessed == true or st.alarmed == true
  local f = { noise = st.noise, alarm = st.alarmed, day = not night(), witness = st.witnessed, patrol = patrolNear(o:getPosition(), rules.PATROL_M) }
  if st.tool and rules.tool(st.tool).uses then rules.useTool(t.tools, st.tool) end
  endSession()
  takeCar(s, o, st.car, reported, f)
  say(strings.t('theft.yours_for_now_1', st.car.name), 6)
end
-- the screens (or the autoplay) answer a stage: ok and the noise it made (0..1)
function M.gameResult(vid, stage, ok, noise)
  local s = career()
  local st = session
  if not s or not st or st.vid ~= tonumber(vid) then return end
  st.noise = math.min(1, st.noise + (tonumber(noise) or 0))
  if rules.witness(st.noise, peopleAbout(), not night()) and not st.witnessAt then st.witnessAt = os.clock() end
  if not ok then
    local t = store(s)
    tried[st.vid] = os.clock()
    if st.tool and rules.tool(st.tool).uses and st.car.era == 'modern' then rules.useTool(t.tools, st.tool) end
    alarm(s, st.vid)
    endSession()
    toast(strings.t('theft.failed'))
    return
  end
  if rules.alarm(st.noise) and not st.alarmed then st.alarmed = true alarm(s, st.vid) end
  if st.stage >= #st.d.stages then steal(s) else st.stage = st.stage + 1 startStage() end
end
function M.cancel() if session then tried[session.vid] = os.clock() endSession() toast(strings.t('theft.failed')) end end

-- a record without a car is rebuilt once the player is near its place (the terrain there is loaded by then; a car built far off can fall through)
M.REBUILD_M, M.REBUILD_WAIT_S = 300, 30
local rebuilding, rebuildAfter = {}, {}      -- (session only)
local function rebuildNear(s, t, p)
  for _, r in ipairs(t.stolen) do
    if not r.vid and r.pos and not rebuilding[r] and os.clock() - (rebuildAfter[r] or -1e9) >= M.REBUILD_WAIT_S and (vec3(r.pos[1], r.pos[2], r.pos[3]) - p):length() <= M.REBUILD_M then
      rebuilding[r] = true
      core_jobsystem.create(function(job)
        local ok, veh = pcall(core_vehicles.spawnNewVehicle, r.model, { config = r.config, pos = vec3(r.pos[1], r.pos[2], r.pos[3] + 0.3), autoEnterVehicle = false, canSpawnAnotherVehicleCheck = false })
        rebuilding[r] = nil
        if not (ok and veh) then rebuildAfter[r] = os.clock() log('W', 'sl_theft', 'the hot car (' .. tostring(r.model) .. ') could not be rebuilt; again in 30 s') return end      -- (no spawn storm: half a minute between tries)
        r.vid = veh:getID()
        if r.plate then applyPlate(r.vid, r.plate) end
        if s.wanted and s.wanted.stolen and s.wanted.name == r.name and not s.wanted.vid then s.wanted.vid = r.vid end
        if r.tracked then r.lastTrack = os.clock() end
        changed()
      end)
    end
  end
end

-- ---- the five pursuit deliveries (the jobs board kind 'theftrun'; sl_jobs spawns the car at the first leg and settles the pay): the twists are here
local function valueOf(model)
  local ok, m = pcall(function() return core_vehicles.getModel(model) end)
  local cfgs = ok and type(m) == 'table' and type(m.configs) == 'table' and m.configs or {}
  local best
  for _, c in pairs(cfgs) do if type(c) == 'table' and tonumber(c.Value) then best = math.max(best or 0, tonumber(c.Value)) end end
  return best or 20000
end
local function kerbLeg(rng, name, radius) local k = sl_jobs and sl_jobs.randomKerb and sl_jobs.randomKerb(rng) if not k then return nil end return { id = 'kerb', name = name, x = k.x, y = k.y, z = k.z, radius = radius } end
local function metres(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
function M.deliveryOffer(ctx, rng)
  local s = career()
  if not s or opt('slTheftDeliveries', true) == false or (s.rep or 0) < rules.DELIVERY_UNLOCK then return nil end
  local open = rules.openDeliveries(store(s).deliveries.done or 0)
  local d = open[rng:int(#open)]
  local docks = ctx.byId.meet_docks
  if not d or not docks then return nil end
  local to = { id = docks.id, name = strings.t('theft.deliv_the_docks'), x = docks.x, y = docks.y, z = docks.z, radius = 14 }
  local from
  if d.from == 'dealer' and ctx.byId.dealer then local p = ctx.byId.dealer from = { id = p.id, name = p.name, x = p.x, y = p.y, z = p.z, radius = 14 }
  else from = kerbLeg(rng, strings.t('theft.deliv_a_kerb'), 14) end
  if not from then return nil end
  local legs = { from }
  if d.minMetres then      -- the long way round: a far kerb to pass through first
    local far
    for _ = 1, 12 do local k = kerbLeg(rng, strings.t('theft.deliv_the_long_way'), 14) if k and (not far or metres(k, from) + metres(k, to) > metres(far, from) + metres(far, to)) then far = k end end
    if not far or metres(far, from) + metres(far, to) < d.minMetres then return nil end
    far.through = true
    legs[#legs + 1] = far
  elseif d.swap then legs[#legs + 1] = kerbLeg(rng, strings.t('theft.deliv_the_hand_off'), 14)
  elseif d.wash then
    local wash
    for _, p in ipairs(ctx.places) do if p.kind == 'carwash' and (not wash or metres(p, from) < metres(wash, from)) then wash = p end end
    if wash then legs[#legs + 1] = { id = wash.id, name = wash.name, x = wash.x, y = wash.y, z = wash.z, radius = 14 } end
  end
  local need = (d.minMetres or d.swap or d.wash) and 2 or 1
  if #legs < need then return nil end
  legs[#legs + 1] = to
  local total = 0
  for i = 2, #legs do total = total + metres(legs[i - 1], legs[i]) end
  local model = d.car.models[rng:int(#d.car.models)]
  local value = valueOf(model)
  return { item = d.title, legs = legs, metres = math.floor(total), fragile = false, theft = d.id, tow = d.tow or nil,
    car = { model = model, wear = 0.05, limp = d.car.limp }, hint = d.tow and strings.t('theft.deliv_tow') or nil,
    seconds = math.max(300, math.floor(total * 1.4 / (d.tow and 6 or 14) * 1.5)), pay = rules.deliveryPay(d, value) }
end
local jobTrack = nil      -- the decoy's tracker (the same mechanism as a hot car's)
local lastJobsDone = nil
local function deliveryTick(s, v)
  local j = sl_jobs and sl_jobs.activeJob and sl_jobs.activeJob()
  if not (j and j.theft) then
    if jobTrack then trackedOff(jobTrack, nil) jobTrack = nil end
    if lastJobsDone ~= nil and sl_jobs and sl_jobs.summary then      -- (the delivery ended: done if the board counted it)
      local sum = sl_jobs.summary()
      if sum and (sum.done or 0) > lastJobsDone then local t = store(s) t.deliveries.done = (t.deliveries.done or 0) + 1 changed() end
      lastJobsDone = nil
    end
    return
  end
  local d = rules.delivery(j.theft)
  if j.carVid and not j.theftStarted then      -- picked up: the police on you at once
    j.theftStarted = true
    lastJobsDone = sl_jobs.summary and (sl_jobs.summary() or {}).done or 0
    s.heat = math.max(s.heat or 0, rules.DELIVERY_HEAT)
    if sl_police and sl_police.chaseFromHere then pcall(sl_police.chaseFromHere) end
    say(strings.t('theft.deliv_pickup'), 6)
    if d.alarm then alarm(s, j.carVid) end
    if d.tracked then jobTrack = { tracked = true, vid = j.carVid, name = j.item, model = j.car.model } trackedOn(jobTrack) toast(strings.t('theft.deliv_decoy')) end
    changed()
  end
  if j.theftStarted and j.leg >= 3 then
    if d.swap and not j.swapped then      -- the hand-off: another car waits at the kerb; the hot one stays
      j.swapped = true
      local old = getObjectByID(j.carVid)
      local p = old and old:getPosition() or v:getPosition()
      local model = d.swap.models[math.random(#d.swap.models)]
      core_jobsystem.create(function(job)
        local ok, veh = pcall(core_vehicles.spawnNewVehicle, model, { pos = vec3(p.x + 6, p.y, p.z + 0.5), autoEnterVehicle = false, canSpawnAnotherVehicleCheck = false })
        if not (ok and veh) then return end
        local oldVid = j.carVid
        j.carVid = veh:getID()
        if gameplay_walk and gameplay_walk.getInVehicle then gameplay_walk.getInVehicle(veh) end
        job.sleep(1)
        local o = getObjectByID(oldVid)
        if o then o:delete() end
        toast(strings.t('theft.deliv_swap_1', model))
      end)
    elseif d.wash and jobTrack and jobTrack.tracked then trackedOff(jobTrack, strings.t('theft.deliv_washed')) end
  end
  if jobTrack and jobTrack.tracked and v:getID() == jobTrack.vid then trackTick(s, jobTrack, v) end
end

-- ---- the tick: the prompts on foot, the witness clock, the tracker, the plates, the fence's introduction
local tickT = 0
local function tick()
  local s = career()
  if not s then marks = {} return end
  if session then
    local st = session
    if st.witnessAt and os.clock() - st.witnessAt >= rules.WITNESS_S and not st.witnessed then
      local v, o = getPlayerVehicle(0), getObjectByID(st.vid)
      if v and o and (v:getPosition() - o:getPosition()):length() <= rules.WITNESS_M then
        st.witnessed = true
        say(strings.t('theft.witness'), 5)
        if opt('slTheftWitnesses', true) ~= false then raiseHeat(s, heatLib.BUST) end
      end
    end
    return
  end
  local t = store(s)
  local v = getPlayerVehicle(0)
  if v and not onFoot() then
    local rec = recordOf(s, v:getID())
    if rec and rec.tracked then trackTick(s, rec, v) end
    if opt('slTheftPlates', true) ~= false then plateTick(s, v) end
  end
  if v then deliveryTick(s, v) end
  for _, r in ipairs(t.stolen) do local o = carOf(r) if o then local p = o:getPosition() r.pos = { p.x, p.y, p.z } end end      -- (where it stands, for the rebuild after a restart)
  if v then rebuildNear(s, t, v:getPosition()) end
  if not t.fenceKnown and t.busts >= 1 and (s.rep or 0) >= 300 then t.fenceKnown = true sl_career.sendText('benny', strings.t('theft.benny_fence'), 2) changed() end
  local list = onFoot() and candidates(s) or {}
  local sig = {}
  for _, m in ipairs(list) do sig[#sig + 1] = tostring(m.vid) end
  sig = table.concat(sig, ',')
  if sig ~= markSig then
    markSig, marks = sig, list
    if sl_pois and sl_pois.refresh then sl_pois.refresh() end
  end
end
function M.onUpdate(dtReal)
  tickT = tickT + dtReal
  if tickT < ((session or pulling) and 0.5 or 3) then return end
  tickT = 0
  local ok, err = pcall(tick)
  if not ok then log('E', 'sl_theft', tostring(err)) end
end

-- the record's car goes (the impound, the fence, the owner): only the record's own vehicle is ever deleted
local function deleteCar(rec)
  local o = carOf(rec)
  if not o then return end
  local vid = o:getID()
  core_jobsystem.create(function(job)
    if playerVid() == vid and gameplay_walk then gameplay_walk.setWalkingMode(true, nil, nil, true) end
    job.sleep(1)
    local v = getObjectByID(vid)
    if v and v:getJBeamFilename() == rec.model and not fleetCar(vid) then v:delete() end
  end)
end
local function drop(s, i)
  local t = store(s)
  local r = table.remove(t.stolen, i)
  if r and s.wanted and s.wanted.vid == r.vid then s.wanted = nil end
  if r and r.tracked then guihooks.trigger('slTheftTracked', { on = false, name = r.name }) end
  return r
end
-- a bust in a hot car: the car is gone to the impound, not yours to pay for
function M.onPursuitAction(id, action)
  local s = career()
  if not s or action ~= 'arrest' or id ~= playerVid() then return end
  local t = store(s)
  t.busts = t.busts + 1
  local r, i = recordOf(s, id)
  if r then
    deleteCar(r)
    drop(s, i)
    say(strings.t('theft.busted_in_it_1', r.name), 8)
  end
  changed()
end
-- a new day: a hot car left somewhere is found and gone; an unreported one is reported
function M.onStreetLegalNewDay(day)
  local s = career()
  if not s then return end
  local t = store(s)
  local me = playerVid()
  for i = #t.stolen, 1, -1 do
    local r = t.stolen[i]
    if r.vid ~= me and not rules.legal(r) then
      deleteCar(r)
      drop(s, i)
      sl_career.sendText('benny', strings.t('theft.benny_gone_1', r.name), 2)
    elseif not r.reported and rules.reportedBy(r, day or s.day) then
      M.wantIt(s, r)
      sl_career.sendText('benny', strings.t('theft.benny_reported_1', r.name), 2)
    end
  end
end
-- a repaint of a hot car (the paint shop or the garage): half of what makes it legal
function M.onWrenchWorksPainted(vid)
  local s = career()
  local r = s and recordOf(s, vid)
  if not r then return end
  r.resprayed = true
  if rules.legal(r) and s.wanted and s.wanted.vid == vid then s.wanted = nil toast(strings.t('theft.legal_now_1', r.name)) end
  changed()
end
function M.onVehicleDestroyed(vid) stoodSince[vid] = nil tried[vid] = nil end

-- ---- the fence and the black market (19's shops call these; docs/THEFT_CONTRACT.md); `paid` = the shop took the money already
function M.tools()
  local s = career()
  local owned = s and store(s).tools or {}
  local out = {}
  for _, def in ipairs(rules.TOOLS) do
    local t = rules.tool(def.id)
    out[#out + 1] = { id = t.id, title = t.title, price = t.price, uses = t.uses, era = t.era, kind = t.kind, have = owned[t.id] ~= nil, usesLeft = owned[t.id] and owned[t.id].uses or nil }
  end
  return out
end
function M.giveTool(id)          -- (the shop has taken the money; a tool with uses stacks)
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  local t = rules.tool(id)
  if not t then return false, strings.t('theft.no_such_tool') end
  rules.giveTool(store(s).tools, id)
  changed()
  return true, strings.t('theft.tool_bought_1', t.title)
end
M.buyTool = M.giveTool
function M.toolCount(id) local s = career() local o = s and store(s).tools[id] if not o then return 0 end return o.uses or 1 end
local function hotAt(s, i) local t = store(s) return t.stolen[tonumber(i) or 0] end
local function hotRow(s, i, r)
  return { index = i, name = r.name, model = r.model, era = r.era, value = r.value, plated = r.plated, resprayed = r.resprayed, legal = rules.legal(r), tracked = r.tracked == true, plate = r.plate,
    wanted = s.wanted ~= nil and s.wanted.vid == r.vid, driving = r.vid == playerVid(), present = carOf(r) ~= nil,
    sell = rules.sellPrice(r), strip = rules.stripPay(r), plates = rules.platePrice(true), title = rules.titlePrice(r), stripTracker = rules.TRACKER_STRIP }
end
function M.hotCars()
  local s = career()
  if not s then return {} end
  local out = {}
  for i, r in ipairs(store(s).stolen) do out[#out + 1] = hotRow(s, i, r) end
  return out
end
-- the hot car the player is driving (the car under the counter), or nil
function M.current()
  local s = career()
  if not s then return nil end
  local r, i = recordOf(s, playerVid())
  return r and hotRow(s, i, r) or nil
end
function M.fenceKnown() local s = career() return s ~= nil and store(s).fenceKnown == true end
function M.sell(i)
  local s = career()
  local r = s and hotAt(s, i)
  if not r then return false, strings.t('theft.no_such_car') end
  if not carOf(r) then return false, strings.t('theft.not_here') end
  local pay = rules.sellPrice(r)
  deleteCar(r)
  drop(s, tonumber(i))
  sl_career.payOut(pay, strings.t('theft.fence'))
  changed()
  return true, strings.t('theft.sold_1_2', r.name, pay)
end
function M.strip(i)
  local s = career()
  local r = s and hotAt(s, i)
  if not r then return false, strings.t('theft.no_such_car') end
  if not carOf(r) then return false, strings.t('theft.not_here') end
  local pay = rules.stripPay(r)
  deleteCar(r)
  drop(s, tonumber(i))
  sl_career.payOut(pay, strings.t('theft.chop_shop'))
  changed()
  return true, strings.t('theft.stripped_1_2', r.name, pay)
end
local function charge(s, price, what, paid)
  if paid then return true end
  if sl_career.addMoney(-price, what) then return true end
  return false, strings.t('carcare.it_is_d_you_have', price, s.money)
end
-- new plates on a hot car: $700; with a respray too the car is legal (the wanted record goes)
function M.plates(i, paid)
  local s = career()
  local r = s and hotAt(s, i)
  if not r then return false, strings.t('theft.no_such_car') end
  if r.plated then return false, strings.t('theft.already_plated') end
  local o = carOf(r)
  if not o then return false, strings.t('theft.not_here') end
  local ok, why = charge(s, rules.platePrice(true), strings.t('theft.plates'), paid)
  if not ok then return false, why end
  r.plated = true
  r.plate = rules.plateText((s.seed or 0) .. ':hot:' .. tostring(r.vid) .. ':' .. os.clock())
  applyPlate(o:getID(), r.plate)
  local legal = rules.legal(r)
  if legal and s.wanted and s.wanted.vid == r.vid then s.wanted = nil end
  changed()
  return true, strings.t(legal and 'theft.legal_now_1' or 'theft.plated_respray_1', r.name)
end
-- the tracker out at the fence
function M.stripTracker(i, paid)
  local s = career()
  local r = s and hotAt(s, i)
  if not r then return false, strings.t('theft.no_such_car') end
  if not r.tracked then return false, strings.t('theft.not_tracked') end
  local ok, why = charge(s, rules.TRACKER_STRIP, strings.t('theft.fence'), paid)
  if not ok then return false, why end
  trackedOff(r, nil)
  return true, strings.t('theft.pulled')
end
function M.title(i, paid)
  local s = career()
  local r = s and hotAt(s, i)
  if not r then return false, strings.t('theft.no_such_car') end
  if not rules.legal(r) then return false, strings.t('theft.plates_first') end
  local o = carOf(r)
  if not o or not (sl_fleet and sl_fleet.registerVehicle) then return false, strings.t('theft.not_here') end
  local ok, why = charge(s, rules.titlePrice(r), strings.t('theft.title'), paid)
  if not ok then return false, why end
  local car = rules.titled(r)
  local okr, fleet = pcall(sl_fleet.registerVehicle, o:getID(), { name = car.name, condition = car.condition, value = car.value })
  if not (okr and type(fleet) == 'table') then      -- (no fleet car: the record stays, the money back)
    if not paid then sl_career.addMoney(rules.titlePrice(r), strings.t('theft.title')) end      -- (a shop that charged refunds its own line on false)
    return false, strings.t('theft.not_here')
  end
  fleet.plate, fleet.history = car.plate, car.history
  drop(s, tonumber(i))
  changed()
  return true, strings.t('theft.titled_1', car.name)
end

-- the black market: the day's stolen cars, cheap; bought, the car stands by the counter: hot (wanted) and maybe tracked
local market = nil      -- { day, list }
local function marketPool()
  local pool = {}
  if not (core_vehicles and core_vehicles.getModel) then return pool end
  local keys = {}
  for k in pairs(rules.MODEL_YEARS) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local ok, m = pcall(core_vehicles.getModel, key)
    local cfgs = ok and type(m) == 'table' and type(m.configs) == 'table' and m.configs or nil
    if cfgs then
      local names = {}
      for name, c in pairs(cfgs) do if type(c) == 'table' and tonumber(c.Value) then names[#names + 1] = name end end
      table.sort(names)
      local c = names[1] and cfgs[names[1]]
      if c then
        local info = type(m.model) == 'table' and m.model or {}
        local prestige = c.InsuranceClass == 'prestige' or info.InsuranceClass == 'prestige'
        local year = rules.year(c.Years, info.Years, key)
        pool[#pool + 1] = { model = key, config = 'vehicles/' .. key .. '/' .. names[1] .. '.pc', name = (info.Brand and (info.Brand .. ' ') or '') .. tostring(info.Name or key) .. ' ' .. tostring(c.Configuration or names[1]), value = tonumber(c.Value), era = rules.era(year, prestige), prestige = prestige }
      end
    end
  end
  return pool
end
function M.blackMarket()
  local s = career()
  if not s then return {} end
  if not market or market.day ~= s.day then market = { day = s.day, list = rules.blackMarketList(marketPool(), s.day, s.seed or 0) } end
  local out = {}
  for i, c in ipairs(market.list) do out[#out + 1] = { index = i, model = c.model, name = c.name, value = c.value, era = c.era, price = c.price, sold = c.sold == true } end
  return out
end
function M.buyHot(i, paid)
  local s = career()
  if not s then return false, strings.t('needs.no_career') end
  M.blackMarket()
  local c = market and market.list[tonumber(i) or 0]
  if not c or c.sold then return false, strings.t('theft.no_such_car') end
  local v = getPlayerVehicle(0)
  if not v or not (core_vehicles and core_vehicles.spawnNewVehicle) then return false, strings.t('theft.not_here') end
  local ok, why = charge(s, c.price, strings.t('theft.black_market'), paid)
  if not ok then return false, why end
  c.sold = true
  local p = v:getPosition()
  core_jobsystem.create(function(job)
    local okv, veh = pcall(core_vehicles.spawnNewVehicle, c.model, { config = c.config, pos = vec3(p.x + 8, p.y, p.z + 0.5), autoEnterVehicle = false, canSpawnAnotherVehicleCheck = false })
    if not (okv and veh) then
      c.sold = false
      sl_career.addMoney(c.price, strings.t('theft.black_market'))      -- (no car: the money back, whoever charged: the shop was told true already)
      toast(strings.t('theft.not_here'))
      return
    end
    job.sleep(1)
    local car = { model = c.model, config = c.config, name = c.name, value = c.value, era = c.era, prestige = c.prestige }
    takeCar(s, veh, car, true, nil, c.tracked)
    toast(strings.t('theft.bought_hot_1', c.name))
  end)
  return true, strings.t('theft.bought_hot_1', c.name)
end

-- ---- the career start: vehicle ids never survive a restart: the hot cars are rebuilt where they stood, the rest of the records go
function M.onStreetLegalStarted()
  local s = career()
  if not s then return end
  local t = store(s)
  market, session, pulling = nil, nil, nil
  for i = #t.stolen, 1, -1 do
    local r = t.stolen[i]
    r.vid, r.lastTrack, r.jammedUntil = nil, nil, nil
    if not (r.pos and r.model and r.config and core_vehicles and core_vehicles.spawnNewVehicle) then table.remove(t.stolen, i) if s.wanted and s.wanted.stolen then s.wanted = nil end end
  end
  if s.wanted and s.wanted.stolen then s.wanted.vid = nil end
end
function M.summary()
  local s = career()
  if not s then return nil end
  local t = store(s)
  local tools = {}
  for id, o in pairs(t.tools) do local def = rules.tool(id) tools[#tools + 1] = { id = id, title = def and def.title or id, uses = o.uses } end
  table.sort(tools, function(a, b) return a.id < b.id end)
  local cur = recordOf(s, playerVid())
  return { hot = M.hotCars(), tools = tools, deliveries = t.deliveries.done or 0, delivering = (sl_jobs and sl_jobs.activeJob and sl_jobs.activeJob() or {}).theft, breakingIn = session ~= nil, tracked = cur ~= nil and cur.tracked == true, fenceKnown = t.fenceKnown == true, busts = t.busts }
end
function M.status()
  local s = career()
  if not s then return 'no career' end
  local sum = M.summary()
  return string.format('hot cars %d, tools %d, deliveries %d, marks %d, tracked %s, session %s', #sum.hot, #sum.tools, sum.deliveries, #marks, tostring(sum.tracked), session and (session.d.stages[session.stage] .. ' noise ' .. string.format('%.2f', session.noise)) or 'none')
end
-- for the tester: a tool for nothing; the fence known
function M.debugTool(id) local s = career() if not s then return 'no career' end return tostring(M.giveTool(id)) end
function M.debugFence() local s = career() if not s then return 'no career' end store(s).fenceKnown = true changed() return 'known' end
function M.onStreetLegalStopped() session, pulling, market, jobTrack, lastJobsDone = nil, nil, nil, nil, nil marks, markSig, stoodSince, tried, rebuilding, rebuildAfter = {}, '', {}, {}, {}, {} end
function M.onClientEndMission() session, pulling = nil, nil marks, markSig, stoodSince = {}, '', {} end

features.gate('theft', M, nil, nil, { 'summary', 'tools', 'buyTool', 'giveTool', 'hotCars', 'current', 'sell', 'strip', 'plates', 'stripTracker', 'title', 'blackMarket', 'buyHot', 'newPlate', 'begin', 'gameResult', 'pullTracker', 'jam', 'deliveryOffer' })      -- (the part off: no prompts, nothing)

return M
