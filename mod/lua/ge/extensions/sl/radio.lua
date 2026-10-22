-- Street Legal: the car radio's DJ (extension name: sl_radio; campaign idea #15; Mods > Street Legal > Parts of the game > Car radio DJ, off by default). Rules and the lines in sl/core/radio.
-- A text station, "Street Legal FM": while the car radio (Wrench Works, slrr_carRadio) is on that station, a short line about the career is shown now and then (the HUD message area), built
-- from its events. Nothing is said in a race, a chase or with the police on you; the news waits. Without the car radio's station API the lines come over any station while it is on.
-- No voices and no music from here: the music is the car radio's.

local M = {}

local rules = require('sl/core/radio')
local rngLib = require('sl/core/rng')
local crewsLib = require('sl/core/crews')

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

local radio = rules.new()
local rng = rngLib.new(os.time())
local clock, timer, registered = 0, 0, false

-- the car radio's side (slrr_carRadio.status(): { on, station, text, id }); nil without the radio
local function status()
  local ok, st = pcall(function() return slrr_carRadio and slrr_carRadio.status and slrr_carRadio.status() end)
  return ok and type(st) == 'table' and st or nil
end

local function register()
  if registered or not (slrr_carRadio and slrr_carRadio.registerStation) then return end
  registered = pcall(slrr_carRadio.registerStation, { id = rules.STATION_ID, name = rules.STATION_NAME, text = true }) == true
end
local function unregister()
  if registered and slrr_carRadio and slrr_carRadio.unregisterStation then pcall(slrr_carRadio.unregisterStation, rules.STATION_ID) end
  registered = false
end

-- is the DJ on the air: the radio is on, and (with the station API) tuned to our station
local function onAir()
  local st = status()
  if not st or st.on ~= true then return false end
  if registered then return st.id == rules.STATION_ID end
  return true
end

-- a race, a chase or the police: nothing is said
local function quiet()
  if sl_career and sl_career.freeToStart and sl_career.freeToStart() then return true end
  if slrr_garage and slrr_garage.getPhase and slrr_garage.getPhase() ~= 'idle' then return true end      -- (the car radio is off in a garage visit)
  if sl_police and sl_police.level and (sl_police.level() or 0) > 0 then return true end
  return false
end

local function news(kind, args)
  local s = career()
  if not s or not kind then return end
  rules.push(radio, kind, args, s.day or 0)
end

function M.onStreetLegalRaceResult(won, opponent, _, stake) news(rules.fromRace(won, opponent, stake)) end
function M.onStreetLegalPinkSlip(won, opponent) news(won and 'pink_won' or 'pink_lost', { opponent or '?' }) end
function M.onStreetLegalWeather(id) news(rules.fromWeather(id), {}) end
function M.onStreetLegalHeatUp() news('heat', {}) end
function M.onStreetLegalBusted() news('busted', {}) end
function M.onStreetLegalKingOfValo() news('king', {}) end
function M.onStreetLegalDistrictTaken(_, crewId)
  local c = crewsLib.crew and crewsLib.crew(crewId)
  news('district', { c and c.name and c.name:gsub('^%l', string.upper) or '?' })
end

function M.onUpdate(dt)
  timer = timer + (dt or 0)
  if timer < 1 then return end
  clock, timer = clock + timer, 0
  local s = career()
  if not s then return end
  register()
  if not onAir() then return end
  local text = rules.next(radio, clock, s.day or 0, quiet(), rng)
  if text and ui_message then ui_message(text, 7, 'slrrRadio') end
end

-- for the phone and the tester
function M.status() return { registered = registered, news = #radio.queue, spoke = radio.spoke, onAir = onAir() } end

function M.onStreetLegalStopped() unregister() radio = rules.new() clock, timer = 0, 0 end
function M.onStreetLegalStarted() radio = rules.new() end
function M.onClientEndMission() registered = false radio = rules.new() end

require('sl/core/features').gate('radio', M, nil, nil, { 'status' })

return M
