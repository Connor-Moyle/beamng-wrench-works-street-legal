-- Street Legal: the rules of the cinematic moments (docs/TRANSITIONS.md). Pure: no game calls. A moment is a short full-screen scene the UI plays while the game
-- changes something behind it (the clock jumps to the night, the day starts). This file decides what is shown and for how long; sl/scenes.lua plays it.
local M = {}

-- seconds the scene holds the screen: the full one, and the reduced-motion one (a still title card)
M.KINDS = {
  night = { hold = 3.4, reduce = 1.4, title = 'scenes.night', sub = 'scenes.night_sub',
    cues = { { at = 0, event = 'event:>UI>Bigmap>Whoosh_In' }, { at = 1.3, event = 'event:>UI>Missions>Info_Open' } }, reduceCues = { { at = 0.1, event = 'event:>UI>Missions>Info_Open' } } },
  day = { hold = 3.0, reduce = 1.2, title = 'scenes.day', sub = 'scenes.day_sub',
    cues = { { at = 0, event = 'event:>UI>Bigmap>Whoosh_In' }, { at = 1.3, event = 'event:>UI>Missions>Checkpoint' } }, reduceCues = { { at = 0.1, event = 'event:>UI>Missions>Checkpoint' } } },
}

M.FADE_IN = 0.5          -- the screen goes dark under the scene this long before the game changes anything behind it
M.FADE_OUT = 0.6         -- and clears this long after it ends

-- what the UI is told: nil for a kind that has no scene. t = the strings function (key, ...) -> text
function M.spec(kind, data, reduce, t)
  local k = M.KINDS[kind]
  if not k then return nil end
  data = data or {}
  local day = tonumber(data.day) or 1
  return {
    kind = kind, reduce = reduce == true, hold = reduce and k.reduce or k.hold, fadeIn = M.FADE_IN, fadeOut = M.FADE_OUT,
    title = t(k.title), subtitle = t(k.sub, day), skipHint = t('scenes.skip'), day = day,
    cues = reduce and k.reduceCues or k.cues,      -- the game's own UI sounds, played by sl/scenes at their time (seconds since the scene began)
  }
end

-- a scene may be skipped once it has been up this long (not at the first instant: a key still held down from the menu must not cancel it)
M.SKIP_AFTER = 0.4

function M.canSkip(elapsed)
  return (tonumber(elapsed) or 0) >= M.SKIP_AFTER
end

return M
