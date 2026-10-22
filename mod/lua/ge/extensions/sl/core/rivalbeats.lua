-- Street Legal: the rival story beats' rules (Graph docs/RIVAL_BEATS.md). Pure, no game calls: tested by tools/luatest.js.
-- The hunt: a rival wants the car you took off them back (a pink-slip offer for the car itself, a sweetener when you make them wait, then they
-- give up). The beaten crew's three nights: three races on three nights, two wins for their respect and a truce. The game side is sl/rivalbeats.lua.
-- The numbers in CAPITALS are Mods rows (sl/balance).

local M = {}

M.HUNT_WAIT_MIN, M.HUNT_WAIT_MAX = 2, 5      -- days after the pink win before the first text
M.HUNT_AGAIN = 3                            -- days after a lapsed offer before the next text
M.SWEETENER = 0.25                          -- of the car's value, on the second text; doubled on the third (the sim: 0.6 paid $466 a minute, a stall-and-collect tap)
M.HUNT_REP, M.METER_GONE, M.METER_SOLD = 15, -20, -10
M.SERIES_NIGHTS, M.TRUCE_DAYS, M.SERIES_REP, M.SERIES_BET_X = 3, 14, 40, 1.5
M.KINDS = { 'hunt', 'hunt2', 'hunt3', 'hunt_won', 'hunt_lost', 'hunt_gone', 'crewcall', 'crew_respect', 'crew_mock' }      -- the persona text kinds (rivals.<persona>.<kind>_1/2)

-- ---- the hunt
function M.newHunt(rivalId, carId, day, value, rng)
  local wait = rng and rng:int(M.HUNT_WAIT_MIN, math.max(M.HUNT_WAIT_MIN, M.HUNT_WAIT_MAX)) or M.HUNT_WAIT_MIN
  return { rival = rivalId, carId = carId, day = day, value = tonumber(value) or 0, stage = 0, nextDay = day + wait }
end
-- the beat due today: the text kind and the stage it moves to, or nil (done, an offer standing, or not yet)
function M.huntDue(h, day)
  if not h or h.done or h.offered or h.racing or (day or 0) < (h.nextDay or 0) then return nil end
  local stage = (h.stage or 0) + 1
  if stage > 3 then return 'hunt_gone', stage end
  return ({ 'hunt', 'hunt2', 'hunt3' })[stage], stage
end
-- what the rival puts on top of the car for a win: nothing on the first text, the share on the second, twice it on the third
function M.sweetener(h)
  local st = h and h.stage or 0
  if st <= 1 then return 0 end
  return math.floor((h.value or 0) * M.SWEETENER * (st >= 3 and 2 or 1) / 100 + 0.5) * 100
end
-- the offer lapsed or the player walked away: the next text after HUNT_AGAIN days
function M.lapse(h, day) h.offered, h.racing = nil, nil h.nextDay = (day or 0) + M.HUNT_AGAIN end
-- the player may take the offer only in the hunted car
function M.canAccept(h, currentCarId) return h ~= nil and h.offered == true and not h.done and currentCarId ~= nil and currentCarId == h.carId end

-- ---- the beaten crew's three nights
-- racers: the crew's members by skill, the leader last; the series takes the best two and the leader
function M.seriesRacers(members, leaderId)
  local list = {}
  for _, r in ipairs(members or {}) do if r.id ~= leaderId then list[#list + 1] = r end end
  table.sort(list, function(a, b) if (a.skill or 0) == (b.skill or 0) then return a.id < b.id end return (a.skill or 0) > (b.skill or 0) end)
  local out = {}
  for i = 1, math.min(M.SERIES_NIGHTS - 1, #list) do out[#out + 1] = list[i].id end
  if leaderId then out[#out + 1] = leaderId end
  return out
end
function M.newSeries(crewId, districtId, racerIds, day) return { crew = crewId, district = districtId, racers = racerIds, night = 1, results = {}, day = day } end
function M.seriesRacer(sr) return sr and sr.racers[sr.night] or nil end
function M.seriesRecord(sr, won) sr.results[#sr.results + 1] = won == true sr.night = sr.night + 1 sr.sentDay = nil end
function M.seriesOver(sr) return sr ~= nil and (#sr.results >= #sr.racers or #sr.results >= M.SERIES_NIGHTS) end
function M.seriesVerdict(sr)
  local w = 0
  for _, r in ipairs(sr and sr.results or {}) do if r then w = w + 1 end end
  return w >= 2, w
end
-- a night's race sent and not run by the next day: a loss
function M.seriesMissed(sr, day) return sr ~= nil and sr.sentDay ~= nil and (day or 0) > sr.sentDay end
function M.seriesBet(racer) return math.max(50, math.floor(((tonumber(racer and racer.betMin) or 100) + (tonumber(racer and racer.betMax) or 300)) / 2 * M.SERIES_BET_X / 50 + 0.5) * 50) end
function M.truceUntil(day) return (day or 0) + M.TRUCE_DAYS end
function M.inTruce(truce, crewId, day) return truce ~= nil and truce[crewId] ~= nil and (day or 0) < truce[crewId] end

return M
