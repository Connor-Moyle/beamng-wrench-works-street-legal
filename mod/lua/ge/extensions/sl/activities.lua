-- Wrench Works: Street Legal: the map's activities in the career (extension name: sl_activities)
-- The map's BeamNG missions (street sprints, police evades, drift, parking, jumps, crawl...) pay into
-- the career: an entry fee when one starts, money and rep from the result BeamNG records. Which
-- missions and what they pay is the RULES table, matched on the mission id (docs: DESIGN2_activities.md).

local M = {}

local progression = require('sl/core/progression')
local stateLib = require('sl/core/state')
local splitphase = require('sl/core/splitphase')

local rules = require('sl/core/activityrules')      -- which missions pay, and what
M.RULES = rules.RULES

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function tell(text) guihooks.trigger('slPhoneToast', { text = text }) if ui_message then ui_message(text, 6, 'streetLegal') end end

local function ruleFor(id) return rules.ruleFor(sl_career.LEVEL, id) end

local function night() return sl_career.isNight() end

local paidFee = {}   -- mission id -> true while a paid attempt runs

local refuse
function M.onUpdate()
  local m = refuse
  if not m then return end
  local mm = gameplay_missions_missionManager
  if not (m._isOngoing and mm and mm.attemptAbandonMissionWithFade) then refuse = nil return end
  if mm.attemptAbandonMissionWithFade(m, true) then refuse = nil end      -- (true: it handles its own stopping; else onMissionAbandoned, or a running task: again next frame)
end

function M.onMissionAbandoned() refuse = nil end

function M.onAnyMissionChanged(change, mission)
  local s = career()
  local r = s and change == 'started' and mission and ruleFor(mission.id)
  if not r then return end
  if r.kind and not splitphase.available('races', r.kind, sl_career.phase()) then
    refuse = mission                                   -- (a track event at night: stopped as soon as the game has finished starting it)
    tell('Track events run in the day.')
    return
  end
  if not r.fee then return end
  if r.nightOnly and not night() then return end                    -- by day: a practice run, nothing on it
  if r.prizeOnce and (s.activitiesDone or {})[mission.id] then return end      -- done before: a practice run
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
  if r.prize and (paid or not r.fee) and not (r.prizeOnce and not first) then money = math.floor(r.prize * (1 + (r.perStar or 0) * stars) / 10) * 10 end
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
