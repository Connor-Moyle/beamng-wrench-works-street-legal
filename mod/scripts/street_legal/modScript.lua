-- Street Legal Racing: load the career, the phone and the menu tile, and keep them across level loads.
for _, name in ipairs({ 'sl_career', 'sl_fleet', 'sl_lot', 'sl_streets', 'sl_races', 'sl_markers', 'sl_debugCars', 'sl_phone', 'sl_menuTile', 'sl_hud', 'sl_carcare', 'sl_station', 'sl_police', 'sl_services', 'sl_jobs', 'sl_wwjobs', 'sl_classifieds', 'sl_activities', 'sl_tutorial', 'sl_achievements', 'sl_bank', 'sl_clubs', 'sl_lockdown', 'sl_cab', 'sl_tow', 'sl_options', 'sl_crews', 'sl_hospital', 'sl_upgrades', 'sl_computer', 'sl_dealers' }) do
  extensions.load(name)
  setExtensionUnloadMode(name, 'manual')
end
