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

-- the short moments (banners over the live game: bars, a big title; no black screen, nothing held): style -> hold seconds, text keys, tone (the UI's colour), cues
M.BANNERS = {
  busted = { hold = 2.6, title = 'scenes.busted', sub = 'scenes.busted_sub', tone = 'bad', cues = { { at = 0, event = 'event:>UI>Career>Drift_Canceled' } } },
  impound = { hold = 2.4, title = 'scenes.impound', sub = 'scenes.impound_sub', tone = 'bad', cues = { { at = 0, event = 'event:>UI>Career>Drift_Canceled' } } },
  pinkwin = { hold = 2.8, title = 'scenes.pinkwin', sub = 'scenes.pinkwin_sub', tone = 'good', cues = { { at = 0, event = 'event:>UI>Career>EndScreen_Receive_Money' } } },
  pinklose = { hold = 2.8, title = 'scenes.pinklose', sub = 'scenes.pinklose_sub', tone = 'bad', cues = { { at = 0, event = 'event:>UI>Career>Drift_Canceled' } } },
  heat = { hold = 2.0, title = 'scenes.heat', sub = 'scenes.heat_sub', tone = 'warn', cues = { { at = 0, event = 'event:>UI>Career>Drift_Tier' } } },
  reveal = { hold = 2.6, title = 'scenes.reveal', sub = 'scenes.reveal_sub', tone = 'good', cues = { { at = 0, event = 'event:>UI>Career>Buy_01' } } },
  tier = { hold = 3.0, title = 'scenes.tier', sub = 'scenes.tier_sub', tone = 'good', cues = { { at = 0, event = 'event:>UI>Career>EndScreen_Receive_XP' } } },
  garage_in = { hold = 1.6, title = 'scenes.garage_in', sub = 'scenes.garage_sub', tone = 'plain', cues = {} },
  garage_out = { hold = 1.4, title = 'scenes.garage_out', sub = 'scenes.garage_out_sub', tone = 'plain', cues = {} },
  reminder = { hold = 3.0, title = 'scenes.reminder', sub = 'scenes.reminder_sub', tone = 'warn', cues = { { at = 0, event = 'event:>UI>Missions>Info_Open' } } },
  count = { hold = 0.9, title = 'scenes.count', tone = 'warn', cues = { { at = 0, event = 'event:>UI>Main>Click_Tonal_01' } } },
  go = { hold = 1.0, title = 'scenes.go', tone = 'good', cues = { { at = 0, event = 'event:>UI>Missions>Checkpoint' } } },
}

-- a banner's spec: nil for an unknown style. data: { name, level, n, day }. Under reduce motion the same card, with no movement and the same hold (the UI does the rest).
function M.banner(style, data, reduce, t)
  local b = M.BANNERS[style]
  if not b then return nil end
  data = data or {}
  local name = data.name and tostring(data.name) or ''
  local title = b.title and t(b.title, tonumber(data.n) or tonumber(data.level) or name) or ''
  return {
    kind = 'banner', style = style, tone = b.tone, reduce = reduce == true, hold = b.hold, title = title,
    subtitle = b.sub and t(b.sub, name, tonumber(data.level) or '') or '', cues = b.cues, skipHint = '',
  }
end

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
