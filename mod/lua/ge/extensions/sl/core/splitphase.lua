-- Street Legal: what belongs to the day and what to the night (D2, PLAN_R1). Pure rules, no engine calls; tested by tools/luatest.js.
-- The career is in one phase at a time (sl/core/phase: 'day' | 'night'). Day is the legal, money-making half: jobs, shops, dealers, the stock
-- track events with prize money. Night is the street half: street races, meets, pink slips, a few shady jobs, rep instead of money.
-- Every kind of thing the career offers has one answer here: 'day', 'night' or 'both'. Callers ask `available(table, kind, phase)`; nothing
-- else in the career decides it. A kind not listed is 'both' (new things are not hidden by accident).

local M = {}

-- the jobs on the phone's board (sl_jobs TYPES kinds, and the ones other modules add)
M.JOBS = {
  part = 'day', courier = 'day', taxi = 'day', crush = 'day', transport = 'day', testdrive = 'day', recovery = 'day', errand = 'day',
  move = 'day', flip = 'day', dyno = 'day', quarter = 'day',
  food = 'night', hot = 'night', valet = 'night',
}

-- places by kind (sl_career places, and the Wrench Works shops): when they are open
M.PLACES = {
  shop = 'day', dealer = 'day', scrapyard = 'day', carwash = 'day', parts = 'day',
  junkyard = 'both',         -- the night gate stays: no questions asked
  garage = 'both', hospital = 'both', computer = 'both', cab = 'both', station = 'both',
  meet = 'night', valet = 'night',
}

-- races and track events (sl_races kinds, sl_streets, the stock missions by type)
M.RACES = {
  night = 'night', street = 'night', pink = 'night', roc = 'night', meet = 'night',          -- street racing
  drag = 'day', circuit = 'day', venue = 'day', timeTrial = 'day', track = 'day', rally = 'day', drift = 'day', evade = 'night',
}

-- other things that happen
M.EVENTS = {
  meet = 'night', showAndShine = 'night', pinkSlip = 'night', crewContract = 'night', turf = 'night', raid = 'night', policeChase = 'night',
  clubDay = 'day', clubSeason = 'day', clubNight = 'night', sponsor = 'day', swapMeet = 'day', auction = 'both', classifieds = 'both',
  tutorial = 'both',
}

local TABLES = { jobs = M.JOBS, places = M.PLACES, races = M.RACES, events = M.EVENTS }

-- 'day' | 'night' | 'both' for a kind in one of the tables ('jobs', 'places', 'races', 'events')
function M.phaseOf(table_, kind)
  local t = TABLES[table_]
  return t and t[kind] or 'both'
end

-- may this kind be offered / open / run in this phase
function M.available(table_, kind, phase)
  local p = M.phaseOf(table_, kind)
  return p == 'both' or p == phase
end

-- the kinds of a list that are on in this phase; kindOf(item) -> its kind
function M.filter(table_, list, phase, kindOf)
  local out = {}
  for _, x in ipairs(list or {}) do
    if M.available(table_, kindOf and kindOf(x) or x.kind, phase) then out[#out + 1] = x end
  end
  return out
end

-- what a closed place or an unavailable thing says
function M.closedText(table_, kind, phase)
  if M.available(table_, kind, phase) then return nil end
  if M.phaseOf(table_, kind) == 'day' then return 'Closed for the night. Open by day.' end
  return 'Only after dark.'
end

-- what a phase pays in (D5 builds on it): money by day, rep by night; a heat multiplier applies to the night's rep
function M.pays(phase) return phase == 'night' and 'rep' or 'money' end

return M
