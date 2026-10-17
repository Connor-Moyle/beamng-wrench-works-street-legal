-- Street Legal: the player\'s help, in one place (#55). Pure: no game calls (tested by tools/luatest.js).
-- The phone\'s Help app and the laptop\'s Help window show these pages (sl_phone.requestHelp sends them), and docs/PLAYER_GUIDE.md is made from them by
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
    'The pace: day jobs pay about a third more than they used to. Your first garage is free; the second needs 175 reputation and $6,000, the third 1,000 reputation and $25,000. A few days of jobs and a few night wins get you the second.',
  } },
  { id = 'dealers', title = 'Dealers, factory orders and the car report', body = {
    'At a dealer, walk up to the door marker and choose Look at the cars. The game\'s own screen elements hide while you look. Left and right change the car; leave the camera alone and it plays cinematic shots (the wheels, the badge, the engine bay with the hood open); touch the camera to stop them.',
    'Every car has a card with Test drive, Buy and Show full car report. The report opens a panel with every part by section (condition, the worst fault, a repair estimate) and scrolls with the wheel, by dragging or with the pad\'s stick. Close or B shuts it.',
    'High-end dealers also take factory orders: Order from the factory opens a catalogue of every model with its trims. Pick a trim, then the factory options (paint, interior, wheels, steering wheel and more) with a live price. The car arrives at your garage six game hours after you pay, and My cars lists it as on order. Some vehicles (the quad bike, buggy, crawlers, loaders) can only be bought this way.',
    'Dealers, the junkyard and the scrap yard are open by day and say "Closed. Opens at HH:00" at night.',
  } },
  { id = 'weather', title = 'Weather, wet roads and puddles', body = {
    'Each half of a day has its own weather: clear, cloudy, rain in three strengths, and fog banks at night. The forecast is on the phone\'s home screen and in the Wait app.',
    'In rain the sky goes grey and dark and the road gets wet. A wet road has less grip, so brake earlier. Puddles collect on the road: a wheel through one throws spray and leaves a wet trail, and at speed a deep puddle drags the car and can make it aquaplane (the wheels float and steering goes light). Lift off and keep straight.',
    'The roads dry out after the rain. Some jobs pay more in bad weather.',
  } },
  { id = 'carcare', title = 'Dirt, scratches and washing', body = {
    'With the optional Car Surface FX mod installed your cars get wet paint in the rain, pick up dust or mud on the road and can be scratched in a knock. Without it nothing here applies.',
    '- My cars (phone and laptop) says how dirty and scratched each car is, for example "Dusty, light scratches". Dirt is clean, dusty or muddy; scratches are none, light or heavy.',
    '- Wash: roll slowly through a car wash bay, or choose Wash at a fuel pump ($15). It takes the dirt off. It does not take scratches off.',
    '- Repair: a repair in the garage (Wrench Works) buffs the scratches out with the dents. A paint job leaves the car clean and unscratched.',
    '- A car you put away keeps its dirt and scratches, and so does the save.',
  } },
  { id = 'carmeets', title = 'Car meets', body = {
    'At night a car meet fills a car park with parked cars in the painted bays, each with its owner beside it and some owners in pairs and trios. The meet has a theme (JDM, muscle, drift or euro) and a purple marker on the map.',
    'Walk up to an owner on foot and press the prompt (Talk to the owner). They tell you a story and make an offer: a tip, a race word or a car for sale. Nothing opens by itself while you walk through. The music is loudest at one car and the crowd murmur is in the middle.',
    'At high heat (4 or 5) the police can raid a meet: you get a text, the cars and people scatter and the heat goes up a little. Keep your heat low near a meet.',
  } },
  { id = 'jobs', title = 'Jobs', body = {
    'The Jobs app lists what is on offer now. Taking one gives you a destination or a task, and it pays when you finish: couriers, taxi, parts runs, test drives, dyno and quarter-mile jobs and more. Most jobs are by day; a few shady ones are by night.',
    'Some jobs need a car you own, some a certain reputation. Finish the job you are on before you take another.',
    'Taxi fares: a walker waits at the kerb. Drive smoothly; hard braking and hard cornering cost the tip (up to half the fare). Tow jobs: a dead car waits at the kerb; hook it to your car with the tow coupler of the game and tow it to the garage; the clock and the damage are the towed car's. Parts runs from the scrapyard carry fragile parts. Dealer deliveries take a new car to the customer; with Car Surface FX a single new scratch means no pay.',
  } },
  { id = 'daynight', title = 'Day and night', body = {
    'The career has two halves. Day (07:00 to 19:00) is the legal half: jobs, shops and dealers, the track events with prize money. Night (21:00 to 04:00) is the street half: street races, meets, pink slips. Shops and dealers close at night and open again in the day.',
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
  { id = 'graphics', title = 'Graphics: anti-aliasing and sharpening', body = {
    'Wrench Works adds a group to the game\'s Options > Graphics page, under the anti-aliasing type: "Wrench Works: anti-aliasing and sharpening". The first time after installing, restart the game once to see it.',
    '- Anti-aliasing: Game\'s own (the default; nothing changes), Off, FXAA, FXAA HQ, SMAA High, SMAA Ultra, or SMAA Ultra with Temporal smoothing (it blends with the last frame to calm shimmer but adds no detail). Each choice has a note under it, and Game\'s own puts the game back exactly as it was.',
    '- Sharpening (off by default): AMD CAS, AMD FSR 1 RCAS or NVIDIA NIS, with a strength slider.',
    '- Presets: Balanced, Smooth, Maximum. Heavier choices cost frame time, so try one and watch the performance overlay.',
  } },
  { id = 'extras', title = 'Optional extras', body = {
    '- Performance overlay: Settings > Performance overlay (off by default) shows the frame time, the video memory and counts of what is in the world. Use it when the game stutters, and say what it showed when you report it.',
    '- Flex driver (EXPERIMENTAL, can crash the game when switching cars: leave it off; off by default): with the Drivers & Pedestrians mod the driver in the car is normally a set of rigid parts. To try the rigged driver, open the game\'s Lua console (the ~ key) and type slrrDriverMount.setDriverRig("flex"); it is saved and applies to cars spawned from then on. Type slrrDriverMount.setDriverRig("props") to go back.',
  } },
  { id = 'settings', title = 'Settings and tools', body = {
    'The Settings app has the options of the career: police and their aggression, pay, hardcore mode (no pull-outs, no insurance, no free cab), clock speed, race traffic, and more.',
    '- Street Legal dashboard: the game\'s own HUD is used by default; switch this on for the Street Legal gauges and map.',
    '- Performance overlay: frame time and counts, for reporting stutters.',
    '- Text size (Normal, Large, Huge): applies to the phone, the laptop and the HUD; on a pad the phone is never smaller than Large.',
    '- Colour-blind friendly colours: blue and orange instead of green and red on the phone, the laptop and the HUD, with a tick, a cross or an arrow beside every good or bad figure.',
    '- Show co-driver notes on screen: on rally stages what the co-driver calls is also written on screen.',
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
