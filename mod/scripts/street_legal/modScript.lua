-- Street Legal Racing: load the career, the phone and the menu tile, and keep them across level loads.
setExtensionUnloadMode('gameplay_drag_core', 'manual')       -- sl_drag loads the game's drag core while the script runs: 0.40 warns unless it is set first
for _, name in ipairs({ 'sl_career', 'sl_fleet', 'sl_lot', 'sl_streets', 'sl_races', 'sl_markers', 'sl_phone', 'sl_menuTile', 'sl_hud', 'sl_carcare', 'sl_station', 'sl_police', 'sl_services', 'sl_jobs', 'sl_wwjobs', 'sl_classifieds', 'sl_activities', 'sl_tutorial', 'sl_achievements', 'sl_bank', 'sl_weekly', 'sl_service', 'sl_series', 'sl_sponsor', 'sl_invite', 'sl_mates', 'sl_barnfinds', 'sl_danger', 'sl_scenes', 'sl_traps', 'sl_perks', 'sl_clubs', 'sl_lockdown', 'sl_cab', 'sl_tow', 'sl_options', 'sl_crews', 'sl_hospital', 'sl_upgrades', 'sl_computer', 'sl_dealers', 'sl_pois', 'sl_drag', 'sl_uipush', 'sl_surfacefx', 'sl_tyrecare', 'sl_weather', 'sl_puddlefx', 'sl_perf', 'sl_replay', 'sl_spectators', 'sl_ambience', 'sl_billboards', 'sl_rally', 'sl_carauctions', 'sl_photos', 'sl_wetworld', 'sl_rivals', 'sl_balance', 'sl_mapsfeed', 'sl_mode', 'sl_show', 'sl_mastery', 'sl_hillduel', 'sl_shops', 'sl_calendar', 'sl_gridrace', 'sl_needs', 'sl_lotpre', 'sl_rallyservice', 'sl_fartraffic' }) do
  setExtensionUnloadMode(name, 'manual')       -- before the load: 0.40 warns otherwise
  extensions.load(name)
end
-- the tester's console cheat-car list: only in a development install (the released zip does not contain the file), and no warning when it is absent.
-- (double quotes: the release check of extension names looks at single-quoted names and this one is meant to be missing from the zip)
if FS and FS:fileExists("/lua/ge/extensions/sl/debugCars.lua") then
  setExtensionUnloadMode("sl_debugCars", "manual")
  extensions.load("sl_debugCars")
end
