-- Street Legal: the grab bag (extension name: sl_grabbag; the Grab bag part: Mods > Street Legal > Parts of the game > Grab bag).
-- Rules in sl/core/grabbag. On the first day of each ledger week the past week is judged from the counters marked at its start (jobs done,
-- race wins, money earned); a good week leaves a box waiting: Benny texts, and the next time you drive a car of yours into the garage,
-- two to four used parts that fit it go on its shelf for nothing (Wrench Works' shelf; without the garage mod the box waits).
-- The save keeps s.grabbag = { week, mark, pending, given }.

local M = {}

local rules = require('sl/core/grabbag')
local weekly = require('sl/core/weekly')
local strings = require('sl/core/strings')
local features = require('sl/core/features')
local rngLib = require('sl/core/rng')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end
local function store(s) s.grabbag = rules.repair(s.grabbag) return s.grabbag end
local function counters(s) return rules.mark(s.jobs and s.jobs.done or 0, s.stats and s.stats.wins or 0, s.stats and s.stats.earned or 0) end

-- the week turns: judge the one that ended, mark the new one
function M.onStreetLegalNewDay(day)
  local s = career()
  if not s then return end
  local st = store(s)
  local week = weekly.week(day or s.day)
  if st.week == nil then st.week, st.mark = week, counters(s) return end      -- (the first day the part sees: nothing is judged backwards)
  if week == st.week then return end
  if rules.goodWeek(st.mark, counters(s)) and not st.pending then
    st.pending = true
    sl_career.sendText('benny', strings.t('grabbag.benny_box'), 2)
  end
  st.week, st.mark = week, counters(s)
  extensions.hook('onStreetLegalChanged')
end

-- the garage: the box goes on the shelf of the car you brought in
local function handOver(s)
  local st = store(s)
  if not st.pending then return end
  if not (slrr_garage and slrr_garage.lookupParts and slrr_garage.addShelfPart) then return end      -- (no garage mod: the box waits)
  local car = sl_fleet and sl_fleet.currentCar and sl_fleet.currentCar()
  local veh = car and sl_fleet.vehicleOf and sl_fleet.vehicleOf(car.id)
  if not (car and veh) then return end
  local ok, list, model = pcall(slrr_garage.lookupParts, veh:getID(), {})
  if not ok or type(list) ~= 'table' then return end
  local rng = rngLib.new(rngLib.hash('grabbag:' .. s.day .. ':' .. tostring(s.seed) .. ':' .. (st.given or 0)))
  local parts = rules.pick(list, rng)
  if #parts == 0 then return end
  local put = 0
  for _, p in ipairs(parts) do
    local okp = pcall(slrr_garage.addShelfPart, model or car.model, { part = p.part, name = p.name, slotId = p.slotId, value = p.value, condition = p.condition })
    if okp then put = put + 1 end
  end
  if put == 0 then return end
  st.pending = false
  st.given = (st.given or 0) + 1
  toast(strings.t('grabbag.on_the_shelf_1_2', put, rules.names(parts)))
  extensions.hook('onStreetLegalChanged')
end
function M.onWrenchWorksGarageEntered()
  local s = career()
  if not s then return end
  local ok, err = pcall(handOver, s)
  if not ok then log('E', 'sl_grabbag', tostring(err)) end
end

function M.summary()
  local s = career()
  if not s then return nil end
  local st = store(s)
  return { pending = st.pending == true, given = st.given or 0, week = st.week }
end
function M.status()
  local s = career()
  if not s then return 'no career' end
  local st = store(s)
  local now, m = counters(s), st.mark or {}
  return string.format('week %s, box waiting %s, given %d; this week so far: jobs %d, wins %d, earned $%d', tostring(st.week), tostring(st.pending), st.given or 0,
    now.jobs - (m.jobs or 0), now.wins - (m.wins or 0), now.earned - (m.earned or 0))
end
-- for the tester: a box waiting now
function M.debugPending() local s = career() if not s then return 'no career' end store(s).pending = true return M.status() end

features.gate('grabbag', M, nil, nil, { 'summary' })      -- (the part off: no judging, no box)

return M
