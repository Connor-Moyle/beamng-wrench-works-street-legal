-- Wrench Works: Street Legal: race replays (extension name: sl_replay; #48)
-- A street race is recorded with BeamNG's own replay (core_replay) from its start line to its end. Afterwards the phone's Races page offers
-- "Watch replay" (the game's replay opens at the start of the race) and "Save clip" (the file is renamed after the race, so it is kept; the
-- last race's replay that was not saved is deleted when the next race starts). Off in the Settings app: 'Record street races'.

local M = {}

local strings = require('sl/core/strings')

local lib = require('sl/core/replay')

local last                 -- { name, file, saved } the last recorded race
local recording            -- the file being recorded now

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function enabled() return not (sl_options and sl_options.get) or sl_options.get('slReplay') ~= false end
local function say(text) guihooks.trigger('slPhoneToast', { text = text }) end

local function start()
  if recording or not enabled() or not career() or not core_replay or not core_replay.startRecording then return end
  local state = core_replay.getState and core_replay.getState()
  if state == 'recording' or state == 'playback' then return end         -- (your own recording, or a replay being watched)
  if last and not last.saved and last.file then pcall(core_replay.removeRecording, last.file) end      -- (only the last race is kept, until it is saved)
  last = nil
  local ok, res = pcall(core_replay.startRecording)
  if ok and type(res) == 'table' and res.success and res.filename then recording = res.filename end
end
M.onStreetLegalRaceStarted = start
M.onSlrrRaceStarted = start

local function stop(r)
  if not recording then return end
  local file = recording
  recording = nil
  local ok, res = pcall(core_replay.stopRecording)
  if ok and type(res) == 'table' and res.success then
    last = { name = lib.raceName(r), file = res.filename or file, saved = false }
    guihooks.trigger('slPhoneToast', { text = 'Race recorded: Watch replay or Save clip in the Races app.' })
    extensions.hook('onStreetLegalChanged')
  end
end
M.onSlrrRaceFinished = stop
function M.onStreetLegalRaceResult() end                      -- (the finish itself is onSlrrRaceFinished; kept so a module that reports only this still stops)
M.onStreetLegalStopped = function() recording = nil end

-- the phone's view
function M.summary()
  if not last or not last.file then return nil end
  return { name = last.name, saved = last.saved == true }
end

-- the game's replay opens on the race, from its start
function M.watch()
  if not last or not last.file or not core_replay or not core_replay.loadFile then return false, strings.t('replay.no_race_recorded') end
  if not FS:fileExists(last.file) then return false, strings.t('replay.that_replay_is_gone') end
  local ok, res = pcall(core_replay.loadFile, last.file, true)
  if not ok or (type(res) == 'table' and res.success == false) then return false, strings.t('replay.the_replay_would_not_open') end
  return true, 'Replay: ' .. last.name .. '.'
end

-- keep it: named after the race
function M.save()
  if not last or not last.file or last.saved then return false, last and 'Already saved.' or 'No race recorded.' end
  local name = lib.clipName(last.name, os.date('%Y-%m-%d %H-%M'))
  local ok, res = pcall(core_replay.acceptRename, last.file, name)
  if not ok or type(res) ~= 'table' or res.success ~= true then return false, strings.t('replay.could_not_save_the_clip') end
  last.file = type(res.newFilename) == 'string' and res.newFilename or ((last.file:match('^(.*/)') or 'replays/') .. name .. '.rpl')
  last.saved = true
  extensions.hook('onStreetLegalChanged')
  return true, 'Saved as "' .. name .. '" in the game\'s replays.'
end

return M
