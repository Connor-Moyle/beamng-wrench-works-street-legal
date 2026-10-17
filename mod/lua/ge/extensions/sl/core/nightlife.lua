-- Street Legal: the night city (#17) and the themed car meets (#43). Pure, tested by tools/luatest.js.
-- Each meet spot has a theme each night (JDM, muscle, drift, euro), rotating by the day; the parked cars at the spot are of that theme, their
-- owners stand by them, and an owner offers something when you talk: a race, a car for sale or a tip. Racers cruising the main strips can be
-- challenged by flashing them or by stopping beside them.

local rngLib = require('sl/core/rng')

local M = {}

local strings = require('sl/core/strings')

-- models (the game's vehicle folder names) by theme; drift is by build: rear-drive, light, with some power
M.JDM = { bx = true, covet = true, hopper = true, miramar = true, midsize = true, pessima = true, pigeon = true, sunburst2 = true, sbr = true }
M.MUSCLE = { barstow = true, moonhawk = true, burnside = true, bluebuck = true, nine = true, legran = true }
M.EURO = { bolide = true, scintilla = true, etk800 = true, etkc = true, etki = true, vivace = true, autobello = true }

M.THEMES = {
  { id = 'jdm', name = strings.t('nightlife.jdm_night'), blurb = strings.t('nightlife.tuned_imports_from_the_east'), tips = {
    strings.t('nightlife.the_cops_sit_by_the'), strings.t('nightlife.a_small_turbo_does_more'),
    strings.t('nightlife.light_cars_win_the_hill') } },
  { id = 'muscle', name = strings.t('nightlife.muscle_night'), blurb = strings.t('nightlife.big_engines_straight_lines'), tips = {
    strings.t('nightlife.all_that_power_is_useless'), strings.t('nightlife.the_drag_strip_pays_by'),
    strings.t('nightlife.rear_drive_and_a_wet') } },
  { id = 'drift', name = strings.t('nightlife.drift_night'), blurb = strings.t('nightlife.rear_drive_light_sideways'), tips = {
    strings.t('nightlife.do_not_fight_the_slide'), strings.t('nightlife.a_locked_diff_is_half'),
    strings.t('nightlife.cold_tyres_bite_warm_them') } },
  { id = 'euro', name = strings.t('nightlife.euro_night'), blurb = strings.t('nightlife.clean_lines_from_across_the'), tips = {
    strings.t('nightlife.they_take_care_of_their'), strings.t('nightlife.brakes_first_then_power_the'),
    strings.t('nightlife.old_money_sells_quiet_ask') } },
}
local byId = {}
for _, t in ipairs(M.THEMES) do byId[t.id] = t end
function M.themeById(id) return byId[id] end

-- tonight's theme at a meet spot: rotates with the day and differs from spot to spot
function M.theme(placeId, day)
  local n = (rngLib.hash(tostring(placeId)) + math.floor(tonumber(day) or 0)) % #M.THEMES
  return M.THEMES[n + 1]
end

-- does a car of the pool belong to a theme. car: { model, power (PS), weight (kg), raw = { Drivetrain } }
function M.fits(themeId, car)
  if type(car) ~= 'table' then return false end
  local model = tostring(car.model or '')
  if themeId == 'jdm' then return M.JDM[model] == true end
  if themeId == 'muscle' then return M.MUSCLE[model] == true end
  if themeId == 'euro' then return M.EURO[model] == true end
  if themeId == 'drift' then
    local drive = type(car.raw) == 'table' and car.raw.Drivetrain
    return drive == 'RWD' and (tonumber(car.weight) or 9e9) < 1600 and (tonumber(car.power) or 0) >= 150
  end
  return false
end

-- n distinct cars of a theme from the pool, in a seeded order; fewer when the pool has fewer
function M.pickCars(themeId, pool, n, rng)
  local fit = {}
  for _, c in ipairs(pool or {}) do if M.fits(themeId, c) then fit[#fit + 1] = c end end
  local out = {}
  while #out < n and #fit > 0 do out[#out + 1] = table.remove(fit, rng:int(#fit)) end
  return out
end

M.FIRST = { 'Dave', 'Marcus', 'Tito', 'Jin', 'Lena', 'Rico', 'Sasha', 'Kenji', 'Omar', 'Bree', 'Cal', 'Dana', 'Hugo', 'Ivy', 'Mo' }
M.LAST = { 'Okafor', 'Reyes', 'Tanaka', 'Novak', 'Brandt', 'Silva', 'Quinn', 'Moreau', 'Hale', 'Park', 'Duarte', 'Wolfe' }
function M.ownerName(rng) return M.FIRST[rng:int(#M.FIRST)] .. ' ' .. M.LAST[rng:int(#M.LAST)] end

-- what an owner offers when you talk: { kind = 'race' | 'sale' | 'tip', text, price (sale), bet (race) }; ctx: { rep, value (the car's) }
function M.offer(theme, rng, ctx)
  ctx = ctx or {}
  local x = rng:float()
  if x < 0.35 and (ctx.value or 0) > 0 then
    local price = math.floor((ctx.value * rng:range(0.5, 0.85)) / 50 + 0.5) * 50
    return { kind = 'sale', price = price, text = string.format(strings.t('nightlife.i_d_let_this_one'), price) }
  elseif x < 0.65 then
    local bet = math.floor(math.max(100, (ctx.rep or 0) * 0.5 + 100 * rng:range(1, 5)) / 50 + 0.5) * 50
    return { kind = 'race', bet = bet, text = string.format(strings.t('nightlife.somebody_here_wants_a_race'), bet) }
  end
  local tips = theme and theme.tips or M.THEMES[1].tips
  return { kind = 'tip', text = tips[rng:int(#tips)] }
end

-- the main strips: the wider roads (half-width, metres) where the racers cruise
M.MAIN_STRIP = 3.0
function M.mainStrip(radius) return (tonumber(radius) or 0) >= M.MAIN_STRIP end

-- stopped beside a racer counts as a challenge: you are nearly still for a moment, and the racer is alongside (not ahead or behind)
-- rel: the racer's position minus yours ({ x, y }), dir: your heading ({ x, y }, unit)
M.BESIDE_SPEED, M.BESIDE_TIME = 2.0, 1.2
function M.besideStopped(rel, dir, speed, stoppedFor)
  if (speed or 99) > M.BESIDE_SPEED or (stoppedFor or 0) < M.BESIDE_TIME then return false end
  local along = rel.x * dir.x + rel.y * dir.y
  local side = math.abs(rel.x * dir.y - rel.y * dir.x)
  return math.abs(along) < 6 and side > 1.5 and side < 8
end

return M
