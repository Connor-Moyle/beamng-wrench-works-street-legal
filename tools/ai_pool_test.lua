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

  -- #34: the pump's own price
  local CC = require('sl_carcare')
  check('pump price: the stock litre price scales every grade; nil or nonsense is 1; held between a third and three times', math.abs(CC.scaleFor(0.725) - 0.5) < 1e-9 and CC.scaleFor(nil) == 1 and CC.scaleFor(-3) == 1
    and CC.scaleFor(0.01) == 1 / 3 and CC.scaleFor(100) == 3 and CC.fillCost('regular', 10) == 14.5 and CC.fillCost('regular', 10, 0.5) == 7.25)

  -- #30: part wear and the engine swap
  local WR = require('sl/core/wear')
  local l0 = WR.lost(0, nil)
  local l1 = WR.lost(120000, nil)
  local l2 = WR.lost(120000, { brakes = 100 })
  check('wear: nothing lost at no km, a section at its life loses half, the tyres wear before the engine', l0.engine == 0 and math.abs(l1.brakes - 0.5) < 1e-9 and l1.wheels == 0.5 and l1.engine < 0.2 and l1.wheels > l1.engine)
  check('wear: hard stops wear the brakes (and a little the tyres) faster, never past the cap', l2.brakes == 0.5 and l2.wheels == 0.5 and WR.lost(1e9, nil).engine == 0.5 and WR.lost(5000, { drive = 1000 }).drivetrain > WR.lost(5000, nil).drivetrain)
  check('wear: km since you bought it', WR.kmSince(105000, 100000) == 5000 and WR.kmSince(90, 100) == 0 and WR.kmSince(nil, nil) == 0)
  local CCc = require('sl_carcare')
  local a1 = CCc.abuseSample({ dt = 0.1, rpmRatio = 0.97, coolantC = 120, prevSpeed = 0, speed = 0 })
  local a2 = CCc.abuseSample({ dt = 0.1, prevSpeed = 30, speed = 29.95, brake = 1 })
  local a3 = CCc.abuseSample({ dt = 0.1, prevSpeed = 30, speed = 20, brake = 1 })
  local a4 = CCc.abuseSample({ dt = 0.5, throttle = 1, speed = 1, rpmRatio = 0.8 })
  check('abuse: the limiter and overheating count engine seconds, a hard stop from speed counts, a gentle one not, a launch counts', math.abs(a1.engine - 0.4) < 1e-9 and a2.brakes == 0 and a3.brakes == 0.1 and a4.drive == 0.5 and CCc.abuseSample({ dt = 1 }).engine == 0)
  local worn = CR.build({ name = 'Worn', value = 10000, condition = 0.8, damage = 0, mileage = 50000, faults = {}, wear = WR.lost(100000, nil) })
  local fresh = CR.build({ name = 'Worn', value = 10000, condition = 0.8, damage = 0, mileage = 50000, faults = {} })
  check('report: the wear since you bought it lowers every wearing section, leaves the body and the interior, and adds to the estimate', worn.sections[4].condition < fresh.sections[4].condition and worn.sections[5].condition < fresh.sections[5].condition
    and worn.sections[7].condition == fresh.sections[7].condition and worn.total > fresh.total)
  local ES = require('sl/core/engineswap')
  check('swap: 4 hours at the cheapest engine, more for a dear one, capped at 14; labour is hours times the rate', ES.hours(0) == 4 and ES.hours(10000) == 6 and ES.hours(1e6) == 14 and ES.labour(10000) == 540 and ES.labour(0) == 360)
  local q = ES.quote({ name = 'V8', value = 10000, oldName = 'Inline-4', needs = { 'transmission', 'ecu' } })
  check('swap: the quote says labour, the old engine on the shelf and what it needs (sorted)', q.labour == 540 and q.needs[1] == 'ecu' and q.text:find('$540') ~= nil and q.text:find('Inline%-4 goes on the shelf') ~= nil and q.text:find('ecu, transmission') ~= nil
    and ES.NO_CROSS_MODEL:find('own engines') ~= nil)

  -- #17/#43: the night city and the themed meets
  local NL = require('sl/core/nightlife')
  local RNG = require('sl/core/rng')
  local seen = {}
  for d = 1, 8 do local t = NL.theme('meetA', d).id seen[t] = (seen[t] or 0) + 1 end
  local differs = false
  for d = 1, 8 do if NL.theme('meetB', d).id ~= NL.theme('meetA', d).id then differs = true end end
  check('themes: a spot cycles through all four themes over four nights, the same each time asked; another spot is out of step', seen.jdm == 2 and seen.muscle == 2 and seen.drift == 2 and seen.euro == 2
    and NL.theme('meetA', 3).id == NL.theme('meetA', 3).id and differs)
  check('theme cars: Japanese, American, European models; drift by build', NL.fits('jdm', { model = 'covet' }) and not NL.fits('jdm', { model = 'barstow' }) and NL.fits('muscle', { model = 'barstow' }) and NL.fits('euro', { model = 'vivace' })
    and NL.fits('drift', { model = 'x', power = 220, weight = 1300, raw = { Drivetrain = 'RWD' } }) and not NL.fits('drift', { model = 'x', power = 220, weight = 1300, raw = { Drivetrain = 'FWD' } })
    and not NL.fits('drift', { model = 'x', power = 100, weight = 1300, raw = { Drivetrain = 'RWD' } }) and not NL.fits('nothing', { model = 'covet' }) and not NL.fits('jdm', nil))
  local pool = { { model = 'covet' }, { model = 'pessima' }, { model = 'barstow' }, { model = 'bx' } }
  local pick = NL.pickCars('jdm', pool, 5, RNG.new(4))
  check('theme pick: only the theme, no repeats, fewer than asked when the pool is short', #pick == 3 and pick[1] ~= pick[2] and pick[2] ~= pick[3] and #NL.pickCars('euro', pool, 2, RNG.new(4)) == 0)
  local kinds = { race = 0, sale = 0, tip = 0 }
  local R = RNG.new(11)
  local priceOk = true
  for _ = 1, 300 do
    local o = NL.offer(NL.THEMES[1], R, { rep = 800, value = 12000 })
    kinds[o.kind] = kinds[o.kind] + 1
    if o.kind == 'sale' and (o.price < 6000 or o.price > 10250) then priceOk = false end
  end
  local noCar = true
  for _ = 1, 100 do if NL.offer(nil, R, { value = 0 }).kind == 'sale' then noCar = false end end
  check('owner offers: all three kinds come up, a sale is half to 85 percent of the car, no car to sell: no sale', kinds.race > 30 and kinds.sale > 30 and kinds.tip > 30 and priceOk and noCar)
  check('main strips: half-width 3 m or more', NL.mainStrip(3) and NL.mainStrip(4.5) and not NL.mainStrip(2) and not NL.mainStrip(nil))
  check('beside: nearly stopped for a moment, the racer alongside at 2-8 m; not ahead, not too far, not moving, not just stopped', NL.besideStopped({ x = 4, y = 0 }, { x = 0, y = 1 }, 0.5, 2) and NL.besideStopped({ x = -3, y = 2 }, { x = 0, y = 1 }, 1, 1.5)
    and not NL.besideStopped({ x = 0, y = 12 }, { x = 0, y = 1 }, 0, 3) and not NL.besideStopped({ x = 12, y = 0 }, { x = 0, y = 1 }, 0, 3) and not NL.besideStopped({ x = 4, y = 0 }, { x = 0, y = 1 }, 6, 3) and not NL.besideStopped({ x = 4, y = 0 }, { x = 0, y = 1 }, 0, 0.3))

  -- #45: the weather
  local WX = require('sl/core/weather')
  local counts = { day = {}, night = {} }
  for d = 1, 400 do
    for _, ph in ipairs({ 'day', 'night' }) do
      local id = WX.forecast(77, d, ph)
      counts[ph][id] = (counts[ph][id] or 0) + 1
      assert(WX.forecast(77, d, ph) == id, 'the same every time')
    end
  end
  check('weather: by day clear, cloudy and rain (no fog), at night fog too; rain about a fifth of the time', (counts.day.clear or 0) > 150 and (counts.day.rain or 0) > 50 and (counts.day.rain or 0) < 120 and counts.day.fog == nil
    and (counts.night.fog or 0) > 40 and (counts.night.fog or 0) < 110)
  check('weather: another career has another sky; the forecast is the same when asked twice', WX.forecast(1, 5, 'day') == WX.forecast(1, 5, 'day'))
  check('weather: rain is wet (less grip), pays more, fog a little less grip; clear is plain', WX.grip('rain') < 0.85 and WX.pay('rain') > 1 and WX.grip('fog') < 1 and WX.pay('clear') == 1 and WX.grip('nonsense') == 1 and WX.pay(nil) == 1)
  local a, b = WX.after('day', 4)
  local c, d2 = WX.after('night', 4)
  check('weather: the night follows the day, the next day follows the night', a == 'night' and b == 4 and c == 'day' and d2 == 5)
  check('weather: the forecast line says now, the wet and what is next', WX.text('night', 'rain', 'clear'):find('Rain tonight') ~= nil and WX.text('night', 'rain', 'clear'):find('Wet roads') ~= nil and WX.text('day', 'clear', 'fog'):find('Fog banks tonight') ~= nil
    and WX.text('night', 'fog', nil):find('Visibility') ~= nil)
  check('weather: earned money in the rain is 8 percent more, rounded to ten', WX.earned(1000, 'rain') == 1080 and WX.earned(1000, 'clear') == 1000 and WX.earned(55, 'rain') == 60)
  local mid = WX.blend(WX.STATES.clear, WX.STATES.rain, 0.5)
  check('weather: the sky blends between states', mid.drops == 175 and math.abs(mid.grip - 0.89) < 1e-9 and WX.blend(WX.STATES.clear, WX.STATES.rain, 2).drops == 350 and WX.blend(WX.STATES.clear, WX.STATES.rain, -1).drops == 0)

  -- #40: where the spectators stand
  local SPC = require('sl/core/spectators')
  local spots = SPC.stand({ x = 0, y = 0, z = 10 }, { x = 0, y = 20, z = 10 }, 4, 3)
  local left, right, nearest, facing = 0, 0, 1e9, true
  for _, sp in ipairs(spots) do
    if sp[1] < 0 then left = left + 1 else right = right + 1 end
    nearest = math.min(nearest, math.abs(sp[1]))
    if (sp[1] < 0 and sp[4] <= 0) or (sp[1] > 0 and sp[4] >= 0) then facing = false end          -- facing the track
  end
  check('spectators: spots on both sides of a stretch, in rows, none nearer the track than the half-width plus the gap, all facing it', #spots > 20 and left == right and math.abs(nearest - 7) < 1e-9 and facing and #SPC.stand({ x = 1, y = 1, z = 0 }, { x = 1, y = 1, z = 0 }, 4, 3) == 0)
  local capped = SPC.stand({ x = 0, y = 0, z = 0 }, { x = 0, y = 500, z = 0 }, 4, 3)
  check('spectators: a zone never has more than its cap of spots', #capped == SPC.MAX_SPOTS)
  local ring = SPC.ring({ x = 10, y = 10, z = 5 }, 9, 13, 24)
  local rok = #ring == 24
  for _, sp in ipairs(ring) do
    local d = math.sqrt((sp[1] - 10) ^ 2 + (sp[2] - 10) ^ 2)
    if not (math.abs(d - 9) < 1e-6 or math.abs(d - 13) < 1e-6) or sp[3] ~= 5 or (sp[4] * (10 - sp[1]) + sp[5] * (10 - sp[2])) <= 0 then rok = false end
  end
  check('spectators: a meet ring is two radii, facing the middle, at the spot height', rok)
  local z = SPC.zone('z', 'race', spots)
  check('spectators: a zone has its middle, a radius that holds every spot, and finds the ground itself', z.ground and z.id == 'z' and z.r > 10 and math.abs(z.c[2] - 10) < 2 and SPC.zone('e', 'race', {}) == nil)
  local strip = SPC.dragStrip({ { from = { x = 0, y = 0, z = 1 }, to = { x = 0, y = 400, z = 1 } }, { from = { x = 5, y = 0, z = 1 }, to = { x = 5, y = 400, z = 1 } } })
  local minx, maxx = 1e9, -1e9
  for _, sp in ipairs(strip) do minx, maxx = math.min(minx, sp[1]), math.max(maxx, sp[1]) end
  check('spectators: the drag strip crowd stands outside both lanes', #strip > 0 and minx < -4 and maxx > 9)
  local nodes = {}
  for i = 1, 12 do nodes[i] = { pos = { math.cos(i / 12 * 6.283) * 300, math.sin(i / 12 * 6.283) * 300, 20 }, radius = 8 } end
  local stands = SPC.circuitStands(nodes)
  check('spectators: a circuit gets four stands, none with fewer than 4 nodes', #stands == 4 and #stands[1] > 10 and #SPC.circuitStands({ nodes[1], nodes[2], nodes[3] }) == 0)

  -- #46: the ambient sound zones
  local AM = require('sl/core/ambience')
  check('ambience volume: loudest close in, falling to nothing at the range, quieter than the base beyond a bit; unknown kinds are silent', AM.volume('harbour', 0) == AM.BASE.harbour and AM.volume('harbour', 160) == 0
    and AM.volume('harbour', 80) < AM.volume('harbour', 40) and AM.volume('harbour', 80) > 0 and AM.volume('harbour', 500) == 0 and AM.volume('nothing', 1) == 0)
  local function slope(x, y) return x > 100 and -5 or 20 end                    -- water to the east of x = 100
  local edge = AM.waterEdge(slope, 0, { x = 70, y = 0 }, 160)
  check('water edge: the first ring that has water; none on dry land; no sampler or no water level: none', edge and edge.x > 100 and edge.z == 0 and AM.waterEdge(slope, 0, { x = -500, y = 0 }, 160) == nil and AM.waterEdge(nil, 0, { x = 0, y = 0 }) == nil and AM.waterEdge(slope, nil, { x = 0, y = 0 }) == nil)
  local nodes = { a = { pos = { x = 50, y = 0, z = 1 }, radius = 3 }, b = { pos = { x = 90, y = 0, z = 1 }, radius = 6 }, c = { pos = { x = 400, y = 0, z = 1 }, radius = 8 } }
  local fw, fd = AM.freewayNode(nodes, { x = 0, y = 0 }, 130)
  check('freeway: the nearest wide road node within range (a narrow road is no freeway)', fw and fw.x == 90 and fd == 90 and AM.freewayNode({ a = nodes.a }, { x = 0, y = 0 }, 130) == nil and AM.freewayNode(nodes, { x = 0, y = 0 }, 50) == nil)
  local places = { s1 = { kind = 'shop', pos = { x = 100, y = 0, z = 0 } }, s2 = { kind = 'dealer', pos = { x = 120, y = 0, z = 0 } }, far = { kind = 'shop', pos = { x = 900, y = 900, z = 0 } }, meet = { kind = 'meet', pos = { x = 105, y = 5, z = 0 } } }
  local cc, cn = AM.crowd(places, { x = 80, y = 0 }, 90)
  check('crowd: two city places close together make one, its middle between them; a lone place or a meet spot does not', cc and cn == 2 and math.abs(cc.x - 110) < 1e-6 and AM.crowd({ s = places.s1 }, { x = 80, y = 0 }, 90) == nil and AM.crowd({ a = places.meet, b = places.meet }, { x = 80, y = 0 }, 90) == nil)
  local plan = AM.plan({ player = { x = 80, y = 0, z = 0 }, height = slope, waterZ = 0, nodes = nodes, places = places, phase = 'day' })
  local kinds = {}
  for _, em in ipairs(plan) do kinds[em.kind] = em end
  check('plan by day: the harbour, the freeway and the town crowd, loudest first, each with its file', kinds.harbour and kinds.freeway and kinds.crowd and kinds.harbour.file == 'harbour.wav' and plan[1].volume >= plan[#plan].volume and kinds.music == nil)
  local night = AM.plan({ player = { x = 80, y = 0, z = 0 }, height = slope, waterZ = 0, nodes = nodes, places = places, phase = 'night', meet = { pos = { x = 100, y = 20, z = 0 } } })
  local nk = {}
  for _, em in ipairs(night) do nk[em.id] = em end
  check('plan at night: no town crowd, but the meet has its crowd and its music (no file: the radio)', nk.crowd == nil and nk.crowd_meet and nk.music and nk.music.file == nil)
  local rain = AM.plan({ player = { x = 80, y = 0, z = 0 }, height = slope, waterZ = 0, nodes = nodes, places = places, phase = 'day', raining = true })
  local rk = {}
  for _, em in ipairs(rain) do rk[em.id] = true end
  check('plan in the rain: the crowd stays indoors; nothing at all far from everything', not rk.crowd and #AM.plan({ player = { x = -5000, y = 5000, z = 0 }, height = slope, waterZ = 0, nodes = nodes, places = places, phase = 'day' }) == 0 and #AM.plan({}) == 0)

  -- #47: sponsor billboards
  local BB = require('sl/core/billboards')
  check('billboards: the sponsor first, else the club by its level, else the stock ads; a name without an atlas is ignored', BB.choose('Nightrun Energy', 2) == 'Nightrun Energy' and BB.choose(nil, 2) == 'Club 2' and BB.choose(nil, nil) == nil
    and BB.choose('Some Other Co', nil) == nil and BB.choose('Some Other Co', 3) == 'Club 3' and BB.choose(nil, 9) == nil)
  check('billboards: the atlas file is in the mod folder by slug; no name, no file', BB.file('Valo Tyre & Wheel') == '/art/street_legal/billboards/valo-tyre-wheel.jpg' and BB.file('Club 1') == '/art/street_legal/billboards/club-1.jpg' and BB.file(nil) == nil and BB.file('x') == nil)
end
