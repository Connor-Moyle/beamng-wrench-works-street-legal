-- Street Legal: the brand invitationals (docs/DESIGN_SPONSORSHIPS.md section 5, docs/INVITATIONAL_INVENTORY.md). A rare event: a brand you have a good standing with (a sponsorship of four weeks, or a
-- standing of 250) invites you, at most three times in a career, to a race on a closed circuit in a race-spec car the brand lends you. No entry fee, nothing at stake but standing. Pure, no
-- game calls: tested by tools/luatest.js.

local M = {}

M.MAX = 3                       -- invitations in a whole career
M.STANDING_MIN = 250
M.WEEKS_MIN = 4                 -- weeks of sponsorship that count as good standing as well
M.LEAD = 5                      -- days between the invitation and the event
M.GAP = 14                      -- days between two invitations at the least
M.HOUR = 15
M.LATE_H = 1.5                  -- hours after the start the race may still begin
M.REACH = 80                    -- metres from the grid to be on time
M.LAYERS = { '003', '005', '006' }      -- the long dockyards layouts, one for each invitation
M.LAPS = 3
M.PLACE = 'Belasco Dockyards'

-- the race-spec configs the game ships (read from the vehicle zips; docs/INVITATIONAL_INVENTORY.md section 2), in the order a brand without a better one is given
M.RACE_CARS = {
  { model = 'covet', config = 'race' }, { model = 'bolide', config = 'race' }, { model = 'scintilla', config = 'race' }, { model = 'vivace', config = 'ardente_race' },
  { model = 'etkc', config = 'race_DCT' }, { model = 'moonhawk', config = 'race' }, { model = 'legran', config = 'race' }, { model = 'pessima', config = 'race' },
  { model = 'midsize', config = 'race' }, { model = 'miramar', config = 'race' }, { model = 'etki', config = 'race' }, { model = 'pigeon', config = 'race' },
}

-- may a brand invite the player now? info = { count (given so far), pending (an invitation is open), last (the day of the last one), day, brand, standing, sponsorWeeks }
function M.eligible(info)
  if (info.count or 0) >= (info.max or M.MAX) or info.pending or not info.brand then return false end
  if info.last and (info.day or 0) - info.last < (info.gap or M.GAP) then return false end
  return (info.standing or 0) >= (info.min or M.STANDING_MIN) or (info.sponsorWeeks or 0) >= M.WEEKS_MIN
end

-- the car the brand lends: a race config of one of its own models (ofCar(model) -> maker id), else the first of the list
function M.loaner(brand, ofCar)
  for _, c in ipairs(M.RACE_CARS) do
    local ok, maker = pcall(ofCar or function() return nil end, c.model)
    if ok and maker == brand then return c, true end
  end
  return M.RACE_CARS[1], false
end

-- a new invitation (n = how many were given before it). car = { model, config }: the race car the brand lends
function M.new(n, brand, day, car)
  return { id = 'invite:' .. (n + 1), n = n + 1, brand = brand, day = day + M.LEAD, hour = M.HOUR, layer = M.LAYERS[(n % #M.LAYERS) + 1], laps = M.LAPS, car = car }
end

-- the brand that invites: the sponsor of four weeks, else the maker with the best standing from 250 (standing = { [brand] = { standing } }, kindOf(id) -> 'maker'|...)
function M.pickBrand(standing, sponsor, day, kindOf, min)
  min = min or M.STANDING_MIN
  if sponsor and sponsor.brand and (day - (sponsor.since or day)) >= M.WEEKS_MIN * 7 then return sponsor.brand end
  local best, bestStanding
  for id, e in pairs(standing or {}) do
    if kindOf(id) == 'maker' and (tonumber(e.standing) or 0) >= min and (not best or (tonumber(e.standing) or 0) > bestStanding or ((tonumber(e.standing) or 0) == bestStanding and id < best)) then best, bestStanding = id, tonumber(e.standing) or 0 end
  end
  return best
end

-- the invitation as a calendar event (no fee, no travel, at the dockyards)
function M.event(inv, title, place)
  return { id = inv.id, title = title, kind = 'invite', day = inv.day, hour = inv.hour, place = place, map = nil, travel = { needed = false, fee = 0, hours = 0 }, series = nil,
    reward = nil, fee = 0, laps = inv.laps, layer = inv.layer, invite = true, brand = inv.brand }
end

-- the reward of a place (nil place: did not finish): money, reputation, standing with the brand, and the trophy for a win
function M.reward(place, scale)
  local table_ = { [1] = { money = 3000, rep = 60, standing = 100 }, [2] = { money = 1800, rep = 35, standing = 60 }, [3] = { money = 1000, rep = 20, standing = 30 } }
  local r = place and table_[place] or { money = place and 300 or 0, rep = place and 5 or 0, standing = place and 10 or 0 }
  scale = tonumber(scale) or 1
  return { money = math.floor(r.money * scale + 0.5), rep = r.rep, standing = math.floor(r.standing * scale + 0.5), trophy = place == 1 }
end

return M
