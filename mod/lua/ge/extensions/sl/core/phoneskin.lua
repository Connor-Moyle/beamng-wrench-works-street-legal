-- Street Legal: phone skins (pure, tested by tools/luatest.js). A skin is a folder with a skin.json (and images next to it): colours and shapes of the phone, a colour for each app,
-- the app icons, a little extra CSS. The classic look is the phone as it is, with no skin. sl/phoneskins finds the folders and reads the files; this file only checks what a skin.json
-- says and turns it into what the UI needs: { id, css, appColors, icons = { app = '<svg ...>' | '<img ...>' } }. Nothing from a skin.json reaches the UI unchecked: a colour is #rgb or
-- #rrggbb, a number is clamped, an icon path may only hold path characters, the extra CSS may not load anything but data: pictures.

local M = {}

M.ID_PATTERN = '^[a-z0-9][a-z0-9_%-]*$'
M.MAX_ID, M.MAX_NAME, M.MAX_PATH, M.MAX_CSS = 32, 40, 4000, 8000
M.CLASSIC = 'classic'

local function colour(v)
  if type(v) ~= 'string' then return nil end
  if v:match('^#%x%x%x$') or v:match('^#%x%x%x%x%x%x$') then return v:lower() end
end

local function number(v, lo, hi)
  v = tonumber(v)
  if not v or v ~= v then return nil end
  return math.max(lo, math.min(hi, v))
end

local function text(v, max)
  if type(v) ~= 'string' then return nil end
  v = v:gsub('[%c<>&"\']', ''):sub(1, max)
  if v == '' then return nil end
  return v
end

-- the extra CSS: nothing that loads or runs anything but a data: picture
function M.safeCss(css)
  if type(css) ~= 'string' or #css > M.MAX_CSS then return nil, 'css missing or too long' end
  local low = css:lower()
  if low:find('@import', 1, true) or low:find('javascript:', 1, true) or low:find('expression(', 1, true) or low:find('</', 1, true)
    or low:find('<', 1, true) or low:find('behavior:', 1, true) or low:find('-moz-binding', 1, true) then return nil, 'css not allowed' end
  for u in low:gmatch('url%s*%(%s*([^%)]*)') do
    local arg = u:gsub('^["\']', '')
    if not arg:find('^data:image/') then return nil, 'css url() other than data:image' end
  end
  return css
end

-- an app icon from its skin.json entry: { path, viewBox, stroke } drawn by the UI as an svg (filled, or an outline when stroke is set), or { file } resolved to a data uri by the caller
function M.icon(spec)
  if type(spec) ~= 'table' then return nil end
  if spec.path ~= nil then
    local d = spec.path
    if type(d) ~= 'string' or #d > M.MAX_PATH or d:find('[^%dMmLlHhVvCcSsQqTtAaZz%s%.,%-eE]') then return nil end
    local vb = spec.viewBox or '0 0 24 24'
    if type(vb) ~= 'string' or not vb:match('^[%d%.%-]+ [%d%.%-]+ [%d%.%-]+ [%d%.%-]+$') then return nil end
    local stroke = number(spec.stroke, 0.5, 6)
    if stroke then
      return '<svg viewBox="' .. vb .. '"><path d="' .. d .. '" style="fill:none;stroke:currentColor;stroke-width:' .. stroke .. ';stroke-linecap:round;stroke-linejoin:round"/></svg>'
    end
    return '<svg viewBox="' .. vb .. '"><path d="' .. d .. '"/></svg>'
  end
  return nil
end

local VAR_COLOURS = { 'frame', 'rim', 'screen', 'text', 'accent' }

-- The CSS of the variables. Every rule is under .slp-root so a skin cannot touch anything else on the page.
function M.cssOf(vars)
  local out = {}
  local function add(s) out[#out + 1] = s end
  if vars.frame or vars.rim or vars.frameRadius then
    local rule = ''
    if vars.frame then rule = rule .. 'background:' .. vars.frame .. ';' end
    if vars.frameRadius then rule = rule .. 'border-radius:' .. vars.frameRadius .. 'px;' end
    if vars.rim then rule = rule .. 'box-shadow:0 0 0 2px ' .. vars.rim .. ',0 30px 80px rgba(0,0,0,.65);' end
    add('.slp-root .slp-device:not(.slp-land){' .. rule .. '}')
    if vars.frame then add('.slp-root .slp-device.slp-land{background:' .. vars.frame .. '}') end
  end
  if vars.screen or vars.screenRadius then
    add('.slp-root .slp-screen{' .. (vars.screen and ('background:' .. vars.screen .. ';') or '') .. (vars.screenRadius and ('border-radius:' .. vars.screenRadius .. 'px;') or '') .. '}')
  end
  if vars.text then add('.slp-root .slp-app span,.slp-root .slp-clock,.slp-root .slp-date{color:' .. vars.text .. '}') end
  if vars.iconRadius then add('.slp-root .slp-ico{border-radius:' .. vars.iconRadius .. 'px}') end
  if vars.gloss then add('.slp-root .slp-ico{background-image:linear-gradient(160deg,rgba(255,255,255,.30),rgba(255,255,255,0) 55%)}') end
  if vars.accent then add('.slp-root .slp-ib svg,.slp-root .slp-act i svg,.slp-root .slp-pbadge svg{fill:' .. vars.accent .. '}') end
  if vars.notch == 'pill' then
    add('.slp-root .slp-screen::before{content:"";position:absolute;top:9px;left:50%;width:88px;height:24px;margin-left:-44px;border-radius:12px;background:#000;z-index:30;pointer-events:none}')
  end
  return table.concat(out, '\n')
end

-- Checks a parsed skin.json found in the folder `dir`. Returns the skin for the UI, or nil and why. files: optional function(name) -> data uri or nil, for { file = ... } icons.
function M.validate(raw, dir, files)
  if type(raw) ~= 'table' then return nil, 'not a table' end
  local id = type(raw.id) == 'string' and raw.id or dir
  if type(id) ~= 'string' or #id > M.MAX_ID or not id:match(M.ID_PATTERN) then return nil, 'bad id' end
  if id == M.CLASSIC then return nil, 'classic is the phone as it is' end
  local name = text(raw.name, M.MAX_NAME) or id
  local vars = {}
  local v = type(raw.vars) == 'table' and raw.vars or {}
  for _, k in ipairs(VAR_COLOURS) do vars[k] = colour(v[k]) end
  vars.frameRadius = number(v.frameRadius, 0, 70)
  vars.screenRadius = number(v.screenRadius, 0, 60)
  vars.iconRadius = number(v.iconRadius, 0, 40)
  vars.gloss = v.gloss == true
  vars.notch = v.notch == 'pill' and 'pill' or nil
  local css = M.cssOf(vars)
  if raw.css ~= nil then
    local extra, why = M.safeCss(raw.css)
    if not extra then return nil, why end
    css = css .. '\n' .. extra
  end
  local appColors, icons, dropped = {}, {}, 0
  for app, c in pairs(type(raw.appColors) == 'table' and raw.appColors or {}) do
    if type(app) == 'string' and app:match('^[%w_]+$') and colour(c) then appColors[app] = colour(c) else dropped = dropped + 1 end
  end
  for app, spec in pairs(type(raw.icons) == 'table' and raw.icons or {}) do
    local html
    if type(app) == 'string' and app:match('^[%w_]+$') then
      html = M.icon(spec)
      if not html and type(spec) == 'table' and type(spec.file) == 'string' and files then
        local uri = files(spec.file)
        if uri then html = '<img class="slp-skinimg" src="' .. uri .. '" alt="">' end
      end
    end
    if html then icons[app] = html else dropped = dropped + 1 end
  end
  return { id = id, name = name, author = text(raw.author, M.MAX_NAME), css = css, appColors = appColors, icons = icons, dropped = dropped }
end

-- the Mods menu's choice list: Classic first, then the skins by name
function M.choices(skins)
  local out = { { id = M.CLASSIC, label = 'Classic' } }
  local list = {}
  for _, s in pairs(skins) do list[#list + 1] = s end
  table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
  for _, s in ipairs(list) do out[#out + 1] = { id = s.id, label = s.name } end
  return out
end

return M
