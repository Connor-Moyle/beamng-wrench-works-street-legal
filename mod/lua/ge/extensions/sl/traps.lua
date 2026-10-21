-- Street Legal: speed traps and speed zones (extension name: sl_traps; campaign idea #1). Rules and the choice of roads in sl/core/traps. The list lives in the career save (s.traps =
-- { level, list, rec = { [id] = { best, count, paid } } }) so a career keeps the same traps; the player's own motion is watched ten times a second, and only the traps within 150 m are tested.

local M = {}

local strings = require('sl/core/strings')
local rules = require('sl/core/traps')
local rngLib = require('sl/core/rng')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) if ui_message then ui_message(text, 5, 'streetLegal') end end

local function level() return getCurrentLevelIdentifier and getCurrentLevelIdentifier() or '' end

-- the traps of this career on this map (chosen once from the road graph, then kept in the save)
local function ensure(s)
  local lv = level()
  if s.traps and s.traps.level == lv and type(s.traps.list) == 'table' then return s.traps end
  local ok, nodes = pcall(function() return map.getMap().nodes end)
  if not (ok and nodes and next(nodes)) then return nil end            -- (the road graph is not up yet: tried again)
  local list = rules.select(nodes, rngLib.new(rngLib.hash('traps:' .. lv .. ':' .. tostring(s.seed))))
  s.traps = { level = lv, list = list, rec = (s.traps and s.traps.level == lv and s.traps.rec) or {} }
  return s.traps
end

local prev, near, nearAt, nearPos, zoneStart = nil, {}, -1e9, nil, {}
local timer = 0

local function result(s, t, kmh)
  local rec, info = rules.score(s.traps.rec[t.id], t, kmh)
  s.traps.rec[t.id] = rec
  local line = strings.t(t.kind == 'zone' and 'traps.zone_result' or 'traps.trap_result', t.name, math.floor(kmh), t.target)
  if info.first then
    sl_career.payOut(rules.PAY[t.kind], strings.t('traps.paid', t.name))
    require('sl/core/state').addRep(s, rules.REP)
    line = line .. ' ' .. strings.t('traps.target_met', rules.PAY[t.kind])
  elseif info.best and rec.count > 1 then
    line = line .. ' ' .. strings.t('traps.new_best')
  end
  toast(line)
  extensions.hook('onStreetLegalChanged')
end

function M.onUpdate(dt)
  timer = timer + (dt or 0)
  if timer < 0.1 then return end
  local step = timer
  timer = 0
  local s = career()
  local v = s and getPlayerVehicle(0)
  if not v then prev = nil return end
  local st = ensure(s)
  if not st then return end
  local p = v:getPosition()
  local now = { x = p.x, y = p.y }
  if prev and (now.x - prev.x) ^ 2 + (now.y - prev.y) ^ 2 > 80 ^ 2 then prev = nil end        -- (a teleport or a fast travel is no drive through a gate)
  local t0 = os.clock()
  if t0 - nearAt > 1 or (nearPos and (nearPos.x - now.x) ^ 2 + (nearPos.y - now.y) ^ 2 > 100 ^ 2) then          -- (a second, or a fast car that has moved 100 m)
    nearAt, nearPos, near = t0, now, {}
    for _, t in ipairs(st.list) do
      if (t.x - now.x) ^ 2 + (t.y - now.y) ^ 2 < (t.len / 2 + 150) ^ 2 then near[#near + 1] = t end
    end
  end
  if prev then
    for _, t in ipairs(near) do
      local d = { dx = t.dx, dy = t.dy }
      if t.kind == 'trap' then
        if rules.crossed(prev, now, t.g1, d) then result(s, t, v:getVelocity():length() * 3.6) end
      else
        if rules.crossed(prev, now, t.g1, d) then zoneStart[t.id] = t0
        elseif zoneStart[t.id] and rules.crossed(prev, now, t.g2, d) then
          local dt2 = t0 - zoneStart[t.id]
          zoneStart[t.id] = nil
          if dt2 >= 3 and dt2 <= rules.ZONE_MAX_TIME then result(s, t, (t.len / dt2) * 3.6) end
        elseif zoneStart[t.id] and t0 - zoneStart[t.id] > rules.ZONE_MAX_TIME then zoneStart[t.id] = nil end
      end
    end
  end
  prev = now
end

-- for the phone's list and the map: nil with no career or the roads not up yet
function M.summary()
  local s = career()
  local st = s and ensure(s)
  if not st then return nil end
  local v = getPlayerVehicle(0)
  local p = v and v:getPosition()
  local list = {}
  for _, t in ipairs(st.list) do
    local rec = st.rec[t.id] or {}
    list[#list + 1] = { id = t.id, name = t.name, kind = t.kind, target = t.target, best = rec.best or 0, count = rec.count or 0, paid = rec.paid == true, x = t.x, y = t.y,
      metres = p and math.floor(math.sqrt((t.x - p.x) ^ 2 + (t.y - p.y) ^ 2)) or nil, pay = rules.PAY[t.kind] }
  end
  return { list = list }
end

function M.onClientEndMission() prev, near, nearAt, nearPos, zoneStart = nil, {}, -1e9, nil, {} end

require('sl/core/features').gate('traps', M, nil, nil, { 'summary' })

return M
