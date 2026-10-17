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

  -- T44: the cars' sound is off while a lot is made and comes back from the player's own settings
  local LA = require('sl/core/lotaudio')
  local vols = { AudioChannelMaster = 0.8, AudioChannelPower = 0.7, AudioChannelCollision = 0.5, AudioChannelUi = 0.9, AudioChannelMusic = 0.3 }
  local live = {}
  for k, v in pairs(vols) do live[k] = v end
  local audio = { get = function(ch) return vols[ch] end, set = function(ch, v) live[ch] = v end }
  LA.mute(audio)
  check('the car channels go silent (power, collision, ...)', live.AudioChannelPower == 0 and live.AudioChannelCollision == 0 and live.AudioChannelSuspension == 0)
  check('...the master, the music and the interface are left alone', live.AudioChannelMaster == 0.8 and live.AudioChannelMusic == 0.3 and live.AudioChannelUi == 0.9)
  LA.restore(audio)
  check('restored to what the player set, nothing was remembered by us', live.AudioChannelPower == 0.7 and live.AudioChannelCollision == 0.5)
  LA.restore(audio)
  check('a second restore (or one after a crash) changes nothing', live.AudioChannelPower == 0.7)
  local broken = { get = function() error('no audio') end, set = function() error('no audio') end }
  check('an audio system that errors does not break the lot', pcall(LA.mute, broken) and pcall(LA.restore, broken))

  -- T45: one marker a place: the stock dealerships have the walking marker at their door only; the other lots a mission marker
  local PO = require('sl/core/pois')
  local recs = PO.records({
    dealer = { id = 'dealer', kind = 'dealer', name = 'Jefferson Motors', at = { x = 1, y = 2, z = 3 }, stockId = 'jeffersonmotors' },
    junkyard = { id = 'junkyard', kind = 'junkyard', name = 'Wrecks', at = { x = 4, y = 5, z = 6 } },
    scrapyard = { id = 'scrapyard', kind = 'scrapyard', name = 'Scrap', at = { x = 7, y = 8, z = 9 } },
  })
  local byId = {}
  for _, r in ipairs(recs) do byId[r.placeId] = r end
  check('a stock dealership has one marker, the walking marker at its door; the used lot and the scrap yard one mission marker', byId.dealer.marker == 'walking' and byId.junkyard.marker == 'mission' and byId.scrapyard.marker == 'mission')

  -- T46: the cab starts out of sight and ends a ride to a lot in its car park
  local CP = require('sl/core/cabplan')
  local cam = { x = 0, y = 0, fx = 0, fy = 1 }              -- looking along +Y
  local cands = { { x = 0, y = 30, dist = 30 }, { x = 0, y = 120, dist = 120 }, { x = 0, y = -150, dist = 150 }, { x = 200, y = 0, dist = 200 } }
  local c1 = CP.approach(cands, cam)
  check('the cab starts far enough away and not in front of the camera: the first road behind or beside, not the one ahead', c1 and c1.y == -150)
  local c2 = CP.approach({ { x = 0, y = 30, dist = 30 }, { x = 0, y = 120, dist = 120 } }, cam)
  check('every road far enough is in view: nothing (the caller takes the nearest lane as before)', c2 == nil)
  local c3 = CP.approach({ { x = 500, y = 500, dist = 700 } }, cam)
  check('a road that is in the camera direction but too far to see is fine', c3 and c3.dist == 700)
  check('a road at the side (90 degrees) is out of a 100 degree view', CP.approach({ { x = 120, y = 0, dist = 120 } }, cam) ~= nil)
  check('no camera direction known: only the distance counts', CP.approach({ { x = 0, y = 30, dist = 30 }, { x = 0, y = 120, dist = 120 } }, { x = 0, y = 0, fx = 0, fy = 0 }).dist == 120 and CP.approach(nil, cam) == nil)
  local drop = CP.dropAt({ kind = 'dealer', at = { x = 10, y = 20, z = 5 }, pos = { x = 40, y = 50, z = 6 }, dir = { x = 0, y = -1 } })
  check('a ride to a dealer ends at its arrival spot in the car park (not the lane-nudged position), facing the cars', drop and drop.x == 10 and drop.y == 20 and drop.z == 5 and drop.dy == -1)
  check('the used lot and the scrap yard too; a garage, a meet or nothing: no drop spot (the lane, as before)', CP.dropAt({ kind = 'junkyard', pos = { x = 1, y = 2, z = 3 } }).x == 1 and CP.dropAt({ kind = 'scrapyard', at = { x = 4, y = 5, z = 6 } }).z == 6
    and CP.dropAt({ kind = 'garage', pos = { x = 1, y = 2, z = 3 } }) == nil and CP.dropAt({ kind = 'meet', pos = { x = 1, y = 2, z = 3 } }) == nil and CP.dropAt(nil) == nil)

  -- B66: a street racer is a road car (no limousine, bus, van, truck, ambulance or police car), and the race leaves the way the cars face
  local function cfg(name, body, ctype, aggBody) return { name = name, model = 'm', config = name, raw = { ['Body Style'] = body, ['Config Type'] = ctype, aggregates = aggBody and { ['Body Style'] = { [aggBody] = true } } or nil } } end
  check('a sedan, a coupe, a wagon, an SUV, a pickup race', C.racerOk(cfg('Sunburst', 'Sedan', 'Factory')) and C.racerOk(cfg('Covet', 'Hatchback', 'Factory')) and C.racerOk(cfg('Barstow', 'Coupe', 'Factory'))
    and C.racerOk(cfg('Roamer', 'SUV', 'Factory')) and C.racerOk(cfg('D-Series', 'Pickup', 'Factory')) and C.racerOk(cfg('Wagon', 'Wagon', 'Custom')))
  check('a limousine, a bus, a van, a truck, an ambulance do not (body style, any case or spaces, or the aggregate)', not C.racerOk(cfg('Grand Marshal Limo', 'Limousine', 'Factory')) and not C.racerOk(cfg('City', 'Bus', 'Factory'))
    and not C.racerOk(cfg('H', 'Van', 'Factory')) and not C.racerOk(cfg('T', 'Fifth Wheel Truck ', 'Factory')) and not C.racerOk(cfg('A', 'Ambulance', 'Service'))
    and not C.racerOk(cfg('X', ' limousine ', 'Factory')) and not C.racerOk({ name = 'Y', raw = { aggregates = { ['Body Style'] = { Limousine = true } } } }))
  check('a police or service config does not; a name with the word limo or bus does; Bluebuck and Sunburst do not trip it', not C.racerOk(cfg('Cop', 'Sedan', 'Police')) and not C.racerOk(cfg('Fire', 'Sedan', 'Service'))
    and not C.racerOk({ name = 'Fullsize Limo Luxe' }) and not C.racerOk({ name = 'Citybus' .. ' bus city' }) and C.racerOk({ name = 'Bluebuck' }) and C.racerOk({ name = 'Sunburst 2.0' }))
  check('no raw entry: allowed; nothing at all: not', C.racerOk({ name = 'Covet' }) and not C.racerOk(nil))
  local RA = require('sl/core/races')
  local nodes = { a = { pos = { x = 0, y = 0, z = 0 }, links = {} }, b = { pos = { x = 3, y = 0, z = 0 }, links = {} }, c = { pos = { x = 3, y = 40, z = 0 }, links = {} }, d = { pos = { x = 3, y = 90, z = 0 }, links = {} } }
  local path = { 'a', 'b', 'c', 'd' }
  local first, ahead = RA.routeDir(nodes, path), RA.routeDir(nodes, path, 25)
  check('the route leaves along the first edge, or (25 m ahead) by where it really goes: a 3 m first edge east then north', first.x == 1 and first.y == 0 and ahead.y > 0.99 * math.sqrt(1 - ahead.x ^ 2) and ahead.y > 0.9)
  check('a route shorter than the lookahead uses the first edge', RA.routeDir(nodes, { 'a', 'b' }, 25).x == 1 and RA.routeDir(nodes, { 'a' }, 25) == nil)
  local wps = RA.waypoints({ 'n1', 'n2', 'n3', 'n4', 'n5', 'n6', 'n7', 'n8', 'n9', 'n10', 'n11', 'n12', 'n13', 'n14', 'n15', 'n16', 'n17', 'n18', 'n19', 'n20' }, 4)
  check('the markers follow the race route: a few waypoints along it, the goal last', #wps <= 5 and wps[#wps] == 'n20' and wps[1] ~= 'n1' and #wps >= 3 and #RA.waypoints({}, 4) == 0 and RA.waypoints({ 'x', 'y' }, 4)[1] == 'y')
  check('facing: a car along the route is fine, across is not, backwards is not, no direction is not', RA.facingOk({ x = 0, y = 1 }, { x = 0, y = 1 }) and RA.facingOk({ x = 0.2, y = 1 }, { x = 0, y = 1 })
    and not RA.facingOk({ x = 1, y = 0 }, { x = 0, y = 1 }) and not RA.facingOk({ x = 0, y = -1 }, { x = 0, y = 1 }) and not RA.facingOk({ x = 0, y = 0 }, { x = 0, y = 1 }))

  -- B67: one game function swapped for ours while the career runs, the game's own put back after
  local PT = require('sl/core/patch')
  local game = { teleportToPoi = function() return 'game' end }
  local original = game.teleportToPoi
  local function ours() return 'ours' end
  local saved = {}
  check('installed: the module calls ours', PT.install(game, 'teleportToPoi', ours, saved) and game.teleportToPoi() == 'ours')
  check('installing again changes nothing and keeps the game original', PT.install(game, 'teleportToPoi', ours, saved) == false and saved.teleportToPoi.original == original)
  check('restored: the game original is back', PT.restore(game, 'teleportToPoi', saved) and game.teleportToPoi == original and saved.teleportToPoi == nil)
  check('restoring twice does nothing', PT.restore(game, 'teleportToPoi', saved) == false and game.teleportToPoi == original)
  PT.install(game, 'teleportToPoi', ours, saved)
  game.teleportToPoi = function() return 'reloaded' end           -- the game reloaded the module in between: its fresh function is not overwritten by a restore
  check('a module the game replaced meanwhile is left as the game made it', PT.restore(game, 'teleportToPoi', saved) == false and game.teleportToPoi() == 'reloaded')
  check('nothing to patch, nothing to fear', PT.install(nil, 'x', ours, {}) == false and PT.install({}, 'x', 5, {}) == false and PT.restore(nil, 'x', {}) == false)

  -- B69: the lot camera glides from one car to the next
  local LCG = require('sl/core/lotcam')
  local A, B, LA, LB = { x = 0, y = 0, z = 2 }, { x = 30, y = 6, z = 2.5 }, { x = 5, y = 0, z = 0 }, { x = 35, y = 6, z = 0.4 }
  local p0, l0, d0 = LCG.glide(A, B, LA, LB, 0, 0.8, 1.2)
  local p1, l1, d1 = LCG.glide(A, B, LA, LB, 0.8, 0.8, 1.2)
  check('the glide starts where the camera was and ends at the next framing, position and look-at', p0.x == 0 and p0.z == 2 and l0.x == 5 and not d0 and p1.x == 30 and p1.z == 2.5 and l1.x == 35 and d1)
  local pm = LCG.glide(A, B, LA, LB, 0.4, 0.8, 1.2)
  check('half way: half way along, lifted 1.2 m over the cars between', math.abs(pm.x - 15) < 1e-9 and math.abs(pm.y - 3) < 1e-9 and math.abs(pm.z - (2.25 + 1.2)) < 1e-9)
  local prev, monotone = -1, true
  for i = 0, 20 do
    local p = LCG.glide(A, B, LA, LB, i * 0.04, 0.8, 1.2)
    if p.x < prev - 1e-12 then monotone = false end
    prev = p.x
  end
  check('it only ever moves forward (along the lot to the next car), never back', monotone)
  local pa = LCG.glide(A, B, LA, LB, 0.02, 0.8, 1.2)
  local pb = LCG.glide(A, B, LA, LB, 0.78, 0.8, 1.2)
  check('slow at both ends (smoothstep: no jerk), the middle fastest', pa.x < 0.1 and pb.x > 29.9)
  local pOver = LCG.glide(A, B, LA, LB, 5, 0.8)
  local pUnder = LCG.glide(A, B, LA, LB, -1, 0.8)
  check('time outside the glide is clamped; the defaults are 0.8 s and 1.2 m', pOver.x == 30 and pUnder.x == 0 and LCG.GLIDE == 0.8 and LCG.GLIDE_LIFT == 1.2)

  -- D2: what belongs to the day and what to the night (sl/core/splitphase)
  local SP = require('sl/core/splitphase')
  check('the jobs: the everyday ones by day, hot car / valet / food by night', SP.available('jobs', 'courier', 'day') and not SP.available('jobs', 'courier', 'night')
    and SP.available('jobs', 'hot', 'night') and not SP.available('jobs', 'hot', 'day') and SP.available('jobs', 'valet', 'night') and SP.available('jobs', 'food', 'night')
    and SP.available('jobs', 'part', 'day') and SP.available('jobs', 'taxi', 'day') and SP.available('jobs', 'recovery', 'day'))
  check('shops, dealers and the scrap yard open by day and close at night; the junkyard stays open (the night gate); meets are the night', SP.available('places', 'shop', 'day') and not SP.available('places', 'shop', 'night')
    and SP.available('places', 'dealer', 'day') and not SP.available('places', 'dealer', 'night') and not SP.available('places', 'scrapyard', 'night')
    and SP.available('places', 'junkyard', 'day') and SP.available('places', 'junkyard', 'night') and SP.available('places', 'meet', 'night') and not SP.available('places', 'meet', 'day'))
  check('the garage, the hospital, the laptop and the cab are always there', SP.available('places', 'garage', 'night') and SP.available('places', 'hospital', 'day') and SP.available('places', 'computer', 'night') and SP.available('places', 'cab', 'night'))
  check('races: street sprints, the ROC and pink slips at night; the stock track events (drag strip, circuits, time trials) by day with prize money', SP.available('races', 'night', 'night') and not SP.available('races', 'night', 'day')
    and SP.available('races', 'roc', 'night') and SP.available('races', 'pink', 'night') and SP.available('races', 'drag', 'day') and not SP.available('races', 'drag', 'night')
    and SP.available('races', 'circuit', 'day') and SP.available('races', 'timeTrial', 'day') and not SP.available('races', 'timeTrial', 'night'))
  check('events: meets, show and shine, crew turf and chases at night; the club day and sponsors by day; the market and the tutorial both', SP.available('events', 'meet', 'night') and not SP.available('events', 'meet', 'day')
    and SP.available('events', 'showAndShine', 'night') and SP.available('events', 'turf', 'night') and SP.available('events', 'policeChase', 'night') and SP.available('events', 'clubDay', 'day')
    and not SP.available('events', 'clubDay', 'night') and SP.available('events', 'sponsor', 'day') and SP.available('events', 'classifieds', 'night') and SP.available('events', 'classifieds', 'day') and SP.available('events', 'tutorial', 'day'))
  check('a kind nobody listed is on in both (new things are never hidden by accident); an unknown table too', SP.available('jobs', 'newjob', 'day') and SP.available('jobs', 'newjob', 'night') and SP.available('nothing', 'x', 'day') and SP.phaseOf('jobs', 'newjob') == 'both')
  local board = { { kind = 'courier' }, { kind = 'hot' }, { kind = 'valet' }, { kind = 'part' }, { kind = 'food' } }
  local dayBoard, nightBoard = SP.filter('jobs', board, 'day'), SP.filter('jobs', board, 'night')
  check('a job board filtered by phase: day = courier and part, night = hot car, valet and food', #dayBoard == 2 and dayBoard[1].kind == 'courier' and dayBoard[2].kind == 'part' and #nightBoard == 3 and nightBoard[1].kind == 'hot')
  check('filter with another way to read the kind, and no list', #SP.filter('places', { { t = 'shop' }, { t = 'meet' } }, 'night', function(x) return x.t end) == 1 and #SP.filter('jobs', nil, 'day') == 0)
  check('what a closed thing says: shut for the night / only after dark / nothing when it is on', SP.closedText('places', 'shop', 'night'):find('night') ~= nil and SP.closedText('places', 'meet', 'day'):find('dark') ~= nil and SP.closedText('places', 'shop', 'day') == nil)
  check('day pays money, night pays rep', SP.pays('day') == 'money' and SP.pays('night') == 'rep')
  -- every kind the job board has today has an answer here (a new one without is on in both: say so in this table)
  local known = true
  for _, kind in ipairs({ 'part', 'courier', 'food', 'taxi', 'crush', 'transport', 'hot', 'testdrive', 'recovery', 'valet', 'move' }) do
    if SP.JOBS[kind] == nil then known = false end
  end
  check('every job kind of the board is in the table', known)

  -- #19: a racer's car is built out of the player's sight and off his way, one at a time, not while he races along
  local SPN = require('sl/core/spawnplan')
  local me = { x = 0, y = 0, vx = 0, vy = 20 }                  -- driving north at 20 m/s
  local cam = { x = 0, y = 0, fx = 0, fy = 1 }                  -- looking north
  check('a road ahead of him, in view, is no place to build a car', not SPN.hidden({ x = 0, y = 300 }, me, cam) and not SPN.hidden({ x = 40, y = 250 }, me, cam))
  check('behind him, or at the side, it is fine', SPN.hidden({ x = 0, y = -300 }, me, cam) and SPN.hidden({ x = 300, y = 0 }, me, cam) and SPN.hidden({ x = -250, y = -50 }, me, cam))
  check('beside his way but out of the camera view: on his way (60 degrees of his direction) is out; 70 degrees off is fine', not SPN.hidden({ x = 200, y = 150 }, me, { x = 0, y = 0, fx = 0, fy = -1 })
    and SPN.hidden({ x = 300, y = 80 }, me, { x = 0, y = 0, fx = 0, fy = -1 }))
  check('standing still: only the camera counts (his way is nowhere yet)', SPN.hidden({ x = 0, y = -200 }, { x = 0, y = 0, vx = 0, vy = 0 }, cam) and SPN.hidden({ x = 0, y = 200 }, { x = 0, y = 0, vx = 0, vy = 0 }, { x = 0, y = 0, fx = 0, fy = -1 })
    and not SPN.hidden({ x = 0, y = 200 }, { x = 0, y = 0, vx = 0, vy = 0 }, cam))
  check('far beyond sight range a spot in the camera direction is fine; unknown camera or player: allowed', SPN.hidden({ x = 0, y = 800 }, { x = 0, y = 0, vx = 0, vy = 0 }, cam) and SPN.hidden({ x = 5, y = 5 }, nil, nil))
  check('one build at a time, with a gap, and not while he races along (until it has been long)', not SPN.canBuild(5, 100, true) and not SPN.canBuild(5, 3, false) and SPN.canBuild(5, 10, false)
    and not SPN.canBuild(25, 20, false) and SPN.canBuild(25, 50, false) and SPN.canBuild(14, 9, false) and SPN.canBuild(0, nil, false))

  -- #18: a race route as a small map
  local RP = require('sl/core/routepreview')
  local pts = {}
  for i = 0, 200 do pts[#pts + 1] = { x = i * 10, y = 100 * math.sin(i / 20) } end
  local th = RP.thin(pts, 50)
  check('thin keeps the ends and at most n points', #th == 50 and th[1] == pts[1] and th[50] == pts[#pts] and #RP.thin({ pts[1], pts[2] }, 50) == 2)
  local f = RP.fit({ { x = 0, y = 0 }, { x = 1000, y = 0 }, { x = 1000, y = 500 } }, 240, 140, 12)
  check('fit: 1500 m, start bottom-left, finish above the end, inside the picture', f.metres == 1500 and f.start.x >= 12 and f.start.y > f.finish.y and f.finish.x <= 228 and f.finish.y >= 12 and f.start.y <= 128)
  check('fit: nothing to draw with fewer than two points', RP.fit({ { x = 1, y = 1 } }) == nil and RP.fit(nil) == nil)
  check('fit: a straight line (no height) does not divide by zero', RP.fit({ { x = 0, y = 5 }, { x = 100, y = 5 } }) ~= nil)

  -- #58: the full car report
  local CR = require('sl/core/carreport')
  local car = { name = 'Test Coupe', value = 12000, condition = 0.45, damage = 0.3, mileage = 180000, faults = { 'brakes', 'exhaust' } }
  local rp = CR.build(car)
  local rp2 = CR.build(car)
  local ids, parts, sumEst = {}, 0, 0
  for _, sec in ipairs(rp.sections) do ids[#ids + 1] = sec.id parts = parts + #sec.parts sumEst = sumEst + sec.estimate end
  check('report: seven sections in order, every part listed', table.concat(ids, ',') == 'engine,drivetrain,suspension,brakes,wheels,body,interior' and parts == 5 + 4 + 2 + 2 + 2 + 2 + 2)
  check('report: the same car gives the same report every time (offer, ad and garage agree)', rp.total == rp2.total and rp.sections[1].parts[1].condition == rp2.sections[1].parts[1].condition)
  check('report: the faults sit in their parts, capped, and listed per section', rp.sections[4].parts[1].fault == 'brakes' and rp.sections[4].parts[1].condition <= 30 and rp.sections[1].parts[4].fault == 'exhaust'
    and rp.sections[4].faults[1] == 'brakes' and #rp.faults == 2)
  check('report: damage shows (30 %, Moderate) and the body is worse than the interior', rp.damage.amount == 30 and rp.damage.label == 'Moderate' and rp.sections[6].condition < rp.sections[7].condition)
  check('report: the estimate is the sum of the sections and at least the faults ($600 each part of 12000 x 5 %)', rp.total == sumEst and rp.total >= 1200)
  local fixed = CR.build({ name = 'Test Coupe', value = 12000, condition = 0.45, damage = 0.3, mileage = 180000, faults = { 'brakes', 'exhaust' }, fixed = { brakes = 80, exhaust = 60 }, repaired = 2000 })
  check('report: a repaired car shows no open faults and costs less to finish', #fixed.faults == 0 and fixed.total < rp.total and fixed.condition > rp.condition)
  local mint = CR.build({ name = 'Mint', value = 9000, condition = 0.97, damage = 0, mileage = 20, faults = {} })
  check('report: a mint car has nothing to repair', mint.total == 0 and mint.damage.label == 'None' and mint.label == 'Excellent')

  -- #22 tiers and #20 fast travel
  local TI = require('sl/core/tiers')
  check('tier: median of odd and even lists, nil for none', TI.median({ 5, 1, 3 }) == 3 and TI.median({ 1, 2, 3, 10 }) == 2.5 and TI.median({}) == nil)
  local t1 = TI.forPool({ 60000, 40000, 20000 }, 'dealer')
  local t2 = TI.forPool({ 30000, 20000, 10000 }, 'dealer')
  local t3 = TI.forPool({ 30000, 20000, 10000 }, 'used')
  local t4 = TI.forPool({ 9000, 12000, 15000 }, 'used')
  local t5 = TI.forPool({ 30000, 20000, 10000 }, 'scrap')
  check('tier: dealer pool 40000 is high-end, 20000 mid, the same cars at a used lot low-end (11000), a scrap yard junk', t1 == 'high' and t2 == 'mid' and t3 == 'low' and t4 == 'low' and t5 == 'junk' and TI.forPool({}, 'used') == nil)
  local FT = require('sl/core/fasttravel')
  check('travel: refused during a race, a chase, a cab ride or a job, free otherwise', FT.refusal({ racing = true }) ~= nil and FT.refusal({ chase = true }) ~= nil and FT.refusal({ cab = true }) ~= nil
    and FT.refusal({ job = true }) ~= nil and FT.refusal({}) == nil and FT.refusal(nil) == nil)
  local lotPlace = { id = 'jeff', kind = 'dealer', name = 'Jefferson Motors', pos = { x = 1, y = 2, z = 3 }, at = { x = 10, y = 20, z = 3 }, dir = { x = 0, y = -1 } }
  local a = FT.arrival(lotPlace)
  check('travel: a lot arrives at its car park (the cab drop-off), facing its cars; a place without one at its own spot', a.x == 10 and a.y == 20 and a.dy == -1
    and FT.arrival({ kind = 'garage', pos = { x = 5, y = 6, z = 0 }, dir = { x = 1, y = 0 } }).dx == 1 and FT.arrival({}) == nil)
  local places = { slrrGarage1 = { id = 'slrrGarage1', kind = 'garage', name = 'Club Garage 1', pos = { x = 1, y = 1, z = 0 }, dir = { x = 0, y = 1 } },
    slrrGarage2 = { id = 'slrrGarage2', kind = 'garage', name = 'Club Garage 2', pos = { x = 9, y = 9, z = 0 }, dir = { x = 0, y = 1 } }, jeff = lotPlace }
  local ex = FT.extras(places, { { id = 'torres', name = 'Torres Tires', trade = 'Wheels', pos = { x = 7, y = 8, z = 9 } }, { id = 'nopos' } }, { rep = 100, garageLevel = 1 })
  check('travel: garages and shops get an entry, lots do not; shops need a position', #ex == 3 and ex[1].kind == 'garage' and ex[3].kind == 'shop' and ex[3].placeId == 'torres' and ex[3].arrive.x == 7)
  check('travel: your garage is open, the next one locked with the reputation it needs; a shop is never locked', not ex[1].locked and ex[2].locked and ex[2].why:find('1500') ~= nil and ex[2].what:find('1500') ~= nil and not ex[3].locked)
  local up = FT.extras(places, {}, { rep = 2000, garageLevel = 2 })
  check('travel: after moving up, the garage opens', not up[2].locked)

  -- #23: the drag strip
  local DR = require('sl/core/drag')
  local et = DR.etEstimate(300, 1300)
  check('drag: a 300 PS 1300 kg car is a 12-13 s car doing ~110 mph, a slow one is slower, nonsense gives nil', et > 12 and et < 13 and DR.etEstimate(100, 1300) > et and DR.etEstimate(0, 1300) == nil and DR.etEstimate('x', 1) == nil
    and DR.trapSpeed(300, 1300) > 42 and DR.trapSpeed(300, 1300) < 52)
  check('drag: the opponent dials within 6 percent, a better driver closer, never under 6 s', math.abs(DR.aiDial(14, 0, 1) - 14.84) < 0.01 and DR.aiDial(14, 1, 1) == 14 and DR.aiDial(14, 0.5, -1) == 13.58 and DR.aiDial(1, 0, 0) == 6 and DR.aiDial(nil, nil, nil) == 14.5)
  check('drag: a win pays 1.9 times the fee and rep, a loss nothing', DR.purse(true, 50).money == 100 and DR.purse(true, 50).rep == 12 and DR.purse(false, 50).money == 0 and DR.purse(true).money == 100)
  local sl = DR.slip({ et = 12.9, reaction = 0.043, speed = 50, dial = 13.2 })
  check('drag: the slip has mph, the diff against the dial and a break-out when under it', math.abs(sl.mph - 111.8) < 0.1 and math.abs(sl.diff + 0.3) < 1e-9 and sl.breakout and not DR.slip({ et = 13.5, dial = 13.2 }).breakout)
  check('drag: the slip text', DR.slipText(sl):find('ET 12.900 s') ~= nil and DR.slipText(sl):find('break%-out') ~= nil and DR.slipText({ dq = 'red light' }):find('red light') ~= nil and DR.slipText({}) == 'No time.')
end
