-- Street Legal: sponsor billboards (#47). Pure, tested by tools/luatest.js. Which name is on the city's billboards: the player's sponsor, else the club he races
-- in (Club 1-3, by garage), else nothing (the stock ads). The atlas for a name is mod/art/street_legal/billboards/<slug>.jpg (tools/make_billboards.py).

local M = {}

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
  local club = clubLevel and ('Club ' .. tostring(clubLevel))
  if club and M.SLUGS[club] then return club end
  return nil
end

function M.file(name) return name and M.SLUGS[name] and (M.DIR .. M.SLUGS[name] .. '.jpg') or nil end

return M
