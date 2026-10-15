-- Street Legal: the rules of the Wrench Works jobs (Design 3 #7 repair tickets, #8 tune to spec, #9 scrapyard
-- scavenging). No game calls: rng is sl/core/rng; parts are WW slot paths and part names.

local M = {}

local function round10(x) return math.floor(x / 10 + 0.5) * 10 end

----------------------------------------------------------------------------------------------
-- #8 tune to spec: "250 PS for under $3,000" or "a 13.9 s quarter mile"; proven on the dyno or the strip

-- { target, parts budget, pay } per tier; a tier opens at TIER_REP[tier] reputation
M.POWER = { { 180, 2000, 500 }, { 250, 3000, 900 }, { 320, 5000, 1500 }, { 420, 8000, 2200 }, { 550, 12000, 3000 } }     -- PS
M.QUARTER = { { 15.5, 2000, 500 }, { 14.5, 3500, 900 }, { 13.5, 5500, 1500 }, { 12.5, 8500, 2200 }, { 11.5, 13000, 3000 } } -- s
M.TIER_REP = { 500, 900, 1500, 2500, 4000 }
M.UNDER = 0.8           -- spending under this share of the budget earns the bonus
M.BONUS = 0.2           -- of the pay
M.TUNE_DAYS = 2         -- in-game days to deliver

function M.tiers(rep)
  local n = 0
  for i, r in ipairs(M.TIER_REP) do if (rep or 0) >= r then n = i end end
  return n
end

-- a spec for this reputation, or nil below the first tier
function M.tuneSpec(rng, rep)
  local n = M.tiers(rep)
  if n == 0 then return nil end
  local metric = rng:chance(0.5) and 'power' or 'quarter'
  local t = (metric == 'power' and M.POWER or M.QUARTER)[rng:int(math.max(1, n - 1), n)]
  local text = metric == 'power' and string.format('%d PS for under $%d', t[1], t[2]) or string.format('a %.1f s quarter mile for under $%d', t[1], t[2])
  return { metric = metric, target = t[1], budget = t[2], pay = t[3], item = text }
end

-- does a dyno figure (PS) or a quarter-mile time (s) meet the spec?
function M.tuneMet(spec, value)
  if type(value) ~= 'number' then return false end
  if spec.metric == 'power' then return value >= spec.target end
  return value > 0 and value <= spec.target
end

-- pay for a spec that was met, by what the parts cost: over budget pays half, well under it a bonus
function M.tuneSettle(spec, spent)
  spent = spent or 0
  if spent > spec.budget then return round10(spec.pay * 0.5), 'over budget' end
  if spent <= spec.budget * M.UNDER then return round10(spec.pay * (1 + M.BONUS)), 'under budget' end
  return round10(spec.pay), 'on budget'
end

----------------------------------------------------------------------------------------------
-- #7 repair tickets: a customer's car on your lift with faults; paid the labour at drive-out, minus the parts
-- you bought for it, plus a share of whatever is left of the parts allowance

-- faults a ticket can list: { kind, what the customer says, labour, parts allowance }. "dent" is body damage
-- (WW's damage list), "part" a part to replace (the slot must hold a different part, or a part again, at drive-out)
M.FAULTS = {
  { kind = 'dent', area = 'front', text = 'a smashed front end', labour = 250, parts = 0 },
  { kind = 'dent', area = 'rear', text = 'a dented rear', labour = 200, parts = 0 },
  { kind = 'dent', area = 'side', text = 'a scraped side', labour = 150, parts = 0 },
  { kind = 'part', slot = 'tire', text = 'a worn-out tyre', labour = 60, parts = 150 },
  { kind = 'part', slot = 'exhaust', text = 'a blowing exhaust', labour = 120, parts = 300 },
  { kind = 'part', slot = 'radiator', text = 'a leaking radiator', labour = 150, parts = 250 },
  { kind = 'part', slot = 'brake', text = 'grinding brakes', labour = 100, parts = 200 },
}
M.MODELS = { 'covet', 'pessima', 'legran', 'midsize', 'fullsize', 'vivace' }

function M.repairTicket(rng)
  local n, faults, used, labour, parts = rng:int(1, 3), {}, {}, 0, 0
  while #faults < n do
    local i = rng:int(#M.FAULTS)
    if not used[i] then
      used[i] = true
      local f = M.FAULTS[i]
      faults[#faults + 1] = f
      labour, parts = labour + f.labour, parts + f.parts
    end
  end
  local names = {}
  for _, f in ipairs(faults) do names[#names + 1] = f.text end
  return { model = M.MODELS[rng:int(#M.MODELS)], faults = faults, labour = labour, budget = parts,
    item = table.concat(names, ', '), pay = labour + round10(parts * 0.5) }
end

-- fixed: how many of the ticket's faults are fixed at drive-out; spent: what its parts cost you
function M.repairSettle(ticket, fixed, spent)
  spent = spent or 0
  if (fixed or 0) < #ticket.faults then return 0, 'unfinished' end
  local left = math.max(0, ticket.budget - spent)
  return math.max(0, round10(ticket.labour + left * 0.5 - math.max(0, spent - ticket.budget))), spent <= ticket.budget and 'done' or 'over budget'
end

----------------------------------------------------------------------------------------------
-- #9 scrapyard scavenging: pull the named parts off the yard's wrecks and sell them at the pawn shop; the
-- shop pays their resale (Wrench Works), the job a finder's fee per part once all of them are sold

M.SALVAGE = { { slot = 'turbo', text = 'a turbo' }, { slot = 'radiator', text = 'a radiator' }, { slot = 'alternator', text = 'an alternator' },
  { slot = 'seat', text = 'a seat' }, { slot = 'wheel', text = 'a wheel' }, { slot = 'headlight', text = 'a headlight' },
  { slot = 'gearbox', text = 'a gearbox' }, { slot = 'exhaust', text = 'an exhaust' } }
M.FINDER_FEE = 60       -- per part
M.SCAVENGE_SECONDS = 1800

function M.scavengeList(rng)
  local n, list, used = rng:int(2, 4), {}, {}
  while #list < n do
    local i = rng:int(#M.SALVAGE)
    if not used[i] then used[i] = true list[#list + 1] = M.SALVAGE[i] end
  end
  local names = {}
  for _, s in ipairs(list) do names[#names + 1] = s.text end
  return { parts = list, item = table.concat(names, ', '), pay = #list * M.FINDER_FEE, seconds = M.SCAVENGE_SECONDS }
end

-- the job's wanted parts ticked off by a sold part's slot path; true when all are sold
function M.scavengeSold(job, slotPath)
  job.sold = job.sold or {}
  for i, s in ipairs(job.parts) do
    if not job.sold[i] and tostring(slotPath):lower():find(s.slot, 1, true) then
      job.sold[i] = true
      break
    end
  end
  for i = 1, #job.parts do if not job.sold[i] then return false end end
  return true
end

return M
