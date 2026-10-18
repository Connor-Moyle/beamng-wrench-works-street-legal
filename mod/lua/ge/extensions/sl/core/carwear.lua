-- Street Legal: what a used car looks like on the outside (Car Surface FX): the dirt and grime a car of its condition and mileage carries when it stands on a lot, and the
-- wash-off. Pure, tested by tools/luatest.js. A fresh car from a dealer is clean; a tired one is grimy; a scrap-yard one is filthy. The same offer always gets the same look.

local rngLib = require('sl/core/rng')

local M = {}

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

-- offer: { id, kind = 'dealer'|'used'|'scrap'|..., condition 0..1, mileage in km, build }
-- -> { dirt = { dust, mud, rubber, grime, bugs } } or nil for a clean car
function M.dirtFor(offer)
  if type(offer) ~= 'table' then return nil end
  local cond = clamp(offer.condition or 0.6, 0, 1)
  local km = tonumber(offer.mileage) or 0
  if offer.kind == 'dealer' or offer.build then return nil end            -- a new car, a track special: clean
  if cond >= 0.97 and km < 500 then return nil end
  local rng = rngLib.new(rngLib.hash('wear:' .. tostring(offer.id or offer.model or '?')))
  local tired = 1 - cond
  local age = clamp(km / 300000, 0, 1)                                      -- 300 thousand km is a car that has lived
  local jitter = function() return rng:range(0.8, 1.2) end
  local d = {
    dust = clamp((0.15 + 0.55 * tired + 0.2 * age) * jitter(), 0, 0.9),
    grime = clamp((0.6 * tired + 0.25 * age) * jitter(), 0, 0.9),
    rubber = clamp(0.35 * age * jitter(), 0, 0.5),
    bugs = clamp(0.3 * age * tired * 2 * jitter(), 0, 0.5),
    mud = 0,
  }
  if offer.kind == 'scrap' then d.mud = clamp(rng:range(0.25, 0.7), 0, 0.8) d.grime = math.max(d.grime, 0.5) d.dust = math.max(d.dust, 0.5) end
  if offer.kind == 'used' and rng:chance(0.15 * tired * 2) then d.mud = clamp(rng:range(0.1, 0.35), 0, 0.5) end
  for k, v in pairs(d) do d[k] = math.floor(v * 1000 + 0.5) / 1000 end
  return { dirt = d }
end

-- the wash-off: how much dirt (CSFX takes `amount` off every kind, 0..1 each) a step of dt seconds takes off so that all of it is gone after `duration` seconds
function M.washStep(dt, duration) return clamp((dt or 0) / math.max(0.1, duration or 3), 0, 1) end

-- how long a wash takes to show: a car that is hardly dirty is quick
function M.washSeconds(dirtLevel) return clamp(1.5 + 3 * (dirtLevel or 0), 1.5, 4.5) end

return M
