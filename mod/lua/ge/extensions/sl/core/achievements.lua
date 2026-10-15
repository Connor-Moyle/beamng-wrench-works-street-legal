-- Street Legal: achievements and personal bests (BACKLOG X23). No game calls: each achievement is a
-- check on the career's own record, so nothing new has to be counted to earn one.

local M = {}

local function stat(s, k) return s.stats and s.stats[k] or 0 end
local function jobs(s) return s.jobs or {} end
local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

M.LIST = {
  { id = 'first_car', title = 'Wheels', desc = 'Own a car.', check = function(s) return #(s.cars or {}) > 0 end },
  { id = 'first_job', title = 'Paid work', desc = 'Finish a job.', check = function(s) return (jobs(s).done or 0) >= 1 end },
  { id = 'first_part', title = 'Spanners out', desc = 'Buy your first part in Wrench Works.', check = function(s) return jobs(s).upgraded == true end },
  { id = 'first_race', title = 'Lights out', desc = 'Race on the street.', check = function(s) return stat(s, 'races') >= 1 end },
  { id = 'first_win', title = 'First blood', desc = 'Win a race.', check = function(s) return stat(s, 'wins') >= 1 end },
  { id = 'wins_10', title = 'Regular winner', desc = 'Win 10 races.', check = function(s) return stat(s, 'wins') >= 10 end },
  { id = 'wins_50', title = 'Street machine', desc = 'Win 50 races.', check = function(s) return stat(s, 'wins') >= 50 end },
  { id = 'pink_won', title = 'Pink slip', desc = "Win somebody's car.", check = function(s) return stat(s, 'pinksWon') >= 1 end },
  { id = 'pink_lost', title = 'Walking home', desc = 'Lose a car on a pink slip.', check = function(s) return stat(s, 'pinksLost') >= 1 end },
  { id = 'fleet_3', title = 'Collector', desc = 'Own three cars at once.', check = function(s) return #(s.cars or {}) >= 3 end },
  { id = 'garage_2', title = 'Moving up', desc = 'Move to Club Garage 2.', check = function(s) return (s.garageLevel or 1) >= 2 end },
  { id = 'garage_3', title = 'Top floor', desc = 'Move to Club Garage 3.', check = function(s) return (s.garageLevel or 1) >= 3 end },
  { id = 'rep_1500', title = 'Contender', desc = 'Reach 1,500 reputation.', check = function(s) return (s.rep or 0) >= 1500 end },
  { id = 'rep_6000', title = 'King of Valo City', desc = 'Reach 6,000 reputation.', check = function(s) return (s.rep or 0) >= 6000 end },
  { id = 'roc', title = 'Champion', desc = 'Win the ROC.', check = function(s) return s.roc and s.roc.champion == true end },
  { id = 'money_100k', title = 'Six figures', desc = 'Have $100,000 in the bank.', check = function(s) return (s.money or 0) >= 100000 end },
  { id = 'jobs_25', title = 'Working stiff', desc = 'Finish 25 jobs.', check = function(s) return (jobs(s).done or 0) >= 25 end },
  { id = 'jobs_all', title = 'Jack of all trades', desc = 'Finish eight different kinds of job.', check = function(s) return count(jobs(s).kindDone) >= 8 end },
  { id = 'turf', title = 'On the map', desc = 'Take a district from a crew.', check = function(s) for _, t in pairs(s.crews and s.crews.territory or {}) do if t.owner == 'player' then return true end end return false end },
  { id = 'home', title = 'Their own front door', desc = "Take a crew's home district.", check = function(s) for _, t in pairs(s.crews and s.crews.territory or {}) do if t.home and t.owner == 'player' then return true end end return false end },
  { id = 'king', title = 'King of Valo', desc = 'Win the turf war against the crew leaders.', check = function(s) return s.crews ~= nil and s.crews.king ~= nil end },
  { id = 'flip', title = 'Flipper', desc = 'Sell a car for more than you paid.', check = function(s) return jobs(s).flip ~= nil and (jobs(s).flip.flips or 0) >= 1 end },
  { id = 'activities_5', title = 'Explorer', desc = 'Complete five different activities.', check = function(s) return count(s.activitiesDone) >= 5 end },
}

-- the achievements a career has just earned (and marks them earned on that day)
function M.update(s)
  s.achievements = s.achievements or {}
  local new = {}
  for _, a in ipairs(M.LIST) do
    if not s.achievements[a.id] then
      local ok, got = pcall(a.check, s)
      if ok and got then s.achievements[a.id] = s.day or 0 new[#new + 1] = a end
    end
  end
  return new
end

-- a race's time: a new best? (key: the race or mission id; lower is better)
function M.best(s, key, time, name)
  if type(time) ~= 'number' or time <= 0 or key == nil then return false end
  s.bests = s.bests or {}
  local k = tostring(key)
  local b = s.bests[k]
  if b and b.time <= time then return false end
  s.bests[k] = { time = math.floor(time * 100 + 0.5) / 100, name = name or k, day = s.day or 0 }
  return true
end

return M
