-- Wrench Works: Street Legal: rival crews and their districts (extension name: sl_crews; X21, Design 6)
-- Rules in sl/core/crews. Every racer is in a crew; the districts come from the map's
-- /levels/<level>/districts.json (names, polygons, crew homes), or the career's places clustered. A street race
-- won where it started against a member of the crew holding that district takes control from them; at 0 the
-- district is yours. The phone's Turf app shows who holds what.

local M = {}

local crews = require('sl/core/crews')
local rngLib = require('sl/core/rng')
local roster = require('sl/core/roster')
local stateLib = require('sl/core/state')

-- nothing runs, is sent or is shown on a map that cannot host it (progression.MAPS has); the code and the save stay
local function career() return sl_career and sl_career.isActive() and sl_career.has('crews') and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end

-- the map's districts, or the career's own places clustered (kept in the save so they stay put)
local cache = {}            -- level -> the map's districts (read once)
local function mapDistricts()
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier()
  if level and cache[level] then return cache[level] end
  local data = level and jsonReadFile('/levels/' .. level .. '/districts.json')
  local out = {}
  for _, d in ipairs(type(data) == 'table' and type(data.districts) == 'table' and data.districts or {}) do
    if type(d.id) == 'string' and type(d.polygon) == 'table' and #d.polygon >= 3 then
      out[#out + 1] = { id = d.id, name = tostring(d.name or d.id), polygon = d.polygon, label = d.label, home = d.home }
    end
  end
  if level then cache[level] = out end
  return out
end

local function clustered()
  local pts = {}
  for _, p in pairs(sl_career.getPlaces() or {}) do
    if p.pos and p.kind ~= 'track' and p.kind ~= 'roc' then pts[#pts + 1] = { x = p.pos.x, y = p.pos.y } end
  end
  local ds = crews.cluster(pts, 6)
  for _, d in ipairs(ds) do d.centre = { x = math.floor(d.centre.x), y = math.floor(d.centre.y) } end
  return ds
end

-- the career's crews, built once; built again if the map's districts are new or changed
function M.ensure(s)
  s = s or career()
  if not s then return nil end
  local fromMap = mapDistricts()
  local c = s.crews
  local sig = #fromMap > 0 and table.concat((function() local ids = {} for _, d in ipairs(fromMap) do ids[#ids + 1] = d.id end return ids end)(), ',') or 'clustered'
  if c and c.sig == sig then
    if #fromMap > 0 then c.districts = fromMap end           -- (polygons are not saved twice: the map's are read)
    return c
  end
  local rng = rngLib.new(rngLib.hash('crews:' .. tostring(s.seed)))
  local member, leader = crews.assign(s.racers, rng)
  local ds = #fromMap > 0 and fromMap or clustered()
  s.crews = { sig = sig, member = member, leader = leader, territory = crews.newTerritory(ds, rng), districts = ds }
  return s.crews
end

-- the districts only go in the save when they were made here (the map's are read from the map)
function M.onStreetLegalBeforeSave()
  local s = career()
  if s and s.crews and s.crews.sig ~= 'clustered' then s.crews.districts = nil end
end

function M.districtAt(pos)
  local c = M.ensure()
  return c and pos and crews.districtOf(c.districts or {}, pos.x, pos.y) or nil
end

-- where the race starts decides whose turf it is (and the rep before it, for a home crowd's share)
local raceDistrict, repAtStart, homeCrowd
local function noteStart()
  local v = getPlayerVehicle(0)
  local d = v and M.districtAt(v:getPosition())
  local c = d and M.ensure()
  raceDistrict = d and d.id or nil
  repAtStart = (career() or {}).rep
  homeCrowd = c and c.territory[d.id] and c.territory[d.id].owner == 'player'
end
M.onStreetLegalRaceStarted = noteStart
M.onSlrrRaceStarted = noteStart

local turfWarResult    -- (defined below, used by the race result)

function M.onStreetLegalRaceResult(won, opponent, racerId, stake)
  local s = career()
  local c = s and M.ensure(s)
  if not c or not raceDistrict or type(racerId) ~= 'string' then return end
  local crewId = c.member[racerId]
  local dist
  for _, d in ipairs(c.districts or {}) do if d.id == raceDistrict then dist = d end end
  -- a home crowd: a race won in one of your districts is worth a fifth more rep
  if won and homeCrowd and repAtStart and s.rep > repAtStart then
    stateLib.addRep(s, math.floor((s.rep - repAtStart) * (crews.PERKS.rep - 1) + 0.5))
  end
  for i = #(c.callouts or {}), 1, -1 do if c.callouts[i].racer == racerId then table.remove(c.callouts, i) end end    -- (answered)
  if c.turfWar then turfWarResult(s, c, racerId, won) end
  if c.king then raceDistrict = nil return end              -- (the city is yours: nothing more to take)
  local entry, event = crews.raceResult(c.territory, raceDistrict, crewId, c.leader[crewId] == racerId, won, stake == 'pink', c.friendly)
  raceDistrict, repAtStart, homeCrowd = nil, nil, nil
  local crew = crews.crew(crewId)
  if not entry or not dist or not crew then return end
  if event == 'taken' then
    sl_career.sendText('benny', string.format('Word is %s is yours now. %s won\'t take that lying down.', dist.name, crew.name:gsub('^%l', string.upper)), 3)
    c.callouts = c.callouts or {}
    c.callouts[#c.callouts + 1] = { crew = crewId, district = dist.id, day = s.day }
    c.angry = c.angry or {}
    c.angry[crewId] = s.day
    extensions.hook('onStreetLegalDistrictTaken', dist.id, crewId)
  elseif event == 'lost' then
    sl_career.sendText('benny', string.format('%s took %s back off you.', crew.name:gsub('^%l', string.upper), dist.name), 3)
  elseif entry.owner == crewId then
    toast(string.format('%s: %s hold it, %d%% control.', dist.name, crew.name, entry.control))
  end
  extensions.hook('onStreetLegalChanged')
end

----------------------------------------------------------------------------------------------
-- call-outs: a crew that lost a district to you wants it back: a race there tonight, on its terms (through the
-- career's arranged races, so the map's own race runs it). Ignored, they take some of it back at midnight.

local CALLOUT_IGNORED = 10

local function raceIn(c, districtId)
  for _, r in ipairs(sl_career.racesList and sl_career.racesList() or {}) do
    local d = r.start and not r.drag and crews.districtOf(c.districts or {}, r.start.x, r.start.y)
    if d and d.id == districtId then return r end
  end
end

local function sendCallouts(s, c)
  for _, co in ipairs(c.callouts or {}) do
    if not co.racer then
      local t = c.territory[co.district] or {}
      local home = t.home == co.crew
      -- the leader for a home, else the crew's best racer after the leader
      local pick, best = c.leader[co.crew], -1
      if not home then
        for _, r in ipairs(s.racers) do
          if c.member[r.id] == co.crew and r.id ~= c.leader[co.crew] and (r.skill or 0) > best then pick, best = r.id, r.skill or 0 end
        end
      end
      local racer = pick and stateLib.racer(s, pick)
      local race = raceIn(c, co.district)
      co.racer = pick or false
      if racer and race then
        s.known[racer.id] = true
        for i = #s.challenges, 1, -1 do if s.challenges[i].racer == racer.id then table.remove(s.challenges, i) end end
        local pink = home and s.activeCar ~= nil
        local bet = math.floor(((racer.betMin or 100) + (racer.betMax or 300)) * 0.75 / 50) * 50     -- (1.5 x their usual)
        s.challenges[#s.challenges + 1] = { id = racer.id .. ':callout:' .. s.day, racer = racer.id, stake = pink and 'pink' or 'money', bet = pink and 0 or bet,
          race = race.id, raceName = race.name, missionId = race.missionId, nightOnly = true, at = os.time(), callout = co.district }
        local dname = co.district
        for _, d in ipairs(c.districts or {}) do if d.id == co.district then dname = d.name end end
        sl_career.sendText(racer.id, string.format('You think %s is yours? Tonight, %s. %s. Don\'t make us come looking.', dname, race.name,
          pink and 'Pink slips' or ('$' .. bet)), 4)
        extensions.hook('onStreetLegalChanged')
      end
    end
  end
end

----------------------------------------------------------------------------------------------
-- the turf war: hold enough of the city and the leaders come, one a night, each on their own home streets.
-- Beat them all and the city is yours (King of Valo); lose one and it is off for a week.

local function crewHome(c, crewId)
  for id, t in pairs(c.territory) do if t.home == crewId then return id end end
end

local function turfWarNext(s, c)
  local w = c.turfWar
  local crewId = w and w.order[w.stage]
  if not crewId or w.sentDay == s.day then return end
  local leader = stateLib.racer(s, c.leader[crewId])
  local home = crewHome(c, crewId)
  local race = home and raceIn(c, home) or (sl_career.racesList() or {})[1]
  if not leader or not race then return end
  w.sentDay = s.day
  s.known[leader.id] = true
  for i = #s.challenges, 1, -1 do if s.challenges[i].racer == leader.id then table.remove(s.challenges, i) end end
  local bet = math.floor((leader.betMax or 1000) * 2 / 50) * 50
  s.challenges[#s.challenges + 1] = { id = leader.id .. ':turfwar:' .. s.day, racer = leader.id, stake = 'money', bet = bet, race = race.id,
    raceName = race.name, missionId = race.missionId, nightOnly = true, at = os.time(), turfWar = crewId }
  sl_career.sendText(leader.id, string.format('So you want the whole city. Tonight, %s, $%d. You and me. (%d of %d)', race.name, bet, w.stage, #w.order), 4)
  extensions.hook('onStreetLegalChanged')
end

turfWarResult = function(s, c, racerId, won)
  local w = c.turfWar
  local crewId = w and w.order[w.stage]
  if not crewId or c.leader[crewId] ~= racerId then return end
  if not won then
    sl_career.sendText('benny', 'They beat you. The crews are laughing. Give it a week and try again.', 3)
    c.turfWar, c.turfWarAfter = nil, s.day + 7
    return
  end
  w.stage = w.stage + 1
  if w.stage > #w.order then
    c.king, c.turfWar = s.day, nil
    stateLib.addRep(s, 1000)
    for _, t in pairs(c.territory) do t.owner, t.control = 'player', 100 end
    sl_career.sendText('benny', sl_career.mapText('You did it. Every crew in Valo answers to you now. King of Valo!'), 3)
    extensions.hook('onStreetLegalKingOfValo')
  else
    sl_career.sendText('benny', string.format('That is %d down. %s is next, tomorrow night.', w.stage - 1, crews.crew(w.order[w.stage]).name), 3)
  end
end

local function turfWarCheck(s, c)
  if c.king or c.turfWar or (c.turfWarAfter and s.day < c.turfWarAfter) or not crews.turfWarReady(c.territory) then return end
  -- three leaders: the crews still holding their home first, then the others
  local holding, beaten, order = {}, {}, {}
  for _, cr in ipairs(crews.CREWS) do
    local home = crewHome(c, cr.id)
    if c.leader[cr.id] then
      local list = (home and c.territory[home].owner ~= 'player') and holding or beaten
      list[#list + 1] = cr.id
    end
  end
  for _, id in ipairs(holding) do if #order < 3 then order[#order + 1] = id end end
  for _, id in ipairs(beaten) do if #order < 3 then order[#order + 1] = id end end
  c.turfWar = { stage = 1, order = order }
  sl_career.sendText('benny', 'The crew leaders have noticed you. They want a turf war: three nights, three races, one each on their own streets. Win them all and the city is yours.', 3)
end

----------------------------------------------------------------------------------------------
-- raids (Settings: Crew raids): a crew you took a district from may come for a car you left out, the night after
-- you hear of it: lights and mirrors smashed (its own break groups: nothing flies), never a car at the garage
-- or the one you are in, and once a week a crew at most

local RAID_HOUR = 22
local SMASH = [[
local groups, seen = {}, {}
for _, b in pairs(v.data.beams or {}) do
  local g = b.breakGroup
  for _, name in ipairs(type(g) == 'table' and g or { g }) do
    local n = type(name) == 'string' and name:lower() or ''
    if not seen[name] and (n:find('mirror') or n:find('headlight') or n:find('taillight')) then seen[name] = true groups[#groups + 1] = name end
  end
end
for i = 1, math.min(3, #groups) do beamstate.breakBreakGroup(groups[math.random(#groups)]) end
]]

local function raidsOn() return not sl_options or sl_options.get('slRaids') ~= false end

local function planRaid(s, c, day)
  if c.raid or not raidsOn() or c.king then return end
  c.raided = c.raided or {}
  for crewId, since in pairs(c.angry or {}) do
    if day - since <= 7 and (c.raided[crewId] or -99) + 7 <= day then
      c.raid = { crew = crewId, day = day + 1 }
      sl_career.sendText('benny', string.format('Heads up: word is %s are going after one of your cars tomorrow night. Keep them in the garage.', crews.crew(crewId).name), 3)
      return
    end
  end
end

local function doRaid(s, c)
  local r = c.raid
  if not r or s.day < r.day or (sl_career.hour and sl_career.hour() or 0) < RAID_HOUR then return end
  c.raid = nil
  c.raided = c.raided or {}
  c.raided[r.crew] = s.day
  if not raidsOn() then return end
  local me = getPlayerVehicle(0)
  for _, car in ipairs(s.cars or {}) do
    local v = sl_fleet.vehicleOf(car.id)
    local away = v and me and (v:getPosition() - me:getPosition()):length() > 150
    if v and v:getID() ~= (me and me:getID()) and away and not sl_fleet.atGarage(v:getPosition(), s) then
      v:queueLuaCommand(SMASH)
      sl_career.sendText('benny', string.format('%s got to your %s: the lights are smashed. Should have kept it in the garage.', crews.crew(r.crew).name:gsub('^%l', string.upper), car.name), 3)
      return
    end
  end
  sl_career.sendText('benny', string.format('%s came looking for your cars last night and found nothing. Good call.', crews.crew(r.crew).name:gsub('^%l', string.upper)), 3)
end

local timer = 0
function M.onUpdate(dtReal)
  timer = timer + (dtReal or 0)
  if timer < 5 then return end
  timer = 0
  local s = career()
  local c = s and s.crews
  if c and c.callouts and #c.callouts > 0 then sendCallouts(s, c) end
  if c then turfWarCheck(s, c) if c.turfWar then turfWarNext(s, c) end if c.raid then doRaid(s, c) end end
end

-- the crews trade a district between them now and then, overnight; call-outs not answered cost you
function M.onStreetLegalNewDay(day)
  local s = career()
  local c = s and M.ensure(s)
  if not c then return end
  for _, co in ipairs(c.callouts or {}) do
    local t = c.territory[co.district]
    if co.racer and t and t.owner == 'player' and co.day + 1 < day then     -- (a whole day and a night to answer it)
      t.control = t.control - CALLOUT_IGNORED
      for i = #s.challenges, 1, -1 do if s.challenges[i].callout == co.district then table.remove(s.challenges, i) end end
      if t.control <= 0 then t.owner, t.control = co.crew, crews.TAKEN_CONTROL end
    end
  end
  local keep = {}
  for _, co in ipairs(c.callouts or {}) do if co.day + 1 >= day then keep[#keep + 1] = co end end
  c.callouts = keep
  planRaid(s, c, day)
  local id, who = crews.nightly(c.territory, rngLib.new(rngLib.hash('crewnight:' .. tostring(day) .. ':' .. tostring(s.seed))))
  if id then
    for _, d in ipairs(c.districts or {}) do
      if d.id == id then sl_career.sendText('benny', string.format('%s pushed into %s last night.', crews.crew(who).name:gsub('^%l', string.upper), d.name), 2) end
    end
  end
end

-- a shop in one of your districts: 10 % off (Wrench Works asks when you walk in)
function M.onWrenchWorksShopOpened(shop, more)
  local c = career() and M.ensure()
  local d = c and shop and shop.pos and crews.districtOf(c.districts or {}, shop.pos.x, shop.pos.y)
  if d and type(more) == 'table' then more.extra = math.max(more.extra or 0, 1 - crews.perks(c.territory, d.id).shop) end
end

-- a racer's crew, for the contacts list
function M.crewOf(racerId)
  local c = M.ensure()
  local crew = c and crews.crew(c.member[racerId])
  return crew and crew.name or nil
end

-- the perks where the player stands (their districts)
function M.perksHere()
  local s = career()
  local c = s and M.ensure(s)
  local v = getPlayerVehicle(0)
  local d = c and v and crews.districtOf(c.districts or {}, v:getPosition().x, v:getPosition().y)
  return d and crews.perks(c.territory, d.id) or crews.perks({}, nil)
end

-- for the phone's Turf app
function M.summary()
  local s = career()
  local c = s and M.ensure(s)
  if not c then return nil end
  local here
  local v = getPlayerVehicle(0)
  if v then local d = crews.districtOf(c.districts or {}, v:getPosition().x, v:getPosition().y) here = d and d.id end
  local list = {}
  for _, d in ipairs(c.districts or {}) do
    local t = c.territory[d.id] or {}
    local crew = crews.crew(t.owner)
    list[#list + 1] = { id = d.id, name = d.name, owner = t.owner == 'player' and 'You' or (crew and crew.name or '?'), yours = t.owner == 'player',
      control = t.control or 0, home = t.home and crews.crew(t.home).name or nil, here = d.id == here }
  end
  local members = {}
  for _, cr in ipairs(crews.CREWS) do
    local lead = c.leader[cr.id] and stateLib.racer(s, c.leader[cr.id])
    members[#members + 1] = { name = cr.name, leader = lead and roster.displayName(lead) or nil }
  end
  return { districts = list, crews = members, held = crews.held(c.territory), turfWar = crews.turfWarReady(c.territory) }
end

function M.onStreetLegalStarted() local s = career() if s then M.ensure(s) end end

return M
