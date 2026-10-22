-- Street Legal: the calendar's rules (docs/DESIGN_CAREER_TRAVEL.md section 4). Pure, no game calls: tested by tools/luatest.js.
-- The schedule is built from the career day, the seed and the reputation; nothing is stored except what the player entered, declined, asked
-- to be reminded of, and what was done or missed (the store, in the save as s.calendar). Event ids are stable: kind:slot:cycle.
-- Weekend home races: days 6 and 7 of the week (the weekly ledger's week), one of the six dockyards layouts each, a grid race against a field
-- of the player's class (sl_gridrace). The monthly series (28 days, one at a time) are listed with their rounds; entering and travel come with T3.

local M = {}

local strings = require('sl/core/strings')
local weekly = require('sl/core/weekly')

M.WEEKEND = { [6] = true, [7] = true }
M.HOME_HOUR = 15                    -- the weekend race starts at three in the afternoon
M.HOME_LAPS = 3
M.AHEAD = 14                        -- days listed ahead
M.KEEP = 7                          -- days a done or missed event stays
M.START_REACH = 80                  -- metres from the grid to be on time
M.LATE_H = 1.5                      -- hours after the start the race may still begin; after that it is missed
M.SERIES_DAYS = 28
M.SERIES_FIRST = 15                 -- a series starts on the 15th day of its 28-day cycle
M.SERIES_HOUR = 10
M.HISTORY = 12

-- the six dockyards layouts (levels/west_coast_usa/gameplay/trackLayers/dockyards/<layer>/race.race.json)
M.HOME = {
  { slot = 'dock-1', layer = '001', title = 'Dockyards sprint', fee = 100, purse = 500 },
  { slot = 'dock-2', layer = '002', title = 'Dockyards short loop', fee = 100, purse = 500 },
  { slot = 'dock-3', layer = '003', title = 'Dockyards 3-lap sprint', fee = 150, purse = 800 },
  { slot = 'dock-4', layer = '004', title = 'Dockyards harbour loop', fee = 150, purse = 700 },
  { slot = 'dock-5', layer = '005', title = 'Dockyards long loop', fee = 150, purse = 800 },
  { slot = 'dock-6', layer = '006', title = 'Dockyards pier circuit', fee = 150, purse = 800 },
}
M.HOME_PLACE = 'Belasco Dockyards'

-- the monthly series, in rotation (T3 and later bring the travel; listed from the start so the calendar shows what is coming)
M.SERIES = {
  { id = 'utah-rally', name = 'NGRC Utah Rally', map = 'Utah', place = 'Utah paddock', rounds = 4, fee = 800, hours = 6, rep = 600, purse = 3000, requires = 'A gravel or rally car',
    titles = { 'SS1 River', 'SS2 Canyon', 'SS3 River reverse', 'SS4 Canyon reverse' } },
  { id = 'jv-offroad', name = 'Johnson Valley off-road', map = 'Johnson Valley', place = 'Johnson Valley', rounds = 5, fee = 600, hours = 5, rep = 300, purse = 1200 },
  { id = 'hirochi-cup', name = 'Hirochi circuit cup', map = 'Hirochi Raceway', place = 'Hirochi Raceway', rounds = 4, fee = 700, hours = 4, rep = 450, purse = 2000 },
}

function M.newStore() return { entered = {}, declined = {}, remind = {}, done = {}, fired = {}, history = {} } end
function M.repair(st)
  if type(st) ~= 'table' then return M.newStore() end
  for _, k in ipairs({ 'entered', 'declined', 'remind', 'done', 'fired', 'history' }) do if type(st[k]) ~= 'table' then st[k] = {} end end
  return st
end

-- which layout a weekend day gets: the week and the day pick one of the six, every layout within three weekends
function M.homeFor(day, seed)
  local week, dow = weekly.week(day), weekly.dayOfWeek(day)
  if not M.WEEKEND[dow] then return nil end
  local i = (week * 2 + dow + (tonumber(seed) or 0)) % #M.HOME + 1
  return M.HOME[i], week
end

local function homeEvent(day, seed)
  local h, week = M.homeFor(day, seed)
  if not h then return nil end
  return { id = 'weekend:' .. h.slot .. ':' .. week, title = h.title, kind = 'weekend', day = day, hour = M.HOME_HOUR, place = M.HOME_PLACE, map = nil,
    travel = { needed = false, fee = 0, hours = 0 }, series = nil, reward = h.purse, fee = h.fee, laps = M.HOME_LAPS, layer = h.layer,
    requires = { label = strings.t('calendar.any_road_car'), met = true } }
end

-- the series of a 28-day cycle, its rounds as events (one a day from the cycle's 15th day); nil below the series' reputation
function M.seriesFor(cycle, rep)
  local sr = M.SERIES[cycle % #M.SERIES + 1]
  if (rep or 0) < sr.rep then return nil end
  return sr
end
local function seriesEvents(day, rep, from, to)
  local out = {}
  for cycle = math.floor((from - 1) / M.SERIES_DAYS), math.floor((to - 1) / M.SERIES_DAYS) do
    local sr = M.seriesFor(cycle, rep)
    if sr then
      local sid = sr.id .. ':' .. (cycle + 1)
      for r = 1, sr.rounds do
        local d = cycle * M.SERIES_DAYS + M.SERIES_FIRST + r - 1
        if d >= from and d <= to then
          out[#out + 1] = { id = sid .. ':r' .. r, title = sr.name .. ': ' .. (sr.titles and sr.titles[r] or strings.t('calendar.round_1', r)), kind = 'series', day = d, hour = M.SERIES_HOUR,
            place = sr.place, map = sr.map, travel = { needed = true, fee = sr.fee, hours = sr.hours }, series = { id = sid, name = sr.name, round = r, rounds = sr.rounds },
            reward = strings.t('calendar.purse_by_place_up_to_1', sr.purse), requires = sr.requires and { label = sr.requires, met = false } or nil, expiresIn = math.max(0, d - day) }
        end
      end
    end
  end
  return out
end

-- the swap meet: weekend nights (the swap meet part decides where; listed so the week shows it)
local function swapEvent(day, place)
  local week, dow = weekly.week(day), weekly.dayOfWeek(day)
  if not M.WEEKEND[dow] then return nil end
  return { id = 'swap:meet:' .. week .. ':' .. dow, title = strings.t('calendar.swap_meet'), kind = 'weekend', day = day, hour = 20, place = place or strings.t('calendar.the_biggest_car_park'), map = nil,
    travel = { needed = false, fee = 0, hours = 0 }, series = nil, reward = nil, requires = nil, info = true }
end

-- the status of an event from the store (nil: not shown)
function M.status(st, ev, day, hour)
  local d = st.done[ev.id]
  if d then return d.won == nil and 'missed' or 'done' end
  if st.declined[ev.id] then return 'declined' end
  local past = ev.day < day or (ev.day == day and (hour or 0) > (ev.hour or 0) + M.LATE_H)
  if st.entered[ev.id] then return past and 'missed' or 'entered' end
  return past and nil or 'open'
end

-- every event of the window: the last KEEP days (only what was done or missed), today and AHEAD days
function M.schedule(day, hour, seed, rep, st, opts)
  opts = opts or {}
  st = M.repair(st)
  local list = {}
  local function add(ev)
    if not ev then return end
    local status = M.status(st, ev, day, hour)
    if not status then return end
    if ev.day < day and status ~= 'done' and status ~= 'missed' then return end
    ev.status = status
    ev.reminder = st.remind[ev.id] == true
    if ev.expiresIn == nil then ev.expiresIn = nil end
    if status == 'done' then ev.reward = st.done[ev.id].reward or ev.reward end
    list[#list + 1] = ev
  end
  local from, to = day - M.KEEP, day + M.AHEAD
  for d = from, to do
    if opts.home ~= false then add(homeEvent(d, seed)) end
    if opts.swap ~= false then add(swapEvent(d, opts.swapPlace)) end
  end
  if opts.series ~= false then for _, ev in ipairs(seriesEvents(day, rep, from, to)) do add(ev) end end
  for _, ev in ipairs(opts.extra or {}) do add(ev) end          -- (the brand invitationals, sl_invite)
  table.sort(list, function(a, b) if a.day ~= b.day then return a.day < b.day end if (a.hour or 0) ~= (b.hour or 0) then return (a.hour or 0) < (b.hour or 0) end return a.id < b.id end)
  return list
end

function M.find(list, id) for _, ev in ipairs(list) do if ev.id == id then return ev end end return nil end

-- the phone's shape (tools/calendar_fixture.js is the contract)
function M.summary(day, hour, seed, rep, st, opts)
  local events = {}
  for _, ev in ipairs(M.schedule(day, hour, seed, rep, st, opts)) do
    events[#events + 1] = { id = ev.id, title = ev.title, kind = ev.kind, day = ev.day, hour = ev.hour, place = ev.place, map = ev.map, travel = ev.travel, series = ev.series,
      status = ev.status, reward = ev.reward, requires = ev.requires, reminder = ev.reminder, expiresIn = ev.expiresIn }
  end
  return { today = { day = day, hour = hour, week = weekly.week(day), dayOfWeek = weekly.dayOfWeek(day) }, events = events, series = {}, invites = {} }
end

-- ---- the actions: each answers ok, text (and the fee to take for an entry)
function M.enter(st, ev, money, day, hour)
  if not ev then return false, strings.t('calendar.no_such_event') end
  if ev.info then return false, strings.t('calendar.nothing_to_enter') end
  if ev.travel and ev.travel.needed then return false, strings.t('calendar.travel_not_yet') end
  local status = M.status(st, ev, day, hour)
  if status == 'entered' then return false, strings.t('calendar.already_entered') end
  if status ~= 'open' and status ~= 'declined' then return false, strings.t('calendar.that_one_is_over') end
  local fee = ev.fee or 0
  if (money or 0) < fee then return false, strings.t('carcare.it_is_d_you_have', fee, money or 0) end
  st.entered[ev.id] = { day = ev.day, hour = ev.hour, fee = fee }
  st.declined[ev.id] = nil
  st.remind[ev.id] = true
  return true, strings.t('calendar.entered_1_be_at_2_on_day_3_at_4', ev.title, ev.place, ev.day, M.clock(ev.hour)), fee
end
function M.decline(st, ev)
  if not ev then return false, strings.t('calendar.no_such_event') end
  if st.entered[ev.id] then return false, strings.t('calendar.you_are_entered') end
  st.declined[ev.id] = true
  st.remind[ev.id] = nil
  return true, strings.t('calendar.declined_1', ev.title)
end
function M.remind(st, ev, on)
  if not ev then return false, strings.t('calendar.no_such_event') end
  st.remind[ev.id] = on and true or nil
  return true, strings.t(on and 'calendar.reminder_on_1' or 'calendar.reminder_off_1', ev.title)
end

-- the reminders due now, for entered or reminded events, at 24 and 1 hours ahead, each once; returns { { event, hoursLeft } }
M.REMIND_AT = { 24, 1 }
function M.reminders(list, st, day, hour)
  local out = {}
  for _, ev in ipairs(list) do
    if (st.entered[ev.id] or st.remind[ev.id]) and ev.status ~= 'done' and ev.status ~= 'missed' and ev.status ~= 'declined' then
      local left = (ev.day - day) * 24 + (ev.hour or 0) - hour
      for _, at in ipairs(M.REMIND_AT) do
        local key = ev.id .. ':' .. at
        if left <= at and left > 0 and not st.fired[key] then st.fired[key] = true out[#out + 1] = { event = ev, hoursLeft = at } end
      end
    end
  end
  return out
end

-- the entered event that should run now (the player at the grid within reach, the hour come, not LATE_H past), or nil
function M.due(list, st, day, hour, distToGrid)
  for _, ev in ipairs(list) do
    if ev.status == 'entered' and ev.day == day and hour >= (ev.hour or 0) and hour <= (ev.hour or 0) + M.LATE_H and not ev.info and not (ev.travel and ev.travel.needed) then
      if distToGrid and distToGrid(ev) <= M.START_REACH then return ev end
    end
  end
  return nil
end

-- an entered event whose time has passed without a start: missed (recorded once)
function M.missed(list, st, day, hour)
  local out = {}
  for _, ev in ipairs(list) do
    if ev.status == 'missed' and st.entered[ev.id] and not st.done[ev.id] then
      st.done[ev.id] = { won = nil, day = ev.day }
      out[#out + 1] = ev
    end
  end
  return out
end

-- the race is over: done with the place (nil: did not finish), the purse share and the reputation of the place (sl/core/gridrace); the history keeps the last HISTORY
function M.result(st, ev, place)
  if not ev or st.done[ev.id] then return 0, 0 end
  local money, rep = require('sl/core/gridrace').payout(place, ev.reward)
  st.done[ev.id] = { won = place == 1, place = place, day = ev.day, reward = money }
  st.entered[ev.id] = nil
  st.history[#st.history + 1] = { id = ev.id, title = ev.title, day = ev.day, place = place, won = place == 1, reward = money }
  while #st.history > M.HISTORY do table.remove(st.history, 1) end
  return money, rep
end

-- a day is over: the store forgets what is older than KEEP days
function M.sweep(st, day)
  for id, e in pairs(st.done) do if (e.day or 0) < day - M.KEEP then st.done[id] = nil end end
  for id, e in pairs(st.entered) do if (e.day or 0) < day - M.KEEP then st.entered[id] = nil end end
  for key in pairs(st.fired) do
    local id = key:match('^(.*):%d+$')
    if id and not st.entered[id] and not st.remind[id] then st.fired[key] = nil end
  end
end

-- a dockyards layout (race.race.json: pathnodes, segments from->to, startNode, startPositions) as a circuit for sl_streets: cps in lap order
-- from the start node (pos, dir to the next, half the width), the grid spot and its facing. vec3(x, y, z) builds the points. nil when the file is not a loop.
function M.trackFromLayer(data, name, vec3)
  if type(data) ~= 'table' or type(data.pathnodes) ~= 'table' or type(data.segments) ~= 'table' then return nil end
  local byId, nxt = {}, {}
  for _, p in ipairs(data.pathnodes) do byId[p.oldId] = p end
  for _, sg in ipairs(data.segments) do nxt[sg.from] = sg.to end
  local order, seen, at = {}, {}, data.startNode
  while at ~= nil and byId[at] and not seen[at] do seen[at] = true order[#order + 1] = at at = nxt[at] end
  if #order < 3 or at ~= order[1] then return nil end
  local cps = {}
  for i, id in ipairs(order) do
    local p, q = byId[id].pos, byId[order[i % #order + 1]].pos
    local dir = vec3(q[1] - p[1], q[2] - p[2], 0)
    cps[i] = { pos = vec3(p[1], p[2], p[3]), dir = dir, half = math.max(4, tonumber(byId[id].radius) or 6) }
  end
  local start
  for _, sp in ipairs(data.startPositions or {}) do if sp.oldId == data.defaultStartPosition then start = sp end end
  return { name = name, cps = cps, start = start and { pos = vec3(start.pos[1], start.pos[2], start.pos[3]), rot = start.rot } or nil }
end

function M.clock(h) h = tonumber(h) or 0 return string.format('%02d:%02d', math.floor(h) % 24, math.floor((h % 1) * 60 + 0.5)) end

return M
