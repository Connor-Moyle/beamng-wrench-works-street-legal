-- Street Legal: a lot's row built ahead of time (sl_lotpre). Pure rules, tested by tools/luatest.js.
-- The row of the nearest lot is built while the screen is black (the career start, a fast travel, a cab ride) and kept inactive at its spots;
-- the lot activates it when it opens, so the stalls of building are never seen. One store at a time, for one lot and one day.

local M = {}

M.WITHIN = 500          -- m: the lot to build ahead is the nearest one this close to where the player arrives
M.MAX_BUILD_S = 12      -- s of building behind one fade; the lot builds what is left when it opens
M.LOT_KINDS = { junkyard = true, dealer = true, scrapyard = true }

-- the offer ids of a row, in order (what a store is keyed by)
function M.ids(offers)
  local out = {}
  for i, o in ipairs(offers or {}) do out[i] = tostring(o.id) end
  return out
end

-- does a store hold this lot's row for today?
function M.matches(store, placeId, day, offers)
  if not store or store.placeId ~= placeId or store.day ~= day then return false end
  local ids = M.ids(offers)
  if #ids ~= #store.ids then return false end
  for i, id in ipairs(ids) do if store.ids[i] ~= id then return false end end
  return true
end

-- the lot to build ahead: `place` when it is a lot, else the nearest lot kind within `within` m of pos. places: id -> { id, kind, pos, stock }
function M.pick(place, places, pos, within)
  if place and (M.LOT_KINDS[place.kind] or place.stock) then return place end
  if not pos then return nil end
  local best, bd
  for _, p in pairs(places or {}) do
    if (M.LOT_KINDS[p.kind] or p.stock) and p.pos then
      local d = math.sqrt((p.pos.x - pos.x) ^ 2 + (p.pos.y - pos.y) ^ 2)
      if d <= (within or M.WITHIN) and (not bd or d < bd) then best, bd = p, d end
    end
  end
  return best
end

-- how many cars a lot shows: the day's count capped by the setting (the Performance preset shows 4)
function M.cap(count, setting)
  local c = tonumber(setting)
  if not c then return count end
  return math.max(1, math.min(count, math.floor(c)))
end

-- a new store for a lot's row
function M.newStore(placeId, day, offers) return { placeId = placeId, day = day, ids = M.ids(offers), cars = {} } end

return M
