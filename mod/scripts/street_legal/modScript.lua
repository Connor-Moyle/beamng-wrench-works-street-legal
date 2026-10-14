-- Street Legal Racing: load the career, the phone and the menu tile, and keep them across level loads.
for _, name in ipairs({ 'sl_career', 'sl_phone', 'sl_menuTile' }) do
  extensions.load(name)
  setExtensionUnloadMode(name, 'manual')
end
