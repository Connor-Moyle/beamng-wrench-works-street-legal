-- Street Legal: ambient sound zones (extension name: sl_ambience; #46)
-- Placed, mono ambience near the player: waves at the water's edge, the roar of a wide road, a crowd in town (by day, not in the rain), and at a car
-- meet its crowd and music (the radio station files: /settings/slrr_garage/music/<station>/ and /art/sound/slrr_garage/music/). What should be
-- playing is decided in sl/core/ambience from the player's surroundings; here the sources are made, placed, faded by distance and dropped when
-- the player has moved away from them (nothing plays or is kept out of range). The loops are synthesised (tools/make_ambience.py).

local M = {}

local rules = require('sl/core/ambience')

local DIR = '/art/sound/street_legal/ambience/'
local MUSIC_DIRS = { '/settings/slrr_garage/music/', '/art/sound/slrr_garage/music/' }
local PLACED = 'AudioDefault3D'
local sources = {}            -- emitter id -> { sid = the sound source's id, file }
local timer, nodeTimer = 0, 0
local nodeCache
local tracks, trackAt = nil, 0
local waterZ
local volumeScale = 1
M.USE_STOCK = false          -- stock game events instead of the synthesised loops, once sl_ambience.probe() shows them to exist
local stockOk = {}           -- kind -> the stock event that made a source (or false)

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function source(e) return e and e.sid and scenetree.findObjectById(e.sid) or nil end

local function drop(id)
  local e = sources[id]
  sources[id] = nil
  if not e then return end
  local snd = source(e)
  if snd then snd:stop(-1) end
  if e.sid then Engine.Audio.deleteSource(e.sid) end
end

local function dropAll() for id in pairs(sources) do drop(id) end end

local function musicFile()
  if not tracks then
    tracks = {}
    for _, dir in ipairs(MUSIC_DIRS) do
      for _, f in ipairs(FS:findFiles(dir, '*.ogg\t*.wav\t*.flac', -1, false, false) or {}) do tracks[#tracks + 1] = f end
    end
    for i = #tracks, 2, -1 do local j = math.random(i) tracks[i], tracks[j] = tracks[j], tracks[i] end
  end
  if #tracks == 0 then return nil end
  trackAt = trackAt % #tracks + 1
  return tracks[trackAt]
end

local function water()
  if waterZ == nil then
    waterZ = false
    local ok, list = pcall(getObjectsByClass, 'WaterPlane')
    for _, o in pairs(ok and list or {}) do waterZ = o:getPosition().z break end
  end
  return waterZ or nil
end

local function roadNodes()
  if not nodeCache or nodeTimer <= 0 then
    nodeTimer = 3
    local ok, nodes = pcall(function() return map.getMap().nodes end)
    nodeCache = ok and nodes or {}
  end
  return nodeCache
end

local function context()
  local v = getPlayerVehicle(0)
  if not v then return nil end
  local p = v:getPosition()
  local meetPos = sl_streets and sl_streets.meetPos and sl_streets.meetPos()
  local speaker = meetPos and sl_streets.meetSpeakerPos and sl_streets.meetSpeakerPos() or meetPos
  return {
    player = { x = p.x, y = p.y, z = p.z },
    height = function(x, y) local ok, h = pcall(core_terrain.getTerrainHeight, vec3(x, y, 0)) return ok and h or nil end,
    waterZ = water(), nodes = roadNodes(), places = sl_career.getPlaces(), phase = sl_career.phase(),
    meet = meetPos and { pos = { x = meetPos.x, y = meetPos.y, z = meetPos.z }, speaker = { x = speaker.x, y = speaker.y, z = speaker.z } } or nil,
    raining = sl_weather and sl_weather.state and sl_weather.state() == 'rain',
  }
end

local function ensure(em)
  local e = sources[em.id]
  if not e then
    local file = em.file and (DIR .. em.file) or musicFile()
    if not file then return end
    local sid
    if M.USE_STOCK and em.file then
      if stockOk[em.kind] == nil then
        stockOk[em.kind] = false
        for _, ev in ipairs(rules.STOCK[em.kind] or {}) do
          local id = Engine.Audio.createSource(PLACED, ev)
          if type(id) == 'number' and id ~= 0 and scenetree.findObjectById(id) then stockOk[em.kind] = ev Engine.Audio.deleteSource(id) break end
        end
      end
      if stockOk[em.kind] then file = stockOk[em.kind] end
    end
    sid = Engine.Audio.createSource(PLACED, file)
    if type(sid) ~= 'number' or sid == 0 or not scenetree.findObjectById(sid) then return end
    e = { sid = sid, file = file }
    sources[em.id] = e
  end
  local snd = source(e)
  if not snd then sources[em.id] = nil return end
  local m = MatrixF(true)
  m:setPosition(vec3(em.pos.x, em.pos.y, em.pos.z))
  if snd.setTransform then snd:setTransform(m) end
  snd:setVolume(em.volume * volumeScale)
  if not snd:isPlaying() and (not e.at or os.clock() - e.at > 3) then          -- (a source takes a moment to report that it is playing)
    if em.kind == 'music' and e.started then          -- the track is over: the next one
      drop(em.id)
      return
    end
    snd:play(-1)
    e.started, e.at = true, os.clock()
  end
end

-- which stock events the running game accepts: one log line per candidate (read the game log for 'sl_ambience probe')
function M.probe()
  local out = {}
  for kind, list in pairs(rules.STOCK) do
    for _, ev in ipairs(list) do
      local ok, id = pcall(Engine.Audio.createSource, PLACED, ev)
      local valid = ok and type(id) == 'number' and id ~= 0 and scenetree.findObjectById(id) ~= nil
      if valid then pcall(Engine.Audio.deleteSource, id) end
      out[#out + 1] = kind .. ' ' .. ev .. ' -> ' .. (valid and 'source made' or 'refused')
      log('I', 'street_legal', 'sl_ambience probe: ' .. out[#out])
    end
  end
  return out
end

function M.setVolume(v) volumeScale = math.max(0, math.min(1, tonumber(v) or 1)) end

function M.onUpdate(dtReal)
  dtReal = dtReal or 0
  if not career() or not Engine or not Engine.Audio then
    if next(sources) then dropAll() end
    return
  end
  nodeTimer = nodeTimer - dtReal
  timer = timer - dtReal
  if timer > 0 then return end
  timer = 1.5
  -- in a garage, a menu or a cab: the world is not heard
  local silent = (slrr_garage and slrr_garage.getPhase and slrr_garage.getPhase() ~= 'idle') or (simTimeAuthority and simTimeAuthority.getPause and simTimeAuthority.getPause()) or (sl_lot and sl_lot.uiHidden and sl_lot.uiHidden())
  local ctx = not silent and context() or nil
  local plan = ctx and rules.plan(ctx) or {}
  local wanted = {}
  for _, em in ipairs(plan) do wanted[em.id] = true ensure(em) end
  for id in pairs(sources) do if not wanted[id] then drop(id) end end
end

function M.status()
  local out = {}
  for id, e in pairs(sources) do out[id] = e.file end
  return out
end

function M.onStreetLegalStopped() dropAll() nodeCache, waterZ, stockOk = nil, nil, {} end
function M.onClientEndMission() dropAll() nodeCache, waterZ = nil, nil tracks = nil end
function M.onExtensionUnloaded() dropAll() end

-- (the Mods menu's Parts of the game: with this part off, the hooks above do nothing)
require('sl/core/features').gate('ambience', M)

return M
