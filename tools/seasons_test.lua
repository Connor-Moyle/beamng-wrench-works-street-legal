-- Tests of the seasons (sl/core/seasons.lua), called from luatest.lua: the season of a day, the odds of the weather, the air temperature and the snow line, the thirst rule, the purses.
return function(check, rngLib)
  local S = require('sl/core/seasons')

  check('day 1 is spring, week 1', select(1, S.season(1)) == 'spring' and select(2, S.season(1)) == 1)
  check('a season is 28 days of four weeks', select(1, S.season(28)) == 'spring' and select(2, S.season(28)) == 4 and select(1, S.season(29)) == 'summer' and select(2, S.season(29)) == 1)
  check('summer, autumn, winter, then spring again', select(1, S.season(57)) == 'autumn' and select(1, S.season(85)) == 'winter' and select(1, S.season(112)) == 'winter' and select(1, S.season(113)) == 'spring')
  check('nonsense days are day 1', select(1, S.season(nil)) == 'spring' and select(1, S.season(-5)) == 'spring' and select(1, S.season('x')) == 'spring')

  -- the odds add up to one and have the states of the plain weather
  for _, season in ipairs(S.ORDER) do
    for _, phase in ipairs({ 'day', 'night' }) do
      local sum, hasFog = 0, false
      for _, o in ipairs(S.odds(season, phase)) do sum = sum + o[2] if o[1] == 'fog' then hasFog = true end end
      check(season .. ' ' .. phase .. ' odds add up to 1', math.abs(sum - 1) < 1e-9)
      check(season .. ' ' .. phase .. ': fog banks only at night', hasFog == (phase == 'night'))
    end
  end

  -- the draw: deterministic for a seed and a day, and it follows the season over many days
  check('the same seed and day always give the same state', S.forecast(77, 40, 'day') == S.forecast(77, 40, 'day') and S.forecast(77, 40, 'night') == S.forecast(77, 40, 'night'))
  local function share(first, last, phase, state)
    local n, hits = 0, 0
    for seed = 1, 6 do
      for day = first, last do n = n + 1 if S.forecast(seed, day, phase) == state then hits = hits + 1 end end
    end
    return hits / n
  end
  local rainSummer, rainWinter = share(29, 56, 'day', 'rain'), share(85, 112, 'day', 'rain')
  local clearSummer, clearWinter = share(29, 56, 'day', 'clear'), share(85, 112, 'day', 'clear')
  check('winter days rain more than summer days', rainWinter > rainSummer + 0.1)
  check('summer days are clear more often than winter days', clearSummer > clearWinter + 0.15)
  check('autumn nights have more fog than summer nights', share(57, 84, 'night', 'fog') > share(29, 56, 'night', 'fog') + 0.05)
  check('every state that is drawn is one of the weather states', (function() for d = 1, 120 do local s = S.forecast(3, d, 'night') if s ~= 'clear' and s ~= 'cloudy' and s ~= 'rain' and s ~= 'fog' then return false end end return true end)())

  -- air temperature, snow and the snow line
  check('summer is warmer than winter by day and by night', S.airC('summer', 'day', 'clear', 0) > S.airC('winter', 'day', 'clear', 0) and S.airC('summer', 'night', 'clear', 0) > S.airC('winter', 'night', 'clear', 0))
  check('rain cools the air a little', S.airC('winter', 'day', 'rain', 0) == S.airC('winter', 'day', 'clear', 0) - S.RAIN_COOL)
  check('the air falls with height by the lapse rate', math.abs(S.airC('summer', 'day', 'clear', 1000) - (S.airC('summer', 'day', 'clear', 0) - 6.5)) < 1e-9 and S.airC('summer', 'day', 'clear', -50) == S.airC('summer', 'day', 'clear', 0))
  check('summer rain never snows on the roads of the map', not S.snows('summer', 'night', 'rain', 900))
  check('winter night rain snows on the high road but not at sea level', S.snows('winter', 'night', 'rain', 900) and not S.snows('winter', 'night', 'rain', 0))
  check('only rain snows', not S.snows('winter', 'night', 'clear', 2000) and not S.snows('winter', 'night', 'fog', 2000))
  local line = S.snowLine('winter', 'night')
  check('the snow line is where the rain starts to snow', line > 0 and S.snows('winter', 'night', 'rain', line) and not S.snows('winter', 'night', 'rain', line - 20))
  check('the winter snow line is lower than the spring one', S.snowLine('winter', 'night') < S.snowLine('spring', 'night'))
  check('the phone line says it', S.note(85):find('Winter, week 1', 1, true) and S.note(85):find('snow above', 1, true) and not S.note(29):find('snow', 1, true))

  -- thirst
  check('clear summer days are hot, nothing else is', S.hot('summer', 'day', 'clear') and not S.hot('summer', 'night', 'clear') and not S.hot('summer', 'day', 'rain') and not S.hot('spring', 'day', 'clear') and not S.hot('winter', 'day', 'clear'))

  -- events
  check('the purses move by a few percent and never by much', (function()
    for kind, by in pairs(S.PURSE) do for _, v in pairs(by) do if v < 0.85 or v > 1.2 then return false end end end
    return true
  end)())
  check('winter sprints pay more, summer meets pay more, an unknown kind is 1', S.purse('sprint', 'winter') > 1 and S.purse('meet', 'summer') > 1 and S.purse('nothing', 'winter') == 1 and S.purse('sprint', 'x') == 1)
end
