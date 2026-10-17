-- Tests of the pools the career builds cars from (T29), called from listings_test.lua: no racer or opponent gets an excluded model
return function(check, rngLib)
  local C = require('sl/core/cars')
  -- T29: no racer or opponent is given an excluded model either (carBuilder.aiPool = carsLib.withoutModels)
  local racerCars = {}
  for i = 1, 30 do racerCars[#racerCars + 1] = { model = 'covet', config = 'c' .. i, pw = i / 100, value = 1000 * i } end
  for i = 1, 12 do racerCars[#racerCars + 1] = { model = 'midtruck', config = 'mt' .. i, pw = i / 400, value = 5000 + i } end
  racerCars[#racerCars + 1] = { model = 'sunburst2', config = 'cop', pw = 0.9, value = 100, raw = { ['Config Type'] = 'Police' } }
  local aiPool = C.withoutModels(racerCars, { midtruck = true })
  check('withoutModels drops the excluded model and nothing else (a race or police car stays for an AI)', #aiPool == 31 and aiPool[#aiPool].config == 'cop' and #C.withoutModels(racerCars, nil) == #racerCars and #C.withoutModels(nil, { midtruck = true }) == 0)
  local trucksPicked = 0
  for _, class in ipairs(C.CLASSES) do
    for seed = 1, 80 do
      local pick = C.pickConfig(aiPool, class, rngLib.new(rngLib.hash('ai' .. seed)))
      if pick and pick.model == 'midtruck' then trucksPicked = trucksPicked + 1 end
    end
  end
  check('over every class and 80 seeds a racer is never given a midtruck', trucksPicked == 0)
  local truckBefore = 0
  for _, class in ipairs(C.CLASSES) do
    for seed = 1, 80 do
      local pick = C.pickConfig(racerCars, class, rngLib.new(rngLib.hash('ai' .. seed)))
      if pick and pick.model == 'midtruck' then truckBefore = truckBefore + 1 end
    end
  end
  check('(and the unfiltered pool did give them one: the rule is what keeps them out)', truckBefore > 0)

  -- T43: a lot is made in two rounds: every car first, then the dents one car at a time
  local LB = require('sl/core/lotbuild')
  local plan = LB.plan(5, { [2] = { 'a' }, [4] = { 'b', 'c' }, [5] = {} })
  check('the plan spawns every car in order, and only then dents the ones that have dents, in order', table.concat(plan.spawn, ',') == '1,2,3,4,5' and table.concat(plan.dent, ',') == '2,4')
  check('no dents anywhere: nothing to dent; no pending table at all too', #LB.plan(3, {}).dent == 0 and #LB.plan(3, nil).dent == 0 and #LB.plan(0, nil).spawn == 0)
  local madeSet = { [1] = false, [2] = true, [3] = true }
  local function made(i) return madeSet[i] end
  check('the car shown is the one asked for if it was made, else the first that was', LB.shown(3, 3, made) == 3 and LB.shown(3, 1, made) == 2 and LB.shown(3, nil, made) == 2)
  check('nothing made: nothing to show', LB.shown(3, 1, function() return false end) == nil and LB.shown(0, 1, made) == nil)
end
