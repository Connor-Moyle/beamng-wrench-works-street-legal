-- Wrench Works: Street Legal: the numbers a player may tune (not an extension: required by sl_rivals, sl_carauctions and the Mods menu schema in sl_storymenu)
-- They live in /settings/street_legal/tuning.json, written by the Mods menu (ESC > Mods, slrr_settings: store kind 'json'); read here every few seconds,
-- the defaults are the constants the modules were written with. `get('rivals.escalateChance', 0.35)`.

local M = {}

M.FILE = '/settings/street_legal/tuning.json'
local cache, at = nil, -1e9

local function clock() return os.clock() end

function M.refresh() cache = nil at = -1e9 end

local function all()
  if not cache or clock() - at > 10 then
    at = clock()
    local ok, t = pcall(function() return jsonReadFile and jsonReadFile(M.FILE) end)
    cache = ok and type(t) == 'table' and t or {}
  end
  return cache
end

function M.get(path, default)
  local v = all()
  for key in tostring(path):gmatch('[^.]+') do
    if type(v) ~= 'table' then return default end
    v = v[key]
  end
  if v == nil then return default end
  if type(default) == 'number' then return tonumber(v) or default end
  if type(default) == 'boolean' then return v == true end
  return v
end

return M
