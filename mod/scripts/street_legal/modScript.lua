-- Street Legal Racing: load the career, the phone and the menu tile, and keep them across level loads.
for _, name in ipairs({ 'sl_career', 'sl_fleet', 'sl_lot', 'sl_streets', 'sl_markers', 'sl_debugCars', 'sl_phone', 'sl_menuTile', 'sl_hud' }) do
  extensions.load(name)
  setExtensionUnloadMode(name, 'manual')
end
