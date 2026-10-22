-- Street Legal: crew mates (extension name: sl_mates; the part: Mods > Street Legal > Parts of the game > Crew mates, off by default; docs: Graph CREW_MATES_DESIGN.md).
-- Rules in sl/core/mates. Taking a district recruits one person of that crew: a mechanic (cheaper parts in the shops, cheaper service labour), a tipster (a text a day), or a scout (calls
-- the police ahead and rides in the passenger seat through Drivers). Saved as the career's additive key s.mates. A mate is a person only.

local M = {}

local rules = require('sl/core/mates')
local crews = require('sl/core/crews')
local rngLib = require('sl/core/rng')
local strings = require('sl/core/strings')
local features = require('sl/core/features')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end
local function roster(s) if type(s.mates) ~= 'table' then s.mates = rules.new() end return s.mates end
local function text(m) if m then sl_career.sendText('benny', m.from .. ': ' .. m.text, 3) end end
local function on() return features.on('mates') end
local function opt(key, default) local v = sl_options and sl_options.get and tonumber((sl_options.get(key))) return v or default end

-- ---- the mechanic: parts in the shops (sl_shops), labour in the service (sl_service reads labourFactor)
local registered = false
-- the shop kinds that sell parts (sl/core/shops TYPES with catalogue goods); the services, the food and the rest are not the mechanic's to cut
local PARTS_KINDS = { tyre = true, exhaust = true, parts = true, performance = true, dealerparts = true }
local function partsFactor(_, shop)
  local s = career()
  if not (s and on() and type(shop) == 'table' and PARTS_KINDS[shop.kind]) then return 1 end
  return rules.has(roster(s), 'mechanic') and (1 - opt('slMatePartsCut', 5) / 100) or 1
end
local function register(want)
  if not want and not registered then return end          -- (nothing is touched in the shops unless this part handed them a factor)
  registered = want
  if rawget(_G, 'sl_shops') and sl_shops.setPriceFactor then pcall(sl_shops.setPriceFactor, 'mate', want and partsFactor or nil) end
end
local function refreshShops() local s = career() register(s ~= nil and on() and rules.has(roster(s), 'mechanic')) end
function M.labourFactor() local s = career() return s and on() and rules.has(roster(s), 'mechanic') and (1 - opt('slMateLabourCut', 10) / 100) or 1 end

-- ---- recruiting
function M.onStreetLegalDistrictTaken(districtId, crewId)
  local ok, err = pcall(function()
    local s = career()
    if not s then return end
    local rng = rngLib.new(rngLib.hash('mate:' .. tostring(crewId) .. ':' .. tostring(s.seed or 0)))
    local mate = rules.recruit(roster(s), crewId, s.day, rng)
    if not mate then return end
    local crew = crews.crew(crewId)
    text(rules.welcome(mate, crew and crew.name or crewId))
    refreshShops()
    extensions.hook('onStreetLegalChanged')
  end)
  if not ok then log('E', 'sl_mates', 'recruiting failed: ' .. tostring(err)) end
end

-- ---- the tipster: one text a game day, about the next race on the calendar
local lastTipDay
function M.onStreetLegalNewDay(day)
  local ok, err = pcall(function()
    local s = career()
    if not s then return end
    local world = {}
    local cal = sl_calendar and sl_calendar.summary and sl_calendar.summary()
    for _, ev in ipairs(cal and cal.events or {}) do
      local hours = (ev.day - day) * 24 + (ev.hour or 0)
      if ev.status == 'open' and hours > 0 and hours <= 48 and ev.kind ~= 'info' then world.race = { name = ev.title, hours = math.floor(hours) } break end
    end
    text(rules.tip(roster(s), world, day, lastTipDay, opt('slMateTips', 7) / 7, rngLib.new(rngLib.hash('tip:' .. day .. ':' .. tostring(s.seed or 0)))))
    if world.race then lastTipDay = day end
  end)
  if not ok then log('E', 'sl_mates', 'the tip failed: ' .. tostring(err)) end
end

-- ---- the scout: the police ahead, scanned every 2 s, called at most every WARN_GAP seconds
local scanT, lastWarn, fails = 0, nil, 0
local function patrols()
  local out = {}
  local data = gameplay_traffic and gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {}
  for _, v in pairs(data) do
    if v.role and v.role.name == 'police' and v.pos then out[#out + 1] = { x = v.pos.x, y = v.pos.y } end
  end
  return out
end
function M.onUpdate(dtReal)
  scanT = scanT + dtReal
  if scanT < 2 or fails >= 5 then return end
  scanT = 0
  local s = career()
  if not s or rules.scouts(roster(s)) == 0 then return end
  local pv = getPlayerVehicle(0)
  if not pv then return end
  local ok, err = pcall(function()
    local p, d = pv:getPosition(), pv:getDirectionVector()
    if lastWarn and os.clock() - lastWarn < opt('slMateWarnGap', 60) then return end          -- (the gap is a setting)
    local w = rules.policeWarning(roster(s), os.clock(), nil, patrols(), { x = p.x, y = p.y, hx = d.x, hy = d.y })
    if w then lastWarn = w.at text(w) end
  end)
  if ok then fails = 0 else
    fails = fails + 1
    log('E', 'sl_mates', tostring(err) .. (fails >= 5 and ' (the scout is off for this session)' or ''))
  end
end

-- ---- the passenger seat: armed by sl_carBuilder just before the career car spawns (Drivers loads the next car that matches the model)
function M.armPassenger(model)
  local s = career()
  local rider = s and rules.rider(roster(s))
  local mount = rawget(_G, 'slrrDriverMount')
  if not (rider and mount and mount.requestPassenger) then return false end
  local list = slrrDrivers and slrrDrivers.getDrivers and slrrDrivers.getDrivers() or {}
  if #list == 0 then return false end
  local pick = list[(rngLib.hash(rider.name) % #list) + 1]
  local ok, armed = pcall(mount.requestPassenger, pick.id, { model = model })
  return ok and armed == true
end

function M.onStreetLegalStarted() local s = career() if s then s.mates = rules.load(s.mates) end lastTipDay, lastWarn, fails = nil, nil, 0 refreshShops() end
function M.onStreetLegalOption(key) if key == 'slMates' then refreshShops() end end
function M.onStreetLegalStopped() register(false) end

function M.status()
  local s = career()
  if not s then return 'no career' end
  local out = {}
  for _, m in ipairs(rules.roster(roster(s))) do out[#out + 1] = string.format('%s %s (%s) since day %s', m.name, m.role, m.crew, tostring(m.day)) end
  return #out > 0 and table.concat(out, '\n') or 'no mates'
end

features.gate('mates', M, nil, { 'onStreetLegalOption' }, { 'labourFactor', 'armPassenger', 'status' })

return M
