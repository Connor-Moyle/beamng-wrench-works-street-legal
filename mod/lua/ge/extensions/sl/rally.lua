-- Street Legal: rally stages on West Coast USA (extension name: sl_rally; #24)
-- The level has none of the game's own rally stages (no notebooks), so these run here: four dirt and gravel roads (mod/street_legal/rally/west_coast_usa.json),
-- day events with a class rule (a rally class car: 300 PS at most, 900 kg at least). Stop on a stage's start marker for a moment and pay the entry
-- fee: a countdown, then the clock; the pacenotes (sl/core/rally, from the road's curvature) are shown a few seconds ahead of each corner; leave the road for
-- too long and you are out. The finish pays by time against the par (once a day per stage), best times are kept in the save.

local M = {}

local strings = require('sl/core/strings')

local rules = require('sl/core/rally')
local splitphase = require('sl/core/splitphase')
local stateLib = require('sl/core/state')
local racelog = require('sl/racelog')

local stages            -- { { id, name, points, width, length, notes, par } }, loaded once per level
local run               -- the stage being run: { stage, i, t, state, vid, calledAt, off }
local standFor, cool = 0, 0

local COUNTDOWN = 3
local OFF_ROAD = 30         -- m from the line where you are off the stage (the road is wider than its line)
local OFF_LIMIT = 15        -- s off the stage and you are out

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function say(text, ttl) if ui_message then ui_message(text, ttl or 4, 'slRally') end guihooks.trigger('slPhoneToast', { text = text }) end

local function load()
  if stages then return stages end
  stages = {}
  local data = jsonReadFile('/street_legal/rally/' .. tostring(sl_career.LEVEL) .. '.json')
  for _, st in ipairs(type(data) == 'table' and data.stages or {}) do
    if type(st.points) == 'table' and #st.points > 10 then
      st.notes = rules.pacenotes(st.points)
      st.par = rules.parTime(st.length or 600)
      st.cum = rules.cumulative(st.points)
      stages[#stages + 1] = st
    end
  end
  return stages
end

local function playerCar()
  local v = getPlayerVehicle(0)
  if v and v:getJBeamFilename() ~= 'unicycle' then return v end
end

local function bests(s) s.rallyBest = s.rallyBest or {} return s.rallyBest end

-- the car's numbers for the class rule, from the game's own config data
local function carNumbers(v)
  local ok, details = pcall(core_vehicles.getVehicleDetails, v:getID())
  local cfg = ok and details and details.configs
  return { power = cfg and cfg.Power, weight = cfg and cfg.Weight }
end

-- The game's own codriver (A9): gameplay_rally reads the stage's folder (tools/make_rally_stages.py: race, driveline, structured notebook) and calls the corners
-- with a shared voicepack, from the car's place on the line. Without it (not loaded, a mission owns it) the text calls below stay the only ones.
local VOICEPACK = { type = 'voicepack', id = 'global:ak_2026-06-15', scope = 'global', dirname = 'ak_2026-06-15' }
M.CODRIVER = true
local function codriverOn(stage)
  if not M.CODRIVER then return false end
  local ok, err = pcall(function()
    pcall(extensions.load, 'gameplay_rally')
    if not gameplay_rally then error('gameplay_rally is not loaded') end
    local loaded, why = gameplay_rally.loadMission(tostring(sl_career.LEVEL) .. '/rallyStage/sl_' .. stage.id, '/street_legal/rally/stages/' .. stage.id, nil, VOICEPACK, { owner = 'external' })
    if not loaded then error(tostring(why)) end
  end)
  racelog.add('rally', 'codriver', { stage = stage.id, ok = ok and 'yes' or 'no', why = ok and '' or tostring(err) })
  return ok
end
local function codriverOff()
  pcall(function() if gameplay_rally and gameplay_rally.unloadMission then gameplay_rally.unloadMission({ owner = 'external' }) end end)
end

local function finish(ok, why)
  local r = run
  run = nil
  codriverOff()
  cool = 8                       -- (a loop ends where it began: no new start at once)
  if not r then return end
  local v = getObjectByID(r.vid)
  if v then v:queueLuaCommand('controller.setFreeze(0)') end
  local s = career()
  if not s then return end
  if not ok then say(why or strings.t('rally.stage_abandoned'), 5) return end
  local t = r.t
  local best = bests(s)
  local newBest = not best[r.stage.id] or t < best[r.stage.id]
  if newBest then best[r.stage.id] = t end
  s.rallyPaid = s.rallyPaid or {}
  local paidToday = s.rallyPaid[r.stage.id] == s.day
  local prize = paidToday and 0 or rules.prize(r.stage.par, t)
  if prize > 0 then
    sl_career.payOut(prize, strings.t('rally.rally_1', (r.stage.name)))
    s.rallyPaid[r.stage.id] = s.day
    stateLib.addRep(s, 8)
  end
  say(string.format(strings.t('rally.s_d_04_1f_par'), r.stage.name, math.floor(t / 60), t % 60, math.floor(r.stage.par / 60), r.stage.par % 60,
    newBest and strings.t('rally.your_best') or '', prize > 0 and string.format(strings.t('rally.d_and_8_reputation'), prize) or strings.t('rally.a_practice_run_it_pays')), 8)
  if slrrPedestrians and slrrPedestrians.cheer then slrrPedestrians.cheer(4) end
  extensions.hook('onStreetLegalChanged')
end

local function begin(stage, v)
  local ok, why = rules.classOk(carNumbers(v))
  if not ok then say(why, 6) return end
  if not sl_career.addMoney(-rules.ENTRY_FEE, strings.t('rally.rally_entry_1', (stage.name))) then say(string.format(strings.t('rally.the_entry_is_d'), rules.ENTRY_FEE), 5) return end
  run = { stage = stage, i = 1, t = 0, state = 'countdown', vid = v:getID(), calledAt = 0, off = 0, count = COUNTDOWN }
  run.codriver = codriverOn(stage)
  v:queueLuaCommand('controller.setFreeze(1)')
  say(string.format(strings.t('rally.s_d_m_d_calls'), stage.name, stage.length or 0, #stage.notes, rules.ENTRY_FEE), 5)
end

local marker, markerBg = ColorF(1, 0.55, 0.1, 0.6), ColorI(40, 20, 0, 190)
local function drawStart(stage, v)
  local p = stage.points[1]
  local pos = vec3(p[1], p[2], p[3])
  if (pos - v:getPosition()):length() > 500 then return end
  debugDrawer:drawCylinder(pos, pos + vec3(0, 0, 6), 0.3, marker)
  debugDrawer:drawTextAdvanced(pos + vec3(0, 0, 7), String(string.format(strings.t('rally.rally_s_d_m_d'), stage.name, stage.length or 0, rules.ENTRY_FEE)), marker, true, false, markerBg)
end

local function running(dt)
  local r = run
  local v = getObjectByID(r.vid)
  local me = getPlayerVehicle(0)
  if not v or not me or me:getID() ~= r.vid then return finish(false, strings.t('rally.stage_abandoned_out_of_the')) end
  if r.state == 'countdown' then
    r.count = r.count - dt
    local shown = math.ceil(r.count)
    if r.count > 0 then
      if shown ~= r.shown then r.shown = shown say(tostring(shown), 1) end
      return
    end
    r.state = 'running'
    v:queueLuaCommand('controller.setFreeze(0)')
    say('GO!', 2)
    return
  end
  r.t = r.t + dt
  local pos = v:getPosition()
  local pts = r.stage.points
  local i, d = rules.progress(pts, pos.x, pos.y, r.i, 25)
  if i > r.i then r.i = i end
  if d > OFF_ROAD then
    r.off = r.off + dt
    if math.floor(r.off) ~= r.offShown then r.offShown = math.floor(r.off) say(string.format(strings.t('rally.off_the_stage_back_on'), math.max(0, OFF_LIMIT - math.floor(r.off))), 1.5) end
    if r.off >= OFF_LIMIT then return finish(false, strings.t('rally.out_of_the_stage')) end
  else
    r.off, r.offShown = 0, nil
  end
  -- the pacenotes, a few seconds ahead of the corner
  local along = r.stage.cum[r.i] or 0
  local speed = v:getVelocity():length()
  local note, idx = rules.nextCall(r.stage.notes, along, math.max(60, speed * 6))
  if note and idx ~= r.calledAt then
    r.calledAt = idx
    if not r.codriver then say(note.text .. (note.dist and (' - ' .. note.dist .. ' m') or ''), 3) end
  end
  if r.i >= #pts - 1 and d < 25 then finish(true) end
end

function M.onUpdate(dtReal)
  dtReal = dtReal or 0
  local s = career()
  if not s or sl_career.LEVEL ~= 'west_coast_usa' then run = nil return end
  if run then return running(dtReal) end
  cool = math.max(0, cool - dtReal)
  if not splitphase.available('races', 'rally', sl_career.phase()) then return end           -- a day event
  local v = playerCar()
  if not v then standFor = 0 return end
  local list = load()
  local near
  for _, st in ipairs(list) do
    drawStart(st, v)
    local p = st.points[1]
    if (vec3(p[1], p[2], p[3]) - v:getPosition()):length() < 8 then near = st end
  end
  if near and cool <= 0 and v:getVelocity():length() < 1.5 then
    standFor = standFor + dtReal
    if standFor > 1.2 then standFor = 0 begin(near, v) end
  else
    standFor = 0
  end
end

function M.status() return { stages = stages and #stages or 0, running = run and run.stage.name or nil, t = run and run.t or nil } end
function M.onStreetLegalStopped() if run then finish(false) end run = nil end
function M.onClientEndMission() stages, run = nil, nil end

return M
