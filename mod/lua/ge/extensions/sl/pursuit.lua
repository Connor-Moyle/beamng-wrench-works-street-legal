-- Street Legal: pursuit tactics, box and PIT (extension name: sl_pursuit; police batch 2, P5; switch Mods > Street Legal > Police chase > Box and PIT).
-- Rules in sl/core/chase (the P5 block). A thin driver over the game's police roles: at pursuit level 2 and above the second-nearest unit is the
-- boxer (its speed capped to the player's, a calm aggression: it crowds the rear quarter while the nearest unit chases); at level 3 the nearest
-- unit gets a PIT window (aggression 1.5 for 6 s, once per 45 s, only above 60 km/h and on a straight). Everything is put back when the chase ends.
-- The numbers are the tester's to tune: the AI may just ram.

local M = {}

local rules = require('sl/core/chase')
local features = require('sl/core/features')

local function on() return not (sl_options and sl_options.get) or sl_options.get('slPoliceTactics') ~= false end
local function policeOn() return not (sl_options and sl_options.get) or sl_options.get('slPolice') ~= false end
local function playerVid() local v = getPlayerVehicle(0) return v and v:getID() or nil end
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local function traffic() return gameplay_traffic and gameplay_traffic.getTrafficData and gameplay_traffic.getTrafficData() or {} end
local function cmd(cid, s) local c = getObjectByID(cid) if c then c:queueLuaCommand(s) end end
local function aggression(cid, a)
  local t = traffic()[cid]
  if t and t.role and t.role.setAggression then pcall(t.role.setAggression, t.role, a) end
end

local boxer, pitter = nil, nil          -- { id, until_ }
local lastPit, headings = -1e9, {}
local function restoreBox()
  if not boxer then return end
  cmd(boxer.id, 'ai.setSpeedMode("off")')
  aggression(boxer.id, rules.BASE_AGGR)
  boxer = nil
end
local function restorePit()
  if not pitter then return end
  aggression(pitter.id, rules.BASE_AGGR)
  pitter = nil
end
local function reset() restoreBox() restorePit() headings = {} end

local function copsByDistance(v)
  local out, p = {}, v:getPosition()
  for cid in pairs(gameplay_police.getPoliceVehicles() or {}) do
    local c = getObjectByID(cid)
    if c and cid ~= v:getID() then out[cid] = (c:getPosition() - p):length() end
  end
  return out
end

local tickT = 0
local function tick()
  local v = getPlayerVehicle(0)
  local pur = v and gameplay_police and gameplay_police.getPursuitData and gameplay_police.getPursuitData(v:getID())
  local mode = pur and tonumber(pur.mode) or 0
  if not v or mode < 1 or not on() or not policeOn() then reset() return end
  local vel = v:getVelocity()
  local speed = vel:length()
  headings[#headings + 1] = math.deg(atan2(vel.y, vel.x)) % 360
  while #headings > rules.STRAIGHT_SAMPLES do table.remove(headings, 1) end
  local cops = copsByDistance(v)
  -- the box
  local want = rules.boxUnit(mode, cops)
  if boxer and (boxer.id ~= want or not cops[boxer.id]) then restoreBox() end
  if want and not boxer then
    boxer = { id = want }
    aggression(want, rules.BOX_AGGR)
    if sl_police and sl_police.radioSay then sl_police.radioSay('box', { unit = 2 }) end
  end
  if boxer then cmd(boxer.id, string.format('ai.setSpeedMode("limit") ai.setSpeed(%.1f)', math.max(5, speed + rules.BOX_SPEED_PLUS))) end
  -- the PIT
  if pitter and os.clock() >= pitter.until_ then restorePit() end
  if not pitter and rules.pitDue(mode, speed, rules.isStraight(headings), os.clock() - lastPit) then
    local id = rules.pitUnit(cops)
    if id then
      lastPit = os.clock()
      pitter = { id = id, until_ = os.clock() + rules.PIT_S }
      aggression(id, rules.PIT_AGGR)
      if sl_police and sl_police.radioSay then sl_police.radioSay('pit', { unit = 1 }) end
    end
  end
end

function M.onUpdate(dtReal)
  tickT = tickT + dtReal
  if tickT < 0.5 then return end
  tickT = 0
  local ok, err = pcall(tick)
  if not ok then log('E', 'sl_pursuit', tostring(err)) reset() end
end

function M.onPursuitAction(id, action)
  if id ~= playerVid() then return end
  if action == 'evade' or action == 'arrest' or action == 'release' then reset() end
end
function M.onStreetLegalStopped() reset() lastPit = -1e9 end
function M.onClientEndMission() boxer, pitter, headings, lastPit = nil, nil, {}, -1e9 end
function M.onStreetLegalOption(key) if key == 'slPoliceTactics' and not on() then reset() end end
function M.status() return string.format('box %s; pit %s (last %.0f s ago); straight %s', boxer and boxer.id or 'none', pitter and (pitter.id .. ' for ' .. math.floor(pitter.until_ - os.clock()) .. ' s') or 'none', os.clock() - lastPit, tostring(rules.isStraight(headings))) end

return M
