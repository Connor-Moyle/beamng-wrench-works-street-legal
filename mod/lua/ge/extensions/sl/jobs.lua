-- Wrench Works: Street Legal: the job board (extension name: sl_jobs)
-- Jobs on the phone's Jobs app: part runs, courier parcels and more (docs: DESIGN3_jobs.md). One
-- machinery for all of them: a job is a list of legs (places to stop at in order); the clock starts
-- at the first stop, the pay is settled at the last, docked for lateness and for damage done on the
-- way. A new kind of job is one row in TYPES: what it is, when it unlocks, and how to make an offer.

local M = {}

local jobsLib = require('sl/core/jobs')
local rngLib = require('sl/core/rng')
local progression = require('sl/core/progression')
local stateLib = require('sl/core/state')

local OFFERS = 6               -- on the board at a time
local STOP_RADIUS = 9          -- metres from a stop, and slow, to count as there
local DAMAGE_FULL = 30000      -- BeamNG damage counted as a wrecked load (a hard crash is ~25000)

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) if ui_message then ui_message(text, 5, 'streetLegal') end end

-- where things are: the career's places, the parts shops (Wrench Works' sites for this level), your garage
local function context(s)
  local places, byId = {}, {}
  for id, p in pairs(sl_career.getPlaces() or {}) do
    local x = { id = id, name = p.name, kind = p.kind, x = p.pos.x, y = p.pos.y, z = p.pos.z }
    places[#places + 1], byId[id] = x, x
  end
  table.sort(places, function(a, b) return a.id < b.id end)
  local shops = {}
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier() or ''
  for _, f in ipairs(FS:findFiles('/wrench_works/sites/', '*.json', 0, false, false) or {}) do
    local d = jsonReadFile(f)
    for _, sh in ipairs(type(d) == 'table' and type(d[level]) == 'table' and d[level].shops or {}) do
      if type(sh.pos) == 'table' then
        local x = { id = 'shop:' .. tostring(sh.id), name = sh.name or sh.id, kind = 'shop', x = sh.pos[1], y = sh.pos[2], z = sh.pos[3] or 0 }
        shops[#shops + 1], byId[x.id] = x, x
      end
    end
  end
  table.sort(shops, function(a, b) return a.id < b.id end)
  return { places = places, shops = shops, garage = byId['slrrGarage' .. tostring(s.garageLevel or 1)], byId = byId }
end

local function leg(p) return { id = p.id, name = p.name, x = p.x, y = p.y, z = p.z } end

-- the kinds of job: { kind, title, unlock = rep, night = true (only after dark), offer = function(ctx, rng) -> job }
-- a job is { item, legs = { stop, stop... }, pay, seconds, fragile }
local TYPES = {
  { kind = 'part', title = 'Part run', unlock = 0, offer = function(ctx, rng)
      local list = jobsLib.offers(ctx.shops, {}, ctx.garage, rng, 1)
      local j = list[1]
      if not j then return nil end
      j.legs = { leg(ctx.byId[j.from]), leg(ctx.byId[j.to]) }
      return j
    end },
  { kind = 'courier', title = 'Courier', unlock = 0, offer = function(ctx, rng)
      local list = jobsLib.offers({}, ctx.places, nil, rng, 2)      -- (the second slot is a courier one)
      local j = list[1]
      if not j then return nil end
      j.legs = { leg(ctx.byId[j.from]), leg(ctx.byId[j.to]) }
      return j
    end },
}
M.TYPES = TYPES

local function jobsState(s)
  s.jobs = s.jobs or { offers = {}, done = 0, earned = 0 }
  return s.jobs
end

-- a fresh board each morning and each dusk
local function refresh(s, force)
  local js = jobsState(s)
  local night = progression.isNight(sl_career.hour())
  local key = s.day .. (night and 'n' or 'd')
  if js.board == key and not force then return end
  js.board = key
  local ctx = context(s)
  local rng = rngLib.new(rngLib.hash('jobs:' .. key .. ':' .. tostring(s.seed)))
  local open = {}
  for _, t in ipairs(TYPES) do
    if (s.rep or 0) >= (t.unlock or 0) and (not t.night or night) then open[#open + 1] = t end
  end
  js.offers = {}
  for i = 1, OFFERS * 2 do
    if #js.offers >= OFFERS or #open == 0 then break end
    local t = open[(i - 1) % #open + 1]
    local ok, j = pcall(t.offer, ctx, rng)
    if ok and j and j.legs and #j.legs >= 2 then
      j.id, j.kind, j.title = key .. ':' .. i, t.kind, t.title
      js.offers[#js.offers + 1] = j
    end
  end
end

local function playerCarId()
  local v = getPlayerVehicle(0)
  local car = v and sl_fleet and sl_fleet.carOfVehicle and sl_fleet.carOfVehicle(v:getID())
  return car and v or nil
end

local function routeTo(stop)
  if core_groundMarkers and stop then core_groundMarkers.setPath(vec3(stop.x, stop.y, stop.z or 0)) end
end

function M.take(jobId)
  local s = career()
  if not s then return false, 'No career running.' end
  local js = jobsState(s)
  if js.active then return false, 'Finish the job you are on first.' end
  if sl_streets and sl_streets.isRacing and sl_streets.isRacing() then return false, 'Not in the middle of a race.' end
  if not playerCarId() then return false, 'You need to be in one of your cars.' end
  for i, j in ipairs(js.offers) do
    if j.id == jobId then
      table.remove(js.offers, i)
      j.leg = 1
      js.active = j
      routeTo(j.legs[1])
      extensions.hook('onStreetLegalChanged')
      return true, string.format('%s: go to %s.', j.title, j.legs[1].name)
    end
  end
  return false, 'That job has gone.'
end

function M.giveUp()
  local s = career()
  local js = s and jobsState(s)
  if not js or not js.active then return false, 'You are not on a job.' end
  js.active = nil
  stateLib.addRep(s, -5)
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  extensions.hook('onStreetLegalChanged')
  return true, 'Job dropped. Word gets round: -5 reputation.'
end

local function finish(s, js, j, v)
  local elapsed = j.startedAt and (os.clock() - j.startedAt) or 0
  local d0, d1 = j.damage0 or 0, sl_carcare and sl_carcare.damageOf and sl_carcare.damageOf(v:getID()) or 0
  local damage = math.max(0, math.min(1, ((d1 or 0) - d0) / DAMAGE_FULL))
  local pay, verdict = jobsLib.settle(j, elapsed, damage)
  js.active = nil
  if core_groundMarkers then core_groundMarkers.setPath(nil) end
  if pay > 0 then sl_career.addMoney(pay, j.title .. ': ' .. (j.item or 'delivery')) end
  stateLib.addRep(s, verdict == 'broken' and -5 or (verdict == 'late' and 2 or 6))
  js.done, js.earned = js.done + 1, js.earned + pay
  toast(verdict == 'broken' and string.format('The %s is broken. No pay.', j.item or 'load')
    or string.format('%s delivered%s. $%d.', j.item or 'Delivery', verdict == 'late' and ', late' or '', pay))
  extensions.hook('onStreetLegalChanged')
end

local timer = 0
function M.onUpdate(dtReal)
  local s = career()
  if not s then return end
  timer = timer + dtReal
  if timer < 0.5 then return end
  timer = 0
  refresh(s)
  local js = jobsState(s)
  local j = js.active
  if not j then return end
  local v = playerCarId()
  if not v then return end
  local stop = j.legs[j.leg]
  local here = v:getPosition()
  if (here - vec3(stop.x, stop.y, stop.z or here.z)):length() < STOP_RADIUS and v:getVelocity():length() < 2 then
    if j.leg == 1 then
      j.startedAt = os.clock()
      j.damage0 = sl_carcare and sl_carcare.damageOf and sl_carcare.damageOf(v:getID()) or 0
      toast(string.format('Picked up the %s%s. %d:%02d to %s.', j.item or 'load', j.fragile and ' (fragile)' or '', math.floor(j.seconds / 60), j.seconds % 60, j.legs[2].name))
    end
    if j.leg >= #j.legs then finish(s, js, j, v) return end
    j.leg = j.leg + 1
    routeTo(j.legs[j.leg])
    extensions.hook('onStreetLegalChanged')
  end
end

-- for the phone
function M.summary()
  local s = career()
  if not s then return nil end
  refresh(s)
  local js = jobsState(s)
  local out = { offers = {}, done = js.done, earned = js.earned }
  for _, j in ipairs(js.offers) do
    out.offers[#out.offers + 1] = { id = j.id, title = j.title, item = j.item, from = j.legs[1].name, to = j.legs[#j.legs].name,
      pay = j.pay, seconds = j.seconds, fragile = j.fragile, metres = j.metres }
  end
  local a = js.active
  if a then
    out.active = { title = a.title, item = a.item, next = a.legs[a.leg].name, to = a.legs[#a.legs].name, pay = a.pay, fragile = a.fragile,
      timeLeft = a.startedAt and math.floor(a.seconds - (os.clock() - a.startedAt)) or nil }
  end
  return out
end

function M.showWay()
  local s = career()
  local a = s and jobsState(s).active
  if a then routeTo(a.legs[a.leg]) end
end

function M.onStreetLegalStopped() if core_groundMarkers then core_groundMarkers.setPath(nil) end end

return M
