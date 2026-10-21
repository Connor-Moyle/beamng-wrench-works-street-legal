-- Street Legal: phone skins, the part that needs the game's files (the checking is sl/core/phoneskin). A skin is a folder <id>/skin.json (+ pictures) in
--   /street_legal/phone_skins/        the mod's own skins, and those of any other mod zip that puts a folder there
--   /settings/street_legal/phone_skins/   the player's own (the user folder)
-- Pictures named by an icon ({ "file": "map.svg" }) are read here and handed to the UI as data: pictures, so the UI needs no access to the folder.
-- Nothing is read until a skin other than Classic is chosen (the list of names is read once when the Mods menu is built).

local rules = require('sl/core/phoneskin')

local M = {}

M.DIRS = { '/street_legal/phone_skins/', '/settings/street_legal/phone_skins/' }
local MAX_IMAGE, MAX_TOTAL = 65536, 524288
local MIME = { svg = 'image/svg+xml', png = 'image/png' }
local MAX_PIXELS = 256          -- a png icon is at most this many pixels wide and high

-- a picture is only what it says it is: a png with the png header and a small size (read from the header, nothing is decoded), an svg that looks like one and has no script
local PNG_HEAD = string.char(137, 80, 78, 71, 13, 10, 26, 10)
local function be32(d, i) local a, b, c, e = d:byte(i, i + 3) return a * 16777216 + b * 65536 + c * 256 + e end
function M.pictureOk(ext, data)
  if ext == 'png' then
    if #data < 24 or data:sub(1, 8) ~= PNG_HEAD or data:sub(13, 16) ~= 'IHDR' then return false end
    local w, h = be32(data, 17), be32(data, 21)
    return w >= 1 and h >= 1 and w <= MAX_PIXELS and h <= MAX_PIXELS
  end
  if ext == 'svg' then
    local low = data:lower()
    return low:sub(1, 1000):find('<svg', 1, true) ~= nil and not low:find('<script', 1, true) and not low:find('foreignobject', 1, true)
  end
  return false
end

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

-- A file's bytes through the game's own reader (the virtual file system: a path inside a mod zip works, io.open would not), after a look at its size so a huge file is never read.
-- nil when it is missing, empty or bigger than max.
-- the game's LuaJIT string buffer is a module ('string.buffer'), not a global (the game's own utils.lua requires it); a global `buffer` only exists in the tests
local okSB, SB = pcall(require, 'string.buffer')
local function newBuffer() if okSB and type(SB) == 'table' then return SB.new() end return rawget(_G, 'buffer').new() end
local function readBytes(path, max)
  local ok, size = pcall(function() return FS:fileSize(path) end)
  if not ok or type(size) ~= 'number' or size <= 0 or size > max then return nil end
  local buf = newBuffer()
  if not io.readFileToBuffer(path, buf) then return nil end
  return buf:tostring()
end
M.MAX_JSON = 65536

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
  local text = readBytes(dir .. 'skin.json', M.MAX_JSON)
  local raw = text and jsonDecode(text, dir .. 'skin.json') or nil
  local total = 0
  local skin, why = rules.validate(raw, id, withImages and function(name)
    if type(name) ~= 'string' or name:find('[/\\]') or name:find('%.%.') then return nil end
    local ext = name:match('%.(%w+)$')
    local mime = ext and MIME[ext:lower()]
    if not mime then return nil end
    local data = readBytes(dir .. name, math.min(MAX_IMAGE, MAX_TOTAL - total))
    if not data or not M.pictureOk(ext:lower(), data) then return nil end
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
