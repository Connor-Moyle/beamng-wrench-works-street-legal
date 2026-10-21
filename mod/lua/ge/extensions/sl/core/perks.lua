-- Street Legal: tier perks (career expansion #6). Your rank (1 + the bosses beaten, core/rivals) unlocks small, lasting advantages; each is a factor on one kind of price or pay.
-- Pure, no game calls: tested by tools/luatest.js. The game side is sl/perks.lua (sl_perks.factor(kind) answers 1 with the part off).

local M = {}

local strings = require('sl/core/strings')

-- rank needed, the kind of thing it changes, the factor
M.PERKS = {
  { id = 'trade', rank = 2, kind = 'upgrades', factor = 0.9 },
  { id = 'mechanic', rank = 2, kind = 'service', factor = 0.85 },
  { id = 'name', rank = 3, kind = 'jobs', factor = 1.1 },
  { id = 'friends', rank = 4, kind = 'fines', factor = 0.8 },
  { id = 'credit', rank = 5, kind = 'loans', factor = 1.25 },
  { id = 'legend', rank = 6 },
}

-- the factor for a kind at a rank: the product of the perks unlocked so far
function M.factor(rank, kind)
  local f = 1
  for _, p in ipairs(M.PERKS) do if p.kind == kind and (rank or 1) >= p.rank then f = f * p.factor end end
  return f
end

-- for the phone: { tier, list = { { id, label, text, unlocked, tier } } }
function M.list(rank)
  rank = rank or 1
  local out = { tier = rank, list = {} }
  for _, p in ipairs(M.PERKS) do
    out.list[#out.list + 1] = { id = p.id, label = strings.t('perks.' .. p.id), text = strings.t('perks.' .. p.id .. '_text'), unlocked = rank >= p.rank, tier = p.rank }
  end
  return out
end

return M
