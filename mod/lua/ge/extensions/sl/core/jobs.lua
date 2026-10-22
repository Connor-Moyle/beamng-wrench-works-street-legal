-- Street Legal: the rules of delivery gigs (part runs for the garages, courier parcels).
-- No game calls: places are { id, name, kind, x, y }; rng is sl/core/rng.

local M = {}

local strings = require('sl/core/strings')

M.SPEED = 14            -- metres per second assumed for the time limit
M.SLACK = 1.35          -- time limit multiplier
M.MIN_SECONDS = 120
M.MIN_METRES = 400
M.PAY_PER_KM = 140
M.MIN_PAY = 120
M.DAY_PAY = 1.35        -- every day job's pay (not the night ones) x this when the board is made (economy balance, tools/economy_sim.py)
M.FRAGILE_BONUS = 1.5
M.PART_ITEMS = { 'turbocharger', 'gearbox', strings.t('jobs.set_of_wheels'), strings.t('jobs.exhaust_manifold'), 'radiator', 'bonnet', strings.t('jobs.set_of_coilovers'), 'ECU' }
M.PARCELS = { 'parcel', strings.t('jobs.box_of_spark_plugs'), 'envelope', strings.t('jobs.case_of_oil'), strings.t('jobs.tool_box'), strings.t('jobs.crate_of_brake_pads') }

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
-- the pay a player is shown and paid: the job's pay with the new-in-town boost, rounded down to ten, and the first-times bonus. One source for the board, the active card and the drop.
function M.shown(pay, boost, firstBonus)
  return math.floor((tonumber(pay) or 0) * (tonumber(boost) or 1) / 10) * 10 + (tonumber(firstBonus) or 0)
end

function M.settle(job, elapsedSeconds, damage)
  damage = damage or 0
  if job.fragile and damage > 0.05 then return 0, 'broken' end
  local pay, verdict = job.pay, strings.t('jobs.on_time')
  if elapsedSeconds > job.seconds then pay, verdict = pay * 0.5, 'late' end
  pay = pay * (1 - math.min(0.8, damage * 2))
  return math.max(0, round10(pay)), verdict
end

-- passenger comfort (taxi fares): the car's speed is sampled; a push of more than HARSH m/s^2 (about 0.4 g, a hard brake, a quick corner) is a bump. The score is the
-- share of the ride without one; the tip grows with it
M.HARSH = 4
function M.comfortNew() return { t = 0, harsh = 0, lastV = nil, peak = 0 } end
function M.comfortStep(c, dt, vx, vy, vz)
  if c.lastV and dt > 0 then
    local a = math.sqrt((vx - c.lastV[1]) ^ 2 + (vy - c.lastV[2]) ^ 2 + (vz - c.lastV[3]) ^ 2) / dt
    c.peak = math.max(c.peak, a)
    if a > M.HARSH then c.harsh = c.harsh + dt end
  end
  c.lastV = { vx, vy, vz }
  c.t = c.t + dt
end
function M.comfortScore(c) return c.t > 1 and math.max(0, 1 - 6 * c.harsh / c.t) or 1 end
function M.tip(pay, score)
  local f = score >= 0.9 and 0.5 or (score >= 0.7 and 0.25 or (score >= 0.5 and 0.1 or 0))
  return round10(pay * f)
end

return M
