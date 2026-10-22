-- The wet world module (sl/wetworld.lua) against a stubbed game: with the material edits off (the default) the rain wets the terrain layers and reloads no material; with the experiment key on, it does.
return function(check)
  local reloads, setFields, terrainUpdates, opts = 0, 0, 0, { slWetWorld = true, slWetTarmac = true, slWetStrength = 1.0 }
  local savedLog, savedOpts = log, sl_options
  log = function() end
  sl_options = { get = function(k) return opts[k] end }
  local mat = { getName = function() return 'road_a' end, getFilename = function() return 'levels/x/art/road.json' end, getField = function() return '0.5' end,
    setField = function() setFields = setFields + 1 end, reload = function() reloads = reloads + 1 end, flush = function() end }
  local layer = { getField = function(_, k) if k == 'groundmodelName' then return 'ASPHALT' elseif k == 'internalName' then return 'asph' else return '/art/x.png' end end, setField = function() setFields = setFields + 1 end }
  local block = { updateMaterial = function() terrainUpdates = terrainUpdates + 1 end }
  local savedClasses, savedFind, savedSim = getObjectsByClass, scenetree, Sim
  getObjectsByClass = function(c) if c == 'Material' then return { mat } elseif c == 'TerrainMaterial' then return { layer } elseif c == 'TerrainBlock' then return { block } end return {} end
  scenetree = { findObject = function() return mat end }
  Sim = nil
  package.loaded['sl/wetworld'] = nil
  local W = require('sl/wetworld')
  for _ = 1, 400 do W.update(0.1, 1.0) end
  check('wet world: in heavy rain the terrain layers are swapped', terrainUpdates >= 1)
  check('wet world: and no material is reloaded while the material edits are off', reloads == 0)
  package.loaded['sl/wetworld'] = nil
  opts.slWetMaterials = true
  W = require('sl/wetworld')
  for _ = 1, 400 do W.update(0.1, 1.0) end
  check('wet world: with the experiment key on the materials are edited again', reloads >= 1)
  log, sl_options, getObjectsByClass, scenetree, Sim = savedLog, savedOpts, savedClasses, savedFind, savedSim
  package.loaded['sl/wetworld'] = nil
end
