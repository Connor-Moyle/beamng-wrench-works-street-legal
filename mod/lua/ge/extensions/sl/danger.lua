-- Street Legal: danger zones (extension name: sl_danger; campaign idea #2). Rules in sl/core/danger (and the choice of roads in sl/core/traps). Two things are watched while you drive:
-- how far you fly (the longest jump, with prizes for 20, 40, 70 and 110 m, each paid once) and the drift points you score between the two gates of a drift zone (two long roads, chosen once).
-- Saved in the career as s.danger = { level, drift = { list, rec = { [id] = { best, count, paid } } }, jump = { paid, best, count } }.

local M = {}

local strings = require('sl/core/strings')
local rules = require('sl/core/danger')
local traps = require('sl/core/traps')
local rngLib = require('sl/core/rng')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) if ui_message then ui_message(text, 5, 'streetLegal') end end
local function level() return getCurrentLevelIdentifier and getCurrentLevelIdentifier() or '' end

-- s.danger = { levels = { [level] = { list, rec } }, jump = { paid, best, count } }: the drift zones and their records are per map, the jump record is the career's (the first shape of this part,
-- { level, drift = { list, rec }, jump }, is read as that level's entry). Returns { drift = { list, rec }, jump } for this map, or nil while the road graph is not up.
local function ensure(s)
  local lv = level()
  local d = s.danger
  if type(d) == 'table' and d.level ~= nil and d.levels == nil then d = { levels = { [d.level] = d.drift }, jump = d.jump } end
  if type(d) ~= 'table' then d = {} end
  d.levels = d.levels or {}
  d.jump = d.jump or { paid = 0, best = 0, count = 0 }
  s.danger = d
  local e = d.levels[lv]
  if not (e and type(e.list) == 'table') then
    local ok, nodes = pcall(function() return map.getMap().nodes end)
    if not (ok and nodes and next(nodes)) then return nil end
    local tl = s.traps and s.traps.levels and s.traps.levels[lv]
    e = { list = traps.selectDrift(nodes, rngLib.new(rngLib.hash('drift:' .. lv .. ':' .. tostring(s.seed))), 2, tl and tl.list or {}), rec = {} }
    d.levels[lv] = e
  end
  e.rec = e.rec or {}
  return { drift = e, jump = d.jump }
end

local prev, jumpSt, nearList, nearAt, nearPos = nil, rules.newJump(), {}, -1e9, nil
local active = {}              -- drift zone id -> points so far, while between its gates
local timer = 0

local function airborne(p)
  if not castRayStatic then return false end
  local ok, dist = pcall(castRayStatic, p + vec3(0, 0, 0.3), vec3(0, 0, -1), 6)
  return ok and type(dist) == 'number' and dist > 1.8 and dist < 6
end

local function finishJump(d, dist)
  local j = d.jump
  j.count, j.best = j.count + 1, math.max(j.best, dist)
  local n, prizes = rules.ladder(j.paid, dist)
  local line = strings.t('danger.jump', math.floor(dist + 0.5))
  local total = 0
  for _, p in ipairs(prizes) do total = total + p end
  j.paid = n
  if total > 0 then
    sl_career.payOut(total, strings.t('danger.jump_label'))
    line = line .. ' ' .. strings.t('danger.prize', total)
  end
  toast(line)
  extensions.hook('onStreetLegalChanged')
end

local function finishDrift(s, d, t, points)
  local rec = d.drift.rec[t.id] or { best = 0, count = 0, paid = false }
  points = math.floor(points)
  local new = { best = math.max(rec.best, points), count = rec.count + 1, paid = rec.paid }
  local line = strings.t('danger.drift_result', t.name, points, t.target)
  if not rec.paid and points >= t.target then
    new.paid = true
    sl_career.payOut(rules.DRIFT_PAY, strings.t('danger.drift_label'))
    require('sl/core/state').addRep(s, rules.DRIFT_REP)
    line = line .. ' ' .. strings.t('danger.prize', rules.DRIFT_PAY)
  elseif points > rec.best and rec.count > 0 then
    line = line .. ' ' .. strings.t('traps.new_best')
  end
  d.drift.rec[t.id] = new
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
  if not v or v:getJBeamFilename() == 'unicycle' then prev, active, jumpSt = nil, {}, rules.newJump() return end
  local d = ensure(s)
  if not d then return end
  local p = v:getPosition()
  local now = { x = p.x, y = p.y }
  if prev and (now.x - prev.x) ^ 2 + (now.y - prev.y) ^ 2 > 80 ^ 2 then prev, active, jumpSt = nil, {}, rules.newJump() end
  -- the jump
  local dist = rules.jumpStep(jumpSt, airborne(p), now.x, now.y, step)
  if dist then finishJump(d, dist) end
  -- the drift zones
  local t0 = os.clock()
  if t0 - nearAt > 1 or (nearPos and (nearPos.x - now.x) ^ 2 + (nearPos.y - now.y) ^ 2 > 100 ^ 2) then
    nearAt, nearPos, nearList = t0, now, {}
    for _, t in ipairs(d.drift.list) do
      if (t.x - now.x) ^ 2 + (t.y - now.y) ^ 2 < (t.len / 2 + 150) ^ 2 then nearList[#nearList + 1] = t end
    end
  end
  if prev then
    for _, t in ipairs(nearList) do
      local dir = { dx = t.dx, dy = t.dy }
      if traps.crossed(prev, now, t.g1, dir) then
        active[t.id] = 0
      elseif active[t.id] and traps.crossed(prev, now, t.g2, dir) then
        local pts = active[t.id]
        active[t.id] = nil
        finishDrift(s, d, t, pts)
      end
    end
    if next(active) then
      local vel, dirv = v:getVelocity(), v:getDirectionVector()
      local pts = rules.driftPoints(vel:length(), rules.slipAngle(vel.x, vel.y, dirv.x, dirv.y), step)
      if pts > 0 then for id in pairs(active) do active[id] = active[id] + pts end end
    end
  end
  prev = now
end

-- for the phone: { drift = { { id, name, target, best, count, paid, x, y, metres, pay } }, jump = { best, count, next (metres of the next rung or nil), prize } }
function M.summary()
  local s = career()
  local d = s and ensure(s)
  if not d then return nil end
  local v = getPlayerVehicle(0)
  local p = v and v:getPosition()
  local drift = {}
  for _, t in ipairs(d.drift.list) do
    local rec = d.drift.rec[t.id] or {}
    drift[#drift + 1] = { id = t.id, name = t.name, target = t.target, best = rec.best or 0, count = rec.count or 0, paid = rec.paid == true, x = t.x, y = t.y,
      metres = p and math.floor(math.sqrt((t.x - p.x) ^ 2 + (t.y - p.y) ^ 2)) or nil, pay = rules.DRIFT_PAY }
  end
  local nextRung = rules.JUMPS[d.jump.paid + 1]
  return { drift = drift, jump = { best = math.floor(d.jump.best), count = d.jump.count, next = nextRung and nextRung[1] or nil, prize = nextRung and nextRung[2] or nil } }
end

function M.onClientEndMission() prev, active, jumpSt, nearList, nearAt, nearPos = nil, {}, rules.newJump(), {}, -1e9, nil end

require('sl/core/features').gate('danger', M, nil, nil, { 'summary' })

return M
