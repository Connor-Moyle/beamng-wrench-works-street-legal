-- Tests of sl/core/listings (the used parts and cars market, Design 4), called from luatest.lua
return function(check, rngLib)
  local L = require('sl/core/listings')
  local items = { { kind = 'part', name = 'Exhaust', value = 300 }, { kind = 'part', name = 'Turbo', value = 2400 },
    { kind = 'part', name = 'Mirror', value = 25 }, { kind = 'car', name = 'Covet', value = 9000 }, { kind = 'car', name = 'Bolide', value = 180000 } }

  check('MIN_BUY is the cheapest corner of the market', L.MIN_BUY > 0.4 and L.MIN_BUY < 0.7, L.MIN_BUY)

  -- THE LOOP CHECK (fails the build): nothing bought in any channel can be sold again, to an AI buyer or a
  -- bidder or the Wrench Works counter, for what it cost
  local worst, n, scams, tellsOk = -math.huge, 0, 0, true
  for seed = 1, 400 do
    local rng = rngLib.new(seed)
    for _, ch in ipairs({ 'paper', 'app', 'auction' }) do
      for _, it in ipairs(items) do
        local l = L.listing(rng, it, ch, L.demand(rng), seed)
        if l.scam then
          scams = scams + 1
          if #L.tells(l) < 3 then tellsOk = false end        -- every scam shows its tells
        else
          n = n + 1
          local paid = l.floor                                 -- the least it can be had for
          local best = L.resaleCap(it.value, l.condition)      -- the most anyone pays for it again
          for _ = 1, 20 do best = math.max(best, L.buyerOffer(rng, it.value, l.condition)) end
          local bid, cap = paid, L.resaleCap(it.value, l.condition)
          while true do local b = L.nextBid(rng, bid, cap) if not b then break end bid = b end
          best = math.max(best, bid > paid and bid or 0)
          worst = math.max(worst, L.proceeds(best) - paid, math.floor(paid * 0.5) - paid)   -- (counter: half of what was paid)
        end
      end
    end
  end
  check('no buy-and-sell-again loop in any channel', worst < 0, worst)
  check('plenty of listings checked', n > 5000, n)
  check('scams happen on the app, and always show their tells', scams > 0 and tellsOk)

  local rng = rngLib.new(3)
  local l = { ask = 500, floor = 450, item = { value = 1000 }, condition = 0.6 }
  check('the asking price is accepted as asked', select(2, L.haggle(l, 600, 0)) == 500)
  check('at or over the floor: a deal', L.haggle(l, 460, 0) == 'accept')
  local r, price = L.haggle(l, 380, 0)
  check('close: a counter, never under the floor', r == 'counter' and price >= 450 and price <= 500)
  check('far off: declined', L.haggle(l, 100, 0) == 'decline')
  check('after two rounds the seller walks', L.haggle(l, 380, 2) == 'walk')
  for _ = 1, 200 do
    local o = L.buyerOffer(rng, 2000, 0.7)
    if o > L.resaleCap(2000, 0.7) then check('buyers never pay over the cap', false, o) end
  end
  check('lowballers and fair offers both come', true)
  check('a bid goes up in steps, and stops at the cap', L.nextBid(rngLib.new(1), 1000, 1040) == nil)
  check('deposit, delivery and fee', L.deposit(500) == 50 and L.delivery(500) == 70 and L.proceeds(1000) == 950)
  check('job parts cannot be listed', not L.canList({ foreign = true }) and L.canList({ part = 'x' }))
  local honest = { ask = 900, item = { value = 1000 }, condition = 0.7, rating = 4 }
  check('an honest listing shows no tells', #L.tells(honest) == 0)
end
