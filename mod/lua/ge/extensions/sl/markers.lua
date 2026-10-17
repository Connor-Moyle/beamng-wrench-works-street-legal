-- Street Legal Racing: race markers and flares (extension name: sl_markers)
-- A start line you can see from down the street: a pulsing ring on the road, a chequered line
-- across it, two posts and the race's name above. And when a race starts, road flares - small
-- burning orange sticks, every few of them throwing a flickering light - along both edges of
-- the whole route, so the way is lit the full length of the track. The map's night races can
-- use both (see docs/integration.md); the career's own races always do.

local M = {}

local strings = require('sl/core/strings')

local flaresLib = require('sl/core/flares')

local SHAPE_DIR = '/temp/street_legal/shapes/'
local MATERIALS = '/art/street_legal/main.materials.json'
local SPACING = 18            -- metres between flares along a route
local MAX_FLARES = 120
local LIGHT_EVERY = 3         -- one flare in this many lights up the road round it

local flares = {}             -- { obj, light, phase, base }
local lights = {}             -- the lit ones, for the flicker: { phase, x, y, light }
local lastFlicker
local counter = 0
local clearAt                 -- os.clock() at which the flares go out
local flareShapePath

----------------------------------------------------------------------------------------------
-- the flare's model: a red stick with a glowing tip, written once to /temp

local function boxesToDae(boxes)
  local positions, groups, order, count = {}, {}, {}, 0
  local faces = {
    { { 2, 1, 1 }, { 2, 2, 1 }, { 2, 2, 2 }, { 2, 1, 2 } }, { { 1, 2, 1 }, { 1, 1, 1 }, { 1, 1, 2 }, { 1, 2, 2 } },
    { { 2, 2, 1 }, { 1, 2, 1 }, { 1, 2, 2 }, { 2, 2, 2 } }, { { 1, 1, 1 }, { 2, 1, 1 }, { 2, 1, 2 }, { 1, 1, 2 } },
    { { 1, 1, 2 }, { 2, 1, 2 }, { 2, 2, 2 }, { 1, 2, 2 } }, { { 1, 2, 1 }, { 2, 2, 1 }, { 2, 1, 1 }, { 1, 1, 1 } },
  }
  for _, b in ipairs(boxes) do
    local xs, ys, zs = { b[1], b[4] }, { b[2], b[5] }, { b[3], b[6] }
    local list = groups[b[7]]
    if not list then list = {}; groups[b[7]] = list; order[#order + 1] = b[7] end
    for f, face in ipairs(faces) do
      local base = count
      for _, c in ipairs(face) do
        positions[#positions + 1] = string.format('%.4f %.4f %.4f', xs[c[1]], ys[c[2]], zs[c[3]])
        count = count + 1
      end
      local n = f - 1
      list[#list + 1] = string.format('%d %d %d %d %d %d %d %d %d %d %d %d', base, n, base + 1, n, base + 2, n, base, n, base + 2, n, base + 3, n)
    end
  end
  local out = {
    strings.t('markers.xml_version_1_0_encoding'),
    strings.t('markers.collada_xmlns_http_www_collada'),
    '<asset><unit name="meter" meter="1"/><up_axis>Z_UP</up_axis></asset>',
    '<library_effects><effect id="fx"><profile_COMMON><technique sid="common"><phong><diffuse><color>1 1 1 1</color></diffuse></phong></technique></profile_COMMON></effect></library_effects>',
    '<library_materials>',
  }
  for _, name in ipairs(order) do out[#out + 1] = string.format(strings.t('markers.material_id_s_material_name'), name, name) end
  out[#out + 1] = '</library_materials><library_geometries><geometry id="mesh" name="mesh"><mesh>'
  out[#out + 1] = string.format(strings.t('markers.source_id_pos_float_array'), count * 3, table.concat(positions, ' '), count)
  out[#out + 1] = '<source id="nrm"><float_array id="nrm-array" count="18">1 0 0 -1 0 0 0 1 0 0 -1 0 0 0 1 0 0 -1</float_array><technique_common><accessor source="#nrm-array" count="6" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common></source>'
  out[#out + 1] = '<vertices id="vtx"><input semantic="POSITION" source="#pos"/></vertices>'
  local binds = {}
  for _, name in ipairs(order) do
    out[#out + 1] = string.format(strings.t('markers.triangles_material_s_material_count'), name, #groups[name] * 2, table.concat(groups[name], ' '))
    binds[#binds + 1] = string.format(strings.t('markers.instance_material_symbol_s_material'), name, name)
  end
  out[#out + 1] = '</mesh></geometry></library_geometries>'
  out[#out + 1] = '<library_visual_scenes><visual_scene id="Scene" name="Scene"><node id="slflare" name="slflare" type="NODE"><instance_geometry url="#mesh" name="slflare"><bind_material><technique_common>' .. table.concat(binds) .. '</technique_common></bind_material></instance_geometry></node></visual_scene></library_visual_scenes>'
  out[#out + 1] = '<scene><instance_visual_scene url="#Scene"/></scene></COLLADA>'
  return table.concat(out, '\n')
end

local function flareShape()
  if flareShapePath then return flareShapePath end
  if FS:fileExists(MATERIALS) and not scenetree.findObject('sl_flare_tip') then loadJsonMaterialsFile(MATERIALS) end
  local path = SHAPE_DIR .. 'flare_v1.dae'
  if not FS:fileExists(path) then
    writeFile(path, boxesToDae({
      { -0.02, -0.02, 0, 0.02, 0.02, 0.2, 'sl_flare_body' },          -- the stick, standing on the road
      { -0.028, -0.028, 0.2, 0.028, 0.028, 0.255, 'sl_flare_tip' },   -- the burning end
      { -0.05, -0.012, 0, 0.05, 0.012, 0.008, 'sl_flare_body' },      -- its little stand
    }))
  end
  flareShapePath = path
  return path
end

----------------------------------------------------------------------------------------------
-- putting flares down and taking them away

local function ground(pos)
  local from = pos + vec3(0, 0, 3)
  local d = castRayStatic(from, vec3(0, 0, -1), 10)
  if d and d < 10 then return from - vec3(0, 0, d) end
  return pos
end

local function addFlare(pos, withLight)
  if #flares >= MAX_FLARES then return end
  counter = counter + 1
  local o = createObject('TSStatic')
  o:setField('shapeName', 0, flareShape())
  o:setField('collisionType', 0, 'None')
  o:setField('decalType', 0, 'None')
  o.canSave = false
  o:registerObject('slFlare' .. counter)
  local m = MatrixF(true)
  m:setPosition(pos)
  o:setTransform(m)
  local light
  if withLight then
    light = createObject('PointLight')
    light.canSave = false
    light.radius = 6
    light:setField('color', 0, '1 0.42 0.08 1')
    light:setField('castShadows', 0, '0')
    light:registerObject('slFlareLight' .. counter)
    local lm = MatrixF(true)
    lm:setPosition(pos + vec3(0, 0, 0.35))
    light:setTransform(lm)
  end
  flares[#flares + 1] = { obj = o, light = light, phase = counter * 1.7, base = 0.9 }
  if light then lights[#lights + 1] = { phase = counter * 1.7, x = pos.x, y = pos.y, light = light } end
end

function M.clear()
  for _, f in ipairs(flares) do
    pcall(function() f.obj:delete() end)
    if f.light then pcall(function() f.light:delete() end) end
  end
  flares, lights, clearAt, lastFlicker = {}, {}, nil, nil
end

-- the flares go out a little after the race (so the finish is still lit as you cross it)
function M.clearSoon(seconds) clearAt = os.clock() + (seconds or 8) end

-- both edges of a road polyline: points = { { pos = vec3, radius = number } }
local function lineFlares(points)
  local placed, carry = 0, 0
  for i = 2, #points do
    local a, b = points[i - 1], points[i]
    local seg = b.pos - a.pos
    local len = seg:length()
    if len > 0.1 then
      local dir = seg / len
      local right = dir:cross(vec3(0, 0, 1)):normalized()
      local s = SPACING - carry
      while s <= len do
        local k = s / len
        local centre = a.pos + seg * k
        local half = ((a.radius or 4) * (1 - k) + (b.radius or 4) * k) * 0.95
        placed = placed + 1
        local lit = placed % LIGHT_EVERY == 1
        addFlare(ground(centre + right * half), lit)
        addFlare(ground(centre - right * half), lit)
        s = s + SPACING
      end
      carry = len - (s - SPACING)
    end
  end
end

-- flares along the road from one point to another (the way the AI would drive it); a straight
-- line when there is no road between them (a drag strip)
-- (off in the settings: sl_options' race flares and start lines)
local function off() return sl_options and sl_options.get('slMarkers') == false end

function M.flareRoute(from, to)
  M.clear()
  if off() then return end
  local points = {}
  local ok, path = pcall(function() return map.getPointToPointPath(from, to) end)
  local nodes = map and map.getMap and map.getMap().nodes or {}
  if ok and type(path) == 'table' and #path >= 2 then
    points[1] = { pos = from, radius = 4 }
    for _, name in ipairs(path) do
      local n = nodes[name]
      if n then points[#points + 1] = { pos = n.pos, radius = n.radius } end
    end
    points[#points + 1] = { pos = to, radius = 4 }
  else
    points = { { pos = from, radius = 5 }, { pos = to, radius = 5 } }
  end
  lineFlares(points)
end

-- a circuit: flares at both sides of every checkpoint. cps = { { pos, dir, half } }
function M.flareCircuit(cps)
  M.clear()
  if off() then return end
  for i, c in ipairs(cps) do
    local right = c.dir:cross(vec3(0, 0, 1)):normalized()
    local lit = i % 2 == 1
    addFlare(ground(c.pos + right * (c.half + 1)), lit)
    addFlare(ground(c.pos - right * (c.half + 1)), lit)
  end
end

----------------------------------------------------------------------------------------------
-- a start line (drawn every frame by whoever wants one; nothing is created)

local ringColor, postColor = ColorF(1, 0.45, 0.05, 0.3), ColorF(1, 0.5, 0.1, 0.9)
local black, white = ColorF(0.05, 0.05, 0.05, 0.85), ColorF(0.95, 0.95, 0.95, 0.85)
local textColor, textBg = ColorF(1, 1, 1, 1), ColorI(25, 12, 0, 210)

-- pos: the middle of the line on the road; dir: the way the race goes; color: a ColorF for the ring
function M.drawStart(pos, dir, label, color, width)
  if off() then return end
  local cam = core_camera and core_camera.getPosition and core_camera.getPosition()
  local dist = cam and (cam - pos):length() or 0
  if dist > 450 then return end
  dir = vec3(dir.x, dir.y, 0)
  dir = dir:length() > 0.01 and dir:normalized() or vec3(0, 1, 0)
  local right = dir:cross(vec3(0, 0, 1)):normalized()
  local pulse = 0.5 + 0.5 * math.sin(os.clock() * 3)
  local ring = color or ringColor
  ring.a = 0.18 + 0.18 * pulse
  debugDrawer:drawCylinder(pos, pos + vec3(0, 0, 0.06), 4.5, ring)
  width = width or 8
  -- the chequered line: two rows of half-metre squares across the road
  local sq = 0.5
  local n = math.floor(width / sq)
  for row = 0, 1 do
    for i = 0, n - 1 do
      local a = pos + right * (-width / 2 + i * sq + sq / 2) + dir * (row * sq) + vec3(0, 0, 0.03)
      debugDrawer:drawSquarePrism(a, a + dir * sq, Point2F(0.02, sq), Point2F(0.02, sq), ((i + row) % 2 == 0) and black or white)
    end
  end
  -- posts either side, and the name between them
  local left, rightPost = pos - right * (width / 2 + 0.6), pos + right * (width / 2 + 0.6)
  debugDrawer:drawCylinder(left, left + vec3(0, 0, 3), 0.08, postColor)
  debugDrawer:drawCylinder(rightPost, rightPost + vec3(0, 0, 3), 0.08, postColor)
  if dist < 160 and label then
    debugDrawer:drawTextAdvanced(pos + vec3(0, 0, 3.4), String(label), textColor, true, false, textBg)
  end
end

----------------------------------------------------------------------------------------------
-- hooks

-- nothing per frame without flares; with them, the flicker writes a few lights' intensity ten times a second
-- (sl/core/flares: the rate and the reach are rules, tested outside the game)
function M.onUpdate()
  if clearAt and os.clock() > clearAt then M.clear() end
  if #lights == 0 then return end
  local cam = core_camera and core_camera.getPosition and core_camera.getPosition()
  local writes
  writes, lastFlicker = flaresLib.flicker(lights, os.clock(), lastFlicker, cam and { x = cam.x, y = cam.y } or nil)
  for _, w in ipairs(writes) do lights[w[1]].light.intensity = w[2] end
end

-- the map's night races (see docs/integration.md)
function M.onSlrrRaceStarted(data)
  if type(data) ~= 'table' then return end
  local function v(t) return type(t) == 'table' and vec3(tonumber(t[1] or t.x) or 0, tonumber(t[2] or t.y) or 0, tonumber(t[3] or t.z) or 0) or nil end
  local from, to = v(data.start), v(data.finish)
  if from and to then M.flareRoute(from, to) end
end

function M.onSlrrRaceFinished() M.clearSoon(8) end
function M.onClientEndMission() flares, lights, clearAt, lastFlicker, flareShapePath = {}, {}, nil, nil, nil end
M.onExtensionUnloaded = M.clear

return M
