-- Street Legal: car theft (extension name: sl_theft; the Car theft part, OFF by default: Mods > Street Legal > Parts of the game > Car theft).
-- Rules in sl/core/theft (Graph docs/CAR_THEFT.md). On foot near a fair-game car (the game's parked cars, a traffic car that stopped and emptied)
-- the walk-up prompt offers a break-in: the era from the car's years decides the stages (the lock and the wires; the bypass box first on a mid car;
-- the fob on a modern one) and the tool it needs. The stages are 9e's screens (docs/THEFT_CONTRACT.md: guihooks 'slTheftGame' in,
-- sl_theft.gameResult out); with the Developer switch "Theft screens: autoplay" the stages resolve by a roll after their time, for the tester.
-- Noise draws witnesses and the alarm (heat, a patrol); a stolen car is a hot record, wanted (sl_justice) once reported, impounded on a bust,
-- sold, stripped, plated or titled at the fence (19's shop calls the functions at the end). The save: s.theft = { tools, stolen, deliveries, tried }.

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
  t.tools, t.stolen, t.deliveries = t.tools or {}, t.stolen or {}, t.deliveries or { done = 0 }
  return t
end
local function onFoot() local v = getPlayerVehicle(0) return v ~= nil and v:getJBeamFilename() == 'unicycle' end
local function playerVid() local v = getPlayerVehicle(0) return v and v:getID() or nil end

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
  if sl_fleet and sl_fleet.carOfVehicle and sl_fleet.carOfVehicle(vid) then return false end
  for _, r in ipairs(store(s).stolen) do if r.vid == vid then return false end end
  local t = gameplay_traffic and gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData()[vid]
  if t and t.role and t.role.name == 'police' then return false end
  if sl_lot and sl_lot.owns and sl_lot.owns(vid) then return false end
  if sl_streets and sl_streets.isMeetCar and sl_streets.isMeetCar(vid) then return false end
  return true
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
    if o and (o:getPosition() - p):length() <= rules.REACH_M and fairGame(vid, s) then out[#out + 1] = { vid = vid, kind = kind, pos = o:getPosition() } end
  end
  return out
end

-- ---- the prompt
local marks, markSig = {}, ''
function M.onGetRawPoiListForLevel(level, elements)
  local s = career()
  if not s or level ~= sl_career.LEVEL then return end
  for _, m in ipairs(marks) do
    local pos = vec3(m.pos.x, m.pos.y, m.pos.z)
    elements[#elements + 1] = {
      id = 'slTheft:' .. m.vid, data = { type = 'other', id = 'slTheft:' .. m.vid, theftVid = m.vid, name = strings.t('theft.break_in'), date = 0 }, clusterType = 'missionMarker',
      clusterInBigMap = false, clusterInPlayMode = false, interactableInPlayMode = true, quickTravelAvailable = false,
      markerInfo = { missionMarker = { pos = pos, rot = quat(0, 0, 0, 1), icon = 'mission_arrival_triangle' } },
    }
  end
end
local session = nil        -- the break-in in progress: { vid, car, d, stage, noise, t0, witnessAt, tool }
function M.onActivityAcceptGatherData(elemData, activityData)
  local s = career()
  if not s or session then return end
  for _, elem in ipairs(elemData or {}) do
    local vid = tonumber(elem.theftVid)
    if vid then
      local car = describe(vid)
      if car then
        local tool = rules.toolFor(car.era, store(s).tools)
        local need = rules.needs(car.era)
        local label = strings.t('theft.break_in_1_2', car.name, strings.t('theft.era_' .. car.era))
        if need and not tool then label = strings.t('theft.needs_1', rules.tool(need[1]).title) end
        table.insert(activityData, {
          icon = 'poi_arrival_round', heading = car.name, preheadings = { strings.t('theft.break_in') },
          sorting = { type = 'slTheft', id = vid },
          buttonLabel = label,
          buttonFun = function() local ok, text = M.begin(vid) if text then toast(text) end end,
          buttonSoundClass = 'bng_hover_generic',
        })
      end
    end
  end
end

-- ---- the alarm, the witnesses, the heat
local function raiseHeat(s, amount)
  s.heat = heatLib.raised(s.heat or 0, amount or heatLib.BUST)
  extensions.hook('onStreetLegalChanged')
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

-- ---- the break-in
local function endSession() session = nil end
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
  if not tool and t.tools.slimjim then tool = 'slimjim' end
  local retry = t.tried and t.tried[tostring(vid)] and (os.clock() - t.tried[tostring(vid)]) < rules.RETRY_S
  session = { vid = vid, car = car, d = rules.difficulty(car.era, car.value, car.prestige, retry), stage = 1, noise = 0, t0 = os.clock(), tool = tool }
  startStage()
  return true, nil
end
-- the stolen car: the player in it, the record, the hot car's wanted state when reported
local function steal(s)
  local st = session
  local t = store(s)
  local o = getObjectByID(st.vid)
  if not o then endSession() return end
  pcall(function() o.playerUsable = true end)
  pcall(function() gameplay_parking.removeVehicle(st.vid) end)
  pcall(function() gameplay_traffic.removeTraffic(st.vid) end)
  local reported = st.witnessed == true or st.noise >= 1
  local rec = rules.stolenRecord(st.car, st.car.era, s.day, reported)
  rec.vid = st.vid
  t.stolen[#t.stolen + 1] = rec
  if st.tool and rules.tool(st.tool).uses then rules.useTool(t.tools, st.tool) end
  if reported then M.wantIt(s, rec) end
  pcall(function() if gameplay_walk and gameplay_walk.getInVehicle then gameplay_walk.getInVehicle(o) else be:enterVehicle(0, o) end end)
  say(strings.t('theft.yours_for_now_1', st.car.name), 6)
  endSession()
  extensions.hook('onStreetLegalChanged')
end
-- the wanted record of a hot car (sl_justice recognises the vehicle by its id)
function M.wantIt(s, rec)
  if s.wanted or not rec.vid then return end
  s.wanted = { vid = rec.vid, name = rec.name, model = rec.model, day = s.day, level = 4, bounty = chaseLib.bounty(4), stolen = true }
  rec.reported = true
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
    t.tried = t.tried or {}
    t.tried[tostring(st.vid)] = os.clock()
    if st.tool and rules.tool(st.tool).uses and st.car.era == 'modern' then rules.useTool(t.tools, st.tool) end
    alarm(s, st.vid)
    endSession()
    toast(strings.t('theft.failed'))
    return
  end
  if rules.alarm(st.noise) then alarm(s, st.vid) end
  if st.stage >= #st.d.stages then steal(s) else st.stage = st.stage + 1 startStage() end
end
function M.cancel() if session then local s = career() if s then store(s).tried = store(s).tried or {} store(s).tried[tostring(session.vid)] = os.clock() end endSession() toast(strings.t('theft.failed')) end end

-- ---- the tick: the prompts on foot, the witness clock, a day's end for cars left behind
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
        raiseHeat(s, heatLib.BUST)
      end
    end
    return
  end
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
  if tickT < (session and 0.5 or 3) then return end
  tickT = 0
  local ok, err = pcall(tick)
  if not ok then log('E', 'sl_theft', tostring(err)) end
end

-- a bust in a hot car: the car is gone to the impound, not yours to pay for
function M.onPursuitAction(id, action)
  local s = career()
  if not s or action ~= 'arrest' or id ~= playerVid() then return end
  local t = store(s)
  for i = #t.stolen, 1, -1 do
    local r = t.stolen[i]
    if r.vid == id then
      table.remove(t.stolen, i)
      if s.wanted and s.wanted.vid == id then s.wanted = nil end
      local vid = id
      core_jobsystem.create(function(job)
        if gameplay_walk then gameplay_walk.setWalkingMode(true, nil, nil, true) end
        job.sleep(1)
        local v = getObjectByID(vid)
        if v then v:delete() end
      end)
      say(strings.t('theft.busted_in_it_1', r.name), 8)
      extensions.hook('onStreetLegalChanged')
      return
    end
  end
end
-- a new day: a hot car left somewhere is found and gone; an unreported one is reported
function M.onStreetLegalNewDay(day)
  local s = career()
  if not s then return end
  local t = store(s)
  local me = playerVid()
  for i = #t.stolen, 1, -1 do
    local r = t.stolen[i]
    if r.vid ~= me and not r.plated then
      local v = r.vid and getObjectByID(r.vid)
      if v then pcall(v.delete, v) end
      table.remove(t.stolen, i)
      if s.wanted and s.wanted.vid == r.vid then s.wanted = nil end
      sl_career.sendText('benny', strings.t('theft.benny_gone_1', r.name), 2)
    elseif not r.reported and rules.reportedBy(r, day or s.day) then
      M.wantIt(s, r)
      sl_career.sendText('benny', strings.t('theft.benny_reported_1', r.name), 2)
    end
  end
end

-- ---- the fence (19's shop calls these; docs/THEFT_CONTRACT.md): the tools, the hot cars, sell, strip, plates, title
function M.tools()
  local s = career()
  local owned = s and store(s).tools or {}
  local out = {}
  for _, t in ipairs(rules.TOOLS) do out[#out + 1] = { id = t.id, title = t.title, price = t.price, uses = t.uses, era = t.era, have = owned[t.id] ~= nil, usesLeft = owned[t.id] and owned[t.id].uses or nil } end
  return out
end
function M.buyTool(id)          -- (the shop has taken the money)
  local s = career()
  local t = s and rules.tool(id)
  if not t then return false, strings.t('theft.no_such_tool') end
  store(s).tools[id] = { uses = t.uses }
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('theft.tool_bought_1', t.title)
end
local function hotAt(s, i) local t = store(s) return t.stolen[tonumber(i) or 0] end
function M.hotCars()
  local s = career()
  if not s then return {} end
  local out = {}
  for i, r in ipairs(store(s).stolen) do
    out[#out + 1] = { index = i, name = r.name, model = r.model, era = r.era, value = r.value, plated = r.plated, wanted = s.wanted ~= nil and s.wanted.vid == r.vid, driving = r.vid == playerVid(),
      sell = rules.sellPrice(r), strip = rules.stripPay(r), plates = rules.platesPrice(r), title = rules.titlePrice(r) }
  end
  return out
end
local function gone(s, i, deleteCar)
  local t = store(s)
  local r = table.remove(t.stolen, i)
  if r and s.wanted and s.wanted.vid == r.vid then s.wanted = nil end
  if r and deleteCar and r.vid then
    local vid = r.vid
    core_jobsystem.create(function(job)
      if playerVid() == vid and gameplay_walk then gameplay_walk.setWalkingMode(true, nil, nil, true) end
      job.sleep(1)
      local v = getObjectByID(vid)
      if v then v:delete() end
    end)
  end
  return r
end
function M.sell(i)
  local s = career()
  local r = s and hotAt(s, i)
  if not r then return false, strings.t('theft.no_such_car') end
  local pay = rules.sellPrice(r)
  gone(s, tonumber(i), true)
  sl_career.payOut(pay, strings.t('theft.fence'))
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('theft.sold_1_2', r.name, pay)
end
function M.strip(i)
  local s = career()
  local r = s and hotAt(s, i)
  if not r then return false, strings.t('theft.no_such_car') end
  local pay = rules.stripPay(r)
  gone(s, tonumber(i), true)
  sl_career.payOut(pay, strings.t('theft.chop_shop'))
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('theft.stripped_1_2', r.name, pay)
end
function M.plates(i)
  local s = career()
  local r = s and hotAt(s, i)
  if not r then return false, strings.t('theft.no_such_car') end
  if r.plated then return false, strings.t('theft.already_plated') end
  local price = rules.platesPrice(r)
  if not sl_career.addMoney(-price, strings.t('theft.plates')) then return false, strings.t('carcare.it_is_d_you_have', price, s.money) end
  r.plated = true
  if s.wanted and s.wanted.vid == r.vid then s.wanted = nil end
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('theft.plated_1', r.name)
end
function M.title(i)
  local s = career()
  local r = s and hotAt(s, i)
  if not r then return false, strings.t('theft.no_such_car') end
  if not r.plated then return false, strings.t('theft.plates_first') end
  local price = rules.titlePrice(r)
  if not sl_career.addMoney(-price, strings.t('theft.title')) then return false, strings.t('carcare.it_is_d_you_have', price, s.money) end
  local car = rules.titled(r)
  local vid = r.vid
  gone(s, tonumber(i), false)
  if vid and getObjectByID(vid) and sl_fleet and sl_fleet.registerVehicle then pcall(sl_fleet.registerVehicle, vid, { name = car.name, condition = car.condition, value = car.value }) end
  extensions.hook('onStreetLegalChanged')
  return true, strings.t('theft.titled_1', car.name)
end

function M.summary()
  local s = career()
  if not s then return nil end
  local t = store(s)
  local tools = {}
  for id, o in pairs(t.tools) do local def = rules.tool(id) tools[#tools + 1] = { id = id, title = def and def.title or id, uses = o.uses } end
  return { hot = M.hotCars(), tools = tools, deliveries = t.deliveries.done or 0, breakingIn = session ~= nil }
end
function M.status()
  local s = career()
  if not s then return 'no career' end
  local sum = M.summary()
  return string.format('hot cars %d, tools %d, deliveries %d, marks %d, session %s', #sum.hot, #sum.tools, sum.deliveries, #marks, session and (session.d.stages[session.stage] .. ' noise ' .. string.format('%.2f', session.noise)) or 'none')
end
-- for the tester: a tool for nothing
function M.debugTool(id) local s = career() if not s then return 'no career' end return tostring(M.buyTool(id)) end
function M.onStreetLegalStopped() session = nil marks, markSig, stoodSince = {}, '', {} end
function M.onClientEndMission() session = nil marks, markSig, stoodSince = {}, '', {} end

features.gate('theft', M, nil, nil, { 'summary', 'tools', 'buyTool', 'hotCars', 'sell', 'strip', 'plates', 'title', 'begin', 'gameResult' })      -- (the part off: no prompts, nothing)

return M
