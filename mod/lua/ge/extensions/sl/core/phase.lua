-- Street Legal: the day and the night (D1). Pure game rules, no engine calls (tested by tools/luatest.js).
-- The career is in one of two phases. Day (07:00 to 19:00) is the legal half, night (21:00 to 04:00) the street half. The clock runs slowly
-- inside a phase and STOPS at the phase's end until the player switches (at a garage or in the phone's Wait app): a phase never rolls over by
-- itself in the middle of something. Dusk (19-21) and dawn (04-07) are only the jump between the two.
-- Hours are the in-game hour, 0..24.

local M = {}

M.DAY = { from = 7, to = 19 }
M.NIGHT = { from = 21, to = 4 }       -- the night crosses midnight

-- real seconds for one in-game day (24 h) by the Clock setting: slow = 2.5 real minutes per hour
M.CLOCKS = { slow = 3600, normal = 1800, fast = 900 }
M.DEFAULT_CLOCK = 'slow'
function M.dayLength(clock) return M.CLOCKS[clock] or M.CLOCKS[M.DEFAULT_CLOCK] end

function M.other(phase) return phase == 'night' and 'day' or 'night' end
function M.title(phase) return phase == 'night' and 'Night' or 'Day' end
function M.switchLabel(phase) return phase == 'night' and 'Start the day' or 'Start the night' end    -- the button, from the phase NOW
function M.startHour(phase) return phase == 'night' and M.NIGHT.from or M.DAY.from end
function M.endHour(phase) return phase == 'night' and M.NIGHT.to or M.DAY.to end

-- The sky follows the real sun for the level's place and date (core_celestial), and the levels' authored dates are summer ones: Valo City is
-- the engine default (47 N, 8 E, 20 June: the sun sets at 21:30 local) and West Coast USA is 22 June (sunset 20:35). A night starting at 21:00 would
-- begin in daylight. The career moves the date to the spring equinox: sunrise about 06:30 and sunset about 18:30 (Valo), 07:10 and 19:20 (West
-- Coast), so the day phase (07:00-19:00) is the daylight and the night phase (21:00-04:00) is dark.
M.SKY_DATE = { year = 2026, month = 3, day = 20 }

-- is the sun expected below the horizon at this hour (the night phase's hours)? Used to check the sky after a jump of the clock.
function M.isDarkHour(h) return h >= M.NIGHT.from or h < M.NIGHT.to end

-- heat as the player sees it, 0 (none) to 5: the police's attention (sl_police keeps it 0..1)
function M.heatLevel(heat)
  heat = tonumber(heat) or 0
  if heat < 0.02 then return 0 end
  return math.min(5, math.ceil(heat * 5))
end

-- is the clock inside the phase's running hours?
local function running(phase, h)
  if phase == 'night' then return h >= M.NIGHT.from or h < M.NIGHT.to end
  return h >= M.DAY.from and h < M.DAY.to
end
function M.ended(phase, h) return not running(phase, h) end

-- an old save has no phase: the one its hour is in (dusk and dawn count to the half they lead into: 20-04 night)
function M.infer(h)
  h = tonumber(h) or 10
  return (h >= 20 or h < 5) and 'night' or 'day'
end

-- the hour the clock holds at when it is outside the phase: the phase's end if it ran out, its start if it has not begun
function M.fit(phase, h)
  if running(phase, h) then return h end
  if phase == 'night' then return (h >= M.NIGHT.to and h < 12) and M.NIGHT.to or M.NIGHT.from end
  return h >= M.DAY.to and M.DAY.to or M.DAY.from
end

-- waiting a few hours (the Wait app): never past the end of the phase. Returns { hours, to } or nil and the reason.
M.WAITS = { ['1'] = true, ['3'] = true, ['6'] = true }
function M.waitPlan(phase, h, what)
  what = tostring(what)
  if not M.WAITS[what] then return nil, 'Wait how long?' end
  if not running(phase, h) then return nil, phase == 'night' and 'The night is over. Start the day.' or 'The day is over. Start the night.' end
  local hours = tonumber(what)
  local left = (M.endHour(phase) - h) % 24
  if hours >= left then return { hours = left, to = M.endHour(phase), ends = true } end
  return { hours = hours, to = (h + hours) % 24 }
end

-- switching: day to night or night to day. Returns { to (the hour), day (true: the day counter goes up) } or nil and the reason.
-- state = { racing, job, heat } as progression.skipRefusal
function M.switchPlan(phase, state)
  state = state or {}
  if state.racing then return nil, 'Not in the middle of a race.' end
  if state.job then return nil, 'Finish the job you are on first.' end
  if (state.heat or 0) > 0.3 then return nil, 'The police are after you. Lose them first.' end
  local to = M.other(phase)
  return { phase = to, to = M.startHour(to), day = to == 'day' }
end

return M
