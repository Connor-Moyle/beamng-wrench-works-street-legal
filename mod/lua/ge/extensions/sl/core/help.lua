-- Street Legal: the player's help, in one place (#55). Pure: no game calls (tested by tools/luatest.js).
-- The phone's Help app and the laptop's Help window show these pages (sl_phone.requestHelp sends them), and docs/PLAYER_GUIDE.md is made from them by
-- tools/helpdoc.py, so the game and the guide never disagree. A page is { id, title, body = { paragraph, ... } }; a paragraph that starts with
-- "- " is a bullet. Keep a page short: it is read on a phone screen.

local M = {}

M.PAGES = {
  { id = 'welcome', title = 'Welcome', body = {
    'Wrench Works: Street Legal is a career on West Coast USA. You start on foot with a few thousand dollars and no car. Buy something that runs, fix it up in the garage, earn money by day, race on the streets by night and build a name.',
    'Your phone (key K) runs everything: races, cars, jobs, the bank, the markets. The same things are on the laptops in the garages.',
    'Benny, who runs your first garage, texts you where to begin. Open Messages.',
  } },
  { id = 'first', title = 'Your first hour', body = {
    '- Read Benny\'s texts and follow the tutorial: it walks you through buying a car.',
    '- Get a car. The Cab app takes you to a dealer or the junkyard, where a few cars stand in a row. Look at them with left and right, test drive one, buy it. The cheapest car on the used lot is always one you can afford.',
    '- Take it to your garage. Drive up to the door: the car backs onto the lift and the garage screen opens. Click a part to take it off, click a shelf part to fit it. Fixing a bent panel costs money, so look before you buy.',
    '- Earn some money with a job from the Jobs app (by day), then spend it on parts from the Part market.',
    '- When you are ready, start the night and race.',
  } },
  { id = 'phone', title = 'The phone', body = {
    'The home screen has the apps: Races, My cars, Bank, Street cred, Jobs, Wait, Settings, Club, Turf, Car market, Part market and Help. Messages, Contacts, Phone and Cab are in the dock.',
    'Press K to open and close it. B (or Back) goes one step back. On a pad the d-pad moves and A opens.',
  } },
  { id = 'garage', title = 'The garage', body = {
    'Drive or walk into a garage door at walking pace. The bar at the top has: Drive out, Catalog, Car info, Mechanic, Tune, Lift, Paint booth, Services, Races, Drivers, Test engine, Settings and Photo.',
    '- Mechanic: click a part to take it off, click a shelf part to fit it. Hover a part in the catalog to see what it does.',
    '- Tune: every tuning item of the car on the right. Changes take hold when you Apply.',
    '- Paint booth: three colours, finishes and mixing sliders. The second and third colours show on trim, bumpers and, on many cars, the rims.',
    '- Services: oil, coolant, battery, nitrous, an engine rebuild. Races and Drivers have their own tabs.',
    '- Photo: hides the screen and saves a picture of the car. Showcase turns the camera round it.',
  } },
  { id = 'cars', title = 'Cars and markets', body = {
    'The Car market has two tabs: the Dealers (their cars today, with pictures, power and when they arrive) and Private ads (cars sold from a kerb). A car you buy is built at your garage after a few hours; the phone tells you when.',
    'The Part market has Revline (parts from private sellers), Swap & Bid (auctions, and the swap meet), Classifieds (the paper) and the Catalog (new parts from the garage, delivered to your shelf).',
    'Used things can be worse than they look. A seller with few stars, or an ad that says "must go today", is a warning. You can make an offer, pick up in person or pay for delivery.',
  } },
  { id = 'money', title = 'Money and the bank', body = {
    'By day you earn money: jobs, the track events, and selling what you do not need. Night pays in reputation instead.',
    'The Bank app shows your balance and statement. You can borrow against your reputation, your garage and the cars you own, up to a limit; a quarter of the loan is due each week, and missed payments cost reputation, then the car.',
    'Insurance costs a little every week and pays half of repair and impound bills over a deductible.',
  } },
  { id = 'jobs', title = 'Jobs', body = {
    'The Jobs app lists what is on offer now. Taking one gives you a destination or a task, and it pays when you finish: couriers, taxi, parts runs, test drives, dyno and quarter-mile jobs and more. Most jobs are by day; a few shady ones are by night.',
    'Some jobs need a car you own, some a certain reputation. Finish the job you are on before you take another.',
  } },
  { id = 'daynight', title = 'Day and night', body = {
    'The career has two halves. Day (07:00 to 19:00) is the legal half: jobs, shops and dealers, the track events with prize money. Night (21:00 to 04:00) is the street half: street races, meets, pink slips. Shops and dealers close at night.',
    'The clock runs slowly inside each half and stops at its end. Start the night or Start the day from the Wait app or a garage computer when you are ready. You cannot switch in a race, on a job or with the police on you. A new day starts when you start the day.',
    'The speed of the clock is a setting (Clock speed).',
  } },
  { id = 'races', title = 'Street races', body = {
    'Racers are in your Contacts. Call or text one: a race for money, for high stakes, or for pink slips. A pink slip race is for keeps: win and their car is yours, lose and they drive off in yours.',
    'You can also flash your high beams at a racer cruising the streets, or roll up to a car meet at night. Races start at a start line with flares along the route. Reputation from a win is bigger at night and bigger still with heat on.',
    'Races are only at night. At the start line the race starts when the lights go green.',
  } },
  { id = 'heat', title = 'Heat and the police', body = {
    'Heat is how much the police want you, from 1 to 5. It only exists at night: Start the day and it is gone. A street race, flashing past a patrol and escaping a chase raise it; it fades while nobody is after you.',
    'The hotter it is, the more patrols, the harder they are to shake, and from 4 there are roadblocks. Reputation counts for more: +15% per heat level.',
    'Reputation you earn at night is "at risk" until you bank it by getting back to a garage (or switching to day). If you are busted you lose what is not banked, pay a fine, and at heat 4 or 5 the car is impounded.',
  } },
  { id = 'clubs', title = 'Clubs and track events', body = {
    'Your garage is in a club, and a club runs a season of seven days. Each day has a night event (a head-to-head street race against the racer just above you) and a day event (a track event from the map: a time trial, drag strip or circuit).',
    'Run a day event from its marker on the map: the stars you earn place you (three stars is first). Points make the standings; a good season pays money and reputation and invites you up. Skipped events only cost their points.',
    'The Club app has today\'s events and the standings.',
  } },
  { id = 'crews', title = 'Crews and turf', body = {
    'Every racer is in one of four crews, and each crew holds districts of West Coast USA. Beat a crew\'s racers on a district\'s streets at night to take it. A district you hold gives you more reputation and less heat there.',
    'A crew that loses a district calls you out to win it back. Hold four districts and the crew leaders come for you one by one in the turf war. The Turf app has a map.',
  } },
  { id = 'meets', title = 'Swap meet and auctions', body = {
    'On weekend nights a swap meet fills the biggest car park in town with stalls. Go there and buy parts on the spot. It is on the Part market page of the phone and the laptop, and says where it is.',
    'Swap & Bid is the auction side: put a bid on a lot, and it is yours if nobody outbids you before it ends.',
  } },
  { id = 'settings', title = 'Settings and tools', body = {
    'The Settings app has the options of the career: police and their aggression, pay, hardcore mode (no pull-outs, no insurance, no free cab), clock speed, race traffic, and more.',
    '- Street Legal dashboard: the game\'s own HUD is used by default; switch this on for the Street Legal gauges and map.',
    '- Performance overlay: frame time and counts, for reporting stutters.',
    '- Record street races: a race can be watched again (Races app, Last race) and saved as a clip.',
    'Developer: a button that gives you all the money, for testing.',
  } },
}

function M.page(id) for _, p in ipairs(M.PAGES) do if p.id == id then return p end end end

-- the pages as plain text, for the guide (the same words)
function M.markdown()
  local out = { '# Wrench Works: Street Legal - player guide', '',
    '(Made from the in-game Help, so the two always agree. Open Help on the phone or the laptop to read it in the game.)', '' }
  for _, p in ipairs(M.PAGES) do
    out[#out + 1] = '## ' .. p.title
    out[#out + 1] = ''
    for _, para in ipairs(p.body) do
      out[#out + 1] = para
      if para:sub(1, 2) ~= '- ' then out[#out + 1] = '' end
    end
    if p.body[#p.body]:sub(1, 2) == '- ' then out[#out + 1] = '' end
  end
  return table.concat(out, '\n')
end

return M
