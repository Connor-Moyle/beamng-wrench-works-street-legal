-- Street Legal: the Style show (extension name: sl_show; campaign idea #9, docs/STYLE_SHOW.md). Rules in sl/core/show. On Saturday nights at one of the career's meet spots the judges score the car
-- the player drives on paint and finish, wheels, aftermarket parts, cleanliness, body and wear, against a field of rival cars; the place pays a purse and reputation. Every input is read from
-- another mod through a guarded call and a missing one drops its criterion (the weights renormalise), so this never errors where Wrench Works, Car Surface FX or Part Wear are absent.
-- Saved in the career as s.show = { history = { [week] = { place, total, prize, rep, spot, day } }, last = { .. } }. Until the calendar lists the event (kind 'show') this module has its own
-- prompt at the spot: stand on the marker for a moment, pay the entry, and the judging starts. The calendar calls begin(eventId); the result goes back through onStreetLegalShowResult.

local M = {}

local strings = require('sl/core/strings')
local rules = require('sl/core/show')
local stateLib = require('sl/core/state')
local weekly = require('sl/core/weekly')
local drawcache = require('sl/core/drawcache')

local DAMAGE_FULL = 30000                 -- BeamNG damage of a wrecked car (sl_jobs uses the same: a hard crash is about 25000)
local standFor, cool, kinds = 0, 0, nil
local last                                -- the last judging, kept for the phone: { place, total, lines, tip, top3, spot, prize, rep }

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function say(text, ttl) if ui_message then ui_message(text, ttl or 5, 'slShow') end if guihooks then guihooks.trigger('slPhoneToast', { text = text }) end end
local function store(s)
  s.show = type(s.show) == 'table' and s.show or {}
  s.show.history = type(s.show.history) == 'table' and s.show.history or {}
  return s.show
end

-- ---- the meet spots: the career's meet places in a fixed order, and where the show of a given Saturday is
local function spots()
  local list = {}
  local ok, places = pcall(function() return sl_career.getPlaces() end)
  for _, p in pairs(ok and places or {}) do if p.kind == 'meet' and p.pos then list[#list + 1] = p end end
  table.sort(list, function(a, b) return tostring(a.id) < tostring(b.id) end)
  return list
end
local function spotNames(list)
  local out = {}
  for i, p in ipairs(list) do out[i] = tostring(p.name or p.id) end
  return out
end

-- tonight's event (or nil): the rules' event for the day, with the place of its spot
function M.eventToday(s)
  s = s or career()
  if not s then return nil end
  local list = spots()
  local ev = rules.event(s.day, s.seed, spotNames(list), s.rep)
  if not ev then return nil end
  local idx = tonumber(tostring(ev.id):match('^show:(%d+):'))
  local place = idx and list[idx]
  if place then ev.pos = { x = place.pos.x, y = place.pos.y, z = place.pos.z } end
  return ev, place
end

-- ---- what the judges look at: one function per input, each guarded, each nil when its source is not there
local function playerCar()
  local v = getPlayerVehicle and getPlayerVehicle(0)
  if v and v:getJBeamFilename() ~= 'unicycle' then return v end
end
local function vehData(vid) local ok, vd = pcall(function() return core_vehicle_manager.getVehicleData(vid) end) return ok and vd or nil end

local function brandKind(id)
  if not kinds then
    kinds = {}
    local b = rawget(_G, 'slrr_brands')
    local ok, list = pcall(function() return b and b.list and b.list() end)
    for _, x in ipairs(ok and list or {}) do kinds[x.id] = x.kind end
  end
  return kinds[id]
end

-- every chosen part of the parts tree with the slot it sits in: { { slot, name } }
local function partList(tree, out, slot)
  out = out or {}
  if type(tree) ~= 'table' then return out end
  if type(tree.chosenPartName) == 'string' and tree.chosenPartName ~= '' then out[#out + 1] = { slot = tree.id or slot, name = tree.chosenPartName } end
  for key, child in pairs(tree.children or {}) do partList(child, out, key) end
  return out
end

local function sameColour(a, b)
  if type(a) ~= 'table' or type(b) ~= 'table' then return false end
  for i = 1, 3 do if math.abs((tonumber(a[i]) or 0) - (tonumber(b[i]) or 0)) > 0.03 then return false end end
  return true
end

-- the paints of the car (the game's config, then Wrench Works' when it has the car attached) and whether the first is not one of the model's factory paints
local function paintsOf(v, vd)
  local paints = vd and vd.config and vd.config.paints
  if type(paints) ~= 'table' or type(paints[1]) ~= 'table' then
    local gp = rawget(_G, 'slrr_garageParts')
    local ok, p = pcall(function() return gp and gp.getPaints and gp.getPaints() end)
    paints = ok and p or nil
  end
  if type(paints) ~= 'table' or type(paints[1]) ~= 'table' then return nil, false end
  local changed = false
  local ok, model = pcall(function() return core_vehicles.getModel(v:getJBeamFilename()) end)
  local factory = ok and model and model.model and model.model.paints
  if type(factory) == 'table' then
    changed = true
    for _, f in pairs(factory) do if sameColour(f.baseColor, paints[1].baseColor) then changed = false break end end
  end
  return paints, changed
end

local function paintCondition(vid)
  local pw = rawget(_G, 'slrr_partwear')
  local ok, c = pcall(function() return pw and pw.conditionsOf and pw.conditionsOf(vid) end)
  if not (ok and type(c) == 'table') then return nil, nil end
  local all, paint = {}, nil
  for _, p in ipairs(c.parts or {}) do
    if type(p.condition) == 'number' then
      all[#all + 1] = p.condition
      if p.kind == 'paint' then paint = p.condition end
    end
  end
  return paint, all
end

-- the inputs of the rules for the car the player drives
function M.inputs(v)
  v = v or playerCar()
  if not v then return nil end
  local vid = v:getID()
  local vd = vehData(vid)
  local inp = {}
  local paints, changed = paintsOf(v, vd)
  local paintCond, wearList = paintCondition(vid)
  if paints then inp.paint = { paints = paints, condition = paintCond or 1, changed = changed } end
  inp.wear = wearList
  -- the parts: aftermarket counts per brand, and whether the rims are of an aftermarket brand
  local brands = rawget(_G, 'slrr_brands')
  if brands and type(brands.ofPart) == 'function' and vd and vd.config and vd.config.partsTree then
    local counts, rims, cache = {}, false, {}
    for _, p in ipairs(partList(vd.config.partsTree)) do
      local id = cache[p.name]
      if id == nil then
        local ok, b = pcall(brands.ofPart, p.name, { info = {} })
        id = ok and b or false
        cache[p.name] = id
      end
      if id and brandKind(id) == 'aftermarket' then
        counts[id] = (counts[id] or 0) + 1
        local okF, fam = pcall(function() return brands.familyOf and brands.familyOf(p.name, { slotId = p.slot }) end)
        if okF and fam == 'wheels' then rims = true end
      end
    end
    inp.parts = counts
    local tread
    local ok, tyres = pcall(function() local t = rawget(_G, 'carSurfaceFx_tyres') return t and t.getTyres and t.getTyres(vid) end)
    if ok and type(tyres) == 'table' and type(tyres.wheels) == 'table' then
      local sum, n = 0, 0
      for _, w in ipairs(tyres.wheels) do if type(w.frac) == 'number' then sum, n = sum + w.frac, n + 1 end end
      if n > 0 then tread = sum / n end
    end
    inp.wheels = { aftermarket = rims, tread = tread }
  end
  local okL, level = pcall(function() return sl_surfacefx and sl_surfacefx.level and sl_surfacefx.level(vid) end)
  if okL and type(level) == 'table' then inp.clean = { dirt = level.dirt, scratches = level.scratches } end
  local okD, dmg = pcall(function() return sl_carcare and sl_carcare.damageOf and sl_carcare.damageOf(vid) end)
  if okD and type(dmg) == 'number' then inp.body = math.max(0, math.min(1, dmg / DAMAGE_FULL)) end
  return inp
end

-- ---- the judging
local function judge(s, inputs)
  local result = rules.score(inputs)
  if not result.total then return nil end
  local lines, tip = rules.lines(result)
  return { result = result, lines = lines, tip = tip }
end

-- what the judges would say now, free, with no entry: { total, lines, tip, missing } or nil (no car, nothing to judge)
function M.preview()
  local s = career()
  if not s then return nil end
  local v = playerCar()
  if not v then return nil end
  local j = judge(s, M.inputs(v))
  if not j then return nil end
  return { total = j.result.total, lines = j.lines, tip = j.tip, missing = j.result.missing }
end

local function podium(top3, place, total)
  local names = {}
  for i = 1, 3 do names[i] = top3[i] and (top3[i].you and strings.t('show.you') or top3[i].name) or nil end
  if sl_scenes and sl_scenes.play then
    local ok = pcall(sl_scenes.play, 'showpodium', { place = place, names = names, total = total })
    return ok
  end
  return false
end

-- run the show: the entry is paid, the car is judged against tonight's field, the prize and the reputation are given, the result is kept. eventId from the calendar, or nil for today's.
function M.begin(eventId)
  local s = career()
  if not s then return false end
  local ev, place = M.eventToday(s)
  if not ev then return false end
  if eventId and eventId ~= ev.id then return false end
  local st = store(s)
  if st.history[ev.week] then say(strings.t('show.already'), 4) return false end
  local v = playerCar()
  if not v then return false end
  local j = judge(s, M.inputs(v))
  if not j then say(strings.t('show.nothing_to_judge'), 5) return false end
  -- the entry: taken here, unless the player already entered on the phone (the calendar's enter() charged ev.fee and keeps the entry in s.calendar.entered, read-only here)
  local entered = type(s.calendar) == 'table' and type(s.calendar.entered) == 'table' and s.calendar.entered[ev.id]
  if not entered and not sl_career.addMoney(-rules.FEE, strings.t('show.title', ev.place)) then say(strings.t('show.no_money', rules.FEE), 5) return false end
  local tier = rules.tierOf(s.rep)
  local field = rules.field(s.seed, ev.week, tier)
  local placeNo, top3 = rules.rank(j.result.total, j.result.used, field, strings.t('show.you'))
  local money, rep = rules.prize(tier, placeNo)
  if money > 0 then sl_career.payOut(money, strings.t('show.title', ev.place)) end
  if rep > 0 then stateLib.addRep(s, rep) end
  local rec = { place = placeNo, total = j.result.total, prize = money, rep = rep, spot = ev.place, day = s.day, week = ev.week, tier = tier }
  st.history[ev.week] = rec
  st.last = rec
  last = { place = placeNo, total = j.result.total, lines = j.lines, tip = j.tip, top3 = top3, spot = ev.place, prize = money, rep = rep }
  podium(top3, placeNo, j.result.total)
  say(strings.t('show.result', placeNo <= 3 and strings.t('show.place_' .. placeNo) or strings.t('show.place_n', placeNo), j.result.total, money, rep), 8)
  if j.tip then say(strings.t('show.tip_label', j.tip), 8) end
  extensions.hook('onStreetLegalShowResult', ev.id, placeNo, last)
  extensions.hook('onStreetLegalChanged')
  return true
end

-- for the phone: the last judging and tonight's event
function M.summary()
  local s = career()
  if not s then return nil end
  local ev = M.eventToday(s)
  return { last = last, history = store(s).history, tonight = ev and { id = ev.id, place = ev.place, hour = ev.hour, fee = ev.fee } or nil }
end

-- ---- the prompt at the spot, until the calendar lists the show
local cachedKey, cachedEv, cachedPlace = nil, nil, nil       -- (the event of the day, rebuilt when the day, seed or rep changes)
local marker, markerBg = ColorF(0.9, 0.3, 0.8, 0.6), ColorI(40, 10, 40, 190)
function M.onUpdate(dtReal)
  dtReal = dtReal or 0
  local s = career()
  if not s or sl_career.LEVEL ~= 'west_coast_usa' then return end
  cool = math.max(0, cool - dtReal)
  local hour = sl_career.hour and sl_career.hour() or 0
  if not (hour >= rules.HOUR and hour <= rules.HOUR + rules.LATE_H) then standFor = 0 return end      -- (an idle frame builds nothing)
  if not (cachedKey and cachedKey.day == s.day and cachedKey.seed == s.seed and cachedKey.rep == s.rep) then
    cachedKey = { day = s.day, seed = s.seed, rep = s.rep }
    cachedEv, cachedPlace = M.eventToday(s)
  end
  local ev, place = cachedEv, cachedPlace
  if not (ev and place) then standFor = 0 return end
  if store(s).history[ev.week] then standFor = 0 return end
  if sl_career.freeToStart and sl_career.freeToStart() then standFor = 0 return end         -- (not in a chase, a job or a race)
  local v = playerCar()
  if not v then standFor = 0 return end
  local vp = v:getPosition()
  local d = math.sqrt((place.pos.x - vp.x) ^ 2 + (place.pos.y - vp.y) ^ 2 + (place.pos.z - vp.z) ^ 2)
  if d < 500 and debugDrawer then
    -- (drawn every frame: its positions and its label are built once per event, not once per frame)
    local m = drawcache.get('show:' .. tostring(ev.id) .. ':' .. tostring(ev.place), function()
      local pos = vec3(place.pos.x, place.pos.y, place.pos.z)
      return { pos = pos, top = pos + vec3(0, 0, 6), label = pos + vec3(0, 0, 7), text = String(strings.t('show.title', ev.place) .. ' - $' .. rules.FEE) }
    end)
    debugDrawer:drawCylinder(m.pos, m.top, 0.3, marker)
    debugDrawer:drawTextAdvanced(m.label, m.text, marker, true, false, markerBg)
  end
  if d < rules.START_REACH * 0.1 and cool <= 0 and v:getVelocity():length() < 1.5 then
    standFor = standFor + dtReal
    if standFor > 1.2 then standFor = 0 cool = 10 M.begin(ev.id) end
  else
    standFor = 0
  end
end

function M.status() return { last = last and last.place or nil, tonight = (career() and M.eventToday() or {}).id } end
function M.onStreetLegalStopped() last, standFor, cachedKey = nil, 0, nil end
function M.onClientEndMission() last, standFor, kinds, cachedKey = nil, 0, nil, nil end

-- (the Mods menu's Parts of the game: with this part off, the hooks above do nothing)
require('sl/core/features').gate('show', M, nil, nil, { 'begin', 'preview', 'summary', 'eventToday' })

return M
