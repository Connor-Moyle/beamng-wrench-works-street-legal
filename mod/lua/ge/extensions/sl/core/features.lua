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
  { id = 'mastery', opt = 'slMastery', title = 'Car mastery', desc = 'Kilometres and clean races in one car earn it small perks: cheaper insurance while you drive it, a better trade-in, cheaper service and tyres, and a badge on My cars. Off: no levels and no perks.' },
  { id = 'perks', opt = 'slPerks', title = 'Tier perks', desc = 'Each boss you beat gives a lasting advantage: cheaper garage upgrades and services, better pay on jobs, lower fines, a higher loan limit. Off: no advantages.' },
  { id = 'radio', opt = 'slRadio', default = false, title = 'Car radio DJ', desc = 'A text station, Street Legal FM, on the Wrench Works car radio: short lines about your career (races, the weather, the police, the crews). Nothing is said in a race or a chase. Off: no station and no lines.' },
  { id = 'inventory', opt = 'slInventory', title = 'Inventory', desc = 'You carry what you buy: parts from shops wait in the boot of your car until you drive into your garage (then they go on the shelf), and oil, coolant, a battery, jerry cans and tools are kept there too. Off: shops put parts on the garage shelf at once, as before, and there is no boot.' },
  { id = 'turf', opt = 'slTurf', default = false, title = 'Turf income', desc = 'The districts you hold pay a weekly cut into the ledger (more at the district with your third garage); an angry crew can raid one, which costs that week\'s cut and some control (never the district by itself). Off: nothing is paid and nothing is raided.' },
  { id = 'myroute', opt = 'slMyRoute', default = false, title = 'My route', desc = 'Drop 4 to 8 waypoints where your car is, save the route and race it against the clock; your best time is kept per route. No money, no reputation. Off: no My routes app, nothing is timed.' },
  { id = 'traps', opt = 'slTraps', title = 'Speed traps', desc = 'Speed traps and speed zones on long roads: your speed through a trap or your average through a zone is recorded against a target, and beating it the first time pays. Off: nothing is watched.' },
  { id = 'danger', opt = 'slDanger', title = 'Danger zones', desc = 'Jumps and drifts count: the longest jump you fly pays at 20, 40, 70 and 110 m, and two drift zones on long roads score your drift points against a target. Off: nothing is watched.' },
  { id = 'barn', opt = 'slBarn', title = 'Barn finds', desc = 'Now and then a contact texts about an old car in a yard far from town; drive there and it shows in the Car market, cheap and in a bad state. Off: no rumours and no hidden cars.' },
  { id = 'sponsors', opt = 'slSponsors', title = 'Brand sponsorships', desc = 'Winning in the cars of a maker, or with its parts fitted, builds standing with that brand; past a threshold it offers a sponsorship: a discount on its parts, a weekly retainer, and terms to keep. Off: the old fixed sponsors by reputation.' },
  { id = 'invites', opt = 'slInvites', title = 'Brand invitationals', desc = 'A brand you are close to (a sponsor of four weeks, or high standing) invites you by text, at most three times, to a race on a long dockyards circuit in a race-spec car it lends you. No fee; a dented car costs standing only. Off: no invitations.' },
  { id = 'mates', opt = 'slMates', default = false, title = 'Crew mates', desc = 'Taking a district from a rival crew brings one of its people over: a mechanic (cheaper parts and service), a tipster (a text a day about the next race) or a scout (calls the police ahead, rides along when Drivers is there). Off: no mates.' },
  { id = 'seasons', opt = 'slSeasons', default = false, title = 'Seasons', desc = 'The career has four seasons of four weeks each (spring first). They change the odds of rain, cloud and fog, the air temperature (cold enough for the rain to fall as snow with Car Surface FX, colder up high), whether a clear day is hot for thirst, and a few per cent on some purses. Off: the plain weather.' },
  { id = 'travel', opt = 'slTravel', title = 'Career travel', desc = 'At a reputation you are invited to race series on other maps (Hirochi Raceway, Utah, Johnson Valley): you take up to three cars, pay a fee and race a round a day, with points, a table and prizes. Off: no trips and no series.' },
  { id = 'service', opt = 'slService', title = 'Servicing and wear', desc = 'Cars wear much faster, a service is due about every 150 km, and skipping it wears the car more. A basic service and an overhaul are bought on the phone. Off: wear stays as slow as it was and there is no service.' },
  { id = 'weekly', opt = 'slWeekly', title = 'Weekly costs', desc = 'Each week the garage rent and the storage of the cars beyond two are paid, with a ledger on the phone. What you cannot pay becomes a debt at the bank (never a repossession). Off: no weekly bills.' },
  { id = 'scenes', opt = 'slScenes', title = 'Cinematic moments', desc = 'A short full-screen scene when the night starts or the day starts (the sky, the city lights, a title card); any key skips it. Off: the plain fade to black.' },
  { id = 'shops', opt = 'slShops', title = 'Shops', desc = 'Shops with their own screens (tyre shop, exhaust shop and others), opened at a shop marker or by another mod. Off: no shop screens and no shop markers.' },
  { id = 'jobs', opt = 'slJobs', title = 'Jobs', desc = 'Courier and workshop jobs, their markers and the Jobs app. Off: no jobs.' },
  { id = 'hillduel', opt = 'slHillDuel', title = 'Hill duels', desc = 'At night the hill roads carry a marker: a duel against a rival for a bet, scored by points (the leader scores while well ahead, the follower while close; off the road costs). Off: no markers, no duels.' },
  { id = 'grabbag', opt = 'slGrabBag', title = 'Grab bag', desc = 'A good week (three jobs, two race wins or $2,000 earned) leaves a box of two to four used parts for the car you bring to the garage next, on its shelf for nothing. Off: no boxes.' },
  { id = 'calendar', opt = 'slCalendar', title = 'Calendar', desc = 'The Calendar app: weekend races on the dockyards circuits (enter on the phone, be on the grid at the hour), the swap meet, and the monthly series to come, with reminders a day and an hour ahead. Off: no app, no weekend races, no reminders.' },
  { id = 'show', opt = 'slShow', title = 'Style shows', desc = 'A weekend show night at a meet spot: judges score your car on paint, wheels, parts, cleanliness, body and wear, against a field of rival cars, with a prize and reputation. Off: no shows and no preview.' },
  { id = 'siphon', opt = 'slSiphon', default = false, title = 'Fuel siphoning', desc = 'On foot, with a jerry can and a siphon tube in your boot, hold the siphon key at a car to take its fuel into the can (somebody may notice), and the pour key at your own car to pour it in. Needs the Inventory part. Off: no prompt and nothing moves.' },
  { id = 'needs', opt = 'slNeeds', default = false, title = 'Needs: hunger, thirst and sleep', desc = 'Three meters drain while you are awake. Low: a nudge on the phone, then a blur, slower reactions or shaky hands, never a game over. Food and drink at fuel stations, sleep when the day starts or a nap at the garage. Off (the default): nothing ticks and nothing shows.' },
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
