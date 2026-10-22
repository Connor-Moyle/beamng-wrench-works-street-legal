-- Street Legal: freight runs in free roam (extension name: sl_frjobs; Mods > Street Legal > Free roam > Jobs, off by default, needs the master switch; docs/DESIGN_FREEROAM_JOBS.md).
-- A small board of freight runs between the game's own delivery businesses, run on the sandbox state of sl_mode. It is NOT sl_jobs: it never reads a career, never writes reputation, heat,
-- a sponsor, a crew or a text, and saves nothing. The pay goes only through Wrench Works' free-roam money (slrr/garageParts.changeMoney). In a career it does nothing (sl_jobs runs there).

local M = {}

local jobsLib = require('sl/core/jobs')
local rngLib = require('sl/core/rng')
local strings = require('sl/core/strings')
local sites = require('sl/sites')

local OFFERS = 3
local board, boardKey, act = {}, nil, nil
local timer, fails = 0, 0

local function opt(key, default) local v = sl_options and sl_options.get and tonumber((sl_options.get(key))) return v or default end
local function toast(text) if ui_message then ui_message(text, 5, 'streetLegal') end end
local function on() return sl_mode ~= nil and sl_mode.kind() == 'freeroam' and sl_mode.enabled('jobs') == true end
local function changeMoney(amount, label)
  local ok, parts = pcall(require, 'slrr/garageParts')
  if ok and type(parts) == 'table' and parts.changeMoney then pcall(parts.changeMoney, amount, label) return true end
  return false
end
local function clearRoute() if core_groundMarkers and core_groundMarkers.setPath then pcall(core_groundMarkers.setPath, nil) end end
local function routeTo(stop) if core_groundMarkers and stop then pcall(core_groundMarkers.setPath, vec3(stop.x, stop.y, stop.z or 0)) end end

-- the board is made again at each change of the game's day or phase (the sandbox clock); freight is a day job
local function refresh()
  local sb = sl_mode.state('jobs')
  if not sb then return end
  local key = tostring(sb.day) .. ':' .. tostring(sb.phase)
  if key == boardKey then return end
  boardKey, board = key, {}
  if sb.phase == 'night' then return end
  local rng = rngLib.new(rngLib.hash('frjobs:' .. key .. ':' .. tostring(sb.seed)))
  local list = sites.deliverySites()
  for i = 1, OFFERS do
    local j = jobsLib.freight(list, rng, opt('slFreightPay', 100) / 100, opt('slFreightMin', jobsLib.MIN_METRES))
    local legs = j and sites.freightLegs(j)
    if legs then
      j.id, j.title, j.legs, j.fragile = key .. ':' .. i, strings.t('jobs.freight_run'), legs, false
      j.pay = math.floor(j.pay * jobsLib.DAY_PAY / 10 + 0.5) * 10
      board[#board + 1] = j
    end
  end
end

-- for the phone: nil when this part is not running
function M.summary()
  if not on() then return nil end
  pcall(refresh)
  local out = { offers = {}, pay = 'Wrench Works' }
  for _, j in ipairs(board) do
    out.offers[#out.offers + 1] = { id = j.id, title = j.title, item = j.item, from = j.legs[1].name, to = j.legs[2].name, pay = j.pay, seconds = j.seconds, metres = j.metres }
  end
  if act then out.active = { title = act.title, item = act.item, next = act.legs[act.leg].name, to = act.legs[2].name, pay = act.pay, leg = act.leg } end
  return out
end

function M.accept(id)
  if not on() then return false, strings.t('frjobs.off') end
  if act then return false, strings.t('classifieds.finish_the_job_you_are') end
  for _, j in ipairs(board) do
    if j.id == id then
      act = j
      act.leg, act.startedAt = 1, nil
      routeTo(act.legs[1])
      return true, string.format('%s: go to %s.', act.title, act.legs[1].name)
    end
  end
  return false, strings.t('jobs.that_job_has_gone')
end

function M.cancel()
  if not act then return false, strings.t('frjobs.none') end
  act = nil
  clearRoute()
  return true, strings.t('frjobs.called_off')
end

-- the pay at the drop: the same settle as a career job (late = half), no damage in free roam; returns the pay
function M.settleJob(job, elapsed)
  local pay = jobsLib.settle(job, elapsed, 0)
  return pay
end

local function tickBody()
  if not on() then
    if act then act = nil clearRoute() end
    return
  end
  refresh()
  if not act then return end
  local v = getPlayerVehicle(0)
  if not v then return end
  local stop = act.legs[act.leg]
  local here = v:getPosition()
  local dz = stop.z and math.abs(here.z - stop.z) or 0
  local d = dz < 12 and math.sqrt((here.x - stop.x) ^ 2 + (here.y - stop.y) ^ 2) or math.huge
  if not (d < (stop.radius or 9) and v:getVelocity():length() < 2) then return end
  if act.leg == 1 then
    act.startedAt = os.clock()
    act.leg = 2
    routeTo(act.legs[2])
    toast(string.format(strings.t('jobs.picked_up_the_s_s'), act.item or 'load', '', math.floor(act.seconds / 60), act.seconds % 60, act.legs[2].name))
    return
  end
  local pay = M.settleJob(act, act.startedAt and (os.clock() - act.startedAt) or 0)
  local paid = pay <= 0 or changeMoney(pay, act.title .. ': ' .. (act.item or 'freight'))
  if paid then toast(string.format(strings.t('jobs.s_delivered_s_d'), act.item or 'Delivery', '', pay))
  else toast(string.format(strings.t('frjobs.pay_failed'), act.item or 'Delivery')) end      -- (the money is Wrench Works': when it cannot add it the toast does not say it was paid)
  act = nil
  clearRoute()
end

-- every half second, under a guard: an error is logged and five in a row switch this part off for the session
function M.onUpdate(dtReal)
  timer = timer + dtReal
  if timer < 0.5 or fails >= 5 then return end
  timer = 0
  local ok, err = pcall(tickBody)
  if ok then fails = 0 else
    fails = fails + 1
    log('E', 'sl_frjobs', tostring(err) .. (fails >= 5 and ' (free-roam freight is off for this session)' or ''))
  end
end

function M.onClientEndMission() board, boardKey, act, fails = {}, nil, nil, 0 clearRoute() end
function M.onStreetLegalStarted() board, boardKey, act = {}, nil, nil end          -- (a career starts: this part stands down)

function M.status() return string.format('%s: %d offers, %s', on() and 'on' or 'off', #board, act and ('active ' .. act.id .. ' leg ' .. act.leg) or 'no job') end

return M
