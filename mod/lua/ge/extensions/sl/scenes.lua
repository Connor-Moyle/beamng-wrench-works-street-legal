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
  guihooks.trigger('slScene', spec)
  return spec.hold
end

-- wait out what is left of a scene's hold (inside a job); a skip ends it at once
function M.hold(job, seconds)
  local left = tonumber(seconds) or 0
  while left > 0 and not skipped do
    job.sleep(0.1)
    left = left - 0.1
  end
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
