-- Tests of sl/core/wwjobs (the Wrench Works jobs), called from luatest.lua with its check and rng
return function(check, rngLib)
  local ww = require('sl/core/wwjobs')

  check('no tune specs below 500 rep', ww.tuneSpec(rngLib.new(1), 499) == nil and ww.tiers(500) == 1 and ww.tiers(1e6) == #ww.TIER_REP)
  for seed = 1, 60 do
    local s = ww.tuneSpec(rngLib.new(seed), 1000)
    check('a spec at 1000 rep is tier 1 or 2 ' .. seed, s and s.pay <= ww.POWER[2][3] and s.budget > 0 and #s.item > 0)
  end
  local p = { metric = 'power', target = 250, budget = 3000, pay = 900 }
  local q = { metric = 'quarter', target = 13.5, budget = 5500, pay = 1500 }
  check('power met at or over the target', ww.tuneMet(p, 250) and not ww.tuneMet(p, 249.9) and not ww.tuneMet(p, nil))
  check('quarter met at or under the target', ww.tuneMet(q, 13.5) and not ww.tuneMet(q, 13.6) and not ww.tuneMet(q, 0))
  check('on budget: the pay', ww.tuneSettle(p, 2900) == 900 and select(2, ww.tuneSettle(p, 2900)) == 'on budget')
  check('well under budget: the bonus', ww.tuneSettle(p, 1000) == 1080 and select(2, ww.tuneSettle(p, 0)) == 'under budget')
  check('over budget: half', ww.tuneSettle(p, 3001) == 450 and select(2, ww.tuneSettle(p, 3001)) == 'over budget')

  local fast = { metric = 'power', target = 250, budget = 3000, pay = 900 }
  check('a car that already meets the spec cannot take it', ww.tuneMeasure(fast, 300, 'a') == 'already')
  local m = { metric = 'power', target = 250, budget = 3000, pay = 900 }
  check('the first run is the baseline', ww.tuneMeasure(m, 180, 'a') == 'baseline' and m.baseline == 180)
  check('another car does not count', ww.tuneMeasure(m, 300, 'b') == 'other car')
  check('not there yet', ww.tuneMeasure(m, 240, 'a') == 'below')
  check('no parts bought, no pay', ww.tuneMeasure(m, 260, 'a') == 'no parts')
  m.spent = 800
  check('built to spec', ww.tuneMeasure(m, 260, 'a') == 'met')
  check('no reading, no change', ww.tuneMeasure(m, nil, 'a') == 'none')

  for seed = 1, 60 do
    local t = ww.repairTicket(rngLib.new(seed))
    local labour, seen = 0, {}
    for _, f in ipairs(t.faults) do labour = labour + f.labour seen[f.text] = (seen[f.text] or 0) + 1 end
    local dup = false
    for _, n in pairs(seen) do if n > 1 then dup = true end end
    check('a ticket has 1-3 different faults ' .. seed, #t.faults >= 1 and #t.faults <= 3 and not dup and t.labour == labour and t.pay % 10 == 0)
  end
  local function car()
    return { path = '/', chosenPartName = 'covet_body', children = {
      covet_exhaust = { path = '/covet_exhaust/', chosenPartName = 'covet_exhaust_stock', partPath = '/covet_exhaust/covet_exhaust_stock' },
      covet_bumper_R = { path = '/covet_bumper_R/', chosenPartName = 'covet_bumper_R', children = {
        covet_taillight = { path = '/covet_bumper_R/covet_taillight/', chosenPartName = 'covet_taillight' } } },
      covet_radiator = { path = '/covet_radiator/', chosenPartName = '' } } }
  end
  local tree = car()
  local faults = { ww.FAULTS[1], ww.FAULTS[2], ww.FAULTS[4] }       -- exhaust, radiator (already empty), rear bumper
  local removed = ww.emptySlots(tree, faults)
  check('the ticket empties fitted slots', removed[1] == '/covet_exhaust/' and removed[2] == false and removed[3] == '/covet_bumper_R/')
  check('an emptied slot is empty, with what was bolted to it', tree.children.covet_exhaust.chosenPartName == '' and tree.children.covet_bumper_R.children == nil)
  check('nothing fitted yet: only the fault that could not be set up counts', ww.fixedCount(tree, faults, removed) == 1)
  tree.children.covet_exhaust.chosenPartName = 'covet_exhaust_sport'
  check('a part back in the slot fixes it', ww.fixedCount(tree, faults, removed) == 2)
  check('all fixed on the original car', ww.fixedCount(car(), faults, removed) == 3)

  local t = { faults = { {}, {} }, labour = 400, budget = 300 }
  check('unfinished pays nothing', ww.repairSettle(t, 1, 0) == 0 and select(2, ww.repairSettle(t, 1, 0)) == 'unfinished')
  check('done on budget: labour and half the leftover', ww.repairSettle(t, 2, 100) == 500 and ww.repairSettle(t, 2, 300) == 400)
  check('over budget: the overspend comes off', ww.repairSettle(t, 2, 500) == 200 and select(2, ww.repairSettle(t, 2, 500)) == 'over budget')
  check('never below nothing', ww.repairSettle(t, 2, 1e6) == 0)

  for seed = 1, 60 do
    local j = ww.scavengeList(rngLib.new(seed))
    check('2-4 different parts to find ' .. seed, #j.parts >= 2 and #j.parts <= 4 and j.pay == #j.parts * ww.FINDER_FEE)
  end
  local j = { parts = { { slot = 'turbo' }, { slot = 'seat' } } }
  check('a sold part ticks one off', not ww.scavengeSold(j, '/etk_engine/etk_turbo/') and j.sold[1])
  check('the same part again ticks nothing more', not ww.scavengeSold(j, '/etk_engine/etk_turbo/'))
  check('the last one finishes it', ww.scavengeSold(j, '/etk_body/etk_seat_FR/'))
end
