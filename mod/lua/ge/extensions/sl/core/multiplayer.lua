-- Street Legal: multiplayer (BeamMP) awareness (#52). Pure, tested by tools/luatest.js. The career spawns and removes cars, moves the player and keeps its own
-- clock, none of which belongs in a shared server session, so it is single-player: it does not start while a session is on, and one that is running when
-- the player joins a server is saved and stopped. BeamMP's client puts MPCoreNetwork and MPGameNetwork in the game's Lua; either says there is a session.

local M = {}

local strings = require('sl/core/strings')

M.NOTE = strings.t('multiplayer.the_street_legal_career_is')

-- core: the MPCoreNetwork table (or nil), game: the MPGameNetwork table (or nil). Never raises.
function M.inSession(core, game)
  local ok, yes = pcall(function()
    if type(core) == 'table' and type(core.isMPSession) == 'function' and core.isMPSession() == true then return true end
    if type(game) == 'table' and type(game.connectionStatus) == 'function' and game.connectionStatus() == 1 then return true end
    return false
  end)
  return ok and yes == true
end

return M
