-- Street Legal: achievements and personal bests (BACKLOG X23). No game calls: each achievement is a
-- check on the career's own record, so nothing new has to be counted to earn one.

local M = {}

local strings = require('sl/core/strings')

local function stat(s, k) return s.stats and s.stats[k] or 0 end
local function jobs(s) return s.jobs or {} end
local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

M.LIST = {
  { id = 'first_car', title = 'Wheels', desc = strings.t('achievements.own_a_car'), check = function(s) return #(s.cars or {}) > 0 end },
  { id = 'first_job', title = strings.t('achievements.paid_work'), desc = strings.t('achievements.finish_a_job'), check = function(s) return (jobs(s).done or 0) >= 1 end },
  { id = 'first_part', title = strings.t('achievements.spanners_out'), desc = strings.t('achievements.buy_your_first_part_in'), check = function(s) return jobs(s).upgraded == true end },
  { id = 'first_race', title = strings.t('achievements.lights_out'), desc = strings.t('achievements.race_on_the_street'), check = function(s) return stat(s, 'races') >= 1 end },
  { id = 'first_win', title = strings.t('achievements.first_blood'), desc = strings.t('achievements.win_a_race'), check = function(s) return stat(s, 'wins') >= 1 end },
  { id = 'wins_10', title = strings.t('achievements.regular_winner'), desc = strings.t('achievements.win_10_races'), check = function(s) return stat(s, 'wins') >= 10 end },
  { id = 'wins_50', title = strings.t('achievements.street_machine'), desc = strings.t('achievements.win_50_races'), check = function(s) return stat(s, 'wins') >= 50 end },
  { id = 'pink_won', title = strings.t('achievements.pink_slip'), desc = strings.t('achievements.win_somebody_s_car'), check = function(s) return stat(s, 'pinksWon') >= 1 end },
  { id = 'pink_lost', title = strings.t('achievements.walking_home'), desc = strings.t('achievements.lose_a_car_on_a'), check = function(s) return stat(s, 'pinksLost') >= 1 end },
  { id = 'fleet_3', title = 'Collector', desc = strings.t('achievements.own_three_cars_at_once'), check = function(s) return #(s.cars or {}) >= 3 end },
  { id = 'garage_2', title = strings.t('achievements.moving_up'), desc = strings.t('achievements.move_to_club_garage_2'), check = function(s) return (s.garageLevel or 1) >= 2 end },
  { id = 'garage_3', title = strings.t('achievements.top_floor'), desc = strings.t('achievements.move_to_club_garage_3'), check = function(s) return (s.garageLevel or 1) >= 3 end },
  { id = 'rep_1500', title = 'Contender', desc = strings.t('achievements.reach_1_500_reputation'), check = function(s) return (s.rep or 0) >= 1500 end },
  { id = 'rep_6000', title = strings.t('achievements.king_of_valo_city'), desc = strings.t('achievements.reach_6_000_reputation'), check = function(s) return (s.rep or 0) >= 6000 end },
  { id = 'all_bosses', title = strings.t('achievements.top_of_the_strip'), desc = strings.t('achievements.beat_the_boss_of_every'), check = function(s) local n = 0 for _, r in ipairs(s.rivals and s.rivals.list or {}) do if r.boss and r.bossBeaten and not r.grandfathered then n = n + 1 end end return n >= 5 end },
  { id = 'roc', title = 'Champion', desc = strings.t('achievements.win_the_roc'), check = function(s) return s.roc and s.roc.champion == true end },
  { id = 'money_100k', title = strings.t('achievements.six_figures'), desc = strings.t('achievements.have_100_000_in_the'), check = function(s) return (s.money or 0) >= 100000 end },
  { id = 'season_champion', title = strings.t('achievements.belasco_champion'), desc = strings.t('achievements.win_a_home_season'), check = function(s) return (s.season and s.season.titles or 0) >= 1 end },
  { id = 'jobs_25', title = strings.t('achievements.working_stiff'), desc = strings.t('achievements.finish_25_jobs'), check = function(s) return (jobs(s).done or 0) >= 25 end },
  { id = 'jobs_all', title = strings.t('achievements.jack_of_all_trades'), desc = strings.t('achievements.finish_eight_different_kinds_of'), check = function(s) return count(jobs(s).kindDone) >= 8 end },
  { id = 'turf', title = strings.t('achievements.on_the_map'), desc = strings.t('achievements.take_a_district_from_a'), check = function(s) for _, t in pairs(s.crews and s.crews.territory or {}) do if t.owner == 'player' then return true end end return false end },
  { id = 'home', title = strings.t('achievements.their_own_front_door'), desc = strings.t('achievements.take_a_crew_s_home'), check = function(s) for _, t in pairs(s.crews and s.crews.territory or {}) do if t.home and t.owner == 'player' then return true end end return false end },
  { id = 'king', title = strings.t('achievements.king_of_valo'), desc = strings.t('achievements.win_the_turf_war_against'), check = function(s) return s.crews ~= nil and s.crews.king ~= nil end },
  { id = 'flip', title = 'Flipper', desc = strings.t('achievements.sell_a_car_for_more'), check = function(s) return jobs(s).flip ~= nil and (jobs(s).flip.flips or 0) >= 1 end },
  { id = 'activities_5', title = 'Explorer', desc = strings.t('achievements.complete_five_different_activities'), check = function(s) return count(s.activitiesDone) >= 5 end },
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
