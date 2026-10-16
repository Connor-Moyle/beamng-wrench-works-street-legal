-- Wrench Works: Street Legal: the map's activities in the career (extension name: sl_activities)
-- The map's BeamNG missions (street sprints, police evades, drift, parking, jumps, crawl...) pay into
-- the career: an entry fee when one starts, money and rep from the result BeamNG records. Which
-- missions and what they pay is the RULES table, matched on the mission id (docs: DESIGN2_activities.md).

local M = {}

local progression = require('sl/core/progression')
local stateLib = require('sl/core/state')

-- { match = pattern on the mission id, fee, prize (money on a pass, more per star), rep, firstOnly (rep the first time only), heat }
local RULES = {
  { match = '/timeTrial/slrr_sprint_', title = 'Street sprint', fee = 100, prize = 400, perStar = 0.25, rep = 15, nightOnly = true },
  { match = '/timeTrial/slrr_rally_', title = 'Rally loop', rep = 20, firstOnly = true },      -- (the ROC rally: a closed timeTrial)
  { match = '/evade/slrr_evade_', title = 'Evade', rep = 20, heatRep = 60, heat = -0.3 },
  { match = '/drift/', title = 'Drift contest', fee = 50, prize = 300, perStar = 0.3, rep = 12 },
  { match = '/precisionParking/', title = 'Parking', rep = 10, firstOnly = true },
  { match = '/longjump/', title = 'Long jump', rep = 15, firstOnly = true },
  { match = '/crawl/', title = 'Rock crawl', rep = 15, firstOnly = true },
  { match = '/rallyLoop/', title = 'Rally loop', rep = 20, firstOnly = true },
  { match = '/scatterPickup/', title = 'Scatter pickup', rep = 10, firstOnly = true },
  { match = '/collection/', title = 'Collection', rep = 10, firstOnly = true },
  { match = '/hypermiling/', title = 'Hypermiling', rep = 10, firstOnly = true },
  { match = '/garageToGarage/', title = 'Garage to garage', rep = 10, firstOnly = true },
}
M.RULES = RULES

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function tell(text) guihooks.trigger('slPhoneToast', { text = text }) if ui_message then ui_message(text, 6, 'streetLegal') end end

local function ruleFor(id)
  if type(id) ~= 'string' or not id:find('^' .. sl_career.LEVEL .. '/') then return nil end
  for _, r in ipairs(RULES) do if id:find(r.match, 1, true) then return r end end
end

local function night() return progression.isNight(sl_career.hour()) end

local paidFee = {}   -- mission id -> true while a paid attempt runs

function M.onAnyMissionChanged(change, mission)
  local s = career()
  local r = s and change == 'started' and mission and ruleFor(mission.id)
  if not r or not r.fee then return end
  if r.nightOnly and not night() then return end                    -- by day: a practice run, nothing on it
  if sl_career.addMoney(-r.fee, r.title .. ' entry') then paidFee[mission.id] = true end
end

function M.onMissionAttemptAggregated(attempt, mission)
  local s = career()
  local r = s and mission and ruleFor(mission.id)
  if not r or type(attempt) ~= 'table' then return end
  local paid = paidFee[mission.id]
  paidFee[mission.id] = nil
  local passed = attempt.type == 'passed' or attempt.type == 'completed'
  if not passed then return end
  s.activitiesDone = s.activitiesDone or {}
  local first = not s.activitiesDone[mission.id]
  s.activitiesDone[mission.id] = (s.activitiesDone[mission.id] or 0) + 1
  local stars = 0
  for _, on in pairs(type(attempt.unlockedStars) == 'table' and attempt.unlockedStars or {}) do if on then stars = stars + 1 end end
  local money = 0
  if r.prize and (paid or not r.fee) then money = math.floor(r.prize * (1 + (r.perStar or 0) * stars) / 10) * 10 end
  local rep = 0
  if not r.firstOnly or first then rep = (r.rep or 0) + math.floor((r.heatRep or 0) * (s.heat or 0)) end
  if money > 0 then sl_career.payOut(money, r.title) end
  if rep ~= 0 then stateLib.addRep(s, rep) end
  if r.heat then s.heat = math.max(0, math.min(1, (s.heat or 0) + r.heat)) end
  if money > 0 or rep ~= 0 then
    tell(string.format('%s: %s%s', r.title, money > 0 and ('$' .. money .. ', ') or '', rep ~= 0 and string.format('%+d reputation', rep) or 'done'))
  end
  extensions.hook('onStreetLegalChanged')
end

return M
