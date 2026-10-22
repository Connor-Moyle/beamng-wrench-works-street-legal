-- Street Legal: the career's own simple tyre wear, for a game without Car Surface FX's tyre system (docs/CAREER_EXPANSION.md #10). Pure, no game calls: the car (slCar) uses
-- hardness() and the factors, the game side (sl/tyrecare) keeps the sets. A set is four tread values 1 (new) .. 0 (down to the belts); distance and hard use wear them, a worn tyre
-- grips a little less. It is deliberately mild and short-lived compared to the real thing: the lives below are the career's, chosen so a set means something in a few hours of play.
-- It is OFF whenever Car Surface FX's tyre system is present (sl/tyrecare decides), so the two never stack.

local M = {}

local function clamp(x, lo, hi) return x < lo and lo or (x > hi and hi or x) end

-- km of ordinary driving a set lasts, by compound (the compound ids are those of sl/core/tyres)
M.LIFE = { road = 260, performance = 190, winter = 220, intermediate = 200, fullwet = 200, offroad = 240, mud = 200, rally = 160, semislick = 120, slick = 90, slicksoft = 70, drag = 40 }
-- the grip of the fresh tyre against the car's own: a little for the sporting compounds, nothing for the rest (the weather and the surface are the game's)
M.BONUS = { performance = 1.04, semislick = 1.07, slick = 1.10, slicksoft = 1.12, drag = 1.05 }
M.MAX_LOSS = 0.20             -- the grip lost by a tyre worn to the belts, as a share
M.HARD_FROM, M.HARD_RANGE, M.HARD_MAX = 3, 7, 3        -- m/s2 of acceleration (any direction) where hard use starts, how far to full, and the most a km counts for

function M.life(compound) return M.LIFE[compound] or M.LIFE.road end

-- how many km a km counts for at this acceleration (m/s2, the size of the change of velocity over a short time): 1 when cruising, up to HARD_MAX when it is braked, thrown or accelerated hard
function M.hardness(accel)
  local a = tonumber(accel) or 0
  return 1 + (M.HARD_MAX - 1) * clamp((a - M.HARD_FROM) / M.HARD_RANGE, 0, 1)
end

-- a new set: tread 1 on every wheel (n wheels). The treads are a plain list 1..n (wheel index + 1) so the save keeps them as a list
function M.newSet(n)
  local treads = {}
  for i = 1, (n or 4) do treads[i] = 1 end
  return { treads = treads }
end

-- wear the set by km of hard-weighted driving on `compound`; returns true when any tread moved by at least 0.0005 (so the game side knows to look at the factors)
function M.wear(set, compound, effKm)
  local d = (tonumber(effKm) or 0) / M.life(compound)
  if d <= 0 or type(set) ~= 'table' then return false end
  for i, t in ipairs(set.treads) do set.treads[i] = clamp(t - d, 0, 1) end
  return d >= 0.0005
end

-- the grip of a tyre with this much tread left, as a share of the new tyre
function M.gripAt(frac)
  frac = clamp(tonumber(frac) or 1, 0, 1)
  return 1 - M.MAX_LOSS * (1 - frac) ^ 1.5
end

-- the factor per wheel the car applies to its tread nodes: { [wheel index 0..n-1] = factor }, to two decimals
function M.factors(set, compound)
  local out = {}
  local bonus = M.BONUS[compound] or 1
  for i, t in ipairs(set and set.treads or {}) do out[i - 1] = math.floor(bonus * M.gripAt(t) * 100 + 0.5) / 100 end
  return out
end

-- the wheels of a car as the tyre screens want them: from the names the car reports ({ [index] = 'FL' | 'FR' | 'RL' | 'RR' | other }); an unnamed or odd car gets its wheels in the order
-- front left, front right, rear left, rear right, then rear pairs
function M.layout(names, n)
  local out = {}
  local count = n or 4
  for i = 0, count - 1 do
    local name = names and names[i] and tostring(names[i]):upper() or ''
    local axle, side = name:match('^([FR])([LR])$')
    if axle then
      out[#out + 1] = { idx = i, axle = axle == 'F' and 'front' or 'rear', side = side == 'L' and 'left' or 'right' }
    else
      out[#out + 1] = { idx = i, axle = i < 2 and 'front' or 'rear', side = (i % 2 == 0) and 'left' or 'right' }
    end
  end
  return out
end

-- the same shape carSurfaceFx_tyres.getTyres() answers, so the career's tyre screens read it unchanged
function M.raw(set, compound, wheels)
  local rows = {}
  for _, w in ipairs(wheels or M.layout(nil, 4)) do
    rows[#rows + 1] = { idx = w.idx, axle = w.axle, side = w.side, frac = set and set.treads and set.treads[w.idx + 1] or 1, compound = compound, flat = 0, blown = false }
  end
  return { compound = compound, wheels = rows }
end

return M
