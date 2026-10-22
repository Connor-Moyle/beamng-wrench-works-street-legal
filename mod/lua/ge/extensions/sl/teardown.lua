-- Street Legal: the end-of-career queue (extension name: sl_teardown; rules in sl/core/teardown). A module that has to give a GPU-touching thing back when the career stops calls
-- sl_teardown.defer('label', function) instead of doing it in the hook: the jobs then run one at a time, a second and a half apart, and every one is logged with the time before and after
-- (the line that is last in a log is what the game was doing when it lost the device). A job is skipped if a career is running again by then, and everything is dropped when the level ends.
local M = {}

local rules = require('sl/core/teardown')
local q = rules.new()

local function now() return os.clock() end

-- do it now when this extension cannot queue (never the case in the game; keeps a module working if it is called before the queue exists)
function M.defer(label, fn)
  if not rules.defer(q, label, fn, now()) then pcall(fn) end
end

function M.onUpdate(dtReal)
  if rules.pending(q) == 0 then return end
  local label, fn = rules.due(q, now())
  if not label then return end
  if sl_career and sl_career.isActive and sl_career.isActive() then
    log('I', 'sl_teardown', string.format('%s: skipped, a career is running again', label))
    return
  end
  local t0 = now()
  log('I', 'sl_teardown', string.format('%s: start (%d more waiting)', label, rules.pending(q)))
  local ok, err = pcall(fn)
  log(ok and 'I' or 'W', 'sl_teardown', string.format('%s: %s in %.1f ms', label, ok and 'done' or ('failed: ' .. tostring(err)), (now() - t0) * 1000))
end

function M.onClientEndMission() rules.clear(q) end          -- (the level takes what is on it with it)
function M.onExtensionUnloaded() rules.clear(q) end
function M.status() return { pending = rules.pending(q), ran = q.ran } end

return M
