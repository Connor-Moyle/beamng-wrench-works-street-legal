-- Street Legal: fuel range (campaign expansion #9; the control repo's docs/FUEL_RANGE.md). Pure, no game calls: tested by tools/luatest.js.
-- The game burns the fuel (the tank's litres drop as the car runs); this only watches the drop. A track keeps the litres and the kilometres of the last WINDOW km of a car, the consumption is the
-- litres used over that distance (blended with a default until there is enough distance to trust), the range is the litres left over it, and a level says how worried to be.

local M = {}

M.WINDOW = 15            -- km of driving the consumption is taken over
M.TRUST_KM = 3           -- km of data at which the observed consumption counts in full
M.DEFAULT_L100 = 9       -- litres per 100 km until the car has shown what it uses
M.REFUEL_LITRES = 0.5    -- a rise of the litres by more than this is a refuel: the window starts again
M.LOW_FRAC, M.CRITICAL_FRAC = 0.15, 0.05
M.LOW_KM, M.CRITICAL_KM = 40, 10
M.EMPTY_LITRES = 0.3

function M.newTrack() return { samples = {} } end

-- one report: the kilometres the car has done in all (its odometer for this) and the litres in the tank now
function M.push(track, km, litres)
  if type(km) ~= 'number' or type(litres) ~= 'number' then return end
  local s = track.samples
  local last = s[#s]
  if last then
    if km < last.km - 0.001 then s = {} track.samples = s last = nil              -- (the odometer went back: a different car or a reset)
    elseif litres > last.litres + M.REFUEL_LITRES then s = {} track.samples = s last = nil end
  end
  s[#s + 1] = { km = km, litres = litres }
  while #s > 2 and s[#s].km - s[1].km > M.WINDOW do table.remove(s, 1) end
end

-- litres per km observed over the window, or nil when there is no distance or nothing was burnt yet; and the distance it is based on
function M.observed(track)
  local s = track.samples
  if #s < 2 then return nil, 0 end
  local km = s[#s].km - s[1].km
  local used = s[1].litres - s[#s].litres
  if km < 0.2 then return nil, km end
  if used <= 0 then return nil, km end
  return used / km, km
end

-- litres per km to plan with: the observed figure in proportion to how much distance backs it, the default for the rest
function M.consumption(track, defaultL100)
  local def = (defaultL100 or M.DEFAULT_L100) / 100
  local obs, km = M.observed(track)
  if not obs then return def, false end
  local w = math.min(1, km / M.TRUST_KM)
  return obs * w + def * (1 - w), true
end

-- the range in km for the litres left, or nil when the consumption is not positive
function M.range(litres, perKm)
  if type(litres) ~= 'number' or type(perKm) ~= 'number' or perKm <= 0 then return nil end
  return math.max(0, litres / perKm)
end

-- 'ok' | 'low' | 'critical' | 'empty', from the tank's fraction, the litres and the range
function M.level(frac, litres, rangeKm)
  if type(litres) == 'number' and litres < M.EMPTY_LITRES then return 'empty' end
  if type(frac) ~= 'number' then return 'ok' end
  if frac < M.CRITICAL_FRAC or (rangeKm and rangeKm < M.CRITICAL_KM) then return 'critical' end
  if frac < M.LOW_FRAC or (rangeKm and rangeKm < M.LOW_KM) then return 'low' end
  return 'ok'
end

M.RANK = { ok = 0, low = 1, critical = 2, empty = 3 }

-- the level worsened (a toast is due) against the last one told; a refuelled car (ok) starts again
function M.worse(new, told)
  return (M.RANK[new] or 0) > (M.RANK[told] or 0)
end

-- the range as the dashboard writes it: rounded to 5 km under 100, to 10 above; nil without a range
function M.display(rangeKm)
  if type(rangeKm) ~= 'number' then return nil end
  if rangeKm < 100 then return math.floor(rangeKm / 5 + 0.5) * 5 end
  return math.floor(rangeKm / 10 + 0.5) * 10
end

return M
