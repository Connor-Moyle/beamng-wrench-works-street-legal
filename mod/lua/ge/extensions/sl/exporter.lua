-- Street Legal Racing: the custom cars in the vehicle selector (extension name: sl_exporter)
-- Writes the showroom lineup (sl/core/showroom) as ordinary vehicle configurations - a .pc file
-- and an info_*.json each - into the user folder's vehicles/ folder, where the game keeps saved
-- configurations, so they show in the vehicle selector like any other. No vehicle is spawned: the
-- parts tree comes from the jbeam files directly. It runs once, a little after the game starts,
-- and again only when the lineup changes (VERSION). From the console: sl_exporter.export(true).

local M = {}

local showroom = require('sl/core/showroom')
local builds = require('sl/core/builds')
local rngLib = require('sl/core/rng')
local builder = require('sl/carBuilder')

local VERSION = 1
local MANIFEST = '/settings/street_legal/showroom.json'
local running = false
local waited = 0

local function classify()
  local ok, catalog = pcall(require, 'slrr/garageCatalog')
  return ok and catalog.classify or nil
end

local function readManifest()
  local m = FS:fileExists(MANIFEST) and jsonReadFile(MANIFEST) or nil
  return type(m) == 'table' and m or { files = {} }
end

local function upToDate(m)
  if m.version ~= VERSION or type(m.files) ~= 'table' or #m.files == 0 then return false end
  for _, f in ipairs(m.files) do
    if not FS:fileExists(f) then return false end
  end
  return true
end

-- one car: its stock config's parts, built up by the recipe, written next to the game's own
local function exportOne(entry, jbeamIO, slotSystem, cls)
  local base = jsonReadFile(entry.config)
  if type(base) ~= 'table' or type(base.parts) ~= 'table' then return nil, 'no parts in ' .. tostring(entry.config) end
  local ioCtx = jbeamIO.startLoading({ '/vehicles/' .. entry.model .. '/', '/vehicles/common/' })
  local main = jbeamIO.getMainPartName(ioCtx)
  if not main then return nil, 'no main part for ' .. entry.model end
  local ok, rootOrError, _, _, tree = pcall(slotSystem.findParts, ioCtx, { mainPartName = main, mainPartPath = '/' .. main, parts = base.parts, vars = base.vars })
  if not ok or type(tree) ~= 'table' then return nil, 'could not resolve ' .. entry.config .. ': ' .. tostring(rootOrError) end
  local function valueOf(name)
    local okPart, part = pcall(jbeamIO.getPart, ioCtx, name)
    return okPart and part and part.information and tonumber(part.information.value) or 0
  end
  local function nameOf(name)
    local okPart, part = pcall(jbeamIO.getPart, ioCtx, name)
    return okPart and part and part.information and tostring(part.information.name or name) or name
  end
  local result = builds.apply(tree, { stage = entry.stage, rng = rngLib.new(entry.seed), classify = cls, valueOf = valueOf, nameOf = nameOf })
  local dir = '/vehicles/' .. entry.model .. '/'
  local pc = dir .. entry.file .. '.pc'
  local info = dir .. 'info_' .. entry.file .. '.json'
  jsonWriteFile(pc, { format = 2, model = entry.model, parts = showroom.flatten(tree), vars = base.vars or {},
    paints = builds.paints(entry.seed, entry.stage == 'race'), licenseName = 'STREET' }, true)
  local race = entry.stage == 'race'
  jsonWriteFile(info, {
    Configuration = entry.label,
    Description = race and 'A track car from Street Legal Racing: race parts throughout, the interior and the trim stripped out.'
      or string.format('A street racer from Street Legal Racing, built to Stage %d.', entry.stage),
    ['Config Type'] = 'Custom',
    Value = entry.value,
  }, true)
  return { pc, info }, nil, #result.upgraded
end

-- export the lineup; force = true writes it again even when it is up to date
function M.export(force)
  if running then return 'Already exporting.' end
  local manifest = readManifest()
  if not force and upToDate(manifest) then return 'The Street Legal cars are in the vehicle selector already.' end
  local cls = classify()
  if not cls then
    log('W', 'street_legal', 'Wrench Works is not installed: the custom cars cannot be built without its parts catalog')
    return 'Needs Wrench Works.'
  end
  running = true
  core_jobsystem.create(function(job)
    local okLibs, jbeamIO = pcall(require, 'jbeam/io')
    local okSlots, slotSystem = pcall(require, 'jbeam/slotSystem')
    if not okLibs or not okSlots then
      running = false
      log('E', 'street_legal', 'jbeam libraries missing; no cars exported')
      return
    end
    -- the cars written last time go first (the lineup may have changed)
    for _, f in ipairs(manifest.files or {}) do
      if FS:fileExists(f) then FS:removeFile(f) end
    end
    local written, failed = {}, 0
    for i, entry in ipairs(showroom.lineup(builder.configs(), showroom.SEED)) do
      local ok, files, why = pcall(exportOne, entry, jbeamIO, slotSystem, cls)
      if ok and files then
        for _, f in ipairs(files) do written[#written + 1] = f end
      else
        failed = failed + 1
        log('W', 'street_legal', 'custom car ' .. tostring(entry.file) .. ' not written: ' .. tostring(ok and why or files))
      end
      if i % 2 == 0 then job.sleep(0) end         -- spread over frames: no hitch on the menu
    end
    if not FS:directoryExists('/settings/street_legal/') then FS:directoryCreate('/settings/street_legal/', true) end
    jsonWriteFile(MANIFEST, { version = VERSION, files = written }, true)
    if core_vehicles and core_vehicles.clearCache then core_vehicles.clearCache() end
    running = false
    log('I', 'street_legal', string.format('%d custom cars in the vehicle selector (%d could not be built)', #written / 2, failed))
  end)
  return 'Exporting the Street Legal cars.'
end

-- a little after start-up, when the vehicle list is there
function M.onUpdate(dtReal)
  if waited < 0 then return end
  waited = waited + dtReal
  if waited > 8 and core_vehicles then
    waited = -1
    M.export(false)
  end
end

return M
