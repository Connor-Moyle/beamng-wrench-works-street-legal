-- Street Legal: the game's own delivery businesses as stops (a plain module, not an extension: sl_jobs and sl_frjobs both require it). The stock delivery providers of the level
-- (freeroam_facilities) with the first parking spot of each as the stop. Works in a career and in free roam: nothing here reads a career.

local M = {}

local STOP_RADIUS = 9          -- metres from a stop, and slow, to count as there (the same as sl_jobs)
local cache = {}

local function leg(p) return { id = p.id, name = p.name, x = p.x, y = p.y, z = p.z, radius = p.radius } end

-- { { id = 'site:<id>', name, x, y, z, radius } }; an empty list is not kept (the facilities may not have been loaded yet the first time)
function M.deliverySites()
  local level = getCurrentLevelIdentifier and getCurrentLevelIdentifier() or ''
  if cache[level] then return cache[level] end
  local out = {}
  local ok0, f = pcall(function() return freeroam_facilities and freeroam_facilities.getFacilities and freeroam_facilities.getFacilities(level) end)
  for _, p in ipairs(ok0 and f and f.deliveryProviders or {}) do
    local ok, spots = pcall(freeroam_facilities.getParkingSpotsForFacility, p)
    local spot = ok and type(spots) == 'table' and spots[1]
    if spot and spot.pos then
      out[#out + 1] = { id = 'site:' .. tostring(p.id or p.name), name = tostring(p.name or p.id or 'Depot'), x = spot.pos.x, y = spot.pos.y, z = spot.pos.z, radius = STOP_RADIUS }
    end
  end
  if #out > 0 then cache[level] = out end
  return out
end

-- the two legs (pickup, drop) of a freight job made by core/jobs.freight from these sites; nil when a site is gone
function M.freightLegs(job)
  local from, to
  for _, site in ipairs(M.deliverySites()) do
    if site.id == job.from then from = leg(site) end
    if site.id == job.to then to = leg(site) end
  end
  if from and to then return { from, to } end
  return nil
end

return M
