-- Street Legal: the brand invitationals (extension name: sl_invite; the part: Mods > Street Legal > Parts of the game > Brand invitationals; docs/DESIGN_SPONSORSHIPS.md section 5).
-- Rules in sl/core/invite. A brand you are close to texts an invitation (at most three in a career); it is an event of the calendar (kind 'invite') at the dockyards. When the player is at the
-- grid at the hour, the brand's race car is spawned, the player gets in, and sl_gridrace runs the race; the reward is money, reputation and standing with the brand. Save: s.invite = { given, last, list }.

local M = {}

local rules = require('sl/core/invite')
local strings = require('sl/core/strings')
local features = require('sl/core/features')
local stateLib = require('sl/core/state')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function store(s) s.invite = type(s.invite) == 'table' and s.invite or {} s.invite.given, s.invite.list = s.invite.given or 0, s.invite.list or {} return s.invite end
local function homeOn() return sl_career.LEVEL == 'west_coast_usa' end
local function api() return rawget(_G, 'slrr_brands') end
local function opt(key, default) local v = sl_options and sl_options.get and tonumber((sl_options.get(key))) return v or default end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end
local function nameOf(brand) return sl_sponsor and sl_sponsor.nameOf and sl_sponsor.nameOf(brand) or tostring(brand) end

-- the invitations as calendar events (the calendar asks every time it builds the schedule)
function M.events()
  local s = career()
  if not s then return nil end
  local out = {}
  for _, inv in ipairs(store(s).list) do out[#out + 1] = rules.event(inv, strings.t('invite.title', nameOf(inv.brand)), rules.PLACE) end
  return out
end

-- a new day: maybe an invitation
function M.onStreetLegalNewDay(day)
  local s = career()
  if not s or not homeOn() or not (sl_sponsor and sl_sponsor.active and sl_sponsor.active()) then return end
  local st = store(s)
  local pending = false
  for _, inv in ipairs(st.list) do if inv.day >= day then pending = true end end
  local brand = rules.pickBrand(sl_sponsor.standing(), s.sponsorship, day, sl_sponsor.kindOf, opt('slInviteStanding', rules.STANDING_MIN))
  -- standing = 999: pickBrand already applied the standing and sponsor rules
  if not rules.eligible({ count = st.given, pending = pending, last = st.last, day = day, brand = brand, standing = 999, max = opt('slInviteMax', rules.MAX), gap = opt('slInviteGap', rules.GAP) }) then return end
  local b = api()
  local car = rules.loaner(brand, b and b.ofCar)
  local inv = rules.new(st.given, brand, day, { model = car.model, config = car.config })
  st.given, st.last = st.given + 1, day
  st.list[#st.list + 1] = inv
  while #st.list > math.max(rules.MAX, opt('slInviteMax', rules.MAX)) do table.remove(st.list, 1) end
  sl_career.sendText('benny', strings.t('invite.text', nameOf(brand), car.model, rules.PLACE, inv.day), 3)
  extensions.hook('onStreetLegalChanged')
end

-- ---- the race: called by the calendar when the player is at the grid at the hour
local running
local function seat(v) pcall(function() if gameplay_walk and gameplay_walk.getInVehicle then gameplay_walk.getInVehicle(v) else be:enterVehicle(0, v) end end) end
local function leave(c, res)
  running = nil
  local s = career()
  -- the player back in their own car first, then the lent one goes (deleting the car the player sits in lets the game pick any vehicle); no car of theirs left: the lent one stays
  local prev = c.prev and getObjectByID(c.prev)
  if prev then seat(prev) end
  if c.loaner and prev then local v = getObjectByID(c.loaner) if v then pcall(v.delete, v) end end
  local ok, err = pcall(function()
    if not s then return end
    local r = res.aborted and rules.reward(nil) or rules.reward(res.place, opt('slInvitePurse', 100) / 100)
    local pts = r.standing
    if c.dented and pts > 0 then pts = math.floor(pts / 2) toast(strings.t('invite.dented')) end
    if r.money > 0 then sl_career.payOut(r.money, strings.t('invite.title', nameOf(c.brand))) end
    if r.rep > 0 then stateLib.addRep(s, r.rep) end
    if pts > 0 and sl_sponsor and sl_sponsor.credit then sl_sponsor.credit(c.brand, pts) end
    if r.trophy then
      local st = store(s)
      st.trophies = (st.trophies or 0) + 1
      s.trophies = require('sl/core/trophies').add(s.trophies, strings.t('invite.title', nameOf(c.brand)), 'invite', s.day, 1)
    end
    -- an aborted or failed race closes the event too: left entered, the calendar would start it again every two seconds for the next hour and a half
    if sl_calendar and sl_calendar.complete then sl_calendar.complete(c.event.id, res.place, r.money) end
    if not res.aborted then
      toast(strings.t('invite.result', nameOf(c.brand), res.place and require('sl/core/gridrace').placeWord(res.place) or 'DNF', r.money, r.rep, pts) .. (r.trophy and (' ' .. strings.t('invite.trophy')) or ''))
    end
  end)
  if not ok then log('E', 'sl_invite', 'the invitational reward failed: ' .. tostring(err)) end
  if c.done then pcall(c.done, res) end          -- (always: the calendar's running flag is cleared here)
end

-- the damage of the loaner when the race ends: map.objects[id].damage is the game's own damage number
local function dentedNow(id)
  local ok, d = pcall(function() return map.objects[id].damage end)
  return ok and (tonumber(d) or 0) > 1000
end

function M.start(ev, done)
  if running or not career() then return false end
  local inv
  for _, i in ipairs(store(career()).list) do if i.id == ev.id then inv = i end end
  local pv = getPlayerVehicle(0)
  if not (inv and inv.car and pv) then return false end
  local c = { event = ev, brand = inv.brand, prev = pv:getID(), done = done }
  running = c
  core_jobsystem.create(function(job)
    local ok, err = pcall(function()
      local builder = require('sl/carBuilder')
      -- (a config the game version lacks: spawnOwned logs a W and builds the stock default)
      local rec = { model = inv.car.model, config = inv.car.config, pcPath = 'vehicles/' .. inv.car.model .. '/' .. inv.car.config .. '.pc', name = nameOf(inv.brand) }
      local veh = builder.spawnOwned(job, rec, pv:getPosition() + pv:getDirectionVector():cross(vec3(0, 0, 1)):normalized() * 5 + vec3(0, 0, 1), pv:getRotation())          -- (beside the player's car, not on it)
      if not veh then error(strings.t('invite.no_car')) end
      c.loaner = veh:getID()
      if gameplay_walk and gameplay_walk.getInVehicle then gameplay_walk.getInVehicle(veh) else be:enterVehicle(0, veh) end
      local seated = false
      for _ = 1, 20 do          -- the seat swap takes a few frames: the race must bind to the lent car, or the swap would abort it
        job.sleep(0.1)
        local now = getPlayerVehicle(0)
        if now and now:getID() == c.loaner then seated = true break end
      end
      if not seated then error('the player did not get into the lent car') end
      local started = sl_gridrace.start({ layer = ev.layer, name = ev.title, laps = ev.laps or rules.LAPS }, function(res)
        c.dented = dentedNow(c.loaner)
        leave(c, res)
      end)
      if not started then error('the grid race would not start') end
    end)
    if not ok then
      log('E', 'sl_invite', tostring(err))
      toast(strings.t('invite.no_car'))
      leave(c, { aborted = true })
    end
  end)
  return true
end

function M.onStreetLegalStopped() running = nil end
function M.onClientEndMission() running = nil end

function M.status()
  local s = career()
  if not s then return 'no career' end
  local st = store(s)
  local out = { string.format('%d invitation(s) given, %d trophies', st.given, st.trophies or 0) }
  for _, inv in ipairs(st.list) do out[#out + 1] = string.format('%s %s day %d layer %s car %s/%s', inv.id, inv.brand, inv.day, inv.layer, inv.car and inv.car.model, inv.car and inv.car.config) end
  return table.concat(out, '\n')
end

features.gate('invites', M, nil, nil, { 'events', 'start' })

return M
