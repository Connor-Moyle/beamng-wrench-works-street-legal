-- Street Legal: heat and the night's risk (D3). Pure game rules, no engine calls (tested by tools/luatest.js).
-- Heat is the police's attention to you, kept as 0..1 in the save (s.heat) and shown as a level 0 to 5 (sl/core/phase heatLevel). It exists only
-- at night. Street races, near misses with the police and busts raise it, an escaped chase cools it, and it fades while nobody is after you.
-- The higher it is: more patrols, a stricter and harder-to-shake police (the game's own pursuit variables), roadblocks at 4 and 5, a bigger
-- reputation multiplier, a bigger fine, and from 4 a bust impounds the car. Reputation earned at night is "at risk" until it is banked at a garage
-- (or by switching phase); a bust loses what is unbanked.

local phase = require('sl/core/phase')

local M = {}

M.RACE = 0.12              -- a street race starting
M.NEAR_MISS = 0.04         -- a patrol car that you flash past
M.ESCAPE = 0.06            -- a chase you got out of (on top of the reputation)
M.BUST = 0.2
M.COOL_PER_MINUTE = 0.01   -- nobody after you (real minutes)

-- the game's police variables (gameplay_police.setPoliceVars) for the phase and the heat level. By day the police leave normal driving alone.
local STRICTNESS = { [0] = 0.3, 0.45, 0.6, 0.75, 0.9, 1.0 }
function M.policeVars(ph, level)
  level = math.max(0, math.min(5, math.floor(tonumber(level) or 0)))
  if ph ~= 'night' then
    return { strictness = 0.1, roadblockFrequency = 0, suspectFrequency = 0, evadeTime = 30, evadeRadius = 80 }
  end
  return {
    strictness = STRICTNESS[level],
    roadblockFrequency = level >= 5 and 1 or (level >= 4 and 0.5 or 0),
    suspectFrequency = 0.2 + 0.1 * level,
    evadeTime = 30 + 12 * level,           -- a hotter city takes longer to lose
    evadeRadius = 80 + 15 * level,
  }
end

-- patrol cars of our own beyond the map's base patrols: one more per heat level, at night only
function M.extraPatrols(ph, level)
  if ph ~= 'night' then return 0 end
  return math.max(0, math.min(5, math.floor(tonumber(level) or 0)))
end

-- the reputation multiplier of the night: +15 % a level
function M.repBoost(ph, level)
  if ph ~= 'night' then return 1 end
  return 1 + 0.15 * math.max(0, math.min(5, math.floor(tonumber(level) or 0)))
end

-- what a bust costs: the base fine, +25 % a level (at night); a day fine is the base and nothing else
function M.fine(base, ph, level)
  if ph ~= 'night' then return base end
  return math.floor(base * (1 + 0.25 * math.max(0, math.min(5, level or 0))) / 10 + 0.5) * 10
end

-- from level 4 a bust impounds the car whether you can pay or not; the fee grows with the level
function M.impounds(ph, level) return ph == 'night' and (level or 0) >= 4 end
function M.impoundFee(level) return 600 + 200 * math.max(0, (level or 0) - 3) end

-- reputation earned since the last bank is at risk, at night
function M.atRisk(ph, rep, banked)
  if ph ~= 'night' then return 0 end
  return math.max(0, (rep or 0) - (banked or 0))
end

-- a bust: the unbanked reputation is lost. Returns the new reputation and how much went.
function M.afterBust(ph, rep, banked)
  local lost = M.atRisk(ph, rep, banked)
  return (rep or 0) - lost, lost
end

-- heat after a time of nobody being after you (minutes); only at night, and never below 0
function M.cooled(heat, minutes)
  return math.max(0, (heat or 0) - M.COOL_PER_MINUTE * (minutes or 0))
end

function M.raised(heat, amount) return math.max(0, math.min(1, (heat or 0) + amount)) end

M.level = phase.heatLevel

return M
