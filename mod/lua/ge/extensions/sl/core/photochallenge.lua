-- Street Legal: photo challenges (campaign idea #3; the control repo's docs/PHOTO_CHALLENGES.md). Pure, no game calls: tested by tools/luatest.js.
-- A challenge is a few parts the picture must show: your car in the colour family, under or over so many hp, near a place, at a time of day. Three a week come from a seeded
-- pool that only asks for what the player can do (the colour and power of a car they own). A frame is judged from a snapshot the game side takes at the shutter:
-- the camera basis, the corners of the car's box (and whether a ray from the camera reaches each), its colour, power and position, the places, the hour.

local rngLib = require('sl/core/rng')
local strings = require('sl/core/strings')

local M = {}

M.PER_WEEK = 3
M.PLACE_R = 80                -- metres from a place's middle that count as "at" it
M.MIN_HEIGHT = 0.20           -- the car's box must be this share of the picture's height
M.MIN_CORNERS = 3             -- corners of the car's box in the picture, and corners a ray reaches
M.PAY_SCALE = 1               -- what a done challenge pays, times this

-- the player's settings (Mods menu): challenges a week (the list of a week already made keeps its size), the radius of "at a place", the pay scale; clamped here
function M.configure(perWeek, radius, payScale)
  M.PER_WEEK = math.floor(math.max(1, math.min(6, tonumber(perWeek) or 3)) + 0.5)
  M.PLACE_R = math.max(30, math.min(200, tonumber(radius) or 80))
  M.PAY_SCALE = math.max(0.25, math.min(4, tonumber(payScale) or 1))
end

M.COLOURS = { 'red', 'orange', 'yellow', 'green', 'blue', 'white', 'black', 'silver' }
M.BANDS = { 'dawn', 'day', 'sunset', 'night' }

-- colour family of an RGB colour (0..1 each): grey scale by value, otherwise by hue; purple, pink and brown are 'other' (no challenge asks for them)
function M.colourFamily(r, g, b)
  r, g, b = tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local d = mx - mn
  local sat = mx > 0 and d / mx or 0
  if mx < 0.16 then return 'black' end
  if sat < 0.16 then
    if mx > 0.82 then return 'white' end
    if mx < 0.28 then return 'black' end
    return 'silver'
  end
  local h
  if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
  h = h * 60
  if h < 12 or h >= 345 then return 'red' end
  if h < 40 then return mx < 0.55 and 'other' or 'orange' end         -- (dark orange is brown)
  if h < 70 then return 'yellow' end
  if h < 165 then return 'green' end
  if h < 255 then return 'blue' end
  return 'other'
end

-- the band of an hour (0..24): dawn 5-8, day 8-17, sunset 17-20, night 20-5
function M.hourBand(hour)
  local h = (tonumber(hour) or 12) % 24
  if h >= 5 and h < 8 then return 'dawn' end
  if h >= 8 and h < 17 then return 'day' end
  if h >= 17 and h < 20 then return 'sunset' end
  return 'night'
end

-- a world point on the picture: x, y in 0..1 (y down) and the depth in front of the camera. cam = { pos = {x,y,z}, fwd, right, up, tanX, tanY }
function M.project(cam, p)
  local rx, ry, rz = p[1] - cam.pos[1], p[2] - cam.pos[2], p[3] - cam.pos[3]
  local depth = rx * cam.fwd[1] + ry * cam.fwd[2] + rz * cam.fwd[3]
  if depth <= 0.1 then return nil, nil, depth end
  local x = rx * cam.right[1] + ry * cam.right[2] + rz * cam.right[3]
  local y = rx * cam.up[1] + ry * cam.up[2] + rz * cam.up[3]
  return 0.5 + 0.5 * x / (depth * cam.tanX), 0.5 - 0.5 * y / (depth * cam.tanY), depth
end

-- is the car shown: corners = 8 points, clear = a table of booleans (a ray from the camera reaches the corner), nil clear means unknown (counted as not clear).
-- Returns { seen, clear, big, height } ; the height is the share of the picture's height the corners inside the picture span
function M.visible(cam, corners, clear)
  local inFrame, reached, lo, hi = 0, 0, 1, 0
  for i, c in ipairs(corners or {}) do
    local x, y = M.project(cam, c)
    if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
      inFrame = inFrame + 1
      if clear and clear[i] then reached = reached + 1 end
      lo, hi = math.min(lo, y), math.max(hi, y)
    end
  end
  local height = inFrame > 0 and (hi - lo) or 0
  return { seen = inFrame >= M.MIN_CORNERS, clear = reached >= M.MIN_CORNERS, big = height >= M.MIN_HEIGHT, height = height }
end

-- the parts a challenge asks for, as a list of ids
function M.partsOf(ch)
  local out = {}
  if ch.colour then out[#out + 1] = 'colour' end
  if ch.hpMax or ch.hpMin then out[#out + 1] = 'power' end
  if ch.place then out[#out + 1] = 'place' end
  if ch.band then out[#out + 1] = 'time' end
  return out
end

-- what a done challenge pays: more parts, more money and rep
function M.pay(ch)
  local n = math.max(1, #M.partsOf(ch))
  return { money = math.floor((40 + 90 * n) * M.PAY_SCALE + 0.5), rep = math.min(3, n) }
end

-- one car of the snapshot against the challenge: { picture = { seen, clear, big }, colour = bool|nil, power = ..., place = ..., time = ..., ok }
local function judge(ch, shot, car)
  local vis = M.visible(shot.cam, car.corners, car.rayClear)
  local r = { seen = vis.seen, clear = vis.clear, big = vis.big }
  if ch.colour then r.colour = car.rgb ~= nil and M.colourFamily(car.rgb[1], car.rgb[2], car.rgb[3]) == ch.colour end
  if ch.hpMax then r.power = tonumber(car.hp) ~= nil and car.hp < ch.hpMax end
  if ch.hpMin then r.power = tonumber(car.hp) ~= nil and car.hp > ch.hpMin end
  if ch.place then
    local p = shot.places and shot.places[ch.place]
    local c = car.pos
    r.place = p ~= nil and c ~= nil and math.sqrt((p[1] - c[1]) ^ 2 + (p[2] - c[2]) ^ 2) <= M.PLACE_R
  end
  if ch.band then r.time = M.hourBand(shot.hour) == ch.band end
  r.ok = r.seen and r.clear and r.big and r.colour ~= false and r.power ~= false and r.place ~= false and r.time ~= false
  return r
end

-- the verdict for a snapshot: { ok, result = the best car's judgement, reasons = { 'photoch.why_small', ... } }. Own-car challenges look at the car marked own only.
function M.check(ch, shot)
  local best, bestScore
  for _, car in ipairs(type(shot) == 'table' and shot.cars or {}) do
    if car.own or not ch.own then
      local r = judge(ch, shot, car)
      local score = (r.ok and 100 or 0) + (r.seen and 8 or 0) + (r.clear and 4 or 0) + (r.big and 2 or 0)
        + ((r.colour ~= false and r.power ~= false and r.place ~= false and r.time ~= false) and 16 or 0)
      if not bestScore or score > bestScore then best, bestScore = r, score end
    end
  end
  if not best then return { ok = false, result = {}, reasons = { 'photoch.why_no_car' } } end
  local why = {}
  if not best.seen then why[#why + 1] = 'photoch.why_not_in_frame'
  elseif not best.clear then why[#why + 1] = 'photoch.why_blocked'
  elseif not best.big then why[#why + 1] = 'photoch.why_small' end
  if best.colour == false then why[#why + 1] = 'photoch.why_colour' end
  if best.power == false then why[#why + 1] = 'photoch.why_power' end
  if best.place == false then why[#why + 1] = 'photoch.why_place' end
  if best.time == false then why[#why + 1] = 'photoch.why_time' end
  return { ok = best.ok, result = best, reasons = why }
end

-- the week's challenges. ctx: { ownColours = { 'red', ... } (families of the cars the player owns), ownHp = { 120, ... }, places = { { id, name } } }.
-- A part is only drawn when the player can meet it. Deterministic for a seed and week; no two the same.
function M.pool(seed, week, ctx)
  ctx = ctx or {}
  local rng = rngLib.new(rngLib.hash('photo:' .. tostring(seed) .. ':' .. tostring(week)))
  local out, seen = {}, {}
  local tries = 0
  while #out < M.PER_WEEK and tries < 60 do
    tries = tries + 1
    local ch = { id = string.format('w%d_%d', week, #out + 1), own = true }
    local want = rng:int(1, 3)
    local kinds = { 'colour', 'power', 'place', 'time' }
    for i = #kinds, 2, -1 do local j = rng:int(1, i) kinds[i], kinds[j] = kinds[j], kinds[i] end
    local got = 0
    for _, kind in ipairs(kinds) do
      if got >= want then break end
      if kind == 'colour' and #(ctx.ownColours or {}) > 0 then
        ch.colour = ctx.ownColours[rng:int(1, #ctx.ownColours)] got = got + 1
      elseif kind == 'power' and #(ctx.ownHp or {}) > 0 then
        local hp = ctx.ownHp[rng:int(1, #ctx.ownHp)]
        if rng:int(1, 2) == 1 then ch.hpMax = (math.floor(hp / 10) + 1 + rng:int(0, 3)) * 10 else ch.hpMin = math.max(0, (math.floor(hp / 10) - 1 - rng:int(0, 3)) * 10) end
        got = got + 1
      elseif kind == 'place' and #(ctx.places or {}) > 0 then
        local p = ctx.places[rng:int(1, #ctx.places)]
        ch.place, ch.placeName = p.id, p.name got = got + 1
      elseif kind == 'time' then
        ch.band = M.BANDS[rng:int(1, #M.BANDS)] got = got + 1
      end
    end
    if got == 0 then ch.band = M.BANDS[rng:int(1, #M.BANDS)] end         -- (a player with nothing to match still gets a time of day)
    local sig = tostring(ch.colour) .. '|' .. tostring(ch.hpMax) .. '|' .. tostring(ch.hpMin) .. '|' .. tostring(ch.place) .. '|' .. tostring(ch.band)
    if not seen[sig] then
      seen[sig] = true
      local pay = M.pay(ch)
      ch.money, ch.rep = pay.money, pay.rep
      out[#out + 1] = ch
    end
  end
  return out
end

-- the line the phone shows: "Photograph your red car under 120 hp at the Pier at sunset."
function M.describe(ch)
  local car = strings.t('photoch.your_car', ch.colour and (strings.t('photoch.c_' .. ch.colour) .. ' ') or '')
  local power = ch.hpMax and (' ' .. strings.t('photoch.under_hp', ch.hpMax)) or (ch.hpMin and (' ' .. strings.t('photoch.over_hp', ch.hpMin)) or '')
  local place = ch.place and (' ' .. strings.t('photoch.at_place', ch.placeName or ch.place)) or ''
  local time = ch.band and (' ' .. strings.t('photoch.t_' .. ch.band)) or ''
  return strings.t('photoch.line', car, power, place, time)
end

return M
