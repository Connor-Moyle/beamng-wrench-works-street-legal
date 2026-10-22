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
  { key = 'slNotify', scope = 'none', title = strings.t('options.text_pop_ups'), type = 'choice', default = 'all', options = LEVELS,
    desc = strings.t('options.which_new_texts_pop_up') },
  { key = 'slClock', title = strings.t('options.clock_speed'), type = 'choice', default = 'slow',
    options = { { id = 'slow', label = strings.t('options.slow_2_5_min_an') }, { id = 'normal', label = strings.t('options.normal_1_25_min_an') }, { id = 'fast', label = strings.t('options.fast_0_6_min_an') } },
    desc = strings.t('options.how_fast_the_in_game') },
  { key = 'slDashboard', feature = true, title = strings.t('options.slrr_dashboard'), type = 'bool', default = false,
    desc = strings.t('options.the_slrr_gauges_map_and') },
  { key = 'slReplay', feature = true, title = strings.t('options.record_street_races'), type = 'bool', default = true,
    desc = strings.t('options.records_a_street_race_with') },
  { key = 'slTextScale', scope = 'none', title = strings.t('settings.textSize'), type = 'choice', default = 'normal',
    options = { { id = 'normal', label = strings.t('settings.textNormal') }, { id = 'large', label = strings.t('settings.textLarge') }, { id = 'huge', label = strings.t('settings.textHuge') } },
    desc = strings.t('settings.textSizeDesc') },
  { key = 'slPhoneCrackThreshold', title = strings.t('options.crack_threshold'), type = 'range', min = 200, max = 8000, step = 100, default = 1500, tab = 'Screens and texts', group = 'Cracked phone',
    desc = strings.t('options.crack_threshold_desc') },
  { key = 'slPhoneCrackChance', title = strings.t('options.crack_chance'), type = 'range', min = 0, max = 1, step = 0.05, default = 0.8, tab = 'Screens and texts', group = 'Cracked phone',
    desc = strings.t('options.crack_chance_desc') },
  { key = 'slPhoneCrackMax', title = strings.t('options.crack_max'), type = 'range', min = 1, max = 3, step = 1, default = 3, tab = 'Screens and texts', group = 'Cracked phone',
    desc = strings.t('options.crack_max_desc') },
  { key = 'slPhoneCrackStrength', title = strings.t('options.crack_strength'), type = 'range', min = 0.3, max = 1, step = 0.05, default = 0.85, tab = 'Screens and texts', group = 'Cracked phone',
    desc = strings.t('options.crack_strength_desc') },
  { key = 'slCamFirstPerson', title = strings.t('options.cam_first_person'), type = 'bool', default = true, tab = 'Screens and texts', group = 'Phone camera', desc = strings.t('options.cam_first_person_desc') },
  { key = 'slCamSway', title = strings.t('options.cam_sway'), type = 'range', min = 0, max = 1, step = 0.05, default = 0.5, tab = 'Screens and texts', group = 'Phone camera', desc = strings.t('options.cam_sway_desc') },
  { key = 'slCamGrid', title = strings.t('options.cam_grid'), type = 'bool', default = true, tab = 'Screens and texts', group = 'Phone camera', desc = strings.t('options.cam_grid_desc') },
  { key = 'slCamBezel', title = strings.t('options.cam_bezel'), type = 'bool', default = true, tab = 'Screens and texts', group = 'Phone camera', desc = strings.t('options.cam_bezel_desc') },
  { key = 'slCamZoomMax', title = strings.t('options.cam_zoom_max'), type = 'range', min = 1, max = 8, step = 1, default = 4, tab = 'Screens and texts', group = 'Phone camera', desc = strings.t('options.cam_zoom_max_desc') },
  { key = 'slColorBlind', scope = 'none', title = strings.t('settings.colorBlind'), type = 'bool', default = false,
    desc = strings.t('settings.colorBlindDesc') },
  { key = 'slReduceMotion', scope = 'none', title = strings.t('settings.reduceMotion'), type = 'bool', default = false,
    desc = strings.t('settings.reduceMotionDesc') },
  { key = 'slCaptions', scope = 'none', title = strings.t('settings.captions'), type = 'bool', default = true,
    desc = strings.t('settings.captionsDesc') },
  { key = 'slPerf', scope = 'graphics', title = strings.t('options.performance_overlay'), type = 'bool', default = false,
    desc = strings.t('options.a_small_box_top_left') },
  { key = 'slWallpaper', scope = 'none', title = strings.t('options.laptop_wallpaper'), type = 'choice', default = 'windows',
    options = { { id = 'windows', label = strings.t('options.my_windows_wallpaper') }, { id = 'builtin', label = 'Built-in' } },
    desc = strings.t('options.the_laptop_s_desktop_your') },
  { key = 'slScenes', feature = true, title = strings.t('options.cinematic_moments'), type = 'bool', default = true,
    desc = strings.t('options.cinematic_moments_text') },
  { key = 'slAutoPhoto', feature = true, title = strings.t('options.photo_of_a_new_car'), type = 'bool', default = true,
    desc = strings.t('options.a_new_car_is_photographed') },
  { key = 'slPuddleCount', scope = 'graphics', title = strings.t('options.puddles_in_the_rain'), type = 'range', min = 10, max = 300, step = 10, unit = '', default = 120,
    tab = 'Clock and weather', group = 'Rain on the ground', presets = { performance = 40, balanced = 90, quality = 150, max = 250 },
    desc = strings.t('options.how_many_puddles_stand_on') },
  { key = 'slSplashSize', scope = 'graphics', title = strings.t('options.splash_size'), type = 'range', min = 0.1, max = 1.5, step = 0.05, unit = 'x', default = 0.4,
    tab = 'Clock and weather', group = 'Rain on the ground', presets = { performance = 0.25, balanced = 0.4, quality = 0.5, max = 0.6 }, desc = strings.t('options.how_high_the_water_a') },
  { key = 'slWetWorld', scope = 'graphics', feature = true, title = strings.t('options.wet_world'), type = 'bool', default = false, tab = 'Clock and weather', group = 'Rain on the ground',
    presets = { performance = false, balanced = false, quality = false, max = false }, desc = strings.t('options.in_the_rain_roads_walls_and') },
  { key = 'slMapStyle', scope = 'none', title = strings.t('options.map_style'), type = 'choice', default = 'street', tab = 'Maps', group = 'Maps',
    options = { { id = 'street', label = strings.t('options.map_style_street') }, { id = 'cruise', label = strings.t('options.map_style_cruise') }, { id = 'atlas', label = strings.t('options.map_style_atlas') } }, desc = strings.t('options.map_style_text') },
  { key = 'slMapHeadingUp', scope = 'none', title = strings.t('options.map_heading_up'), type = 'bool', default = false, tab = 'Maps', group = 'Maps',
    desc = strings.t('options.map_heading_up_text') },
  { key = 'slMapSpeed', feature = true, title = strings.t('options.map_speed'), type = 'bool', default = true, tab = 'Maps', group = 'Maps',
    desc = strings.t('options.map_speed_text') },
  { key = 'slMapKSlide', feature = true, title = strings.t('options.map_k_slide'), type = 'bool', default = true, tab = 'Maps', group = 'Maps',
    desc = strings.t('options.map_k_slide_text') },
  { key = 'slMapZoom', scope = 'none', title = strings.t('options.map_zoom'), type = 'choice', default = 'normal', tab = 'Maps', group = 'Maps',
    options = { { id = 'close', label = strings.t('options.map_zoom_close') }, { id = 'normal', label = strings.t('options.map_zoom_normal') }, { id = 'far', label = strings.t('options.map_zoom_far') } }, desc = strings.t('options.map_zoom_text') },
  { key = 'slPhoneSkin', scope = 'none', title = strings.t('options.phone_skin'), type = 'choice', default = 'classic', tab = 'Screens and texts', group = 'Phone look',
    options = require('sl/phoneskins').choices(), desc = strings.t('options.phone_skin_text') },
  { key = 'slWetTarmac', scope = 'graphics', feature = true, title = strings.t('options.wet_tarmac'), type = 'bool', default = false, tab = 'Clock and weather', group = 'Rain on the ground',
    presets = { performance = false, balanced = false, quality = false, max = false }, desc = strings.t('options.wet_tarmac_text') },
  { key = 'slWetStrength', scope = 'graphics', title = strings.t('options.wet_world_strength'), type = 'range', min = 0, max = 1, step = 0.05, scale = 100, unit = '%', default = 0.8,
    tab = 'Clock and weather', group = 'Rain on the ground', presets = { quality = 0.9, max = 1 }, desc = strings.t('options.how_dark_and_shiny_the') },
  { key = 'slRainBox', scope = 'graphics', title = strings.t('options.rain_around_you'), type = 'range', min = 40, max = 150, step = 10, unit = 'm', default = 70,
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
  { key = 'slPoliceTickets', feature = true, tab = 'Police chase', group = 'Tickets and court', title = 'Tickets and court', type = 'bool', default = true,
    desc = 'Stop within five seconds of the siren at pursuit level 1 and the arrest is a ticket, not a bust: a small fine on the phone with a court day, to pay or contest (a lawyer, better odds with a saved race recording). Three overdue tickets suspend the licence: the police watch by day too until they are paid. Off: every arrest is a bust.' },
  { key = 'slPoliceWanted', feature = true, tab = 'Police chase', group = 'Wanted posters', title = 'Wanted posters', type = 'bool', default = true,
    desc = 'From heat 4 the car gets a wanted record with a bounty that outlives the day: patrols recognise it at any heat until it is repainted or an informant (a crew perk) is paid. Off: the day clears everything, as before.' },
  { key = 'slPoliceImpoundLot', feature = true, tab = 'Police chase', group = 'Impound lot', title = 'The impound lot', type = 'bool', default = true,
    desc = 'An impounded car stands at the police station: pay at the window by day and drive it away, or cut the fence at night and run from a chase at heat 4 with a bounty on the car. Off: pay on the phone and the car comes back to the garage, as before.' },
  { key = 'slPoliceTactics', feature = true, tab = 'Police chase', group = 'Tactics', title = 'Box and PIT', type = 'bool', default = true,
    desc = 'At pursuit level 2 a second patrol boxes you in: it keeps your pace on your rear quarter while the first chases. At level 3 the nearest patrol gets a PIT window above 60 km/h on a straight: six seconds of hard driving, once a minute at most. Off: the game police as they are.' },
  { key = 'slPolicePatrolJob', feature = true, tab = 'Police chase', group = 'Patrol shifts', title = 'Patrol shifts', type = 'bool', default = true,
    desc = 'A day job from 300 reputation: borrow a patrol car at the police station and chase the game own suspects for a ten-minute shift or three arrests; every arrest pays by how fast it came; the car comes back with a charge for its damage. No heat for you on a shift. Off: no such job on the board.' },
  { key = 'slTicketBase', tab = 'Police chase', group = 'Tickets and court', title = 'Ticket, the base fine', type = 'range', min = 0, max = 1000, step = 10, unit = '$', default = 120, advanced = true, scope = 'gameplay', gameplay = { easy = 60, hardcore = 240 },
    desc = 'A ticket at a pull-over: this much plus the offence part per offence.' },
  { key = 'slTicketOffence', tab = 'Police chase', group = 'Tickets and court', title = 'Ticket, per offence', type = 'range', min = 0, max = 500, step = 10, unit = '$', default = 60, advanced = true, scope = 'gameplay', gameplay = { easy = 30, hardcore = 120 },
    desc = 'Added to a ticket for each offence the police counted.' },
  { key = 'slTicketDueDays', tab = 'Police chase', group = 'Tickets and court', title = 'Days to pay a ticket', type = 'range', min = 0, max = 14, step = 1, unit = 'days', default = 1, advanced = true, scope = 'gameplay', gameplay = { easy = 3, hardcore = 1 },
    desc = 'The court day: a ticket unpaid after this many days is overdue; three overdue tickets suspend the licence.' },
  { key = 'slContestWith', tab = 'Police chase', group = 'Tickets and court', title = 'Contest odds with evidence', type = 'range', min = 0, max = 1, step = 0.05, unit = '', default = 0.6, advanced = true, scope = 'gameplay', gameplay = { easy = 0.8, hardcore = 0.45 },
    desc = 'The chance to win a contested ticket with a saved race recording.' },
  { key = 'slContestWithout', tab = 'Police chase', group = 'Tickets and court', title = 'Contest odds without', type = 'range', min = 0, max = 1, step = 0.05, unit = '', default = 0.25, advanced = true, scope = 'gameplay', gameplay = { easy = 0.4, hardcore = 0.15 },
    desc = 'The chance to win a contested ticket with nothing to show.' },
  { key = 'slLostRaise', tab = 'Police chase', group = 'Tickets and court', title = 'A lost contest costs', type = 'range', min = 1, max = 3, step = 0.1, unit = 'x', default = 1.5, advanced = true, scope = 'gameplay', gameplay = { easy = 1.2, hardcore = 2 },
    desc = 'A contested ticket lost is this many times the fine, due a day later.' },
  { key = 'slLawyerFee', tab = 'Police chase', group = 'Tickets and court', title = 'The lawyer', type = 'range', min = 0, max = 1000, step = 10, unit = '$', default = 150, advanced = true, scope = 'gameplay', gameplay = { easy = 80, hardcore = 300 },
    desc = 'What the lawyer takes to contest a ticket (paid back when the court call fails).' },
  { key = 'slSuspendAt', tab = 'Police chase', group = 'Tickets and court', title = 'Overdue tickets for a suspension', type = 'range', min = 1, max = 10, step = 1, unit = '', default = 3, advanced = true, scope = 'gameplay', gameplay = { easy = 5, hardcore = 2 },
    desc = 'This many unpaid overdue tickets and the licence is suspended: the police watch by day as at night.' },
  { key = 'slBountyBase', tab = 'Police chase', group = 'Wanted posters', title = 'Bounty at level 3', type = 'range', min = 0, max = 5000, step = 50, unit = '$', default = 500, advanced = true, scope = 'gameplay', gameplay = { easy = 300, hardcore = 1000 },
    desc = 'The bounty on a wanted car at pursuit level 3 and under; the step adds per level above.' },
  { key = 'slBountyStep', tab = 'Police chase', group = 'Wanted posters', title = 'Bounty, per level above 3', type = 'range', min = 0, max = 2000, step = 50, unit = '$', default = 250, advanced = true, scope = 'gameplay', gameplay = { easy = 100, hardcore = 500 },
    desc = 'Added to the bounty for each pursuit level above 3.' },
  { key = 'slInformantShare', tab = 'Police chase', group = 'Wanted posters', title = 'The informant takes', type = 'range', min = 0, max = 1, step = 0.05, unit = 'x', default = 0.5, advanced = true, scope = 'gameplay', gameplay = { easy = 0.3, hardcore = 0.75 },
    desc = 'A crew perk: the informant clears the wanted record for this share of the bounty.' },
  { key = 'slImpoundBase', tab = 'Police chase', group = 'Impound lot', title = 'Impound fee at level 3', type = 'range', min = 0, max = 5000, step = 50, unit = '$', default = 600, advanced = true, scope = 'gameplay', gameplay = { easy = 300, hardcore = 1200 },
    desc = 'The fee to get a car back from the impound after a bust at level 3; the step adds per level above.' },
  { key = 'slImpoundStep', tab = 'Police chase', group = 'Impound lot', title = 'Impound fee, per level above 3', type = 'range', min = 0, max = 2000, step = 50, unit = '$', default = 200, advanced = true, scope = 'gameplay', gameplay = { easy = 100, hardcore = 400 },
    desc = 'Added to the impound fee for each pursuit level above 3.' },
  { key = 'slPitEvery', tab = 'Police chase', group = 'Tactics', title = 'Seconds between PIT tries', type = 'range', min = 10, max = 180, step = 5, unit = 's', default = 45, advanced = true, scope = 'gameplay', gameplay = { easy = 90, hardcore = 25 },
    desc = 'At pursuit level 4 and up a unit tries a PIT this often (the box at level 3).' },
  { key = 'slPitAggr', tab = 'Police chase', group = 'Tactics', title = 'PIT aggression', type = 'range', min = 0.5, max = 2.5, step = 0.05, unit = '', default = 1.5, advanced = true, scope = 'gameplay', gameplay = { easy = 1.1, hardcore = 2 },
    desc = 'The AI aggression of the unit making a PIT (the game own scale; 0.85 is a normal chase).' },
  { key = 'slBoxAggr', tab = 'Police chase', group = 'Tactics', title = 'Box aggression', type = 'range', min = 0.2, max = 1.5, step = 0.05, unit = '', default = 0.6, advanced = true, scope = 'gameplay', gameplay = { easy = 0.45, hardcore = 0.85 },
    desc = 'The AI aggression of the unit boxing you in ahead (it keeps pace, it does not run away).' },
  { key = 'slPitMaxFails', tab = 'Police chase', group = 'Tactics', title = 'Failed tactics before they stop', type = 'range', min = 1, max = 20, step = 1, unit = '', default = 5, advanced = true, scope = 'gameplay', gameplay = { easy = 3, hardcore = 10 },
    desc = 'After this many failed box or PIT tries in a pursuit the units stop trying.' },
  { key = 'slPatrolShiftS', tab = 'Police chase', group = 'Patrol shift', title = 'Shift length', type = 'range', min = 120, max = 1800, step = 30, unit = 's', default = 600, advanced = true, scope = 'gameplay', gameplay = { easy = 480, hardcore = 900 },
    desc = 'A patrol shift lasts this long (back at the station early after a minute if you want).' },
  { key = 'slPatrolArrests', tab = 'Police chase', group = 'Patrol shift', title = 'Arrests asked', type = 'range', min = 1, max = 10, step = 1, unit = '', default = 3, advanced = true, scope = 'gameplay', gameplay = { easy = 2, hardcore = 4 },
    desc = 'How many arrests a shift asks for its full pay.' },
  { key = 'slPatrolBase', tab = 'Police chase', group = 'Patrol shift', title = 'Shift base pay', type = 'range', min = 0, max = 1000, step = 10, unit = '$', default = 180, advanced = true, scope = 'gameplay', gameplay = { easy = 240, hardcore = 120 },
    desc = 'What a shift pays before the arrests and the damage charge.' },
  { key = 'slPatrolArrestPay', tab = 'Police chase', group = 'Patrol shift', title = 'Pay per arrest', type = 'range', min = 0, max = 1000, step = 10, unit = '$', default = 220, advanced = true, scope = 'gameplay', gameplay = { easy = 300, hardcore = 160 },
    desc = 'A quick arrest pays this; two dollars less a second after twenty, never under $80.' },
  { key = 'slDuelBetX', tab = 'Hill duel', group = 'The stake', title = 'Stake against the rival', type = 'range', min = 0.25, max = 3, step = 0.25, unit = 'x', default = 1, advanced = true, scope = 'gameplay', gameplay = { easy = 0.5, hardcore = 2 },
    desc = 'The duel stake is the middle of the rival bet range times this, at least the floor.' },
  { key = 'slDuelBetMin', tab = 'Hill duel', group = 'The stake', title = 'Stake floor', type = 'range', min = 0, max = 1000, step = 50, unit = '$', default = 50, advanced = true, scope = 'gameplay',
    desc = 'The smallest duel stake.' },
  { key = 'slDuelRepWin', tab = 'Hill duel', group = 'Reputation', title = 'Reputation for a win', type = 'range', min = 0, max = 100, step = 5, unit = '', default = 30, advanced = true, scope = 'gameplay', gameplay = { easy = 40, hardcore = 20 },
    desc = 'Reputation a won duel gives.' },
  { key = 'slDuelRepLoss', tab = 'Hill duel', group = 'Reputation', title = 'Reputation for a loss', type = 'range', min = -50, max = 0, step = 5, unit = '', default = -5, advanced = true, scope = 'gameplay', gameplay = { easy = 0, hardcore = -15 },
    desc = 'Reputation a lost duel takes (a negative number).' },
  { key = 'slDuelLeadGap', tab = 'Hill duel', group = 'Scoring', title = 'Lead gap', type = 'range', min = 5, max = 100, step = 1, unit = 'm', default = 25, advanced = true, scope = 'gameplay', gameplay = { easy = 20, hardcore = 35 },
    desc = 'The leader scores from this far ahead.' },
  { key = 'slDuelCloseGap', tab = 'Hill duel', group = 'Scoring', title = 'Close gap', type = 'range', min = 2, max = 50, step = 1, unit = 'm', default = 12, advanced = true, scope = 'gameplay', gameplay = { easy = 18, hardcore = 8 },
    desc = 'The follower scores up to this far behind.' },
  { key = 'slDuelOffGrace', tab = 'Hill duel', group = 'Scoring', title = 'Off-road grace', type = 'range', min = 0, max = 10, step = 0.5, unit = 's', default = 2, advanced = true, scope = 'gameplay', gameplay = { easy = 4, hardcore = 1 },
    desc = 'Seconds off the road before it costs score.' },
  { key = 'slGrabJobs', tab = 'Grab bag', group = 'A good week', title = 'Jobs for a box', type = 'range', min = 1, max = 10, step = 1, unit = '', default = 3, advanced = true, scope = 'gameplay', gameplay = { easy = 2, hardcore = 5 },
    desc = 'A week with this many jobs done leaves a grab bag at the garage (any one of the three counts).' },
  { key = 'slGrabWins', tab = 'Grab bag', group = 'A good week', title = 'Race wins for a box', type = 'range', min = 1, max = 10, step = 1, unit = '', default = 2, advanced = true, scope = 'gameplay', gameplay = { easy = 1, hardcore = 3 },
    desc = 'A week with this many race wins leaves a box.' },
  { key = 'slGrabEarned', tab = 'Grab bag', group = 'A good week', title = 'Money earned for a box', type = 'range', min = 0, max = 20000, step = 250, unit = '$', default = 2000, advanced = true, scope = 'gameplay', gameplay = { easy = 1000, hardcore = 4000 },
    desc = 'A week with this much earned leaves a box.' },
  { key = 'slGrabPartsMax', tab = 'Grab bag', group = 'The box', title = 'Most parts in a box', type = 'range', min = 1, max = 10, step = 1, unit = '', default = 4, advanced = true, scope = 'gameplay', gameplay = { easy = 6, hardcore = 3 },
    desc = 'A box holds two to this many used parts.' },
  { key = 'slGrabMaxValue', tab = 'Grab bag', group = 'The box', title = 'Dearest part in a box', type = 'range', min = 100, max = 10000, step = 100, unit = '$', default = 1500, advanced = true, scope = 'gameplay', gameplay = { easy = 3000, hardcore = 800 },
    desc = 'A part dearer than this (new) stays out of the box.' },
  { key = 'slBarnPriceShare', tab = 'Barn finds', group = 'Barn finds', title = 'A barn find costs', type = 'range', min = 0.05, max = 1, step = 0.01, unit = 'x', default = 0.22, advanced = true, scope = 'gameplay', gameplay = { easy = 0.15, hardcore = 0.35 },
    desc = 'The share of the car value a barn find is sold for.' },
  { key = 'slBarnMinRep', tab = 'Barn finds', group = 'Barn finds', title = 'Reputation for the first rumour', type = 'range', min = 0, max = 2000, step = 50, unit = '', default = 100, advanced = true, scope = 'gameplay', gameplay = { easy = 50, hardcore = 300 },
    desc = 'The rumours start at this reputation.' },
  { key = 'slBarnGapMin', tab = 'Barn finds', group = 'Barn finds', title = 'Days between rumours, least', type = 'range', min = 1, max = 30, step = 1, unit = 'days', default = 3, advanced = true, scope = 'gameplay', gameplay = { easy = 2, hardcore = 5 },
    desc = 'The shortest wait between two rumours.' },
  { key = 'slBarnGapMax', tab = 'Barn finds', group = 'Barn finds', title = 'Days between rumours, most', type = 'range', min = 1, max = 60, step = 1, unit = 'days', default = 6, advanced = true, scope = 'gameplay', gameplay = { easy = 4, hardcore = 10 },
    desc = 'The longest wait between two rumours.' },
  { key = 'slTrapPay', tab = 'Speed traps', group = 'Pay', title = 'A speed trap pays', type = 'range', min = 0, max = 2000, step = 10, unit = '$', default = 250, advanced = true, scope = 'gameplay', gameplay = { easy = 350, hardcore = 150 },
    desc = 'Beating a speed trap target pays this.' },
  { key = 'slZonePay', tab = 'Speed traps', group = 'Pay', title = 'A danger zone pays', type = 'range', min = 0, max = 3000, step = 10, unit = '$', default = 400, advanced = true, scope = 'gameplay', gameplay = { easy = 550, hardcore = 250 },
    desc = 'Beating a danger zone target pays this.' },
  { key = 'slTrapRep', tab = 'Speed traps', group = 'Pay', title = 'Reputation for a target', type = 'range', min = 0, max = 50, step = 1, unit = '', default = 5, advanced = true, scope = 'gameplay',
    desc = 'Reputation a beaten trap or zone target gives.' },
  { key = 'slTrapCount', tab = 'Speed traps', group = 'How many', title = 'Speed traps on the map', type = 'range', min = 0, max = 20, step = 1, unit = '', default = 6, advanced = true, scope = 'gameplay',
    desc = 'How many speed traps the map gets (a career restart places them).' },
  { key = 'slZoneCount', tab = 'Speed traps', group = 'How many', title = 'Danger zones on the map', type = 'range', min = 0, max = 10, step = 1, unit = '', default = 2, advanced = true, scope = 'gameplay',
    desc = 'How many danger zones the map gets (a career restart places them).' },
  { key = 'slZoneMaxTime', tab = 'Speed traps', group = 'How many', title = 'Danger zone time limit', type = 'range', min = 30, max = 600, step = 10, unit = 's', default = 120, advanced = true, scope = 'gameplay', gameplay = { easy = 180, hardcore = 90 },
    desc = 'Seconds allowed from the first gate of a danger zone to the second.' },
  { key = 'slTheftWitnesses', feature = true, tab = 'Police chase', group = 'Car theft', title = 'Witnesses raise the heat', type = 'bool', default = true,
    desc = 'A noisy break-in with people about draws a witness: stay near the car half a minute and the heat rises a level. Off: only the alarm counts.' },
  { key = 'slTheftDeliveries', feature = true, tab = 'Police chase', group = 'Car theft', title = 'Deliveries on the jobs board', type = 'bool', default = true,
    desc = 'The pursuit deliveries: a contact asks for a car brought to the docks with the police on you. Off: no such jobs.' },
  { key = 'slTheftLockTraffic', feature = true, tab = 'Police chase', group = 'Car theft', title = 'Traffic cars are locked', type = 'bool', default = true,
    desc = 'With Car theft on, a stopped traffic car cannot be entered with the game key: the break-in is the way in. Off: the game own entering stays as it is.' },
  { key = 'slTheftPlates', feature = true, tab = 'Police chase', group = 'Car theft', title = 'Plates are bought', type = 'bool', default = true,
    desc = 'Every career car keeps its plate text: a plate changed outside the career comes back within seconds. A new plate is bought ($300; $700 for a hot car, with a respray it is legal). Off: plates are the game own.' },
  { key = 'slTheftSecondsOld', tab = 'Car theft', group = 'Break-in', title = 'Time for an old car', type = 'range', min = 10, max = 90, step = 5, unit = 's', default = 25, advanced = true, scope = 'gameplay', gameplay = { easy = 40, hardcore = 18 },
    desc = 'The whole break-in on a car from before 1990 (the lock and the wires). Prestige cars get ten seconds more.' },
  { key = 'slTheftSecondsMid', tab = 'Car theft', group = 'Break-in', title = 'Time for a 1990s car', type = 'range', min = 15, max = 120, step = 5, unit = 's', default = 40, advanced = true, scope = 'gameplay', gameplay = { easy = 60, hardcore = 30 },
    desc = 'The whole break-in on a 1990s car (the lock, the bypass box, the wires).' },
  { key = 'slTheftSecondsModern', tab = 'Car theft', group = 'Break-in', title = 'Time for a modern car', type = 'range', min = 20, max = 180, step = 5, unit = 's', default = 60, advanced = true, scope = 'gameplay', gameplay = { easy = 90, hardcore = 45 },
    desc = 'The whole break-in on a keyless car (the fob capture and the match).' },
  { key = 'slTheftChanceOld', tab = 'Car theft', group = 'Break-in', title = 'Odds on an old car', type = 'range', min = 0.2, max = 1, step = 0.05, unit = '', default = 0.85, advanced = true, scope = 'gameplay', gameplay = { easy = 0.95, hardcore = 0.7 },
    desc = 'The chance one stage goes right when the screens are off (the autoplay) or the car is a prestige one minus 0.15; the screens use it for their tolerance.' },
  { key = 'slTheftChanceMid', tab = 'Car theft', group = 'Break-in', title = 'Odds on a 1990s car', type = 'range', min = 0.2, max = 1, step = 0.05, unit = '', default = 0.7, advanced = true, scope = 'gameplay', gameplay = { easy = 0.85, hardcore = 0.55 },
    desc = 'As above, for a 1990s car.' },
  { key = 'slTheftChanceModern', tab = 'Car theft', group = 'Break-in', title = 'Odds on a modern car', type = 'range', min = 0.2, max = 1, step = 0.05, unit = '', default = 0.55, advanced = true, scope = 'gameplay', gameplay = { easy = 0.7, hardcore = 0.4 },
    desc = 'As above, for a keyless car.' },
  { key = 'slTheftNoisePin', tab = 'Car theft', group = 'Noise', title = 'Noise of a dropped pin', type = 'range', min = 0.02, max = 0.4, step = 0.02, unit = '', default = 0.12, advanced = true, scope = 'gameplay',
    desc = 'How much of the noise meter a dropped lock pin (or a slim jim scraping) adds. At one the alarm goes off.' },
  { key = 'slTheftNoiseWire', tab = 'Car theft', group = 'Noise', title = 'Noise of a wrong wire', type = 'range', min = 0.05, max = 0.5, step = 0.05, unit = '', default = 0.2, advanced = true, scope = 'gameplay',
    desc = 'How much a wrong wire cut adds to the noise meter.' },
  { key = 'slTheftWitnessAt', tab = 'Car theft', group = 'Noise', title = 'Witness threshold', type = 'range', min = 0.1, max = 1, step = 0.05, unit = '', default = 0.5, advanced = true, scope = 'gameplay', gameplay = { easy = 0.7, hardcore = 0.35 },
    desc = 'The noise at which somebody about takes notice (half of it by day). Then thirty seconds near the car and the call is made.' },
  { key = 'slTheftWitnessS', tab = 'Car theft', group = 'Noise', title = 'Seconds before a witness calls', type = 'range', min = 5, max = 120, step = 5, unit = 's', default = 30, advanced = true, scope = 'gameplay', gameplay = { easy = 45, hardcore = 15 },
    desc = 'How long you can stay near the car after being noticed before the call is made (a heat level).' },
  { key = 'slTheftAlarmAt', tab = 'Car theft', group = 'Noise', title = 'Alarm threshold', type = 'range', min = 0.3, max = 1, step = 0.05, unit = '', default = 1, advanced = true, scope = 'gameplay', gameplay = { easy = 1, hardcore = 0.8 },
    desc = 'The noise at which the alarm goes off: the horn and the hazards, a heat level, and a patrol within 300 m comes.' },
  { key = 'slTheftTrackerOld', tab = 'Car theft', group = 'Tracker', title = 'Tracker chance, old cars', type = 'range', min = 0, max = 1, step = 0.05, unit = '', default = 0.05, advanced = true, scope = 'gameplay', gameplay = { easy = 0.02, hardcore = 0.15 },
    desc = 'The chance a car from before 1990 carries a stolen-vehicle tracker: the police are sent to it as soon as you drive off, until it is out.' },
  { key = 'slTheftTrackerMid', tab = 'Car theft', group = 'Tracker', title = 'Tracker chance, 1990s cars', type = 'range', min = 0, max = 1, step = 0.05, unit = '', default = 0.25, advanced = true, scope = 'gameplay', gameplay = { easy = 0.1, hardcore = 0.45 },
    desc = 'The chance a 1990s car carries a tracker.' },
  { key = 'slTheftTrackerModern', tab = 'Car theft', group = 'Tracker', title = 'Tracker chance, modern cars', type = 'range', min = 0, max = 1, step = 0.05, unit = '', default = 0.6, advanced = true, scope = 'gameplay', gameplay = { easy = 0.35, hardcore = 0.8 },
    desc = 'The chance a keyless car carries a tracker.' },
  { key = 'slTheftTrackerPrestige', tab = 'Car theft', group = 'Tracker', title = 'Tracker chance, prestige extra', type = 'range', min = 0, max = 0.5, step = 0.05, unit = '', default = 0.2, advanced = true, scope = 'gameplay',
    desc = 'Added to the chance for a prestige car. A loud break-in, daylight, a witness and a patrol near add more; the chance is never zero.' },
  { key = 'slTheftTrackS', tab = 'Car theft', group = 'Tracker', title = 'Seconds until the police come', type = 'range', min = 2, max = 60, step = 1, unit = 's', default = 8, advanced = true, scope = 'gameplay', gameplay = { easy = 15, hardcore = 4 },
    desc = 'A tracked car: how long after driving off the first patrol is sent to it.' },
  { key = 'slTheftTrackResend', tab = 'Car theft', group = 'Tracker', title = 'Seconds between the calls', type = 'range', min = 10, max = 180, step = 5, unit = 's', default = 30, advanced = true, scope = 'gameplay', gameplay = { easy = 60, hardcore = 15 },
    desc = 'A tracked car: how often the police are sent to its live position again (hiding does not help while it is on).' },
  { key = 'slTheftPullS', tab = 'Car theft', group = 'Tracker', title = 'Seconds to find the tracker', type = 'range', min = 10, max = 180, step = 5, unit = 's', default = 45, advanced = true, scope = 'gameplay', gameplay = { easy = 25, hardcore = 75 },
    desc = 'The search inside the standing car; the tracker finder tool cuts it to 40 %.' },
  { key = 'slTheftJamS', tab = 'Car theft', group = 'Tracker', title = 'Seconds the jammer holds', type = 'range', min = 30, max = 600, step = 30, unit = 's', default = 120, advanced = true, scope = 'gameplay',
    desc = 'The jammer tool keeps the tracker silent this long per use.' },
  { key = 'slTheftSellHot', tab = 'Car theft', group = 'The fence', title = 'Fence pays, hot car', type = 'range', min = 0.1, max = 0.8, step = 0.02, unit = 'x', default = 0.2, advanced = true, scope = 'gameplay', gameplay = { easy = 0.3, hardcore = 0.14 },
    desc = 'The share of the value the fence pays for a car that is still hot.' },
  { key = 'slTheftSellPlated', tab = 'Car theft', group = 'The fence', title = 'Fence pays, legal car', type = 'range', min = 0.2, max = 1, step = 0.05, unit = 'x', default = 0.5, advanced = true, scope = 'gameplay',
    desc = 'The share of the value the fence pays once the car is resprayed and on new plates.' },
  { key = 'slTheftStrip', tab = 'Car theft', group = 'The fence', title = 'Chop shop pays', type = 'range', min = 0.1, max = 0.8, step = 0.05, unit = 'x', default = 0.4, advanced = true, scope = 'gameplay',
    desc = 'The share of the value the chop shop pays to strip the car (plus a used part of it on your shelf).' },
  { key = 'slTheftTitleShare', tab = 'Car theft', group = 'The fence', title = 'A title costs', type = 'range', min = 0, max = 0.5, step = 0.01, unit = 'x', default = 0.15, advanced = true, scope = 'gameplay',
    desc = 'The share of the value a title costs (at least $400): the car joins your fleet with a history line.' },
  { key = 'slTheftPlateLegal', tab = 'Car theft', group = 'Plates', title = 'A new plate, normal car', type = 'range', min = 0, max = 2000, step = 50, unit = '$', default = 300, advanced = true, scope = 'gameplay',
    desc = 'What a new plate costs for one of your cars. Plates are bought: a plate changed any other way comes back.' },
  { key = 'slTheftPlateStolen', tab = 'Car theft', group = 'Plates', title = 'A new plate, stolen car', type = 'range', min = 0, max = 3000, step = 50, unit = '$', default = 700, advanced = true, scope = 'gameplay',
    desc = 'What the fence or the black market asks for a plate on a hot car. With a respray the car is legal.' },
  { key = 'slTheftTrackerStrip', tab = 'Car theft', group = 'The fence', title = 'Tracker out at the fence', type = 'range', min = 0, max = 2000, step = 50, unit = '$', default = 350, advanced = true, scope = 'gameplay',
    desc = 'What the fence asks to take the tracker out of a hot car.' },
  { key = 'slTheftMarketShare', tab = 'Car theft', group = 'Black market', title = 'Black market asks', type = 'range', min = 0.1, max = 1, step = 0.05, unit = 'x', default = 0.45, advanced = true, scope = 'gameplay',
    desc = 'The share of the value a stolen car costs at the black market (hot and maybe tracked until resprayed and plated).' },
  { key = 'slTheftToolPriceX', tab = 'Car theft', group = 'Tools', title = 'Tool prices', type = 'range', min = 0.25, max = 3, step = 0.25, unit = 'x', default = 1, advanced = true, scope = 'gameplay', gameplay = { easy = 0.5, hardcore = 1.5 },
    desc = 'All the theft tools cost this many times their price (slim jim $40, bypass box $600, relay kit $2,500, cloning tool $6,000, tracker finder $450, jammer $900).' },
  { key = 'slTheftToolUsesX', tab = 'Car theft', group = 'Tools', title = 'Tool uses', type = 'range', min = 0.25, max = 3, step = 0.25, unit = 'x', default = 1, advanced = true, scope = 'gameplay', gameplay = { easy = 2, hardcore = 0.75 },
    desc = 'A tool with uses (bypass box 10, relay kit 6, finder 3, jammer 4) has this many times as many.' },
  { key = 'slTheftDeliveryPayX', tab = 'Car theft', group = 'Deliveries', title = 'Delivery pay', type = 'range', min = 0.25, max = 3, step = 0.25, unit = 'x', default = 1, advanced = true, scope = 'gameplay',
    desc = 'The pursuit deliveries pay this many times their share of the car value (at least $400).' },
  { key = 'slTheftDeliveryHeat', tab = 'Car theft', group = 'Deliveries', title = 'Heat on a delivery', type = 'range', min = 0, max = 1, step = 0.05, unit = '', default = 0.75, advanced = true, scope = 'gameplay', gameplay = { easy = 0.5, hardcore = 1 },
    desc = 'The heat a delivery sets the moment you drive off with the car (the police are on you at once).' },
  { key = 'slTheftAutoplay', advanced = true, tab = 'Developer', group = 'Car theft', title = 'Theft screens: autoplay', type = 'bool', default = false,
    desc = 'For the tester: each break-in stage resolves by a roll after its time instead of the mini-game screen.' },
  { key = 'slRivalBeats', feature = true, tab = 'Rivals', group = 'Story beats', title = 'Rival story beats', type = 'bool', default = true,
    desc = 'The hunt for a car you won and the beaten crew three nights. Off: no such texts or offers.' },
  { key = 'slHuntWaitMin', tab = 'Rivals', group = 'Story beats', title = 'Days before the hunt text, least', type = 'range', min = 1, max = 14, step = 1, unit = 'days', default = 2, advanced = true, scope = 'gameplay', gameplay = { easy = 3, hardcore = 1 },
    desc = 'The shortest wait after a pink-slip win before the rival asks for the car back.' },
  { key = 'slHuntWaitMax', tab = 'Rivals', group = 'Story beats', title = 'Days before the hunt text, most', type = 'range', min = 1, max = 30, step = 1, unit = 'days', default = 5, advanced = true, scope = 'gameplay', gameplay = { easy = 7, hardcore = 3 },
    desc = 'The longest wait before the rival asks for the car back.' },
  { key = 'slHuntSweetener', tab = 'Rivals', group = 'Story beats', title = 'The sweetener', type = 'range', min = 0, max = 2, step = 0.05, unit = 'x', default = 0.25, advanced = true, scope = 'gameplay', gameplay = { easy = 0.35, hardcore = 0.15 },
    desc = 'What the rival puts on top of the car for your win on the second hunt text, as a share of the car value; doubled on the third.' },
  { key = 'slHuntAgainDays', tab = 'Rivals', group = 'Story beats', title = 'Days before the next hunt text', type = 'range', min = 1, max = 14, step = 1, unit = 'days', default = 3, advanced = true, scope = 'gameplay', gameplay = { easy = 5, hardcore = 2 },
    desc = 'After a hunt offer lapses or you walk away, the rival waits this long before the next text (with the sweetener).' },
  { key = 'slHuntMeterGone', tab = 'Rivals', group = 'Story beats', title = 'Meter drop when they give up', type = 'range', min = -60, max = 0, step = 5, unit = '', default = -20, advanced = true, scope = 'gameplay',
    desc = 'What the rivalry meter loses when the rival gives up the hunt after the third text (a negative number).' },
  { key = 'slHuntMeterSold', tab = 'Rivals', group = 'Story beats', title = 'Meter drop when you sell the car', type = 'range', min = -60, max = 0, step = 5, unit = '', default = -10, advanced = true, scope = 'gameplay',
    desc = 'What the rivalry meter loses when you sell the hunted car before the race (a negative number).' },
  { key = 'slHuntRep', tab = 'Rivals', group = 'Story beats', title = 'Reputation for a won hunt', type = 'range', min = 0, max = 100, step = 5, unit = '', default = 15, advanced = true, scope = 'gameplay',
    desc = 'Reputation for beating the rival in the hunt race.' },
  { key = 'slTruceDays', tab = 'Rivals', group = 'Story beats', title = 'The truce after the three nights', type = 'range', min = 0, max = 60, step = 1, unit = 'days', default = 14, advanced = true, scope = 'gameplay', gameplay = { easy = 21, hardcore = 7 },
    desc = 'A crew beaten over its three nights sends no call-outs and plans no raids for this many days.' },
  { key = 'slSeriesRep', tab = 'Rivals', group = 'Story beats', title = 'Reputation for the three nights', type = 'range', min = 0, max = 200, step = 5, unit = '', default = 40, advanced = true, scope = 'gameplay',
    desc = 'Reputation for taking two of the three nights.' },
  { key = 'slSeriesBetX', tab = 'Rivals', group = 'Story beats', title = 'The three nights bet', type = 'range', min = 0.5, max = 3, step = 0.25, unit = 'x', default = 1.5, advanced = true, scope = 'gameplay', gameplay = { easy = 1, hardcore = 2 },
    desc = 'Each night races for this many times the racer usual bet.' },
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
  { key = 'slWetTrace', scope = 'graphics', advanced = true, tab = 'Developer', group = 'Rain on the ground', title = strings.t('options.wet_trace'), type = 'bool', default = false,
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
  { key = 'slInviteMax', scope = 'gameplay', tab = 'Economy', group = 'Brand invitationals', title = 'Invitations in a career', type = 'range', min = 1, max = 6, step = 1, unit = '', default = 3,
    desc = 'How many invitations the brands send you in a whole career.' },
  { key = 'slInviteGap', scope = 'gameplay', tab = 'Economy', group = 'Brand invitationals', title = 'Days between invitations', type = 'range', min = 3, max = 30, step = 1, unit = 'days', default = 14,
    desc = 'The least number of days between two invitations.' },
  { key = 'slInviteStanding', scope = 'gameplay', tab = 'Economy', group = 'Brand invitationals', title = 'Standing a brand wants', type = 'range', min = 100, max = 600, step = 50, unit = '', default = 250,
    desc = 'The standing with a maker that brings an invitation (a sponsor of four weeks invites at any standing).' },
  { key = 'slInvitePurse', scope = 'gameplay', tab = 'Economy', group = 'Brand invitationals', title = 'Purse and standing won', type = 'range', min = 0, max = 300, step = 25, unit = '%', default = 100,
    desc = 'How much an invitational pays in money and standing (100 is the normal purse).' },
  { key = 'slMatePartsCut', scope = 'gameplay', tab = 'Economy', group = 'Crew mates', title = 'Mechanic: cut off parts', type = 'range', min = 0, max = 20, step = 1, unit = '%', default = 5,
    desc = 'What a mechanic mate takes off parts in the shops that sell them.' },
  { key = 'slMateLabourCut', scope = 'gameplay', tab = 'Economy', group = 'Crew mates', title = 'Mechanic: cut off the service', type = 'range', min = 0, max = 30, step = 1, unit = '%', default = 10,
    desc = 'What a mechanic mate takes off the price of a service.' },
  { key = 'slMateTips', scope = 'gameplay', tab = 'Economy', group = 'Crew mates', title = 'Tipster: texts a week', type = 'range', min = 0, max = 7, step = 1, unit = '', default = 7,
    desc = 'How many game days in a week the tipster texts you a tip (7 is every day, 0 is never).' },
  { key = 'slMateWarnGap', scope = 'gameplay', tab = 'Economy', group = 'Crew mates', title = 'Scout: seconds between police calls', type = 'range', min = 20, max = 180, step = 10, unit = 's', default = 60,
    desc = 'The least time between two police warnings from the scout (20 seconds is the shortest).' },
  { key = 'slSeasonDays', scope = 'gameplay', tab = 'Clock and weather', group = 'Seasons', title = 'Days in a season', type = 'range', min = 14, max = 56, step = 7, unit = 'days', default = 28,
    desc = 'How many career days a season lasts (a year is four seasons). A change takes effect at once: the current season and the weather odds move with it.' },
  { key = 'slSeasonPurse', scope = 'gameplay', tab = 'Clock and weather', group = 'Seasons', title = 'Season effect on purses', type = 'range', min = 0, max = 200, step = 25, unit = '%', default = 100,
    desc = 'How strong the seasonal change of the purses is (0 none, 100 the normal few per cent, 200 double).' },
  { key = 'slSeasonTemp', scope = 'gameplay', tab = 'Clock and weather', group = 'Seasons', title = 'Air temperature offset', type = 'range', min = -10, max = 10, step = 1, unit = 'C', default = 0,
    desc = 'Added to the seasonal air temperature (colder makes snow likelier with Car Surface FX).' },
  { key = 'slWeeklyRent', scope = 'gameplay', tab = 'Economy', group = 'Weekly costs', title = 'Garage rent', type = 'range', min = 0, max = 300, step = 25, unit = '%', default = 100,
    desc = 'The weekly rent of the garage you hold, as a share of the normal rent (100 is normal, 0 is free).' },
  { key = 'slWeeklyStorage', scope = 'gameplay', tab = 'Economy', group = 'Weekly costs', title = 'Storage per extra car', type = 'range', min = 0, max = 200, step = 10, unit = '$', default = 40,
    desc = 'What each car beyond the two free ones costs a week.' },
  { key = 'slServicePrice', scope = 'gameplay', tab = 'Economy', group = 'Servicing', title = 'Service prices', type = 'range', min = 0, max = 300, step = 25, unit = '%', default = 100,
    desc = 'The price of a basic service and of an overhaul (100 is normal).' },
  { key = 'slServiceKm', scope = 'gameplay', tab = 'Economy', group = 'Servicing', title = 'Kilometres between services', type = 'range', min = 50, max = 500, step = 25, unit = 'km', default = 150,
    desc = 'How far a car goes before a service is due (the Wear rate setting scales this too). A change applies to the next interval, not to services already scheduled.' },
  { key = 'slContractBonus', scope = 'gameplay', tab = 'Economy', group = 'Contracts', title = 'Contract bonus', type = 'range', min = 0, max = 200, step = 25, unit = '%', default = 100,
    desc = 'How much extra a kept contract pays over the normal pay (100 is the normal bonus, 0 means the terms add nothing).' },
  { key = 'slContractChance', scope = 'gameplay', tab = 'Economy', group = 'Contracts', title = 'Contracts on the board', type = 'range', min = 0, max = 100, step = 10, unit = '%', default = 50,
    desc = 'The chance that a part run or a courier parcel comes with terms (from 100 reputation).' },
  { key = 'slFirstBonus', scope = 'gameplay', tab = 'Economy', group = 'Jobs', title = 'First-jobs bonus', type = 'range', min = 0, max = 500, step = 50, unit = '$', default = 150,
    desc = 'The extra paid for the first two jobs of each kind.' },
  { key = 'slPerkStrength', scope = 'gameplay', tab = 'Economy', group = 'Tier perks', title = 'Perk strength', type = 'range', min = 0, max = 200, step = 25, unit = '%', default = 100,
    desc = 'How big the advantages of your rank are (100 is normal, 0 switches their effect off, 200 doubles it).' },
  { key = 'slTravelFee', scope = 'gameplay', tab = 'Economy', group = 'Career travel', title = 'Trip fees', type = 'range', min = 0, max = 300, step = 25, unit = '%', default = 100,
    desc = 'The series fee and the fee for each car taken on a trip (100 is normal).' },
  { key = 'slCalFee', scope = 'gameplay', tab = 'Economy', group = 'Calendar', title = 'Calendar race fees', type = 'range', min = 0, max = 300, step = 25, unit = '%', default = 100,
    desc = 'The entry fee of the weekend races (100 is normal).' },
  { key = 'slCalPurse', scope = 'gameplay', tab = 'Economy', group = 'Calendar', title = 'Calendar race purses', type = 'range', min = 0, max = 300, step = 25, unit = '%', default = 100,
    desc = 'The purse of the weekend races (100 is normal).' },
  { key = 'slCalLaps', scope = 'gameplay', tab = 'Economy', group = 'Calendar', title = 'Laps in a weekend race', type = 'range', min = 1, max = 8, step = 1, unit = '', default = 3,
    desc = 'How many laps the weekend races on the dockyards circuits run.' },
  { key = 'slDressingPrice', scope = 'gameplay', tab = 'Economy', group = 'Garage upgrades', title = 'Garage dressing price', type = 'range', min = 0, max = 5000, step = 100, unit = '$', default = 1200,
    desc = 'What the decorations of the garage cost.' },
  { key = 'slFreightPay', scope = 'gameplay', tab = 'Economy', group = 'Freight runs', title = 'Freight run pay', type = 'range', min = 50, max = 250, step = 10, unit = '%', default = 100,
    desc = 'What a freight run pays compared with the normal rate (100 is the normal pay).' },
  { key = 'slFreightMin', scope = 'gameplay', tab = 'Economy', group = 'Freight runs', title = 'Shortest freight run', type = 'range', min = 300, max = 3000, step = 100, unit = 'm', default = 400,
    desc = 'The two depots of a freight run are at least this far apart.' },
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
  { key = 'slSiphonRate', scope = 'gameplay', tab = 'Inventory', group = 'Fuel siphoning', title = 'Siphon rate', type = 'range', min = 0.05, max = 1, step = 0.05, default = 0.25, unit = 'L/s',
    desc = 'How fast fuel moves from a tank into a jerry can (a 10 litre can takes 40 seconds at the default).' },
  { key = 'slSiphonNoise', scope = 'gameplay', tab = 'Inventory', group = 'Fuel siphoning', title = 'Siphon noise', type = 'range', min = 0, max = 1, step = 0.1, default = 0.5, unit = '',
    desc = 'How likely passing cars are to notice you siphoning (they count as witnesses). 0 means nobody sees you but chance.' },
  { key = 'slSiphonRisk', scope = 'gameplay', tab = 'Inventory', group = 'Fuel siphoning', title = 'Risk of being noticed', type = 'range', min = 0, max = 3, step = 0.25, default = 1, unit = 'x',
    desc = 'How often siphoning fuel from somebody else\'s car is noticed (0 never, 1 normal, 3 three times as often). Worse by day and with witnesses.' },
  { key = 'slSiphonOwn', scope = 'gameplay', tab = 'Inventory', group = 'Fuel siphoning', title = 'Siphon your own cars', type = 'bool', default = true,
    desc = 'You may take fuel from your own cars (no risk).' },
  { key = 'slPlateLegal', tab = 'Shops', group = 'Plates', title = 'New plate price', type = 'range', min = 0, max = 3000, step = 50, default = 300, unit = '$',
    desc = 'What a new registration plate costs for a normal car (accessories shop).' },
  { key = 'slPlateStolen', tab = 'Shops', group = 'Plates', title = 'Stolen car plate price', type = 'range', min = 0, max = 5000, step = 50, default = 700, unit = '$',
    desc = 'What the fence charges for plates for a stolen car.' },
  { key = 'slInventoryScale', tab = 'Inventory', group = 'Inventory', title = 'Boot size', type = 'range', min = 0.5, max = 2, step = 0.25, default = 1, unit = 'x',
    desc = 'How much your car carries: 1 is normal (a pickup carries more than a small coupe), 2 is twice as much, 0.5 half.' },
  { key = 'slFitTimeScale', tab = 'Inventory', group = 'Inventory', title = 'Time to fit parts', type = 'range', min = 0, max = 3, step = 0.25, default = 1, unit = 'x',
    desc = 'How long fitting a part takes on the clock (a bolt-on a few minutes, an exhaust half an hour, an engine hours): 1 is normal, 0 means no time passes.' },
  { key = 'slLabourScale', tab = 'Inventory', group = 'Inventory', title = 'Fitting labour at shops', type = 'range', min = 0, max = 3, step = 0.25, default = 1, unit = 'x',
    desc = 'What a shop charges to fit the parts you brought (labour only): 1 is normal, 0 is free.' },
  { key = 'slNeedsMicrosleep', tab = 'Needs', group = 'Effects', title = 'Micro-sleeps when exhausted', type = 'bool', default = false,
    desc = 'A driver who is exhausted nods off for half a second to a second now and then at speed: the pedals and steering are let go for that moment. Never in a race or on a job, and never in the first seconds after you get into a car. Off by default: this one can cost you a crash.' },
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
