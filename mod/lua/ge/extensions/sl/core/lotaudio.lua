-- Street Legal: the sound of cars while a lot is being made (T44). Pure, tested by tools/luatest.js. The game's vehicle audio channels
-- go quiet for the build (cars spawning, rebuilding and being dented are loud and ugly to listen to) and come back after. The change is
-- the game's temporary one (Engine.Audio.setChannelVolume(channel, volume, true): not stored in the player's settings), and the volume
-- it comes back to is the player's own setting (getChannelVolume(channel, false)), read again at the end, so nothing needs remembering:
-- a restore that runs twice, or after a crash and a restart, puts back what the player chose.

local M = {}

-- every channel a car makes sound on (not the master, the music, the interface or the environment)
M.CHANNELS = { 'AudioChannelPower', 'AudioChannelForcedInduction', 'AudioChannelTransmission', 'AudioChannelSuspension', 'AudioChannelAero',
  'AudioChannelCollision', 'AudioChannelSurface', 'AudioChannelLfe' }

-- audio = { get = function(channel) -> the player's volume, set = function(channel, volume) }
function M.mute(audio)
  for _, ch in ipairs(M.CHANNELS) do pcall(audio.set, ch, 0) end
end

function M.restore(audio)
  for _, ch in ipairs(M.CHANNELS) do
    local ok, v = pcall(audio.get, ch)
    if ok and type(v) == 'number' then pcall(audio.set, ch, v) end
  end
end

return M
