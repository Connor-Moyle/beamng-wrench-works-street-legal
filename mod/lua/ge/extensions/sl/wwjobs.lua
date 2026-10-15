-- Wrench Works: Street Legal: the Wrench Works jobs on the job board (extension name: sl_wwjobs; Design 3 #7-9).
-- They are rows in sl_jobs' TYPES with settle = 'ww': the board offers them and the phone shows them as usual,
-- but they end when Wrench Works reports the work (a dyno run, a quarter mile, a car driven out, a part sold),
-- through sl_jobs.finishWith - the one money and rep path. Rules in sl/core/wwjobs.

local M = {}

local ww = require('sl/core/wwjobs')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function active()
  local s = career()
  local js = s and s.jobs
  local j = js and js.active
  if j and j.settle == 'ww' then return s, js, j end
end
local function stop(p, name) return p and { id = p.id, name = name or p.name, x = p.x, y = p.y, z = p.z } end

-- #8 tune to spec: build it in your garage, prove it on the dyno (power) or the test track's quarter mile
local TUNE = { kind = 'tune', title = 'Tune to spec', unlock = ww.TIER_REP[1], settle = 'ww', offer = function(ctx, rng)
    local s = career()
    local spec = s and ctx.garage and ww.tuneSpec(rng, s.rep)
    if not spec then return nil end
    spec.settle, spec.spent, spec.seconds, spec.fragile = 'ww', 0, 0, false
    spec.legs = { stop(ctx.garage), stop(ctx.garage, spec.metric == 'power' and 'the dyno' or 'the test track quarter mile') }
    return spec
  end }

local ROWS = { TUNE }     -- #7 repair tickets and #9 scavenging join once Wrench Works can run them

-- add our rows to the board (again after sl_jobs reloads, which makes a fresh TYPES)
local addedTo
local function register()
  if not (sl_jobs and sl_jobs.TYPES) or addedTo == sl_jobs.TYPES then return end
  for _, row in ipairs(ROWS) do table.insert(sl_jobs.TYPES, row) end
  addedTo = sl_jobs.TYPES
end
M.onExtensionLoaded = register
function M.onUpdate() register() end

local function settleTune(value)
  local s, js, j = active()
  if not j or j.kind ~= 'tune' or not ww.tuneMet(j, value) then return end
  local pay, verdict = ww.tuneSettle(j, j.spent)
  sl_jobs.finishWith(s, js, j, pay, verdict == 'over budget' and 5 or 20,
    string.format('Spec met (%s), %s: $%d. The customer is happy.', j.item, verdict, pay))
end

-- what the job's parts cost: every part bought while a tune or repair job is on
function M.onWrenchWorksPartBought(vid, slotPath, part, price)
  local _, _, j = active()
  if j and tonumber(price) then j.spent = (j.spent or 0) + tonumber(price) end
end

function M.onWrenchWorksDyno(vid, data)
  local _, _, j = active()
  if not j or j.metric ~= 'power' or type(data) ~= 'table' then return end
  if not (sl_fleet and sl_fleet.carOfVehicle and sl_fleet.carOfVehicle(vid)) then return end      -- one of your cars
  settleTune(tonumber(data.maxPower))
end

function M.onSlrrRaceFinished(r)
  local _, _, j = active()
  if not j or j.metric ~= 'quarter' or type(r) ~= 'table' or r.abandoned or type(r.time) ~= 'number' then return end
  for _, x in ipairs(sl_career.racesList and sl_career.racesList() or {}) do
    if x.drag and (x.id == r.raceId or (r.missionId and x.missionId == r.missionId)) and tostring(x.name):find('1/4', 1, true) then
      settleTune(r.time)
      return
    end
  end
end

return M
