-- Wrench Works: Street Legal: achievements and personal bests (extension name: sl_achievements; BACKLOG X23)
-- Earned from the career's own record (rules: sl/core/achievements), checked every few seconds; best
-- times from every race that reports one, the map's (onSlrrRaceFinished) and Street Legal's own.

local M = {}

local ach = require('sl/core/achievements')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function toast(text) guihooks.trigger('slPhoneToast', { text = text }) if ui_message then ui_message(text, 5, 'streetLegal') end end

local timer = 0
function M.onUpdate(dt)
  timer = timer + dt
  if timer < 2 then return end
  timer = 0
  local s = career()
  if not s then return end
  for _, a in ipairs(ach.update(s)) do toast('Achievement: ' .. a.title .. ' - ' .. a.desc) end
end

local function raceName(r)
  for _, x in ipairs(sl_career.racesList and sl_career.racesList() or {}) do
    if x.id == r.raceId or (r.missionId and x.missionId == r.missionId) then return x.name end
  end
  return r.raceName or tostring(r.missionId or r.raceId)
end

function M.onSlrrRaceFinished(r)
  local s = career()
  if not s or type(r) ~= 'table' or r.abandoned or not r.won then return end
  local key = r.missionId or r.raceId
  if ach.best(s, key, r.time, raceName(r)) then toast(string.format('Personal best: %s, %.2f s.', raceName(r), r.time)) end
end

function M.onStreetLegalRaceTimed(key, name, time)
  local s = career()
  if s and ach.best(s, key, time, name) then toast(string.format('Personal best: %s, %.2f s.', name, time)) end
end

-- for the phone's Street cred page
function M.summary()
  local s = career()
  if not s then return nil end
  local earned, all = {}, {}
  for _, a in ipairs(ach.LIST) do
    local day = s.achievements and s.achievements[a.id]
    all[#all + 1] = { title = a.title, desc = a.desc, day = day }
    if day then earned[#earned + 1] = a.id end
  end
  local bests = {}
  for _, b in pairs(s.bests or {}) do bests[#bests + 1] = { name = b.name, time = b.time } end
  table.sort(bests, function(a, b) return a.name < b.name end)
  return { earned = #earned, total = #ach.LIST, list = all, bests = bests }
end

return M
