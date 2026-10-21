-- Street Legal: phone skins, the part that needs the game's files (the checking is sl/core/phoneskin). A skin is a folder <id>/skin.json (+ pictures) in
--   /street_legal/phone_skins/        the mod's own skins, and those of any other mod zip that puts a folder there
--   /settings/street_legal/phone_skins/   the player's own (the user folder)
-- Pictures named by an icon ({ "file": "map.svg" }) are read here and handed to the UI as data: pictures, so the UI needs no access to the folder.
-- Nothing is read until a skin other than Classic is chosen (the list of names is read once when the Mods menu is built).

local rules = require('sl/core/phoneskin')

local M = {}

M.DIRS = { '/street_legal/phone_skins/', '/settings/street_legal/phone_skins/' }
local MAX_IMAGE, MAX_TOTAL = 65536, 524288
local MIME = { svg = 'image/svg+xml', png = 'image/png', jpg = 'image/jpeg', jpeg = 'image/jpeg' }

local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1, c2, c3, c4 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64
    out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1) .. (b and B64:sub(c3 + 1, c3 + 1) or '=') .. (c and B64:sub(c4 + 1, c4 + 1) or '=')
  end
  return table.concat(out)
end
M.base64 = base64

local function readBinary(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local data = f:read('*all')
  f:close()
  return data
end

-- every skin.json under the folders: { id = folder path }; a folder later in DIRS (the player's own) replaces one of the same id
local function folders()
  local found = {}
  for _, root in ipairs(M.DIRS) do
    local ok, files = pcall(function() return FS:findFiles(root, 'skin.json', 1, true, false) end)
    for _, f in ipairs(ok and files or {}) do
      local id = f:match('/([^/]+)/skin%.json$')
      if id then found[id] = f:gsub('skin%.json$', '') end
    end
  end
  return found
end

local loaded = {}      -- id -> the checked skin, read when it is chosen and kept for the session

local function load(id, dir, withImages)
  local raw = jsonReadFile(dir .. 'skin.json')
  local total = 0
  local skin, why = rules.validate(raw, id, withImages and function(name)
    if type(name) ~= 'string' or name:find('[/\\]') or name:find('%.%.') then return nil end
    local ext = name:match('%.(%w+)$')
    local mime = ext and MIME[ext:lower()]
    if not mime then return nil end
    local data = readBinary(dir .. name)
    if not data or #data > MAX_IMAGE or total + #data > MAX_TOTAL then return nil end
    total = total + #data
    return 'data:' .. mime .. ';base64,' .. base64(data)
  end or nil)
  if not skin then log('W', 'sl_phoneskins', 'phone skin ' .. tostring(id) .. ' ignored: ' .. tostring(why)) return nil end
  skin.id = id                      -- (the folder name is the id)
  if withImages and skin.dropped > 0 then log('W', 'sl_phoneskins', 'phone skin ' .. id .. ': ' .. skin.dropped .. ' icon/colour entries ignored') end
  return skin
end

-- the Mods menu's list: Classic and the skins found (only their names are read, no pictures)
function M.choices()
  local ok, list = pcall(function()
    local names = {}
    for id, dir in pairs(folders()) do
      if id:match(rules.ID_PATTERN) then names[id] = load(id, dir, false) end
    end
    return rules.choices(names)
  end)
  return ok and list or { { id = rules.CLASSIC, label = 'Classic' } }
end

-- what the UI gets for a chosen id: nil for Classic, or for a skin that is gone or not valid
function M.payload(id)
  if not id or id == rules.CLASSIC or not id:match(rules.ID_PATTERN) then return nil end
  if loaded[id] == nil then
    local dir = folders()[id]
    loaded[id] = dir and load(id, dir, true) or false
  end
  return loaded[id] or nil
end

return M
