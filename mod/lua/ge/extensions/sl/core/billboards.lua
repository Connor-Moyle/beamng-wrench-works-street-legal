-- Street Legal: sponsor billboards (#47). Pure, tested by tools/luatest.js. Which name is on the city's billboards: the player's sponsor, else the club he races
-- in (Club 1-3, by garage), else nothing (the stock ads). The atlas for a name is mod/art/street_legal/billboards/<slug>.jpg (tools/make_billboards.py).

local M = {}

local strings = require('sl/core/strings')

M.DIR = '/art/street_legal/billboards/'
M.MATERIAL = 'billboards'
M.ORIGINAL = '/levels/west_coast_usa/art/shapes/objects/t_billboards_b.color.png'
-- the names there are atlases for, and their files
M.SLUGS = {
  ['Valo Tyre & Wheel'] = 'valo-tyre-wheel', ['Redline Speed Shop'] = 'redline-speed-shop', ['Nightrun Energy'] = 'nightrun-energy',
  ['the Southside Kings'] = 'southside-kings', ['Riverbed Runners'] = 'riverbed-runners', ['the North End crew'] = 'north-end-crew',
  ['Ring Road Ghosts'] = 'ring-road-ghosts', ['Club 1'] = 'club-1', ['Club 2'] = 'club-2', ['Club 3'] = 'club-3',
}

-- the name for the billboards, or nil for the stock ads. sponsor: the sponsor's name or nil; clubLevel: 1..3 or nil
function M.choose(sponsor, clubLevel)
  if type(sponsor) == 'string' and M.SLUGS[sponsor] then return sponsor end
  local club = clubLevel and (strings.t('billboards.club_1', (tostring(clubLevel))))
  if club and M.SLUGS[club] then return club end
  return nil
end

function M.file(name) return name and M.SLUGS[name] and (M.DIR .. M.SLUGS[name] .. '.jpg') or nil end

-- Overlay mode (release.py --billboards overlay, not the default): the mod then ships no atlas, only our five ads of each name (tiles/<slug>_<n>.png, 512x256), and the
-- atlas is made in the game: the game's own atlas file with the five tiles drawn into it, saved to /temp and put on the material.
M.TILES = { { 3, 3 }, { 0, 3 }, { 1, 3 }, { 2, 3 }, { 2, 0 } }      -- (column, row) of the replaced ads: the same as REPLACED in tools/make_billboards.py
M.TEMP = '/temp/street_legal/'
function M.tileFile(name, n) return name and M.SLUGS[name] and (M.DIR .. 'tiles/' .. M.SLUGS[name] .. '_' .. n .. '.png') or nil end

-- what to put on the material for a name: the shipped atlas; else the tiles to draw into the game's atlas; else nil (the stock ads stay)
function M.plan(name, exists)
  if not (name and M.SLUGS[name]) then return nil end
  local atlas = M.file(name)
  if exists(atlas) then return { kind = 'atlas', file = atlas } end
  local tiles = {}
  for n = 1, #M.TILES do
    tiles[n] = M.tileFile(name, n)
    if not exists(tiles[n]) then return nil end
  end
  return { kind = 'tiles', tiles = tiles, out = M.TEMP .. 'billboards_' .. M.SLUGS[name] .. '.png' }
end

-- Draws the tiles of a plan into the game's atlas, a slice of opts.budget seconds (by opts.clock, os.clock in the game) a frame, the clock looked at every opts.every pixels.
-- newBitmap() makes a GBitmap, newColour() a ColorI; opts.prepare(file) runs before the save (the game makes the /temp folder there). Returns a function to call once a frame:
-- it returns done, ok, why. nil, why when the atlas cannot be read.
function M.composer(newBitmap, newColour, baseFile, plan, opts)
  local budget, clock, every = opts.budget or 0.003, opts.clock or os.clock, opts.every or 512
  local atlas = newBitmap()
  if atlas:loadFile(baseFile) == false then return nil, 'no atlas ' .. baseFile end
  local co = coroutine.create(function()
    local col, n, from = newColour(), 0, clock()
    for i, file in ipairs(plan.tiles) do
      local tile = newBitmap()
      if tile:loadFile(file) == false then error('no tile ' .. file, 0) end
      local tw, th = tile:getWidth(), tile:getHeight()
      if atlas:getWidth() ~= 4 * tw or atlas:getHeight() ~= 4 * th then error('the atlas is not four tiles across and four down', 0) end
      local ox, oy = M.TILES[i][1] * tw, M.TILES[i][2] * th
      for y = 0, th - 1 do
        for x = 0, tw - 1 do
          tile:getColor(x, y, col)
          atlas:setColor(ox + x, oy + y, col)
          n = n + 1
          if n >= every then
            n = 0
            if clock() - from >= budget then coroutine.yield() from = clock() end
          end
        end
      end
    end
    if opts.prepare then opts.prepare(plan.out) end
    if atlas:saveFile(plan.out) == false then error('cannot save ' .. plan.out, 0) end
  end)
  return function()
    local ok, why = coroutine.resume(co)
    if not ok then return true, false, why end
    return coroutine.status(co) == 'dead', true
  end
end

return M
