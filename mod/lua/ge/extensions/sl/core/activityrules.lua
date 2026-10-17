-- Street Legal: which of the map's BeamNG missions pay into the career, and what (rules only, no game calls;
-- tested by tools/luatest.js). A mission id is "<level>/<type>/<name>", the type being the mission type
-- (timeTrial, evade, precisionParking, drift...).
--   match: a piece of the id. The Valo City rules match its own slrr_ missions by name; the others by type.
--   generic: also applies on a map that is not Valo City, to its stock missions of that type (T15)
--   fee, prize (money on a pass, more per star), rep, firstOnly (rep the first time only), heat, prizeOnce (the prize
--   and the fee only the first time, no practice runs paying: a stock map has dozens of time trials, and a prize that repeats is a money loop)

local M = {}

local strings = require('sl/core/strings')

local VALO = 'slrr_valo_city'

M.RULES = {
  { match = '/timeTrial/slrr_sprint_', title = strings.t('activityrules.street_sprint'), fee = 100, prize = 400, perStar = 0.25, rep = 15, nightOnly = true },
  { match = '/timeTrial/slrr_rally_', title = strings.t('activityrules.rally_loop'), rep = 20, firstOnly = true },      -- (the ROC rally: a closed timeTrial)
  { match = '/evade/slrr_evade_', title = 'Evade', rep = 20, heatRep = 60, heat = -0.3 },
  -- the stock track events of a map like West Coast USA are day events (D2, kind = splitphase.RACES): they pay prize money, once, and are refused at night
  { match = '/timeTrial/', generic = true, kind = 'timeTrial', title = strings.t('activityrules.time_trial'), fee = 100, prize = 400, perStar = 0.25, rep = 15, firstOnly = true, prizeOnce = true },
  { match = '/dragStripRace/', generic = true, kind = 'drag', title = strings.t('activityrules.drag_strip'), fee = 50, prize = 300, perStar = 0.25, rep = 10, firstOnly = true, prizeOnce = true },
  { match = '/dragStripAPM/', generic = true, kind = 'drag', title = strings.t('activityrules.drag_strip'), fee = 50, prize = 200, perStar = 0.25, rep = 10, firstOnly = true, prizeOnce = true },
  -- the season finale (#25): the Race of Champions on the race track's first circuit, behind the top garage and the top names (progression.ROC)
  { match = '/aiRace/001-circuit', generic = true, kind = 'circuit', roc = true, title = strings.t('activityrules.race_of_champions'), fee = 50000, prize = 250000, rep = 2000 },
  { match = '/aiRace/', generic = true, kind = 'circuit', title = strings.t('activityrules.circuit_race'), fee = 100, prize = 500, perStar = 0.25, rep = 15, firstOnly = true, prizeOnce = true },
  { match = '/evade/', generic = true, title = 'Evade', rep = 20, heatRep = 60, heat = -0.3 },
  { match = '/drift/', title = strings.t('activityrules.drift_contest'), fee = 50, prize = 300, perStar = 0.3, rep = 12 },
  { match = '/precisionParking/', title = 'Parking', rep = 10, firstOnly = true },
  { match = '/longjump/', title = strings.t('activityrules.long_jump'), rep = 15, firstOnly = true },
  { match = '/crawl/', title = strings.t('activityrules.rock_crawl'), rep = 15, firstOnly = true },
  { match = '/rallyLoop/', title = strings.t('activityrules.rally_loop'), rep = 20, firstOnly = true },
  { match = '/scatterPickup/', title = strings.t('activityrules.scatter_pickup'), rep = 10, firstOnly = true },
  { match = '/collection/', title = 'Collection', rep = 10, firstOnly = true },
  { match = '/hypermiling/', title = 'Hypermiling', rep = 10, firstOnly = true },
  { match = '/garageToGarage/', title = strings.t('activityrules.garage_to_garage'), rep = 10, firstOnly = true },
}

-- the Race of Champions: who may enter (nil: open), what to tell the rest. state: the career save
function M.rocGate(state)
  local progression = require('sl/core/progression')
  if progression.rocOpen(state or {}) then return nil end
  return string.format(strings.t('activityrules.the_race_of_champions_is'), progression.ROC.garageLevel, progression.ROC.rep)
end

-- did the attempt win it (the first place is the gold star)
function M.rocWon(unlockedStars)
  return type(unlockedStars) == 'table' and unlockedStars.finishGold == true
end

-- the rule for a mission of this level, or nil (another level's missions never pay)
function M.ruleFor(level, id)
  if type(id) ~= 'string' or type(level) ~= 'string' or not id:find('^' .. level .. '/') then return nil end
  for _, r in ipairs(M.RULES) do
    if (not r.generic or level ~= VALO) and id:find(r.match, 1, true) then return r end
  end
end

-- is this mission one of the day-only track events and the phase is not day (its marker and prompt are left out then)
function M.closed(level, id, phase)
  local r = M.ruleFor(level, id)
  return r ~= nil and r.kind ~= nil and not require('sl/core/splitphase').available('races', r.kind, phase)
end

return M
