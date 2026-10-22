-- Wrench Works: Street Legal: its own settings (extension name: sl_options; X53), a "Street Legal" group on
-- the Mods menu in the pause menu (Wrench Works' slrr_settings registry; docs/MODS_MENU.md on its branch mods-menu): this list is the data model, the page is generated from it.
-- What changes the game's balance is the career's own (kept in its save, per slot, and shown only while one is
-- played); the rest is the player's, for every career (/settings/street_legal/options.json).

local M = {}

local strings = require('sl/core/strings')

local FILE = '/settings/street_legal/options.json'
local GROUP = strings.t('options.street_legal')

local LEVELS = { { id = 'all', label = strings.t('options.every_text') }, { id = 'important', label = strings.t('options.racers_only') }, { id = 'off', label = 'None' } }
M.defs = {
  { key = 'slPolice', feature = true, career = true, title = 'Police', type = 'bool', default = true,
    desc = strings.t('options.patrols_at_night_heat_from') },
  { key = 'slPoliceLevel', career = true, title = strings.t('options.police_aggression'), type = 'range', min = 0.5, max = 2, step = 0.25, default = 1, unit = 'x',
    desc = strings.t('options.how_many_patrols_and_how') },
  { key = 'slEconomy', career = true, title = 'Pay', type = 'range', min = 0.5, max = 2, step = 0.25, default = 1, unit = 'x',
    desc = strings.t('options.what_jobs_purses_and_season') },
  { key = 'slHardcore', career = true, title = 'Hardcore', type = 'bool', default = false,
    desc = strings.t('options.no_paid_pull_back_to') },
  { key = 'slRaids', feature = true, career = true, title = strings.t('options.crew_raids'), type = 'bool', default = true,
    desc = strings.t('options.a_crew_you_took_a') },
  { key = 'slRaceTraffic', title = strings.t('options.traffic_in_street_races'), type = 'choice', default = 'normal',
    options = { { id = 'normal', label = strings.t('options.as_usual') }, { id = 'light', label = 'Light' }, { id = 'none', label = 'None' } },
    desc = strings.t('options.thins_out_the_town_s') },
  { key = 'slMarkers', feature = true, title = strings.t('options.race_flares_and_start_lines'), type = 'bool', default = true,
    desc = strings.t('options.the_flares_along_a_race') },
  { key = 'slNotify', title = strings.t('options.text_pop_ups'), type = 'choice', default = 'all', options = LEVELS,
    desc = strings.t('options.which_new_texts_pop_up') },
  { key = 'slClock', title = strings.t('options.clock_speed'), type = 'choice', default = 'slow',
    options = { { id = 'slow', label = strings.t('options.slow_2_5_min_an') }, { id = 'normal', label = strings.t('options.normal_1_25_min_an') }, { id = 'fast', label = strings.t('options.fast_0_6_min_an') } },
    desc = strings.t('options.how_fast_the_in_game') },
  { key = 'slDashboard', feature = true, title = strings.t('options.slrr_dashboard'), type = 'bool', default = false,
    desc = strings.t('options.the_slrr_gauges_map_and') },
  { key = 'slReplay', feature = true, title = strings.t('options.record_street_races'), type = 'bool', default = true,
    desc = strings.t('options.records_a_street_race_with') },
  { key = 'slTextScale', title = strings.t('settings.textSize'), type = 'choice', default = 'normal',
    options = { { id = 'normal', label = strings.t('settings.textNormal') }, { id = 'large', label = strings.t('settings.textLarge') }, { id = 'huge', label = strings.t('settings.textHuge') } },
    desc = strings.t('settings.textSizeDesc') },
  { key = 'slColorBlind', title = strings.t('settings.colorBlind'), type = 'bool', default = false,
    desc = strings.t('settings.colorBlindDesc') },
  { key = 'slReduceMotion', title = strings.t('settings.reduceMotion'), type = 'bool', default = false,
    desc = strings.t('settings.reduceMotionDesc') },
  { key = 'slCaptions', title = strings.t('settings.captions'), type = 'bool', default = true,
    desc = strings.t('settings.captionsDesc') },
  { key = 'slPerf', title = strings.t('options.performance_overlay'), type = 'bool', default = false,
    desc = strings.t('options.a_small_box_top_left') },
  { key = 'slWallpaper', title = strings.t('options.laptop_wallpaper'), type = 'choice', default = 'windows',
    options = { { id = 'windows', label = strings.t('options.my_windows_wallpaper') }, { id = 'builtin', label = 'Built-in' } },
    desc = strings.t('options.the_laptop_s_desktop_your') },
  { key = 'slScenes', feature = true, title = strings.t('options.cinematic_moments'), type = 'bool', default = true,
    desc = strings.t('options.cinematic_moments_text') },
  { key = 'slAutoPhoto', feature = true, title = strings.t('options.photo_of_a_new_car'), type = 'bool', default = true,
    desc = strings.t('options.a_new_car_is_photographed') },
  { key = 'slPuddleCount', title = strings.t('options.puddles_in_the_rain'), type = 'range', min = 10, max = 300, step = 10, unit = '', default = 120,
    tab = 'Clock and weather', group = 'Rain on the ground', presets = { performance = 40, balanced = 90, quality = 150, max = 250 },
    desc = strings.t('options.how_many_puddles_stand_on') },
  { key = 'slSplashSize', title = strings.t('options.splash_size'), type = 'range', min = 0.1, max = 1.5, step = 0.05, unit = 'x', default = 0.4,
    tab = 'Clock and weather', group = 'Rain on the ground', presets = { performance = 0.25, balanced = 0.4, quality = 0.5, max = 0.6 }, desc = strings.t('options.how_high_the_water_a') },
  { key = 'slWetWorld', feature = true, title = strings.t('options.wet_world'), type = 'bool', default = false, tab = 'Clock and weather', group = 'Rain on the ground',
    presets = { performance = false, balanced = false, quality = false, max = false }, desc = strings.t('options.in_the_rain_roads_walls_and') },
  { key = 'slMapStyle', title = strings.t('options.map_style'), type = 'choice', default = 'street', tab = 'Maps', group = 'Maps',
    options = { { id = 'street', label = strings.t('options.map_style_street') }, { id = 'cruise', label = strings.t('options.map_style_cruise') }, { id = 'atlas', label = strings.t('options.map_style_atlas') } }, desc = strings.t('options.map_style_text') },
  { key = 'slMapHeadingUp', title = strings.t('options.map_heading_up'), type = 'bool', default = false, tab = 'Maps', group = 'Maps',
    desc = strings.t('options.map_heading_up_text') },
  { key = 'slMapSpeed', feature = true, title = strings.t('options.map_speed'), type = 'bool', default = true, tab = 'Maps', group = 'Maps',
    desc = strings.t('options.map_speed_text') },
  { key = 'slMapKSlide', feature = true, title = strings.t('options.map_k_slide'), type = 'bool', default = true, tab = 'Maps', group = 'Maps',
    desc = strings.t('options.map_k_slide_text') },
  { key = 'slMapZoom', title = strings.t('options.map_zoom'), type = 'choice', default = 'normal', tab = 'Maps', group = 'Maps',
    options = { { id = 'close', label = strings.t('options.map_zoom_close') }, { id = 'normal', label = strings.t('options.map_zoom_normal') }, { id = 'far', label = strings.t('options.map_zoom_far') } }, desc = strings.t('options.map_zoom_text') },
  { key = 'slPhoneSkin', title = strings.t('options.phone_skin'), type = 'choice', default = 'classic', tab = 'Screens and texts', group = 'Phone look',
    options = require('sl/phoneskins').choices(), desc = strings.t('options.phone_skin_text') },
  { key = 'slWetTarmac', feature = true, title = strings.t('options.wet_tarmac'), type = 'bool', default = false, tab = 'Clock and weather', group = 'Rain on the ground',
    presets = { performance = false, balanced = false, quality = false, max = false }, desc = strings.t('options.wet_tarmac_text') },
  { key = 'slWetStrength', title = strings.t('options.wet_world_strength'), type = 'range', min = 0, max = 1, step = 0.05, scale = 100, unit = '%', default = 0.8,
    tab = 'Clock and weather', group = 'Rain on the ground', presets = { quality = 0.9, max = 1 }, desc = strings.t('options.how_dark_and_shiny_the') },
  { key = 'slRainBox', title = strings.t('options.rain_around_you'), type = 'range', min = 40, max = 150, step = 10, unit = 'm', default = 70,
    tab = 'Clock and weather', group = 'Rain on the ground', presets = { performance = 50, balanced = 70, quality = 90, max = 110 }, desc = strings.t('options.rain_only_falls_in_a') },
  { key = 'slWeather', feature = true, needs = 'weather', title = 'Weather', type = 'bool', default = true,
    desc = strings.t('options.rain_wet_roads_and_night') },
  { key = 'slPoliceStrips', feature = true, career = true, tab = 'Police chase', group = strings.t('options.spike_strips'), title = strings.t('options.spike_strips'), type = 'bool', default = true,
    desc = strings.t('options.at_heat_3_and_above') },
  { key = 'slPoliceBreakers', feature = true, career = true, tab = 'Police chase', group = strings.t('options.pursuit_breakers'), title = strings.t('options.pursuit_breakers'), type = 'bool', default = true,
    desc = strings.t('options.marked_spots_on_straight_roads') },
  { key = 'slPoliceLevels', feature = true, tab = 'Police chase', group = 'Pursuit levels', title = 'Pursuit level follows the heat', type = 'bool', default = true,
    desc = 'A chase starts at pursuit level 1 at heat 1 and 2, level 2 at heat 3 and 4, level 3 at heat 5, with more patrols joining the hotter you are, and the game climbs a level sooner. Off: every chase starts at level 1 with the nearest patrol.' },
  { key = 'slPoliceFinish', feature = true, career = true, tab = 'Police chase', group = 'Pursuit levels', title = 'Police at the finish', type = 'bool', default = true,
    desc = 'When a night street race ends, a patrol near the route may be waiting (the chance grows with the heat). Off: patrols only join at the start.' },
  { key = 'slPoliceHide', feature = true, tab = 'Police chase', group = 'Hiding and cooling down', title = 'Hiding spots and cool-down', type = 'bool', default = true,
    desc = 'Parked out of sight at a garage or a fuel station the police lose you three times as fast. After an escape they leave you alone for a minute and a half and the heat cools fast. A repaint at night takes one heat level off, once a night.' },
  { key = 'slPoliceChatter', feature = true, tab = 'Police chase', group = 'Radio', title = 'Police radio (text)', type = 'bool', default = true,
    desc = 'Short radio lines on screen during a chase: the pursuit starting, units joining, visual lost and regained, a roadblock, spikes, the end.' },
  { key = 'slPoliceUnits', feature = true, tab = 'Police chase', group = 'Units', title = 'More police units at high heat', type = 'bool', default = true,
    desc = 'From heat 3 a highway patrol car can be among the patrols, from heat 4 an unmarked car and a police van, all from the game. Off: the three usual patrol cars.' },
  { key = 'slPoliceStripYaw', advanced = true, tab = 'Developer', group = 'Police chase', title = strings.t('options.chase_prop_turn'), type = 'choice', default = '0',
    options = { { id = '0', label = '0' }, { id = '90', label = '90' } }, desc = strings.t('options.turns_the_strip_and_the') },
  { key = 'slNightRaceKinds', feature = true, tab = 'Night traffic', group = strings.t('options.race_kinds'), title = strings.t('options.race_kinds'), type = 'bool', default = true,
    desc = strings.t('options.night_races_go_to_a') },
  { key = 'slMaxCruisers', tab = 'Night traffic', group = strings.t('options.racers_cruising_at_night'), title = strings.t('options.racers_cruising_at_night'), type = 'range', min = 0, max = 6, step = 1, default = 3, unit = '',
    desc = strings.t('options.how_many_street_racers_cruise') },
  { key = 'slCityRace', tab = 'Races', group = strings.t('options.longest_street_race'), title = strings.t('options.longest_street_race'), type = 'range', min = 800, max = 4000, step = 200, default = 1800, unit = ' m',
    desc = strings.t('options.the_furthest_a_street_race') },
  { key = 'slRaceTimeout', tab = 'Races', group = strings.t('options.time_before_a_race_is_called_off'), title = strings.t('options.time_before_a_race_is_called_off'), type = 'range', min = 240, max = 1200, step = 60, default = 600, unit = ' s',
    desc = strings.t('options.a_race_nobody_finishes_is') },
  { key = 'slPatrols', career = true, tab = 'Police chase', group = strings.t('options.patrols_at_night'), title = strings.t('options.patrols_at_night'), type = 'range', min = 0, max = 4, step = 1, default = 2, unit = '',
    desc = strings.t('options.how_many_police_cars_patrol') },
  { key = 'slNightPrespawn', tab = 'Night traffic', group = strings.t('options.prepare_night_traffic_during_the_fade'), title = strings.t('options.prepare_night_traffic_during_the_fade'), type = 'bool', default = true,
    desc = strings.t('options.builds_the_first_two_cruisers') },
  { key = 'slWetTrace', advanced = true, tab = 'Developer', group = 'Rain on the ground', title = strings.t('options.wet_trace'), type = 'bool', default = false,
    desc = strings.t('options.wet_trace_text') },
  { key = 'slOfflineTree', advanced = true, tab = 'Developer', group = 'Night traffic', title = strings.t('options.read_the_parts_tree_without_a_car'), type = 'bool', default = true,
    desc = strings.t('options.a_first_build_of_a') },
  { key = 'slRain', needs = 'weather', title = 'Rain', type = 'range', min = 0, max = 0.5, step = 0.02, default = 0.12, unit = '/h',
    desc = strings.t('options.how_often_a_shower_starts') },
  -- the rivals and the car auctions (sl_rivals, sl_carauctions): shown in the Mods menu only (tab / group), never on the phone or the laptop; the game's balance, per player, for every career
  { key = 'slRivals', feature = true, tab = 'Rivals', group = 'Rivals', title = 'Named rivals', type = 'bool', default = true,
    desc = 'Six racers with names, personalities and cars who text you and challenge you. Off: no rival texts and no tier gate; the street races work as they did before.' },
  { key = 'slRivalEscalate', tab = 'Rivals', group = 'How often', title = 'Bigger bet offers', type = 'range', min = 0, max = 1, step = 0.05, unit = '%', scale = 100, default = 0.35,
    desc = 'The chance each night that a rival you have raced a few times offers a higher stake. Lower means fewer offers.' },
  { key = 'slRivalTaunt', tab = 'Rivals', group = 'How often', title = 'Taunts and words of respect', type = 'range', min = 0, max = 1, step = 0.05, unit = '%', scale = 100, default = 0.3,
    desc = 'The chance each night of a text from a rival you have raced, when nothing else is due. At zero they only write about the races.' },
  { key = 'slRivalReactions', tab = 'Rivals', group = 'How often', title = 'Texts after a race', type = 'range', min = 0, max = 1, step = 0.05, unit = '%', scale = 100, default = 0.7,
    desc = 'The chance a rival texts you after you race them. At zero they stay quiet after races.' },
  { key = 'slRivalOfferDays', tab = 'Rivals', group = 'Pink slips', title = 'Days a pink slip offer stays open', type = 'range', min = 1, max = 10, step = 1, unit = 'days', default = 3,
    desc = 'A rival who offers pink slips waits this many days for your answer. Nothing happens to your car unless you accept.' },
  { key = 'slBossWins', tab = 'The climb', group = 'Bosses', title = 'Wins before a boss calls you out', type = 'range', min = 1, max = 8, step = 1, unit = '', default = 3, advanced = true,
    desc = 'How many races you must win at a tier (or above) before its boss asks for you. Higher means a longer climb.' },
  { key = 'slRapSheet', feature = true, tab = 'The climb', group = 'Bosses', title = 'The file on each boss', type = 'bool', default = false,
    desc = 'Each tier boss keeps a file of three things to do before he asks for you: win races at the tier, earn money, and one more (a run of wins or beating the other named rivals). The phone shows the file on the Rivals card. Off: the boss asks once you have the wins, as before.' },
  { key = 'slBossCooldown', tab = 'The climb', group = 'Bosses', title = 'Days a boss waits after beating you', type = 'range', min = 0, max = 10, step = 1, unit = 'days', default = 3, advanced = true,
    desc = 'After you lose a boss showdown he will not ask again for this many days.' },
  { key = 'slRivalStepRaces', tab = 'The climb', group = 'Stakes', title = 'Races before a rival raises the stake', type = 'range', min = 1, max = 8, step = 1, unit = '', default = 3,
    desc = 'Each time you have raced a rival this many times, his bet steps up: pocket money, his top bet, high stakes.' },
  { key = 'slRivalUpgradeDays', tab = 'The climb', group = 'Their cars', title = 'Days between rival car upgrades', type = 'range', min = 2, max = 15, step = 1, unit = 'days', default = 5,
    desc = 'Rivals improve their cars with the days, and after you beat them. Lower means they get quicker sooner.' },
  { key = 'slAuctionLots', tab = 'Car auctions', group = 'Online auction', title = 'Lots on the online auction', type = 'range', min = 3, max = 10, step = 1, unit = '', default = 6,
    desc = 'How many cars are up for auction on the phone and laptop at once.' },
  { key = 'slAuctionDay', tab = 'Car auctions', group = 'Junkyard auction', title = 'Auction day (day number modulo 7)', type = 'range', min = 0, max = 6, step = 1, unit = '', default = 5, advanced = true,
    desc = 'The live auction at the junkyard happens on every seventh day. This picks which day of the seven.' },
  { key = 'slAuctionFrom', tab = 'Car auctions', group = 'Junkyard auction', title = 'Opens at (hour)', type = 'range', min = 6, max = 18, step = 1, unit = 'h', default = 10,
    desc = 'The hour the junkyard auction opens.' },
  { key = 'slAuctionTo', tab = 'Car auctions', group = 'Junkyard auction', title = 'Closes at (hour)', type = 'range', min = 8, max = 20, step = 1, unit = 'h', default = 13,
    desc = 'The hour the junkyard auction ends. Lots still running finish.' },
  { key = 'slYardLots', tab = 'Car auctions', group = 'Junkyard auction', title = 'Cars in the yard', type = 'range', min = 3, max = 8, step = 1, unit = '', default = 6,
    desc = 'How many cars stand in the junkyard bays on auction day.' },
  { key = 'slAuctionLive', tab = 'Car auctions', group = 'Junkyard auction', title = 'Time on each lot', type = 'range', min = 30, max = 180, step = 5, unit = 's', default = 75,
    desc = 'How long a lot is open at the live auction. A bid in the last seconds adds a few more.' },
  -- the game's balance (sl/balance.lua applies these to the rules): Mods menu only
  { key = 'slPayPerKm', tab = 'Economy', group = 'Jobs', title = 'Job pay per kilometre', type = 'range', min = 60, max = 300, step = 10, unit = '$', default = 140,
    desc = 'How much a courier or delivery job pays for each kilometre. Higher means faster money from jobs.' },
  { key = 'slDayJobPay', tab = 'Economy', group = 'Jobs', title = 'Day job pay multiplier', type = 'range', min = 0.5, max = 3, step = 0.05, unit = 'x', default = 1.35,
    desc = 'Day jobs pay this many times the base rate. The night jobs are not changed.' },
  { key = 'slJobSlack', tab = 'Economy', group = 'Jobs', title = 'Time allowed on jobs', type = 'range', min = 1, max = 2.5, step = 0.05, unit = 'x', default = 1.35, advanced = true,
    desc = 'The time limit of a job is the drive time multiplied by this. Higher gives you more time.' },
  { key = 'slLoanInterest', tab = 'Economy', group = 'Bank', title = 'Loan interest per day', type = 'range', min = 0, max = 0.1, step = 0.005, unit = '%', scale = 100, default = 0.03,
    desc = 'How much of what you owe the bank adds each game day. Zero means free loans.' },
  { key = 'slLoanMax', tab = 'Economy', group = 'Bank', title = 'Biggest loan', type = 'range', min = 20000, max = 300000, step = 10000, unit = '$', default = 120000, advanced = true,
    desc = 'The most the bank will ever lend you, whatever your cars and garage are worth.' },
  { key = 'slInsDeductible', tab = 'Economy', group = 'Bank', title = 'Insurance deductible', type = 'range', min = 0, max = 1000, step = 50, unit = '$', default = 200,
    desc = 'You pay this much of every insurance claim yourself.' },
  { key = 'slInsCover', tab = 'Economy', group = 'Bank', title = 'Insurance cover', type = 'range', min = 0.1, max = 1, step = 0.05, unit = '%', scale = 100, default = 0.5,
    desc = 'The share of a claim above the deductible that the insurance pays.' },
  { key = 'slListingFee', tab = 'Economy', group = 'Markets', title = 'Seller fee', type = 'range', min = 0, max = 0.2, step = 0.01, unit = '%', scale = 100, default = 0.05,
    desc = 'The share of a sale that the market keeps when one of your listings or auction lots sells.' },
  { key = 'slWashPrice', tab = 'Economy', group = 'Services', title = 'Car wash price', type = 'range', min = 0, max = 100, step = 5, unit = '$', default = 15,
    desc = 'What the car wash bay at a gas station charges.' },
  { key = 'slStartMoney', tab = 'Economy', group = 'New careers', title = 'Starting money', type = 'range', min = 1000, max = 20000, step = 500, unit = '$', default = 5000,
    desc = 'The money a new career starts with. Applies to careers you start after changing it.' },
  { key = 'slHeatRace', tab = 'Police & heat', group = 'What raises heat', title = 'Heat from a street race', type = 'range', min = 0, max = 0.5, step = 0.02, unit = '', default = 0.12,
    desc = 'How much a street race starting adds to your heat (1.0 is the most heat there is, five levels).' },
  { key = 'slHeatNearMiss', tab = 'Police & heat', group = 'What raises heat', title = 'Heat from flashing past a patrol', type = 'range', min = 0, max = 0.3, step = 0.01, unit = '', default = 0.04,
    desc = 'How much driving fast past a patrol car adds to your heat.' },
  { key = 'slHeatBust', tab = 'Police & heat', group = 'What raises heat', title = 'Heat after a bust', type = 'range', min = 0, max = 0.6, step = 0.02, unit = '', default = 0.2, advanced = true,
    desc = 'How much heat you start with after you were caught and paid the fine.' },
  { key = 'slHeatEscape', tab = 'Police & heat', group = 'What lowers heat', title = 'Reward for getting away', type = 'range', min = 0, max = 0.3, step = 0.01, unit = '', default = 0.06, advanced = true,
    desc = 'The heat added when you escape a chase (on top of the reputation you earn).' },
  { key = 'slHeatCool', tab = 'Police & heat', group = 'What lowers heat', title = 'Cooling per minute', type = 'range', min = 0, max = 0.05, step = 0.002, unit = '', default = 0.01,
    desc = 'How fast your heat falls each real minute when nobody is after you. Zero means it never cools by itself.' },
  { key = 'slPinkChance', tab = 'Races', group = 'Racers', title = 'Pink slip nights', type = 'range', min = 0, max = 0.5, step = 0.02, unit = '%', scale = 100, default = 0.12,
    desc = 'The chance on a given night that a racer who races for pink slips is up for it. Racing for pinks is always your choice.' },
  { key = 'slRematchChance', tab = 'Races', group = 'Racers', title = 'Rematch texts', type = 'range', min = 0, max = 1, step = 0.05, unit = '%', scale = 100, default = 0.5,
    desc = 'The chance that a racer you beat texts you later asking for a rematch.' },
  { key = 'slTauntChance', tab = 'Races', group = 'Racers', title = 'Taunts after a race', type = 'range', min = 0, max = 1, step = 0.05, unit = '%', scale = 100, default = 0.4,
    desc = 'The chance that a racer texts you a taunt or a sore-loser line after a race.' },
  { key = 'slDoctorBase', tab = 'Economy', group = 'Doctor', title = "Doctor's base bill", type = 'range', min = 0, max = 1000, step = 50, unit = '$', default = 150,
    desc = "The doctor charges this much for any visit after a crash that hurt you." },
  { key = 'slBoneFee', tab = 'Economy', group = 'Doctor', title = "Doctor, per broken bone", type = 'range', min = 0, max = 1000, step = 50, unit = '$', default = 250,
    desc = "Added to the doctor's bill for each broken bone." },
  { key = 'slDoctorSeverity', tab = 'Economy', group = 'Doctor', title = "Doctor, worst injuries", type = 'range', min = 0, max = 3000, step = 100, unit = '$', default = 800,
    desc = "Added to the doctor's bill in proportion to how bad the injuries are (the full amount for the worst)." },
  { key = 'slHospitalBase', tab = 'Economy', group = 'Hospital', title = "Hospital stay", type = 'range', min = 0, max = 6000, step = 100, unit = '$', default = 1200,
    desc = "The hospital's base bill when you were knocked out and woke up there." },
  { key = 'slHospitalDied', tab = 'Economy', group = 'Hospital', title = "Hospital stay after a killing crash", type = 'range', min = 0, max = 10000, step = 100, unit = '$', default = 2500,
    desc = "The base bill when the crash would have killed you (you wake up at the hospital in a normal career)." },
  { key = 'slHospitalSeverity', tab = 'Economy', group = 'Hospital', title = "Hospital, worst injuries", type = 'range', min = 0, max = 10000, step = 100, unit = '$', default = 3000,
    desc = "Added to the hospital bill in proportion to how bad the injuries are." },
  { key = 'slWearRate', tab = 'Difficulty', group = 'Wear', title = 'Wear rate and service interval', type = 'choice', default = 'normal',
    options = { { id = 'half', label = '0.5x: parts last twice as long, service every 300 km' }, { id = 'normal', label = '1x: service every 150 km' },
      { id = 'double', label = '2x: parts wear twice as fast, service every 75 km' }, { id = 'quad', label = '4x: four times as fast, service every 38 km' } },
    desc = 'How fast cars wear and how often they need a service. It sets the wear of the own wear model of the career, Part Wear (when installed) and the tyres (with Car Surface FX). Needs the Servicing and wear part on. Wear already there stays as it is.' },
  { key = 'slBuildGap', tab = 'World', group = 'Performance', title = 'Seconds between built cars', type = 'range', min = 8, max = 60, step = 2, unit = 's', default = 20, advanced = true, presets = { performance = 40, balanced = 20, quality = 14, max = 8 },
    desc = 'Building a car for the night traffic freezes the game for a second or so. Longer gaps mean fewer freezes and a quieter street.' },
  { key = 'slLotPrebuild', feature = true, tab = 'World', group = 'Performance', title = 'Build the nearest lot ahead', type = 'bool', default = true,
    desc = 'The cars of the nearest dealer, junkyard or scrapyard are built while the screen is black (the career start, a fast travel, a cab ride) and kept hidden until you look at the lot, so the lot opens without the freeze per car. Off: a lot builds its cars when you open it.' },
  { key = 'slLotCars', tab = 'World', group = 'Performance', title = 'Most cars on a lot', type = 'range', min = 2, max = 6, step = 1, default = 6, unit = '',
    desc = 'How many cars a lot shows at most. Fewer cars: less to build and less physics while you look.' },
  { key = 'slGridCars', tab = 'World', group = 'Performance', title = 'Cars against you in a grid race', type = 'range', min = 3, max = 7, step = 1, default = 6, unit = '',
    desc = 'How many AI cars line up with you in a weekend race (the calendar) and the other grid races. Fewer cars: a shorter black screen while the grid builds and less physics in the race.' },
  { key = 'slGridCams', tab = 'World', group = 'Performance', title = 'Camera flights at a grid race', type = 'bool', default = true,
    desc = 'The layout camera flight before the start and after the finish of a grid race. Off: straight to the countdown and the result.' },
  { key = 'slLotDents', tab = 'World', group = 'Performance', title = 'Dents on lot cars', type = 'bool', default = true,
    desc = 'Used cars on a lot are bent where their report says. Off: the row builds faster; the dents still count in the report and the price.' },
  -- the Needs part (sl_needs; its on/off switch is in Parts of the game)
  { key = 'slNeedsDrain', tab = 'Needs', group = 'Needs', title = 'Drain speed', type = 'range', min = 0.25, max = 2, step = 0.25, default = 1, unit = 'x',
    desc = 'How fast hunger, thirst and tiredness grow (1 is the normal speed: food lasts about 16 hours of play, water 9, rest 20).' },
  { key = 'slNeedsStrength', tab = 'Needs', group = 'Needs', title = 'Effect strength', type = 'range', min = 0, max = 100, step = 10, default = 100, unit = '%',
    desc = 'How strong the blur, the slower reactions and the shaky hands get at the worst. They are capped so a run is never lost to them.' },
  { key = 'slNeedsBlur', tab = 'Needs', group = 'Effects', title = 'Blur when thirsty or tired', type = 'bool', default = true,
    desc = 'The edges of the screen blur a little when you are parched or very tired, and pulse at night when you are exhausted.' },
  { key = 'slNeedsLag', tab = 'Needs', group = 'Effects', title = 'Slower reactions when tired', type = 'bool', default = true,
    desc = 'Steering and pedals follow your input with a small lag (60 to 120 ms) when you are tired.' },
  { key = 'slNeedsTremor', tab = 'Needs', group = 'Effects', title = 'Shaky hands when hungry', type = 'bool', default = true,
    desc = 'A faint shake on the steering when you are hungry.' },
  { key = 'slNeedsReduceMotion', tab = 'Needs', group = 'Effects', title = 'Reduce motion', type = 'bool', default = false,
    desc = 'No screen blur from needs (the Driver Injuries add-on has its own Reduce motion switch, which also counts).' },
  { key = 'slNeedsShow', tab = 'Needs', group = 'Needs', title = 'Show the meters always', type = 'bool', default = false,
    desc = 'The three meters on the phone pill at all times, not only when one is low.' },
}
-- where each setting is on the Mods menu page: { tab, group }
local PLACE = {
  slPolice = { 'Difficulty', 'Police' }, slPoliceLevel = { 'Difficulty', 'Police' }, slRaids = { 'Difficulty', 'Crews' },
  slEconomy = { 'Difficulty', 'Money' }, slHardcore = { 'Difficulty', 'Hardcore' },
  slRaceTraffic = { 'Street racing', 'Races' }, slMarkers = { 'Street racing', 'Races' }, slReplay = { 'Street racing', 'Recording' },
  slClock = { 'Clock and weather', 'Time' }, slWeather = { 'Clock and weather', 'Weather' }, slRain = { 'Clock and weather', 'Weather' },
  slNotify = { 'Screens and texts', 'Texts' }, slDashboard = { 'Screens and texts', 'Dashboard' }, slWallpaper = { 'Screens and texts', 'Laptop' }, slAutoPhoto = { 'Screens and texts', 'Camera' },
  slTextScale = { 'Accessibility', 'Reading' }, slColorBlind = { 'Accessibility', 'Colours' }, slCaptions = { 'Accessibility', 'Rally' },
  slPerf = { 'Developer', 'Performance' },
}
-- the Quick setup presets of the Mods menu (performance | balanced | quality | max): what costs frames at night or in a race is lighter at Performance
local PRESETS = {
  slRaceTraffic = { performance = 'light', balanced = 'normal', quality = 'normal', max = 'normal' },
  slReplay = { performance = false, balanced = true, quality = true, max = true },
  slMarkers = { performance = false, balanced = true, quality = true, max = true },
  slLotCars = { performance = 4, balanced = 6, quality = 6, max = 6 },
  slGridCars = { performance = 3, balanced = 5, quality = 6, max = 7 },
  slLotDents = { performance = false, balanced = true, quality = true, max = true },
}
-- the parts of the game that can be switched off (sl/core/features: each is gated by its extension): one bool each, on by default, listed on the Active features page
local haveKey = {}
for _, d in ipairs(M.defs) do haveKey[d.key] = true end
for _, f in ipairs(require('sl/core/features').LIST) do
  if not haveKey[f.opt] then      -- (a part with its own row above, like Cinematic moments, is not listed twice: the registry refuses a field id twice)
  M.defs[#M.defs + 1] = { key = f.opt, feature = true, title = f.title, type = 'bool', default = f.default ~= false, tab = 'Parts of the game', group = 'Parts of the game', desc = f.desc }      -- (a part may ship off: features.LIST default = false)
  end
end
-- Street Legal in free roam (sl/core/mode, sl_mode): the master switch and one per feature, all off by default; a feature needs the master and its own switch
for _, f in ipairs(require('sl/core/mode').FEATURES()) do
  M.defs[#M.defs + 1] = { key = require('sl/core/mode').key(f.id), title = f.title, type = 'bool', default = false, tab = 'Free roam', group = 'Free roam', desc = f.tip }
end
local byKey = {}
for _, d in ipairs(M.defs) do
  local own = d.group                          -- (a def of another module names its own group: it is its sub-heading on the Mods menu page)
  d.group = d.group or GROUP
  byKey[d.key] = d
  local at = PLACE[d.key]
  if at then d.tab, d.sub = d.tab or at[1], d.sub or at[2] end
  if own and not d.sub then d.sub = own end
  d.presets = d.presets or PRESETS[d.key]
end

local global
local unreadable

local function career() return sl_career and sl_career.isActive() and sl_career.getState() or nil end

local function sanitize(d, v)
  if d.type == 'bool' then if type(v) == 'boolean' then return v end return d.default end
  if d.type == 'choice' then for _, o in ipairs(d.options) do if o.id == v then return v end end return d.default end
  v = tonumber(v)
  return v and math.max(d.min, math.min(d.max, v)) or d.default
end

-- 0.5.2: Wet tarmac (a terrain texture swap) is suspected of a GPU loss on BeamNG 0.40, so it is off by default; a saved "on" is reset to off once (a player who turns it back on keeps it)
function M.migrate052(data)
  if data.slWetTarmacReset052 then return false end
  data.slWetTarmacReset052 = true
  if data.slWetTarmac == true then data.slWetTarmac = false log('I', 'sl_options', 'Wet tarmac reset to off (0.5.2); it can be turned on again in the Mods menu') end
  return true
end

-- 0.6.0: Wet roads and walls can crash the graphics driver at High graphics in heavy rain (BeamNG 0.40), so it is off by default; a saved "on" is reset to off once (turned on again, it stays)
function M.migrate060(data)
  if data.slWetWorldReset060 then return false end
  data.slWetWorldReset060 = true
  if data.slWetWorld == true then data.slWetWorld = false log('I', 'sl_options', 'Wet roads and walls reset to off (0.6.0); it can be turned on again in the Mods menu') end
  return true
end

local function loadGlobal()
  if global then return global end
  local data = jsonReadFile(FILE)
  global = type(data) == 'table' and data or {}
  unreadable = data == nil and FS ~= nil and FS.fileExists ~= nil and FS:fileExists(FILE) == true      -- (a file that is there but did not read: never written over)
  -- (the flag is set in memory always, so the next normal save carries it; the file is rewritten here only when it was read as a table: a missing, locked or corrupt file is never overwritten by a migration)
  local m52, m60 = M.migrate052(global), M.migrate060(global)
  if (m52 or m60) and type(data) == 'table' then jsonWriteFile(FILE, global, true) end
  return global
end

-- the value of a setting now (the career's own for the career's settings; their default with no career)
function M.get(key)
  local d = byKey[key]
  if not d then return nil end
  if d.needs == 'weather' then
    local w = slrrValoWeather and slrrValoWeather.getState and slrrValoWeather.getState() or {}
    if key == 'slWeather' then return w.enabled ~= false end
    return w.rainChance or d.default
  end
  local src = d.career and ((career() or {}).options or {}) or loadGlobal()
  local v = src[key]
  if v == nil then return d.default end
  return sanitize(d, v)
end

local function set(key, value)
  local d = byKey[key]
  if not d then return false end
  value = sanitize(d, value)
  if key == 'slHospital' and value == false and M.get('slHardcore') == true then error('Hardcore careers need the hospital', 0) end      -- (hardcore death is a hospital rule)
  if key == 'slBank' and value == false and sl_bank and sl_bank.hasLoan and sl_bank.hasLoan() then error('Pay back the loan first', 0) end      -- (the Mods menu shows this; the loan stays in the save)
  if d.needs == 'weather' then
    if not slrrValoWeather then return false end
    if key == 'slWeather' and slrrValoWeather.setEnabled then slrrValoWeather.setEnabled(value) end
    if key == 'slRain' and slrrValoWeather.setRainChance then slrrValoWeather.setRainChance(value) end
  elseif d.career then
    local s = career()
    if not s then return false end
    s.options = s.options or {}
    s.options[key] = value
    extensions.hook('onStreetLegalChanged')
  else
    loadGlobal()[key] = value
    if unreadable then log('W', 'street_legal', 'options.json did not read: the setting ' .. key .. ' is kept for this session only') else jsonWriteFile(FILE, global, true) end
  end
  extensions.hook('onStreetLegalOption', key, value)
  return true
end
M.set = set

-- The Mods menu page of Street Legal (slrr_settings): every setting above by its tab and group. The career's own settings (police, pay, hardcore, raids) are kept in the
-- career's save: they show their start values and take a change only while a career is played. Developer: the all-the-money button.
function M.onSlrrSettingsReady()
  local S = rawget(_G, 'slrr_settings')
  if not (S and S.fromDefs) then return end
  local defs = {}
  for _, d in ipairs(M.defs) do
    if d.needs ~= 'weather' or (slrrValoWeather and slrrValoWeather.setEnabled) then
      local c = deepcopy(d)
      if d.career then c.desc = tostring(d.desc or '') .. ' ' .. strings.t('options.saved_with_the_career') end
      if d.key == 'slPerf' then c.advanced = true end
      defs[#defs + 1] = c
    end
  end
  local fields, tabs = S.fromDefs(defs, { tabOf = function(d) return d.tab or 'More' end, get = M.get, set = set })
  local developer
  for _, t in ipairs(tabs) do if t.id == 'Developer' then developer = t end end
  if not developer then developer = { id = 'Developer', title = 'Developer' } tabs[#tabs + 1] = developer end
  -- the dashboard's parts (kept in hud.json by sl_hud): once the dashboard itself is on
  local function hudField(key, label, tip, kind, extra)
    local f = { id = 'hud_' .. key, tab = 'Screens and texts', group = 'Dashboard', type = kind, label = label, tooltip = tip, default = extra and extra.default,
      visibleIf = { field = 'slDashboard', equals = true },
      store = { kind = 'custom', get = function() local h = sl_hud and sl_hud.getSettings and sl_hud.getSettings() return h and h[key] end,
        set = function(v) if sl_hud and sl_hud.setOption then sl_hud.setOption(key, v) end end } }
    for k, v in pairs(extra or {}) do f[k] = v end
    fields[#fields + 1] = f
  end
  hudField('tacho', 'Rev counter', 'The rev counter of the Street Legal dashboard.', 'bool', { default = true })
  hudField('speedo', 'Speedometer', 'The speedometer of the Street Legal dashboard.', 'bool', { default = true })
  hudField('map', 'Map', 'The map that turns with the car.', 'bool', { default = true })
  hudField('damage', 'Damage diagram', 'The diagram of the car\'s damage.', 'bool', { default = true })
  hudField('units', 'Units', 'Speed in km/h or mph on the dashboard.', 'enum', { default = 'kmh', options = { { id = 'kmh', label = 'km/h' }, { id = 'mph', label = 'mph' } } })
  hudField('freeroam', 'Also outside the career', 'Shows the dashboard in freeroam as well.', 'bool', { default = false })
  fields[#fields + 1] = { id = 'devMoney', tab = 'Developer', group = 'Testing', type = 'button', label = strings.t('ui.give_all_the_money'), advanced = true,
    confirm = strings.t('options.give_money_confirm'),
    tooltip = strings.t('ui.for_testing_the_money_goes'),
    action = function() local ok, text = sl_career.devMoney() return text or '' end }
  for _, f in ipairs(fields) do if f.tab == 'Accessibility' then f.group = f.group or 'Reading' end end
  S.register({ mod = 'street_legal', title = 'Street Legal', icon = 'wrench', order = 20, tabs = tabs, fields = fields })
end
M.onExtensionLoaded = M.onSlrrSettingsReady

----------------------------------------------------------------------------------------------
-- traffic in street races: thinned while a race runs, put back after (and after 15 minutes whatever happens)

local saved, savedAt
local function restoreTraffic()
  if saved and gameplay_traffic and gameplay_traffic.setActiveAmount then gameplay_traffic.setActiveAmount(saved) end
  saved, savedAt = nil, nil
end
local function thinTraffic()
  local mode = M.get('slRaceTraffic')
  if mode == 'normal' or saved or not (gameplay_traffic and gameplay_traffic.setActiveAmount and gameplay_traffic.getTrafficVars) then return end
  saved = (gameplay_traffic.getTrafficVars() or {}).activeAmount or math.huge
  savedAt = os.clock()
  gameplay_traffic.setActiveAmount(mode == 'none' and 0 or math.min(3, saved))
end
M.onStreetLegalRaceStarted = thinTraffic
M.onSlrrRaceStarted = function() if career() then thinTraffic() end end
M.onStreetLegalRaceResult = restoreTraffic
M.onStreetLegalRaceCancelled = restoreTraffic
M.onSlrrRaceFinished = restoreTraffic
M.onStreetLegalStopped = restoreTraffic
function M.onUpdate() if savedAt and os.clock() - savedAt > 900 then restoreTraffic() end end
function M.onClientEndMission() saved, savedAt = nil, nil end

return M
