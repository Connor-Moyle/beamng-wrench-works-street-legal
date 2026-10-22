-- Street Legal: the parts of the game the player can switch off (Mods menu > Street Legal > Parts of the game; also on the Active features page). One option each (default on).
-- A part that is off does nothing: gate() wraps the reaction hooks of its extensions so they return at once (updates, events, new days, race results), and when the switch is
-- turned off at run time the extension is told to stop (onStreetLegalStopped: markers and running things go). Nothing a hook writes into a save is skipped (save, load, start and
-- cleanup hooks always run), and nothing is deleted: switched on again, the part carries on from its save.
local M = {}

-- id, option key, title, what the player gets when it is off (the note under the switch)
M.LIST = {
  { id = 'spectators', opt = 'slSpectators', title = 'Spectators at races', desc = 'Small crowds at the start and the finish of races. Off: nobody watches.' },
  { id = 'billboards', opt = 'slBillboards', title = 'Sponsor billboards', desc = 'The billboards along the road show your sponsor or club. Off: the game\'s own billboards stay as they are.' },
  { id = 'ambience', opt = 'slAmbience', title = 'Ambient sounds', desc = 'Waves at the water, the roar of a wide road, a crowd in town. Off: only the game\'s own sounds.' },
  { id = 'puddles', opt = 'slPuddles', title = 'Puddles and splashes', desc = 'Puddles on the road in the rain, with splashes, mist and aquaplaning. Off: no puddles (wet roads still get dark and shiny with wet tarmac).' },
  { id = 'achievements', opt = 'slAchievements', title = 'Achievements', desc = 'Awards for things you have done, with a toast when you earn one. Off: nothing is awarded or shown.' },
  { id = 'tutorial', opt = 'slTutorial', title = 'Getting-started tips', desc = 'The first-hour tips on the phone. Off: no tips.' },
  { id = 'market', opt = 'slMarket', title = 'Car and part markets', desc = 'Classified ads, car auctions and the Car market and Part market apps. Off: no listings and no apps.' },
  { id = 'rally', opt = 'slRally', title = 'Rally stages', desc = 'The rally stages and their start markers. Off: no stages.' },
  { id = 'races', opt = 'slRaces', title = 'Street races and drag racing', desc = 'Street races, circuits and the drag strip, with their markers and the Races app. Off: no races.' },
  { id = 'clubs', opt = 'slClubs', title = 'Clubs', desc = 'Car clubs, their leagues and club days, and the Club app. Off: no clubs.' },
  { id = 'crews', opt = 'slCrews', title = 'Crews and turf', desc = 'Street crews, their turf and raids, and the Turf app. Off: no crews.' },
  { id = 'tow', opt = 'slTow', title = 'Tow truck', desc = 'A tow truck comes for a car left out on the street. Off: the car is brought round without a truck.' },
  { id = 'cab', opt = 'slCab', title = 'Taxi ride', desc = 'A cab drives you across town. Off: the Cab app still takes you there, at once, with no cab on the road.' },
  { id = 'bank', opt = 'slBank', title = 'Bank', desc = 'A loan and insurance, with the Bank app. Off: no loan, no insurance, repairs and impound bills are paid in full. Cannot be switched off while a loan is open. The switch is global: with it off, a loan open in another career is frozen (no interest, no payments) until it is switched on.' },
  { id = 'hospital', opt = 'slHospital', title = 'Hospital', desc = 'A crash that hurts or kills the driver costs a doctor bill and keeps you off the road for a while. Off: injuries cost nothing and stop nothing (hardcore death needs the hospital on; it cannot be switched off in a hardcore career); the damage of the car stays as it is.' },
  { id = 'hudpill', opt = 'slHudPill', title = 'HUD phone pill', desc = 'The small money and title pill and the message pop-ups on the screen while the phone is closed. Off: neither (the phone itself still works).' },
  { id = 'laptop', opt = 'slLaptop', title = 'Laptops', desc = 'The computers of the map open the laptop for the career. Off: no laptop prompts.' },
  { id = 'maps', opt = 'slMaps', title = 'Maps', desc = 'The Map app on the phone and the Maps HUD app. Off: no Map app and no map feed (the route buttons of the phone still work).' },
  { id = 'upgrades', opt = 'slUpgrades', title = 'Garage upgrades', desc = 'The lift, bench, dyno, paint booth, shelving and photo corner are bought for the garage. Off: the garage has all of them from the start and nothing is for sale.' },
  { id = 'usedcheck', opt = 'slUsedCheck', title = 'Used-car checks', desc = 'A private car ad shows the history of the car (owners, service record, accidents) but not its faults: a mechanic check, for a fee, shows them and what each costs to fix. Off: the ads show every fault, as before.' },
  { id = 'contracts', opt = 'slContracts', title = 'Contracts', desc = 'A few part runs and courier parcels on the Jobs board come with terms (no damage, a tight time, in the rain, or in a car worth $15,000 or more) and pay much more when you keep them. Off: no terms, normal pay.' },
  { id = 'perks', opt = 'slPerks', title = 'Tier perks', desc = 'Each boss you beat gives a lasting advantage: cheaper garage upgrades and services, better pay on jobs, lower fines, a higher loan limit. Off: no advantages.' },
  { id = 'traps', opt = 'slTraps', title = 'Speed traps', desc = 'Speed traps and speed zones on long roads: your speed through a trap or your average through a zone is recorded against a target, and beating it the first time pays. Off: nothing is watched.' },
  { id = 'danger', opt = 'slDanger', title = 'Danger zones', desc = 'Jumps and drifts count: the longest jump you fly pays at 20, 40, 70 and 110 m, and two drift zones on long roads score your drift points against a target. Off: nothing is watched.' },
  { id = 'service', opt = 'slService', title = 'Servicing and wear', desc = 'Cars wear much faster, a service is due about every 150 km, and skipping it wears the car more. A basic service and an overhaul are bought on the phone. Off: wear stays as slow as it was and there is no service.' },
  { id = 'weekly', opt = 'slWeekly', title = 'Weekly costs', desc = 'Each week the garage rent and the storage of the cars beyond two are paid, with a ledger on the phone. What you cannot pay becomes a debt at the bank (never a repossession). Off: no weekly bills.' },
  { id = 'scenes', opt = 'slScenes', title = 'Cinematic moments', desc = 'A short full-screen scene when the night starts or the day starts (the sky, the city lights, a title card); any key skips it. Off: the plain fade to black.' },
  { id = 'jobs', opt = 'slJobs', title = 'Jobs', desc = 'Courier and workshop jobs, their markers and the Jobs app. Off: no jobs.' },
}
local byId = {}
for _, f in ipairs(M.LIST) do byId[f.id] = f end
function M.get(id) return byId[id] end

-- is the part on? get(key) is sl_options.get (a missing option system, or a missing value, is on)
-- parts that are off for the career that is loaded (a save from before the 0.8.0 economy, sl/core/economy): id -> true; the player's own switches are not changed
local saveOff = {}
function M.setSaveOff(ids) saveOff = {} for _, id in ipairs(ids or {}) do saveOff[id] = true end end
function M.isSaveOff(id) return saveOff[id] == true end

function M.on(id, get)
  local f = byId[id]
  if not f then return true end
  if saveOff[id] then return false end
  get = get or (rawget(_G, 'sl_options') and sl_options.get)
  if not get then return true end
  return get(f.opt) ~= false
end

-- hooks that always run: saving, loading, cleaning up (a module can name more, `keep`: a career start that makes its save state)
local ALWAYS = { 'Save', 'Load', 'Stopped', 'Unloaded', 'EndMission', 'StartMission', 'WorldReady', 'SettingsReady', 'Option' }
local function always(name)
  for _, w in ipairs(ALWAYS) do if name:find(w, 1, true) then return true end end
  return false
end

-- wraps every on... hook of the extension table m that is not an always-hook, and the calls named in `also`: with the part off they return nothing. Also takes the option change: switched off, the extension
-- is stopped once (its onStreetLegalStopped), and switched on again the hooks named in `resume` run once. `get` is for tests. Returns m.
function M.gate(id, m, get, keep, also, resume)
  local f = byId[id]
  if not f then return m end
  local kept = {}
  for _, k in ipairs(keep or {}) do kept[k] = true end
  local extra = {}
  for _, k in ipairs(also or {}) do extra[k] = true end                    -- (calls other modules make: a tow, a cab, a summary for the phone, the puddle update)
  for name, fn in pairs(m) do
    if type(fn) == 'function' and ((name:sub(1, 2) == 'on' and not always(name) and not kept[name]) or extra[name]) then
      m[name] = function(...) if M.on(id, get) then return fn(...) end end
    end
  end
  local after = m.onStreetLegalOption
  local stopped = m.onStreetLegalStopped
  m.onStreetLegalOption = function(key, value, ...)
    if key == f.opt and value == false and stopped then pcall(stopped) end
    if key == f.opt and value == true then for _, name in ipairs(resume or {}) do if type(m[name]) == 'function' then pcall(m[name]) end end end      -- (switched on again: start what a career start starts)
    if after then return after(key, value, ...) end
  end
  return m
end

return M
