-- Wrench Works: Street Legal: the first fifteen minutes (extension name: sl_tutorial; BACKLOG X24)
-- A new career (unless started without it) walks the player through the real game: buy a car, do a
-- real part run, fit a first part, race a real low-stakes street race. Benny texts each step, the
-- phone's home screen shows it with a Skip button. Existing saves never get it (no s.tutorial).

local M = {}

local strings = require('sl/core/strings')

local stateLib = require('sl/core/state')
local roster = require('sl/core/roster')

local STEPS = {
  { id = 'car', title = 'Get a car', text = 'Take a cab (phone, Cab) to the junkyard and buy something that runs. Cheap is fine.',
    done = function(s) return #s.cars > 0 end },
  { id = 'job', title = 'Earn your first money', text = 'Open the Jobs app and take the first run on the board (a part run or a courier run): get it there in time, without wrecking the car.',
    start = function(s) M.ensureFirstJob(s) end,
    done = function(s) return (s.jobs and s.jobs.done or 0) > 0 end },
  { id = 'part', title = 'Fit a first part', text = 'Drive into your garage. In the catalog, "Under $1,500" shows what you can afford: buy one and fit it.',
    done = function(s) return s.jobs and s.jobs.upgraded end },
  { id = 'race', title = 'Your first race', text = 'I have set you up a race against somebody easy, $100. It is in the Races app: drive to the start and go.',
    start = function(s) M.arrangeFirstRace(s) end,
    done = function(s) return (s.stats and s.stats.races or 0) > 0 end },
}
M.STEPS = STEPS
local BONUS = 500

local timer = 0                        -- seconds since the steps were last looked at
local skipNext = false
function M.skipNextCareer() skipNext = true end          -- the chooser's "New career, no tutorial"

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

local function announce(s)
  local step = STEPS[s.tutorial.step]
  if not step then return end
  if step.start then pcall(step.start, s) end
  sl_career.sendText('benny', string.format('Step %d of %d: %s. %s', s.tutorial.step, #STEPS, step.title, step.text), 2)
  extensions.hook('onStreetLegalChanged')
end

-- a new career starts it; a continued one only carries on with one already running
function M.onStreetLegalStarted(fresh)
  local s = career()
  if not s then return end
  if fresh then
    if skipNext then s.tutorial = { skipped = true } else s.tutorial = { step = 1 } announce(s) end
    skipNext = false
  end
end

function M.begin()                     -- (for the smoke test: on any career)
  local s = career()
  if not s then return false end
  s.tutorial = { step = 1 }
  timer = 0                            -- (a full second to the first look: one step a second, however it is begun)
  announce(s)
  return true
end

function M.skip()
  local s = career()
  if not s or not s.tutorial or s.tutorial.done then return end
  s.tutorial.skipped, s.tutorial.step = true, nil
  sl_career.sendText('benny', strings.t('tutorial.fair_enough_you_know_your'), 1)
  extensions.hook('onStreetLegalChanged')
end

-- the run the second step needs: a part run or a courier run on the board even if the day's offers had none (a map
-- with no parts shops, as West Coast USA, has no part runs at all)
function M.ensureFirstJob(s)
  if not sl_jobs or not sl_jobs.TYPES then return end
  local js = s.jobs or {}
  for _, j in ipairs(js.offers or {}) do if j.kind == 'part' or j.kind == 'courier' then return end end
  sl_jobs.summary()                                    -- (makes today's board, if not yet made)
  js = s.jobs
  for _, kind in ipairs({ 'part', 'courier' }) do
    for _, t in ipairs(sl_jobs.TYPES) do
      if t.kind == kind then
        local ok, j = pcall(t.offer, sl_jobs.context and sl_jobs.context(s) or nil, require('sl/core/rng').new(s.day * 7 + 1))
        if ok and j and j.legs then
          j.id, j.kind, j.title = 'tutorial:job', kind, t.title
          table.insert(js.offers, 1, j)
          return
        end
      end
    end
  end
end
M.ensurePartRun = M.ensureFirstJob

-- the fourth step's race: the easiest racer the player knows of (or the easiest there is), $100, near by
function M.arrangeFirstRace(s)
  local easiest
  for _, r in ipairs(s.racers) do
    if not r.nightOnly and (not easiest or r.tier < easiest.tier or (r.tier == easiest.tier and r.skill < easiest.skill)) then easiest = r end
  end
  local race = sl_career.nearestRace and sl_career.nearestRace(false)
  if not easiest or not race then
    sl_career.sendText('benny', strings.t('tutorial.no_easy_race_round_here'), 20)
    return
  end
  s.known[easiest.id] = true
  for i = #s.challenges, 1, -1 do if s.challenges[i].racer == easiest.id then table.remove(s.challenges, i) end end
  s.challenges[#s.challenges + 1] = { id = easiest.id .. ':tutorial', racer = easiest.id, stake = 'money', bet = 100, race = race.id,
    raceName = race.name, missionId = race.missionId, at = os.time() }
  sl_career.sendText(easiest.id, 'Benny says you are new. $100, ' .. race.name .. '. Nothing fancy.', 20)
end

-- on to the next step while the current one is met: one step a call (a career that already has jobs done, a part fitted
-- or races run, as the smoke test's, still walks through the steps one at a time, each announced)
function M.advance(s)
  local t = s and s.tutorial
  local step = t and t.step and STEPS[t.step]
  if not step then return end
  local ok, done = pcall(step.done, s)
  if not (ok and done) then return end
  t.step = t.step + 1
  if t.step > #STEPS then
    t.step, t.done = nil, true
    sl_career.addMoney(BONUS, sl_career.mapText('Welcome to Valo City'))
    sl_career.sendText('benny', string.format('That is the lot: a car, a job, a part, a race. $%d from me to get you going. Now go and make a name.', BONUS), 2)
    extensions.hook('onStreetLegalChanged')
  else
    announce(s)
  end
end

function M.onUpdate(dt)
  timer = timer + dt
  if timer < 1 then return end
  timer = 0
  M.advance(career())
end

-- for the phone's home screen
function M.summary()
  local s = career()
  local t = s and s.tutorial
  local step = t and t.step and STEPS[t.step]
  if not step then return nil end
  return { step = t.step, total = #STEPS, title = step.title, text = step.text }
end

return M
