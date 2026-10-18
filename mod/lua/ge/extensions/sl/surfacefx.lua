-- Street Legal: the career's use of Car Surface FX (extension name: sl_surfacefx), the dirt and scratches a car collects. Everything is guarded: without the mod (or with an older
-- one that lacks a function) each call does nothing and returns nil. The mod's API (carSurfaceFx, apiVersion 2): wash(id, amount), repair(id) (that car's scratches),
-- getState(id) / setState(id, t) (what a car looks like, kept in the career save for stored cars), level(id) -> { dirt, dirtName, scratches, scratchName }.
-- Version 1 had wash(id, amount) and repair() for every car, so there repair is only called for the player's own car.

local M = {}

local strings = require('sl/core/strings')

local function api() return rawget(_G, 'carSurfaceFx') end
local function has(name) local a = api() return a ~= nil and type(a[name]) == 'function' end
local function v2() local a = api() return a ~= nil and (tonumber(a.apiVersion) or 1) >= 2 end

-- a car washed: the dirt splats and the dirt on the paint come off
function M.wash(vid)
  if not (vid and has('wash')) then return nil end
  local ok = pcall(api().wash, vid)
  return ok
end

-- a car repaired: its scratches are buffed out
function M.repair(vid)
  if not (vid and has('repair')) then return nil end
  if v2() then return (pcall(api().repair, vid)) end
  local player = getPlayerVehicle and getPlayerVehicle(0)
  if player and player:getID() == vid then return (pcall(api().repair)) end      -- (version 1 repairs every car: only when it is the player's)
  return nil
end

-- the state to keep with a stored car (a plain table for the career save); false when the car is clean and unmarked (keep nothing); nil when the mod is not there
function M.save(vid)
  if not (vid and v2() and has('getState')) then return nil end
  local ok, t = pcall(api().getState, vid)
  if not ok then return nil end
  if type(t) == 'table' then return t end
  return false
end

-- put a kept state back on a car that is out in the world again
function M.restore(vid, t)
  if not (vid and type(t) == 'table' and v2() and has('setState')) then return nil end
  return (pcall(api().setState, vid, t))
end

function M.level(vid)
  if not (vid and v2() and has('level')) then return nil end
  local ok, l = pcall(api().level, vid)
  return ok and type(l) == 'table' and l or nil
end

-- a used car as it stands on a lot, with the dirt of its condition and mileage (sl/core/carwear); a clean car gets nothing. Called for lot cars and cars built from an offer.
function M.dress(vid, offer)
  if not (vid and v2() and has('setState')) then return nil end
  local st = require('sl/core/carwear').dirtFor(offer)
  if not st then return nil end
  return (pcall(api().setState, vid, st))
end

-- a wash that shows: the dirt comes off over a few seconds (CSFX takes `amount` off every kind each call), not in one pop
local washing = {}
function M.washOff(vid, seconds)
  if not (vid and has('wash')) then return nil end
  local lvl = M.level(vid)
  local carwear = require('sl/core/carwear')
  washing[vid] = { left = seconds or carwear.washSeconds(lvl and lvl.dirt or 0.5), total = seconds or carwear.washSeconds(lvl and lvl.dirt or 0.5), t = 0 }
  return true
end
local stepT = 0
function M.onUpdate(dtReal)
  if not next(washing) then return end
  stepT = stepT + (dtReal or 0)
  if stepT < 0.25 then return end
  local dt = stepT
  stepT = 0
  local carwear = require('sl/core/carwear')
  for vid, w in pairs(washing) do
    w.left = w.left - dt
    if w.left <= 0 or not (getObjectByID and getObjectByID(vid)) then
      pcall(api().wash, vid)      -- (the rest, and the splats)
      washing[vid] = nil
    else
      pcall(api().wash, vid, carwear.washStep(dt, w.total))
    end
  end
end

local DIRT = { clean = 'fx.clean', dusty = 'fx.dusty', muddy = 'fx.muddy' }
local SCRATCH = { none = 'fx.no_scratches', light = 'fx.light_scratches', heavy = 'fx.heavy_scratches' }

-- the words for the phone and the garage: 'Clean, no scratches' (nil when the mod is not there)
function M.words(level)
  if type(level) ~= 'table' then return nil end
  local dirt, scratch = DIRT[level.dirtName], SCRATCH[level.scratchName]
  if not (dirt and scratch) then return nil end
  return strings.t(dirt) .. ', ' .. strings.t(scratch)
end

function M.lookText(vid) return M.words(M.level(vid)) end

return M
