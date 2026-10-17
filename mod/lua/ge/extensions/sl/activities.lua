-- Wrench Works: Street Legal: the map's activities in the career (extension name: sl_activities)
-- The map's BeamNG missions (street sprints, police evades, drift, parking, jumps, crawl...) pay into
-- the career: an entry fee when one starts, money and rep from the result BeamNG records. Which
-- missions and what they pay is the RULES table, matched on the mission id (docs: DESIGN2_activities.md).

local M = {}

local strings = require('sl/core/strings')

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

function M.onMissionAbandoned() refuse = nil end

-- the Race of Champions mission (#25) is not in the freeroam list (the game shows its circuits to a stock career only): it is made visible and
-- startable for as long as the career is in its day and the player may enter, and put back after
local function rocMissions()
  local out = {}
  local all = gameplay_missions_missions and gameplay_missions_missions.getAllMissions and gameplay_missions_missions.getAllMissions() or {}
  for _, m in ipairs(all) do
    local r = type(m) == 'table' and m.id and ruleFor(m.id)
    if r and r.roc then out[#out + 1] = m end
  end
  return out
end

local function syncRoc()
  local u = gameplay_missions_unlocks
  if not (u and u.overrideVisible and u.overrideStartable) then return end
  local s = career()
  local open = s ~= nil and sl_career.phase() == 'day' and rules.rocGate(s) == nil
  local changed = false
  for _, m in ipairs(rocMissions()) do
    local want = open or nil
    if u.isMissionVisible(m) ~= (open or false) then changed = true end
    u.overrideVisible(m, want)                       -- (the mission object, not its id: 0.39 reads mission.id inside)
    u.overrideStartable(m, want)
  end
  if changed and gameplay_rawPois and gameplay_rawPois.clear then gameplay_rawPois.clear() end
end
-- the rights change with the state (a rep gain, a move up): looked at every few seconds as well as on the hooks
local rocTimer = 0
function M.onUpdate(dtReal)
  if refuse then
    local m = refuse
    local mm = gameplay_missions_missionManager
    if not (m._isOngoing and mm and mm.attemptAbandonMissionWithFade) then refuse = nil
    elseif mm.attemptAbandonMissionWithFade(m, true) then refuse = nil end
  end
  rocTimer = rocTimer + (dtReal or 0)
  if rocTimer > 3 then rocTimer = 0 if career() then syncRoc() end end
end
M.onStreetLegalStarted = syncRoc
M.onStreetLegalPhase = syncRoc
M.onStreetLegalGarageMoved = syncRoc
M.onStreetLegalChanged = syncRoc
-- #37 at a track event the driver wears a helmet, if there is a helmet mesh for that driver (SLRR Drivers: models/<model>/helmet.dae; the garage's
-- Drivers tab says). The player's own choice is put back when the event ends.
local savedHelmet
local function helmetForEvent(on)
  if not (slrrDrivers and slrrDrivers.setAppearance and slrrDrivers.getAppearance and slrrDrivers.getDriver and slrr_garage and slrr_garage.driverHasHelmet) then return end
  if on then
    local v = getPlayerVehicle(0)
    local driver = v and slrrDrivers.getDriver(v:getID())
    if savedHelmet or not driver or not slrr_garage.driverHasHelmet(driver) then return end
    savedHelmet = { vid = v:getID(), helmet = (slrrDrivers.getAppearance(v:getID()) or {}).helmet == true }
    slrrDrivers.setAppearance(savedHelmet.vid, { helmet = true })
  elseif savedHelmet then
    slrrDrivers.setAppearance(savedHelmet.vid, { helmet = savedHelmet.helmet })      -- (false clears it)
    savedHelmet = nil
  end
end

M.onStreetLegalStopped = function()
  helmetForEvent(false)
  local u = gameplay_missions_unlocks
  if not (u and u.overrideVisible) then return end
  for _, m in ipairs(rocMissions()) do u.overrideVisible(m, nil) u.overrideStartable(m, nil) end
end

function M.onAnyMissionChanged(change, mission)
  if change == 'stopped' then helmetForEvent(false) end
  local s = career()
  local r = s and change == 'started' and mission and ruleFor(mission.id)
  if not r then return end
  if r.roc then
    -- entry rules: the top garage and the top names, the entry fee paid up front; the champion races it for nothing
    local why = rules.rocGate(s)
    if why then refuse = mission tell(why) return end
    if (s.roc or {}).champion then return end
    if not sl_career.addMoney(-r.fee, strings.t('activities.roc_entry')) then
      refuse = mission
      tell(string.format(strings.t('activities.entry_to_the_race_of'), r.fee))
      return
    end
    paidFee[mission.id] = true
    tell(string.format(strings.t('activities.race_of_champions_d_paid'), r.fee))
    return
  end
  if r.kind and not splitphase.available('races', r.kind, sl_career.phase()) then
    refuse = mission                                   -- (a track event at night: stopped as soon as the game has finished starting it)
    tell(strings.t('activities.track_events_run_in_the'))
    return
  end
  if r.kind then helmetForEvent(true) end
  if not r.fee then return end
  if r.nightOnly and not night() then return end                    -- by day: a practice run, nothing on it
  if r.prizeOnce and (s.activitiesDone or {})[mission.id] then return end      -- done before: a practice run
  if sl_career.addMoney(-r.fee, strings.t('activities.1_entry', (r.title))) then paidFee[mission.id] = true end
end

function M.onMissionAttemptAggregated(attempt, mission)
  local s = career()
  local r = s and mission and ruleFor(mission.id)
  if not r or type(attempt) ~= 'table' then return end
  local paid = paidFee[mission.id]
  paidFee[mission.id] = nil
  local passed = attempt.type == 'passed' or attempt.type == 'completed'
  if r.roc then
    if not paid then return end                      -- (the champion's lap for fun, or no entry)
    s.roc = s.roc or { round = 0 }
    if passed and rules.rocWon(attempt.unlockedStars) then
      s.roc.champion = true
      sl_career.payOut(r.prize, strings.t('activities.race_of_champions'))
      stateLib.addRep(s, r.rep)
      tell(string.format(strings.t('activities.champion_the_race_of_champions'), r.prize, r.rep))
      sl_career.sendText('benny', sl_career.mapText(strings.t('activities.you_won_the_race_of')), 3)
    else
      tell(strings.t('activities.out_of_the_race_of'))
    end
    extensions.hook('onStreetLegalChanged')
    return
  end
  if not passed then return end
  if slrrPedestrians and slrrPedestrians.cheer then slrrPedestrians.cheer(6) end          -- the crowd at a track event (#40)
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
  if rep > 0 and sl_career.isNight and sl_career.isNight() then rep = math.floor(rep * require('sl/core/heat').repBoost('night', sl_police and sl_police.level and sl_police.level() or 0) + 0.5) end      -- (D3)
  if rep ~= 0 then stateLib.addRep(s, rep) end
  if r.heat then s.heat = math.max(0, math.min(1, (s.heat or 0) + r.heat)) end
  if money > 0 or rep ~= 0 then
    tell(string.format('%s: %s%s', r.title, money > 0 and ('$' .. money .. ', ') or '', rep ~= 0 and string.format(strings.t('activities.d_reputation'), rep) or 'done'))
  end
  extensions.hook('onStreetLegalChanged')
end

return M
