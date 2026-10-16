-- Wrench Works: Street Legal: what the stock shop shows of a car besides the price (not an extension: required by sl_dealers and
-- sl_classifieds). The preview picture of the exact config (the file the game's own shop uses), its year, brand and specs, from the
-- game's config entry that the offer was made from.

local M = {}

local builder = require('sl/carBuilder')
local rules = require('sl/core/dealers')

local index
local function entry(config)
  if not index then
    index = {}
    for _, c in ipairs(builder.configs()) do index[c.config] = c end
  end
  return index[config]
end

-- offer = { id, model, config (the .pc the offer was made from) } -> { preview, year, brand, specs }
function M.of(offer)
  local c = entry(offer.config)
  local raw = c and c.raw
  local preview = raw and raw.preview
  if not preview and core_vehicles and core_vehicles.getModel then
    local model = core_vehicles.getModel(offer.model)
    preview = model and (model.model and model.model.preview or model.preview) or nil
  end
  local years = raw and ((raw.aggregates and raw.aggregates.Years) or raw.Years)
  return { preview = preview, year = rules.yearOf(offer.id, years), brand = c and c.brand or nil, specs = rules.specs(raw) }
end

return M
