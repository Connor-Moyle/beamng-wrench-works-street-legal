-- Wrench Works: Street Legal: hurt and killed at the wheel (extension name: sl_hospital)
-- Built on Drivers & Pedestrians' injuries (slrrInjury: onSlrrDriverInjured / onSlrrDriverDied, the player's only).
-- Hurt: a doctor's bill by how bad it is, and no racing or jobs at the wheel while slrrInjury says no driving.
-- Knocked out or killed (normal): fade, you wake up at the hospital on foot with its bill (insurance pays its
-- share), and the car is towed to your garage's forecourt as it is. Killed in a Hardcore career: game over.
-- The career is marked ended (it can be looked at, not played on) and the phone shows what it came to.

local M = {}

local progression = require('sl/core/progression')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) end

-- what it costs: a doctor for broken bones, the hospital for a night in it (scaled by how bad)
function M.doctorBill(injuries) return 150 + 250 * #(injuries.broken or {}) + math.floor(800 * (injuries.severity or 0) / 10) * 10 end
function M.hospitalBill(severity, died) return (died and 2500 or 1200) + math.floor(3000 * (severity or 0.5) / 10) * 10 end

-- a bill is paid with what there is: the hospital treats you anyway (and what is left of it is let go)
local function bill(amount, label)
  local s = career()
  local pay = math.max(0, math.min(amount, s and s.money or 0))
  if pay > 0 then sl_career.addMoney(-pay, label) end
  return pay
end

-- no racing or jobs at the wheel while the injuries say no driving
function M.canDrive()
  local st = slrrInjury and slrrInjury.getState and slrrInjury.getState() or nil
  return not (st and st.injured and st.limits and st.limits.noDriving)
end

function M.onSlrrDriverInjured(vehId, injuries)
  if not career() or type(injuries) ~= 'table' or not injuries.player then return end
  if injuries.level == 'unconscious' then return M.toHospital(vehId, injuries.severity, false) end
  if injuries.level == 'broken' then
    local paid = bill(M.doctorBill(injuries), "Doctor's bill")
    sl_career.sendText('benny', string.format("You went to the doctor? That's $%d. Rest up: no racing until it heals.", paid), 4)
  end
end

-- the hospital: fade, the car to the garage as it is, you at the hospital's door, the bill
function M.toHospital(vehId, severity, died)
  local s = career()
  if not s then return end
  local carId = sl_fleet and sl_fleet.carOfVehicle and sl_fleet.carOfVehicle(vehId)
  local place
  for _, p in pairs(sl_career.getPlaces() or {}) do if p.kind == 'hospital' then place = p end end
  core_jobsystem.create(function(job)
    guihooks.trigger('slFade', { on = true })
    job.sleep(1.0)
    if gameplay_walk then gameplay_walk.setWalkingMode(true, nil, nil, true) end
    job.sleep(0.6)
    if carId then sl_fleet.deliver(carId) end                       -- (towed, wrecked as it is)
    local me = getPlayerVehicle(0)
    local pos, dir = place and place.pos, place and place.dir
    if not pos then pos, dir = sl_fleet.forecourt(s, 1), vec3(0, 1, 0) end    -- (no hospital on this map: home)
    if me and pos then spawn.safeTeleport(me, pos + vec3(0, 0, 0.3), quatFromDir(dir or vec3(0, 1, 0), vec3(0, 0, 1)), true) end
    if slrrInjury and slrrInjury.heal then slrrInjury.heal(vehId) end
    local paid = bill(M.hospitalBill(severity, died), 'Hospital')
    job.sleep(1.0)
    guihooks.trigger('slFade', { on = false })
    sl_career.sendText('benny', string.format('You gave us a scare. The hospital took $%d%s, and your car is outside the garage, the state it was in.',
      paid, died and ' (they say you were gone for a minute there)' or ''), 3)
    extensions.hook('onStreetLegalChanged')
  end)
end

-- death counts in a Hardcore career whatever the injuries setting says (otherwise only the setting 'Injuries and death' allows it)
local function setDeath(on) if slrrInjury and slrrInjury.setDeathOverride then slrrInjury.setDeathOverride(on) end end
function M.onStreetLegalStarted() setDeath(sl_options ~= nil and sl_options.get('slHardcore') == true) end
function M.onStreetLegalStopped() setDeath(false) end

-- what the career came to, for the game-over screen
function M.gameOverData(s, cause)
  local a = sl_achievements and sl_achievements.summary and sl_achievements.summary() or {}
  return { day = s.day, money = s.money, rep = s.rep, title = progression.titleFor(s.rep or 0, sl_career.LEVEL), races = s.stats.races, wins = s.stats.wins,
    pinksWon = s.stats.pinksWon, earned = s.stats.earned, cars = #(s.cars or {}), achievements = a.earned, achievementsTotal = a.total, cause = cause }
end

function M.onSlrrDriverDied(vehId, cause, detail)
  local s = career()
  if not s or not (type(detail) == 'table' and detail.player) then return end
  if not (sl_options and sl_options.get('slHardcore')) then return M.toHospital(vehId, 1, true) end
  -- Hardcore: the end
  s.ended = { day = s.day, cause = tostring(cause or 'crash'), at = os.time() }
  local data = M.gameOverData(s, s.ended.cause)
  if sl_career.endCareer then sl_career.endCareer() end
  guihooks.trigger('slGameOver', data)
end

return M
