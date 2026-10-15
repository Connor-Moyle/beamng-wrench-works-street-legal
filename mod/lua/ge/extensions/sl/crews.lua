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

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
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

-- where the race starts decides whose turf it is
local raceDistrict
local function noteStart()
  local v = getPlayerVehicle(0)
  local d = v and M.districtAt(v:getPosition())
  raceDistrict = d and d.id or nil
end
M.onStreetLegalRaceStarted = noteStart
M.onSlrrRaceStarted = noteStart

function M.onStreetLegalRaceResult(won, opponent, racerId, stake)
  local s = career()
  local c = s and M.ensure(s)
  if not c or not raceDistrict or type(racerId) ~= 'string' then return end
  local crewId = c.member[racerId]
  local dist
  for _, d in ipairs(c.districts or {}) do if d.id == raceDistrict then dist = d end end
  local entry, event = crews.raceResult(c.territory, raceDistrict, crewId, c.leader[crewId] == racerId, won, stake == 'pink', c.friendly)
  raceDistrict = nil
  local crew = crews.crew(crewId)
  if not entry or not dist or not crew then return end
  if event == 'taken' then
    sl_career.sendText('benny', string.format('Word is %s is yours now. %s won\'t take that lying down.', dist.name, crew.name:gsub('^%l', string.upper)), 3)
    extensions.hook('onStreetLegalDistrictTaken', dist.id, crewId)
  elseif event == 'lost' then
    sl_career.sendText('benny', string.format('%s took %s back off you.', crew.name:gsub('^%l', string.upper), dist.name), 3)
  elseif entry.owner == crewId then
    toast(string.format('%s: %s hold it, %d%% control.', dist.name, crew.name, entry.control))
  end
  extensions.hook('onStreetLegalChanged')
end

-- the crews trade a district between them now and then, overnight
function M.onStreetLegalNewDay(day)
  local s = career()
  local c = s and M.ensure(s)
  if not c then return end
  local id, who = crews.nightly(c.territory, rngLib.new(rngLib.hash('crewnight:' .. tostring(day) .. ':' .. tostring(s.seed))))
  if id then
    for _, d in ipairs(c.districts or {}) do
      if d.id == id then sl_career.sendText('benny', string.format('%s pushed into %s last night.', crews.crew(who).name:gsub('^%l', string.upper), d.name), 2) end
    end
  end
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
