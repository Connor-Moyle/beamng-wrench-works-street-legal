-- Street Legal: where a cab comes from and where it takes you (T46). Pure, tested by tools/luatest.js.
-- A cab starts on a road out of the player's sight and drives up (the game's AI); a ride to a lot (a dealer's car park, the used lot, the scrap
-- yard) ends in the lot's own arrival spot in front of its cars, not on the nearest road.

local M = {}

M.MIN_APPROACH = 100       -- m: the cab starts at least this far along the road (out of sight)...
M.MAX_APPROACH = 200       -- m: ...and not further (it must be with you in 20-40 s); no such road: the nearest lane, close by
M.FOV = 100                -- degrees across: what counts as in view (the camera's, with a margin)
M.IN_VIEW_UP_TO = 450      -- m: further than this nothing is "in view" (it is too far to see)

-- cands: roadspot candidates { x, y, dist } (nearest first); cam = { x, y, fx, fy } the camera's position and the way it looks (flat).
-- The first candidate far enough and not in view; nil when there is none (the caller then takes the nearest lane, as before).
function M.approach(cands, cam)
  local fl = math.sqrt((cam.fx or 0) ^ 2 + (cam.fy or 0) ^ 2)
  for _, c in ipairs(cands or {}) do
    if c.dist >= M.MIN_APPROACH and c.dist <= M.MAX_APPROACH then
      local dx, dy = c.x - cam.x, c.y - cam.y
      local d = math.sqrt(dx * dx + dy * dy)
      local inView = false
      if fl > 1e-6 and d > 1e-6 and d <= M.IN_VIEW_UP_TO then
        local cosA = (dx * cam.fx + dy * cam.fy) / (d * fl)
        inView = cosA > math.cos(math.rad(M.FOV / 2))
      end
      if not inView then return c end
    end
  end
  return nil
end

-- Boarding: walking up to the cab (within BOARD_RADIUS of its middle) gets you in at once; a cab that has stopped for you (hazards on) waits BOARD_DELAY
-- seconds and then takes you in if you are within AUTO_RADIUS of it (the ground marker leads you there), so a cab that pulled up on the road beside a
-- pavement is not left waiting for a walk the player does not know to make. Further away: it waits (and leaves after its five minutes, no fare).
M.BOARD_RADIUS, M.BOARD_DELAY, M.AUTO_RADIUS = 6, 4, 30
function M.boardNow(dist, hereFor)
  if type(dist) ~= 'number' then return false end
  if dist < M.BOARD_RADIUS then return true end
  return type(hereFor) == 'number' and hereFor >= M.BOARD_DELAY and dist <= M.AUTO_RADIUS
end

-- The fare is paid on arrival: what the player has covers it, or what is left of it (a ride is never refused after it was taken).
function M.fareDue(fee, money)
  return math.max(0, math.min(tonumber(fee) or 0, tonumber(money) or 0))
end

-- The spot a ride to this place ends at, for a lot: { x, y, z, dx, dy } (where the lot's cars are in front of you), else nil.
-- place: { pos, at (the arrival point before any lane nudge), dir, displays }; the kinds that are lots.
local LOTS = { dealer = true, junkyard = true, scrapyard = true }
function M.dropAt(place)
  if type(place) ~= 'table' or not LOTS[place.kind] then return nil end
  local p = place.at or place.pos
  if not p then return nil end
  local d = place.dir or { x = 0, y = 1 }
  return { x = p.x, y = p.y, z = p.z, dx = d.x, dy = d.y }
end

return M
