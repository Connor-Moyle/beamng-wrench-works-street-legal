-- Street Legal: barn finds (campaign idea #3). A contact texts a rumour about an old car rotting in a yard; the yard is one of a few remote spots of the map. Drive there and the car
-- becomes an ad in the Car market (a private ad at that spot): cheap, in a bad state, with faults only a mechanic's check shows. Pure, no game calls: tested by tools/luatest.js.

local M = {}

local strings = require('sl/core/strings')
local market = require('sl/core/market')

M.SPOTS = 4                 -- per map
M.FROM_PLACE = 500          -- m: at least this far from any place of the career
M.APART = 800               -- m between two spots
M.FOUND_RADIUS = 35         -- m: close enough to find it
M.MIN_REP = 100
M.REUSE_DAYS = 30           -- a spot whose car was bought or went off the market holds a new one after this many days
M.GAP = { 3, 6 }            -- days between two rumours
M.PRICE_SHARE = 0.22        -- of the car's value
M.CONDITION = { 0.12, 0.3 }

local function degree(node) local n = 0 for _ in pairs(node.links or {}) do n = n + 1 end return n end

-- the spots: dead ends of the road graph far from every place, spaced apart; places = { { x, y } }; rng is sl/core/rng
function M.select(nodes, places, rng)
  local cands = {}
  for id, n in pairs(nodes or {}) do
    if n.pos and degree(n) == 1 then
      local ok = true
      for _, p in ipairs(places or {}) do
        if (p.x - n.pos.x) ^ 2 + (p.y - n.pos.y) ^ 2 < M.FROM_PLACE ^ 2 then ok = false break end
      end
      if ok then cands[#cands + 1] = { key = id, x = n.pos.x, y = n.pos.y, z = n.pos.z or 0 } end
    end
  end
  table.sort(cands, function(a, b) return a.key < b.key end)       -- (the same order whatever the order of pairs)
  for i = #cands, 2, -1 do local j = rng:int(i) cands[i], cands[j] = cands[j], cands[i] end
  local out = {}
  for _, c in ipairs(cands) do
    if #out >= M.SPOTS then break end
    local apart = true
    for _, o in ipairs(out) do if (o.x - c.x) ^ 2 + (o.y - c.y) ^ 2 < M.APART ^ 2 then apart = false break end end
    if apart then out[#out + 1] = { id = 'b' .. (#out + 1), x = c.x, y = c.y, z = c.z } end
  end
  return out
end

-- (math.atan2 is LuaJIT's, math.atan(y, x) Lua 5.3's: this works in both)
local function atan2(y, x)
  if x > 0 then return math.atan(y / x) end
  if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
  return y > 0 and math.pi / 2 or (y < 0 and -math.pi / 2 or 0)
end

local DIRS = { 'east', 'north-east', 'north', 'north-west', 'west', 'south-west', 'south', 'south-east' }
-- the way from (ax, ay) to (bx, by) in words
function M.compass(ax, ay, bx, by)
  local deg = math.deg(atan2(by - ay, bx - ax))
  return strings.t('barn.' .. DIRS[(math.floor((deg + 22.5) / 45) % 8) + 1])
end

-- the rumour: the nearest place and the way from it, in words
function M.hint(spot, places, carName)
  local best, bd
  for _, p in ipairs(places or {}) do
    local d = (p.x - spot.x) ^ 2 + (p.y - spot.y) ^ 2
    if not bd or d < bd then best, bd = p, d end
  end
  if not best then return strings.t('barn.hint_plain', carName) end
  return strings.t('barn.hint', carName, math.max(1, math.floor(math.sqrt(bd) / 1000 + 0.5)), M.compass(best.x, best.y, spot.x, spot.y), best.name or best.id or '?')
end

-- a lot-style offer turned into what sits in the barn: a poor condition, three to five faults, a high mileage, a low price
function M.carOffer(offer, rng)
  local o = {}
  for k, v in pairs(offer) do o[k] = v end
  o.condition = rng:range(M.CONDITION[1], M.CONDITION[2])
  local pool, faults = {}, {}
  for _, f in ipairs(market.FAULTS) do pool[#pool + 1] = f end
  for _ = 1, rng:int(3, 5) do
    if #pool == 0 then break end
    faults[#faults + 1] = table.remove(pool, rng:int(#pool))
  end
  table.sort(faults)
  o.faults = faults
  o.mileage = rng:int(150000, 300000)
  o.price = math.max(100, math.floor((o.value or 0) * M.PRICE_SHARE / 10 + 0.5) * 10)
  o.kind = 'barn'
  return o
end

-- the most valuable of a list of offers (the find should be worth the drive)
function M.pick(offers)
  local best
  for _, o in ipairs(offers or {}) do if not best or (o.value or 0) > (best.value or 0) then best = o end end
  return best
end

return M
