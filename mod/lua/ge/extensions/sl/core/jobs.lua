-- Street Legal: the rules of delivery gigs (part runs for the garages, courier parcels).
-- No game calls: places are { id, name, kind, x, y }; rng is sl/core/rng.

local M = {}

M.SPEED = 14            -- metres per second assumed for the time limit
M.SLACK = 1.35          -- time limit multiplier
M.MIN_SECONDS = 120
M.MIN_METRES = 400
M.PAY_PER_KM = 140
M.MIN_PAY = 120
M.FRAGILE_BONUS = 1.5
M.PART_ITEMS = { 'turbocharger', 'gearbox', 'set of wheels', 'exhaust manifold', 'radiator', 'bonnet', 'set of coilovers', 'ECU' }
M.PARCELS = { 'parcel', 'box of spark plugs', 'envelope', 'case of oil', 'tool box', 'crate of brake pads' }

local function round10(x) return math.floor(x / 10 + 0.5) * 10 end

function M.distance(a, b)
  return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

function M.make(kind, from, to, rng)
  local distance = M.distance(from, to)
  local item = kind == 'part' and M.PART_ITEMS[rng:int(#M.PART_ITEMS)] or M.PARCELS[rng:int(#M.PARCELS)]
  local fragile = rng:chance(kind == 'part' and 0.35 or 0.2)
  return {
    kind = kind, from = from.id, fromName = from.name, to = to.id, toName = to.name, item = item, fragile = fragile,
    metres = math.floor(distance),
    seconds = math.max(M.MIN_SECONDS, math.floor(distance * 1.4 / M.SPEED * M.SLACK)),   -- 1.4: the roads are longer than a straight line
    pay = round10(math.max(M.MIN_PAY, distance / 1000 * M.PAY_PER_KM * (fragile and M.FRAGILE_BONUS or 1) * (kind == 'part' and 1.25 or 1))),
  }
end

-- up to `count` offers: part runs (a shop to your garage) and courier parcels (between two places), alternating
function M.offers(shops, places, garage, rng, count)
  local out = {}
  for i = 1, count do
    local job
    if i % 2 == 1 and garage and #shops > 0 then
      for _ = 1, 10 do
        local shop = shops[rng:int(#shops)]
        if shop.id ~= garage.id and M.distance(shop, garage) >= M.MIN_METRES then job = M.make('part', shop, garage, rng) break end
      end
    elseif #places >= 2 then
      for _ = 1, 10 do
        local from, to = places[rng:int(#places)], places[rng:int(#places)]
        if from.id ~= to.id and M.distance(from, to) >= M.MIN_METRES then job = M.make('courier', from, to, rng) break end
      end
    end
    if job then
      job.id = job.kind .. ':' .. (#out + 1)
      out[#out + 1] = job
    end
  end
  return out
end

-- what a job pays at the drop: damage is the share of the car (0..1) damaged during the job
function M.settle(job, elapsedSeconds, damage)
  damage = damage or 0
  if job.fragile and damage > 0.05 then return 0, 'broken' end
  local pay, verdict = job.pay, 'on time'
  if elapsedSeconds > job.seconds then pay, verdict = pay * 0.5, 'late' end
  pay = pay * (1 - math.min(0.8, damage * 2))
  return math.max(0, round10(pay)), verdict
end

return M
