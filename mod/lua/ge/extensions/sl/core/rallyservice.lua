-- Street Legal: the rally service stall's rules (career travel T6). Pure, no game calls: tested by tools/luatest.js.
-- On a rally visit the only workbench is the service stall of the game's rally loop (the mission's serviceStallPos): the service card
-- (Basic service, Full overhaul) works there at the normal rate and costs the mobile-mechanic rate elsewhere (sl_service asks sl_rallyservice.atStall()).

local M = {}

-- the rally loops a visit map brings: the mission's info.json holds the stall (missionTypeData.serviceStallPos [x, y, z], Rot, Scl)
M.LOOPS = {
  utah = '/gameplay/missions/utah/rallyLoop/ngrc26-rally-utah/info.json',
}
M.REACH = 8          -- metres from the stall's centre, plus its scale

-- the stall of a rally loop's info table: { pos = { x, y, z }, radius } or nil
function M.stallOf(info)
  local d = type(info) == 'table' and type(info.missionTypeData) == 'table' and info.missionTypeData or nil
  local p = d and d.serviceStallPos
  if type(p) ~= 'table' or not tonumber(p[1]) or not tonumber(p[2]) then return nil end
  return { pos = { x = tonumber(p[1]), y = tonumber(p[2]), z = tonumber(p[3]) or 0 }, radius = M.REACH + (tonumber(d.serviceStallScl) or 0) }
end

-- is the point at the stall? (flat distance: the car stands on the stall's ground)
function M.atStall(p, stall)
  if not p or not stall then return false end
  local dx, dy = (p.x or 0) - stall.pos.x, (p.y or 0) - stall.pos.y
  return dx * dx + dy * dy <= stall.radius * stall.radius
end

return M
