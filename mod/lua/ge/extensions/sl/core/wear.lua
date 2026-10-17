-- Street Legal: part wear (#30). Pure, tested by tools/luatest.js. The parts of a car you own age with the kilometres you drive it and with
-- how you drive it: the car (slCar) counts the abuse, here it is turned into condition lost per section, on top of the condition and the faults
-- the car came with. It is shown in the car report (sl/core/carreport) of every car of yours.

local M = {}

-- kilometres of normal use a section lasts: at this many (since you bought it) it has lost MAX_LOSS of its condition
M.LIFE = { engine = 400000, drivetrain = 350000, suspension = 250000, brakes = 120000, wheels = 60000 }
M.MAX_LOSS = 0.5

-- what one unit of each kind of abuse costs, in kilometres of normal use: engine: a second at the rev limiter (or three overheating),
-- brakes: a hard stop from speed, drive: a second of a launch, susp: a hard landing or bump
M.ABUSE_KM = { engine = 1.5, brakes = 6, drive = 3, susp = 4 }

-- which kinds of abuse wear which section (the tyres take the hard stops and the launches too, lighter)
local SECTION_ABUSE = {
  engine = { engine = 1 }, drivetrain = { drive = 1 }, suspension = { susp = 1 }, brakes = { brakes = 1 }, wheels = { brakes = 0.5, drive = 0.5 },
}

-- km driven since the car became yours, and the abuse counters
function M.kmSince(engineKm, mileage) return math.max(0, (tonumber(engineKm) or 0) - (tonumber(mileage) or 0)) end

-- condition lost (0..MAX_LOSS) per section id: engine, drivetrain, suspension, brakes, wheels
function M.lost(km, abuse)
  abuse = type(abuse) == 'table' and abuse or {}
  local out = {}
  for section, life in pairs(M.LIFE) do
    local eq = km or 0
    for kind, share in pairs(SECTION_ABUSE[section]) do eq = eq + (tonumber(abuse[kind]) or 0) * M.ABUSE_KM[kind] * share end
    out[section] = M.MAX_LOSS * math.min(1, eq / life)
  end
  return out
end

-- (the car counts the abuse itself: sl_carcare.abuseSample, in the car's own Lua)

return M
