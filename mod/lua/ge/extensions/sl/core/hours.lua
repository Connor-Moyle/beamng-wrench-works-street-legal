-- Opening hours (game rules, no engine calls). `time` is the engine's day fraction (noon = 0), so the
-- hour is (time * 24 + 12) % 24, as in sl/career.
local M = {}

local HOURS = { shop = { 8, 18 }, dealer = { 9, 17 }, junkyard = { 8, 17 }, scrapyard = { 8, 17 } }

local function hour(time) return (time * 24 + 12) % 24 end

-- an unknown kind is always open
function M.isOpen(kind, time)
  local h = HOURS[kind]
  if not h then return true end
  local now = hour(time)
  return now >= h[1] and now < h[2]
end

function M.opensAt(kind) return HOURS[kind] and HOURS[kind][1] or nil end

function M.closedText(kind, time)
  if M.isOpen(kind, time) then return nil end
  return string.format('Closed. Opens at %02d:00', M.opensAt(kind))
end

return M
