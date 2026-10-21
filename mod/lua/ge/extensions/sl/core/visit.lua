-- Street Legal: career travel, the rules of a visit to another map (docs/DESIGN_CAREER_TRAVEL.md sections 2 and 3). A visit is a state of the same career: s.visit = { active, level, event,
-- cars = { carId }, fromDay, untilDay, round, rounds, home }. The chosen cars go with the player, every other car waits in the home garage; the visit ends by the way back (always possible),
-- by its last day, or at the next start after a crash (the player is asked first, or sent home when it is over). Pure, no game calls: tested by tools/luatest.js.

local M = {}

local strings = require('sl/core/strings')

M.MAX_CARS = 3
M.FEE_PER_CAR = 200          -- the transporter, on the way out only
M.TRAVEL_HOURS = 6

function M.fee(entry, nCars) return (entry or 0) + M.FEE_PER_CAR * (nCars or 0) end

-- can these cars go? s is the career state; carIds the chosen ids. Returns ok, or false and the reason.
function M.validate(s, carIds, fits)
  if type(carIds) ~= 'table' or #carIds == 0 then return false, strings.t('visit.no_cars') end
  if #carIds > M.MAX_CARS then return false, strings.t('visit.too_many', M.MAX_CARS) end
  local seen = {}
  for _, id in ipairs(carIds) do
    if seen[id] then return false, strings.t('visit.same_car_twice') end
    seen[id] = true
    local car
    for _, c in ipairs(s.cars or {}) do if c.id == id then car = c end end
    if not car then return false, strings.t('visit.no_such_car') end
    if car.impounded then return false, strings.t('visit.car_impounded', car.name or '?') end
    if fits and not fits(car) then return false, strings.t('visit.car_does_not_fit', car.name or '?') end
  end
  return true
end

-- a new visit
function M.new(spec)
  return { active = true, level = spec.level, event = spec.event, series = spec.series, firstDay = spec.firstDay or spec.day, cars = spec.cars, fromDay = spec.day, untilDay = spec.untilDay, round = spec.round or 1,
    rounds = spec.rounds or 1, home = spec.home }
end

-- the start of a career whose save holds a visit: 'none' (no visit), 'home' (it is over or its map is gone: go home by itself, the event counts as missed) or 'ask' (the player chooses)
function M.recover(visit, day, installed)
  if type(visit) ~= 'table' or not visit.active then return 'none' end
  if not installed or (visit.untilDay and day > visit.untilDay) then return 'home' end
  return 'ask'
end

-- the cars leave home: the chosen ones are marked and keep their record; every other car is put in the garage (out = false, no place in the world). Each chosen car gets `visit = true`.
function M.depart(s, visit)
  local chosen = {}
  for _, id in ipairs(visit.cars) do chosen[id] = true end
  for _, car in ipairs(s.cars or {}) do
    if chosen[car.id] then
      car.visit, car.out, car.where = true, true, nil           -- (built at the paddock on arrival)
    else
      car.visit, car.out, car.where = nil, false, nil
    end
  end
  s.visit = visit
end

-- the visit is over (back home, or recovered): every car goes to the garage, the visit is gone. Returns the visit that was.
function M.finish(s)
  local was = s.visit
  for _, car in ipairs(s.cars or {}) do
    car.visit, car.out, car.where = nil, false, nil
  end
  s.visit = nil
  return was
end

-- the paddock: where the visit's cars stand on arrival, in a row beside the player; pos = { x, y, z }, dir = { x, y } the way the player faces. Returns { { pos, rot } } for n cars (rot: x, y, z, w)
function M.paddock(pos, dir, n)
  local len = math.sqrt(dir.x * dir.x + dir.y * dir.y)
  local fx, fy = dir.x / (len > 0 and len or 1), dir.y / (len > 0 and len or 1)
  if len == 0 then fx, fy = 0, 1 end
  local rx, ry = fy, -fx                       -- to the right of the player
  local out = {}
  for i = 1, n do
    local d = 4 + (i - 1) * 3.2
    out[i] = { pos = { x = pos.x + rx * d + fx * 2, y = pos.y + ry * d + fy * 2, z = (pos.z or 0) + 0.5 }, face = { x = fx, y = fy } }
  end
  return out
end

return M
