-- Street Legal Racing: cinematic moments (extension name: sl_scenes). The big turns of the career ("Start the night", "Start the day") get a short full-screen scene:
-- the UI module ui/modModules/slScenes draws it (the sky and the city lights, a title card) and this side starts it, holds the game behind it and ends it.
-- Off with the "Cinematic moments" switch (Mods > Street Legal > Parts of the game), shortened to a still title card by "Reduce motion", and any key or click skips it.
-- Usage (sl/career.lua): local hold = sl_scenes and sl_scenes.begin('night', { day = 4 })   -- nil when there is no scene: do the plain fade
--                        ... change the world behind the dark screen ...
--                        sl_scenes.hold(job, hold)   -- waits out the rest of the scene (ends early when skipped)
--                        sl_scenes.finish()
-- The design and the list of moments: docs/TRANSITIONS.md.
local M = {}

local scenes = require('sl/core/scenes')
local strings = require('sl/core/strings')
local features = require('sl/core/features')

local active              -- the kind of the scene on the screen
local startedAt, skipped = 0, false
local cues, played = {}, 0     -- the sound cues of the scene, and how many were played

local function now() return (os.clockhp or os.clock)() end

local function reduced()
  local get = rawget(_G, 'sl_options') and sl_options.get
  return get ~= nil and get('slReduceMotion') == true
end

-- start a scene; returns the seconds it holds the screen, or nil when scenes are off (the caller does its plain fade)
function M.begin(kind, data)
  if active or not features.on('scenes') or not guihooks then return nil end
  local spec = scenes.spec(kind, data, reduced(), strings.t)
  if not spec then return nil end
  active, startedAt, skipped = kind, now(), false
  cues, played = spec.cues or {}, 0
  M.cue()
  guihooks.trigger('slScene', spec)
  return spec.hold
end

-- play the sounds that are due (the game's own UI sounds: nothing is shipped); a skipped scene plays no more
function M.cue()
  while played < #cues and not skipped and cues[played + 1].at <= now() - startedAt do
    played = played + 1
    local e = cues[played].event
    if Engine and Engine.Audio and Engine.Audio.playOnce and e then pcall(Engine.Audio.playOnce, 'AudioGui', e, { volume = 0.9 }) end
  end
end

-- wait out what is left of a scene's hold (inside a job); a skip ends it at once
function M.hold(job, seconds)
  local left = tonumber(seconds) or 0
  while left > 0 and not skipped do
    M.cue()
    job.sleep(0.1)
    left = left - 0.1
  end
  M.cue()
end

-- the whole flow of a scene around a change of the world: the screen darkens, move(job) changes the world behind it, release() is called AT ONCE after (whatever
-- happens next: a caller's lock is never held by the scene), the scene is held, then cleared. Returns true when a scene runs; false when there is none (the caller does its
-- plain fade). Nothing that fails in here can leave the screen covered or the caller's lock set: begin, move, hold and finish are each guarded.
function M.run(kind, data, move, release)
  if not (core_jobsystem and core_jobsystem.create) then return false end
  local okBegin, hold = pcall(M.begin, kind, data)
  if not okBegin or not hold then
    if not okBegin then M.finish() end
    return false
  end
  core_jobsystem.create(function(job)
    local okSleep = pcall(job.sleep, scenes.FADE_IN)
    local okMove, err = pcall(move, job)
    pcall(release)
    if okSleep then
      pcall(M.hold, job, math.max(0, hold - scenes.FADE_IN - 0.7))      -- (the fade in and the clock jump are already part of the hold)
      pcall(job.sleep, 0.1)
    end
    pcall(M.finish)
    if not okMove and log then log('E', 'sl_scenes', 'the change behind the scene failed: ' .. tostring(err)) end
  end)
  return true
end

-- the world behind the scene is done: the UI clears the screen
function M.finish()
  if not active then return end
  active = nil
  guihooks.trigger('slScene', { kind = 'end' })
end

-- the UI asks (a key or a click on the scene)
function M.skip()
  if active and scenes.canSkip(now() - startedAt) then skipped = true end
  return skipped
end

function M.isActive() return active end

function M.onStreetLegalStopped()
  if active then M.finish() end
end

return M
