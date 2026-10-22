-- Street Legal: the hill duel's rules (campaign idea #6). Pure, no game calls: tested by tools/luatest.js.
-- Two cars on a hill road, points instead of a finish line: the leader scores while the gap is LEAD_GAP or more, the follower while it is
-- CLOSE_GAP or less; off the road for more than OFF_GRACE costs a point a second. The duel ends when the player finishes the road; more points
-- wins, a tie goes to whoever finished first. Run by sl_hillduel on the grid runner (sl_gridrace) against one rival in their own car.

local M = {}

local strings = require('sl/core/strings')

-- the hill roads of West Coast USA (the game's own paths): an open climb, an open climb through the alleys, a mountain loop of two laps
M.ROADS = {
  { id = 'cell', track = 'west_coast_usa/timeTrial/006-Cell', title = 'Cell Hill', laps = 1 },
  { id = 'alley', track = 'west_coast_usa/timeTrial/022-Alleyway', title = 'Alleyway climb', laps = 1 },
  { id = 'mountain', track = 'west_coast_usa/timeTrial/012-Mountain', title = 'Mountain loop', laps = 2 },
}
M.LEAD_GAP = 25         -- metres: the leader scores from here
M.CLOSE_GAP = 12        -- metres: the follower scores up to here
M.OFF_GRACE = 2         -- seconds off the road before it costs
M.REP_WIN, M.REP_LOSS = 30, -5
M.REACH = 30            -- metres from the road's start for the prompt

function M.road(id) for _, r in ipairs(M.ROADS) do if r.id == id then return r end end return nil end

function M.newScore() return { me = 0, them = 0, offMe = 0, offThem = 0, t = 0 } end

-- a second of the duel: `ahead` is 'me', 'them' or nil (level), gap in metres, who is on the road
function M.tick(sc, ahead, gap, meOnRoad, themOnRoad, dt)
  dt = tonumber(dt) or 0
  if dt <= 0 then return sc end
  sc.t = sc.t + dt
  if ahead == 'me' then
    if gap >= M.LEAD_GAP then sc.me = sc.me + dt elseif gap <= M.CLOSE_GAP then sc.them = sc.them + dt end
  elseif ahead == 'them' then
    if gap >= M.LEAD_GAP then sc.them = sc.them + dt elseif gap <= M.CLOSE_GAP then sc.me = sc.me + dt end
  end
  sc.offMe = meOnRoad == false and sc.offMe + dt or 0
  sc.offThem = themOnRoad == false and sc.offThem + dt or 0
  if sc.offMe > M.OFF_GRACE then sc.me = math.max(0, sc.me - dt) end
  if sc.offThem > M.OFF_GRACE then sc.them = math.max(0, sc.them - dt) end
  return sc
end

-- who won: the points, a tie to the first across the line (myPlace 1 = the player)
function M.winner(sc, myPlace)
  if sc.me > sc.them + 1e-9 then return 'me' end
  if sc.them > sc.me + 1e-9 then return 'them' end
  return (myPlace or 2) == 1 and 'me' or 'them'
end

function M.text(sc) return strings.t('hillduel.score_1_2', math.floor(sc.me + 0.5), math.floor(sc.them + 0.5)) end

-- the stake: the middle of the rival's range, to 50
function M.bet(racer)
  local lo, hi = tonumber(racer and racer.betMin) or 100, tonumber(racer and racer.betMax) or 300
  return math.max(50, math.floor((lo + hi) / 2 / 50 + 0.5) * 50)
end

-- money and reputation of the result
function M.payout(won, bet) return won and bet or -bet, won and M.REP_WIN or M.REP_LOSS end

-- a rival within the player's reach of reputation (the meets' rule), in the rng's pick; nil with nobody
function M.rival(racers, rep, rng)
  local fit = {}
  for _, r in ipairs(racers or {}) do if math.abs((r.rep or 0) - (rep or 0)) < 1500 + (rep or 0) * 0.5 then fit[#fit + 1] = r end end
  if #fit == 0 then fit = racers or {} end
  if #fit == 0 then return nil end
  return fit[rng:int(#fit)]
end

-- the road's start (its default start position) from the race file: { x, y, z } or nil
function M.startOf(data)
  if type(data) ~= 'table' or type(data.startPositions) ~= 'table' then return nil end
  local sp
  for _, p in ipairs(data.startPositions) do if p.oldId == data.defaultStartPosition then sp = p end end
  sp = sp or data.startPositions[1]
  local p = sp and sp.pos
  if type(p) ~= 'table' or not tonumber(p[1]) then return nil end
  return { x = tonumber(p[1]), y = tonumber(p[2]) or 0, z = tonumber(p[3]) or 0 }
end

return M
