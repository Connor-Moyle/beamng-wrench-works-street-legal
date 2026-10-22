// Runs the phone (ui/modModules/slPhone/slPhone.js) in a simulated page and checks what it shows and
// what it asks the game for. Needs jsdom:  npm i jsdom   then   node tools/phonetest.js
// With --html <file> it also writes a page showing the phone in a few states, to look at in a browser.
const fs = require('fs'), path = require('path'), assert = require('assert');
const { JSDOM } = require('jsdom');

const code = fs.readFileSync(path.join(__dirname, '..', 'mod/ui/modModules/slPhone/slPhone.js'), 'utf8');
const dom = new JSDOM('<!doctype html><html><body></body></html>', { runScripts: 'outside-only', pretendToBeVisual: true });
const win = dom.window;
win.__slPhoneTest = true;
win.eval(code);

// a clock the test moves by hand
let now = 0, timers = [];
const clock = {
  now: () => now,
  set: (f, ms) => { const t = { at: now + ms, f }; timers.push(t); return t; },
  clear: (t) => { timers = timers.filter((x) => x !== t); },
};
function advance(ms) {
  now += ms;
  const due = timers.filter((t) => t.at <= now);
  timers = timers.filter((t) => t.at > now);
  due.forEach((t) => t.f());
}

const calls = [];
const phone = win.__slPhoneCreate(win.document, (c) => calls.push(c), clock);
const $ = (sel) => phone.root.querySelector(sel);
const text = () => phone.root.textContent;
const click = (a, v) => {
  const el = [...phone.root.querySelectorAll('[data-a="' + a + '"]')].find((e) => v === undefined || e.getAttribute('data-v') === v);
  assert.ok(el, 'nothing to click: ' + a + ' ' + (v || ''));
  el.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
};

const data = {
  active: true, money: 3500, rep: 120, title: 'Street kid', nextRep: 300, titleRep: 100, day: 2, hour: 21, minute: 5, night: true,
  garage: 'Club Garage 1', nextGarage: { name: 'Club Garage 2', canMove: false, why: 'needs 1500 reputation' }, roc: false,
  contacts: [
    { id: 'benny', name: 'Benny (garage)', phone: '555-0100', system: true },
    { id: 'r01', name: 'Mick "Clutch" Santana', short: 'Mick Santana', phone: '555-1137', tier: 1, class: 'beater', nightOnly: true, wins: 1, losses: 2 },
    { id: 'r02', name: 'Dora Kovacs', short: 'Dora Kovacs', phone: '555-1274', tier: 2, class: 'compact', wins: 0, losses: 0 },
  ],
  threads: { benny: [{ from: 'them', text: 'Welcome to Valo City, kid.', at: 1 }], r01: [{ from: 'me', text: 'Up for a race?', at: 2 }, { from: 'them', text: 'You\'re on <b>$300</b>', at: 3 }] },
  unread: { r01: 1 },
  challenges: [{ id: 'r01:1', racer: 'r01', name: 'Mick "Clutch" Santana', stake: 'money', bet: 300, raceName: 'Night race 4', nightOnly: true }],
  ledger: [{ at: 3, amount: -45, label: 'Cab to Junkyard' }, { at: 2, amount: 300, label: 'Won a race against Mick Santana' }],
  places: [{ id: 'junkyard', name: 'Junkyard', kind: 'junkyard' }],
  cars: 0, stats: { races: 3, wins: 2, pinksWon: 0, pinksLost: 0 },
};

// the main menu's own Career button asks which career: the game's, or Street Legal (continue or start over)
const menuBtn = win.document.createElement('div');
menuBtn.className = 'mainmenu-button';
menuBtn.innerHTML = '<div class="label-container"><span class="text">Career</span></div>';
let gameCareer = 0;
menuBtn.addEventListener('click', () => { gameCareer++; });
win.document.body.appendChild(menuBtn);
const pressCareer = () => menuBtn.querySelector('.text').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
phone.handle('slMenu', { show: true, installed: true, summary: 'Day 4, $12300, Street kid' });
assert.ok(!text().includes('Wrench Works: Street Legal'), 'nothing over the main menu until Career is pressed');
pressCareer();
assert.ok(gameCareer === 0 && text().includes('BeamNG Career') && text().includes('Wrench Works: Street Legal') && text().includes('Day 4'), 'Career asks which one');
click('chooser', 'beamng');
assert.ok(gameCareer === 1 && !text().includes('BeamNG Career'), "the game's own career goes ahead");
pressCareer();
click('menustart', 'continue');
assert.ok(calls.includes('@sl_menuTile.startFromMenu(false)') && !text().includes('Day 4'), 'continue');
phone.handle('slMenu', { show: true, installed: true, summary: 'Day 4, $12300, Street kid', maxSlots: 6,
  slots: [{ slot: 1, name: 'Career 1', summary: 'Day 4, $12300, Street kid', last: true }, { slot: 2, name: 'Test', summary: 'Day 1, $5000, Nobody' }] });
pressCareer();
calls.length = 0;
assert.ok(text().includes('Test') && text().includes('last played'), 'the careers are listed');
click('menustart', 'new');
assert.ok(calls.includes('@sl_menuTile.startFromMenu(true)'), 'a new career goes in a free slot, nothing is lost');
// T4: a career left on a trip asks first (Continue and Play both): go back, or go home and count the rest as missed
{
  const visit = { level: 'west_coast_usa', name: 'West Coast USA', round: 2, rounds: 4, verdict: 'ask' };
  const slotsV = { show: true, installed: true, summary: 'Day 4', maxSlots: 6, slots: [{ slot: 1, name: 'Career 1', summary: 'Day 4', last: true, visit }, { slot: 2, name: 'Test', summary: 'Day 1' }] };
  phone.handle('slMenu', slotsV);
  pressCareer();
  calls.length = 0;
  click('menustart', 'continue');
  assert.ok(calls.length === 0, 'Continue on a visit starts nothing yet');
  assert.ok(text().includes('round 2 of 4') && text().includes('Go back to West Coast USA (round 2 of 4)') && text().includes('Go home: the rest counts as missed'), 'the question: ' + text().slice(0, 300));
  click('visitgo', '0|cancel');
  assert.ok(!text().includes('Go home: the rest'), 'Back closes the question');
  click('slotplay', '2');
  assert.ok(calls.some((c) => c.indexOf('startFromMenu(false,2)') >= 0), 'a career without a visit plays straight away');
  phone.handle('slMenu', slotsV);
  pressCareer();
  click('slotplay', '1');
  assert.ok(text().includes('Go home: the rest'), 'Play on the career with a visit asks too');
  click('visitgo', '1|home');
  assert.ok(calls.includes('@sl_menuTile.startFromMenu(false,1,nil,"home")'), 'Go home: ' + calls.join(' '));
  phone.handle('slMenu', slotsV);
  pressCareer();
  click('slotplay', '1');
  click('visitgo', '1|resume');
  assert.ok(calls.includes('@sl_menuTile.startFromMenu(false,1,nil,"resume")'), 'Go back');
}
// W1: with two maps installed the card offers both; the one picked goes with the new career
const maps = [{ id: 'slrr_valo_city', name: 'Valo City', installed: true }, { id: 'west_coast_usa', name: 'West Coast USA', installed: true }];
phone.handle('slMenu', { show: true, installed: true, maps, maxSlots: 6, slots: [] });
pressCareer();
calls.length = 0;
assert.ok(text().includes('Valo City') && text().includes('West Coast USA'), 'both maps offered');
click('newmap', 'west_coast_usa');
click('menustart', 'new');
assert.ok(calls.includes('@sl_menuTile.startFromMenu(true, nil, "west_coast_usa")'), 'the picked map starts the career');
phone.handle('slMenu', { show: true, installed: true, maps: [maps[1]], maxSlots: 6, slots: [] });
pressCareer();
calls.length = 0;
click('menustart', 'new');
assert.ok(!text().includes('Valo City') && calls.includes('@sl_menuTile.startFromMenu(true, nil, "west_coast_usa")'), 'one map installed: no chips, that map');
phone.handle('slMenu', { show: true, installed: true, summary: 'Day 4, $12300, Street kid', maxSlots: 6,
  slots: [{ slot: 1, name: 'Career 1', summary: 'Day 4', last: true }, { slot: 2, name: 'Test', summary: 'Day 1' }] });
pressCareer();
calls.length = 0;
click('slotdel', '2');
assert.ok(!calls.length && text().includes('Click again'), 'deleting asks first');
click('slotdel', '2');
assert.ok(calls.includes('@sl_menuTile.deleteSlot(2)'), 'then deletes');
click('slotname', '2');
assert.ok(calls.includes('@sl_menuTile.renameSlot(2,"Test")'), 'rename sends the typed name');
click('slotplay', '2');
assert.ok(calls.includes('@sl_menuTile.startFromMenu(false,2)'), 'play a slot');
phone.handle('slMenu', { show: true, installed: false });
pressCareer();
assert.ok(text().includes('Needs the West Coast USA map'), 'tells you when the map is missing');
click('chooser', 'close');
assert.ok(!text().includes('BeamNG Career'), 'back closes it');
phone.handle('slMenu', { show: false });
pressCareer();
assert.ok(!text().includes('Wrench Works: Street Legal') && gameCareer === 2, 'in a level the button is left alone');
menuBtn.remove();
calls.length = 0;

// nothing shows before a career runs
assert.ok(!$('.slp-device'), 'no phone without a career');
phone.handle('slPhoneData', data);
assert.ok($('.slp-device.slp-away'), 'the phone starts in the pocket');
assert.ok($('.slp-pill') && text().includes('$3,500'), 'money shows in the corner');
phone.handle('slPhoneData', Object.assign({}, data, { phase: 'night', heat: 2 }));
assert.ok($('.slp-pill').textContent.includes('☾') && $('.slp-pill').textContent.includes('▲▲') && !$('.slp-pill').textContent.includes('▲▲▲'), 'D4: the corner shows night and two heat marks');
phone.handle('slPhoneData', data);

// K takes it out: home screen with the time, the day and badges
phone.handle('slPhoneToggle');
assert.ok(!$('.slp-device.slp-away'), 'K takes it out');
assert.ok(calls.includes('request()'), 'opening asks for fresh data');
assert.ok(text().includes('21:05') && text().includes('Day 2'), 'clock and day on the home screen');
{ const keep = $('.slp-device'); phone.handle('slPhoneData', data); assert.ok($('.slp-device') === keep, 'the same data again does not rebuild the screen (a click between press and release would be lost)'); }
assert.ok(text().includes('Wait'), 'the Wait app is on the home screen');
phone.handle('slPhoneData', Object.assign({}, data, { weather: { state: 'rain', name: 'Rain', wet: true, text: 'Rain tonight. Wet roads, less grip, jobs and races pay a little more. Clear by day.' } }));
assert.ok(text().includes('Rain tonight') && text().includes('Wet roads'), 'the forecast line on the home screen');
phone.handle('slPhoneData', data);

calls.length = 0;
phone.act('open', 'wait');
assert.ok(text().includes('Start the night') && text().includes('Six hours') && !text().includes('next morning'), 'the Wait page offers to start the night and a few hours');
click('wait', 'switch');
click('wait', '3');
assert.ok(calls.includes('wait("switch")') && calls.includes('wait("3")'), 'the buttons ask for the wait');
click('back');
const homeApps = () => ['Club', 'Turf', 'Car market', 'Part market'].filter((n) => text().includes(n));
assert.ok(homeApps().length === 4, 'Valo City (no "has" sent): every app is on the home screen');
phone.handle('slPhoneData', Object.assign({}, data, { has: { clubs: true, crews: true, classifieds: true } }));
assert.ok(homeApps().length === 4, 'a map that hosts them shows Club, Turf, Car market and Part market');
phone.handle('slPhoneData', Object.assign({}, data, { has: { clubs: false, crews: false, classifieds: false } }));
assert.ok(homeApps().length === 1 && text().includes('Car market'), 'a map without clubs, crews and classifieds keeps the Car market (the dealers) and hides the rest');
phone.handle('slPhoneData', data);
assert.strictEqual($('.slp-dock .slp-badge').textContent, '1', 'unread messages badge on Messages');

// contacts -> a contact -> call; it rings, then they answer and the stakes are offered
click('open', 'contacts');
assert.ok(text().includes('Mick "Clutch" Santana') && text().includes('Dora Kovacs'), 'contacts listed');
assert.strictEqual(phone.root.querySelector('[data-v="benny"] .slp-av').textContent, 'B', 'initials leave out what is in brackets');
click('contact', 'r01');
assert.ok(text().includes('555-1137') && text().includes('nights'), 'contact card');
click('call', 'r01');
assert.ok(calls.includes('call("r01")') && text().includes('Calling'), 'calling');
phone.handle('slPhoneCall', { id: 'r01', answered: true, greeting: 'Yeah? Who is this?', options: ['race', 'high', 'pink'] });
assert.ok(text().includes('Calling'), 'it rings a moment first');
advance(2000);
assert.ok(text().includes('Who is this') && text().includes('Pink slips'), 'they answer, stakes offered');
click('stake', 'pink');
assert.ok(calls.includes('challenge("r01","pink")'), 'pink slips asked for');
assert.ok(!$('[data-a="stake"]'), 'one question per call');
phone.handle('slPhoneCallReply', { id: 'r01', accept: true, text: 'Pink slips it is.', challenge: { id: 'r01:9', raceName: 'Night race 7' } });
assert.ok(text().includes('Pink slips it is') && text().includes('Night race 7'), 'their answer and the way to the race');
click('gps', 'r01:9');
assert.ok(calls.includes('waypoint("r01:9")'), 'route asked for');
click('hang');
assert.ok(!$('.slp-call'), 'hung up');

// an unanswered call ends by itself
click('call', 'r01');
phone.handle('slPhoneCall', { id: 'r01', answered: false, text: 'No answer.' });
advance(2000);
assert.ok(text().includes('No answer') && text().includes('Call ended'), 'no answer');
click('hang');

// messages: unread thread, opening it marks it read, quick replies
click('home');
click('open', 'messages');
assert.ok($('.slp-rt span.slp-unread'), 'unread thread stands out');
click('thread', 'r01');
assert.ok(calls.includes('markRead("r01")'), 'opening a thread marks it read');
assert.ok(text().includes('<b>$300</b>') && !$('.slp-bub b'), 'message text is shown as text, never as markup');
click('text', 'high');
assert.ok(calls.includes('text("r01","high")'), 'quick reply sent');
click('back');
click('thread', 'benny');
assert.ok(!$('[data-a="text"]'), 'no race offers to Benny');

// a text arriving while the phone is away pops up; clicking it opens the thread
click('away');
phone.handle('slPhoneNotify', { thread: 'r02', name: 'Dora Kovacs', text: 'Tonight?' });
assert.ok(!$('.slp-hu.slp-gone') && text().includes('Tonight?'), 'heads-up notification');
click('openthread', 'r02');
assert.ok(!$('.slp-device.slp-away') && $('.slp-msgs'), 'the notification opens the thread');
advance(7000);
assert.ok($('.slp-hu.slp-gone'), 'notifications go away');

// dialling a number that belongs to a contact calls them
click('home');
click('open', 'phone');
'5551274'.split('').forEach((d) => click('key', d));
assert.ok(text().includes('Dora Kovacs'), 'the dialler recognises the number');
click('dial');
assert.ok(calls.includes('call("r02")'), 'dialled');
click('hang');
click('del');

// races, bank, cab, profile
click('home');
click('open', 'races');
assert.ok(text().includes('Night race 4') && text().includes('$300'), 'arranged races');
click('raise', 'r01:1');
assert.ok(calls.includes('raise("r01:1")'), 'raising the stake');
click('cancel', 'r01:1');
assert.ok(calls.includes('cancel("r01:1")'), 'calling one off');
click('home');
click('open', 'bank');
assert.ok(text().includes('-$45') && text().includes('+$300'), 'bank statement');
assert.ok(!text().includes('Weekly costs'), 'no weekly card without weekly data');
{
  // the weekly costs card (sl_weekly.summary()): bills, debt with its one button, the last weeks; every part may be missing
  const wk = { enabled: true, week: 3, dayOfWeek: 5, nextBillDay: 2, debt: 120, bills: [{ id: 'rent', label: 'Garage rent', amount: 150, due: 2 }, { id: 'insurance', label: 'Insurance', amount: 80, due: 0 }],
    history: [{ week: 2, income: 900, costs: 400, net: 500 }, { week: 1, income: 100, costs: 300, net: -200 }, { week: 0, income: 1, costs: 1, net: 0 }, { week: -1, income: 1, costs: 1, net: 0 }, { week: -2, income: 1, costs: 1, net: 0 }] };
  phone.handle('slPhoneData', Object.assign({}, data, { weekly: wk }));
  let t = text();
  assert.ok(t.includes('Weekly costs') && t.includes('Week 3, day 5 of 7') && t.includes('bills are paid in 2 days'), 'week, day and the days to the bills: ' + t.slice(0, 200));
  assert.ok(t.includes('Garage rent') && t.includes('-$150') && t.includes('Insurance') && t.includes('tonight'), 'the coming bills');
  assert.ok(t.includes('Debt: $120') && $('[data-a="paydebt"]'), 'debt with its pay button');
  assert.ok(t.includes('Week 2') && t.includes('+$500') && t.includes('-$200'), 'the history, signed');
  assert.ok(!t.includes('Week -2'), 'at most four weeks of history');
  click('paydebt', '120');
  assert.ok(calls.includes('payDebt(120)'), 'the pay button asks the game for payDebt');
  phone.handle('slPhoneData', Object.assign({}, data, { weekly: { enabled: true, week: 1, dayOfWeek: 1, nextBillDay: 0 } }));
  t = text();
  assert.ok(t.includes('bills are paid tonight') && t.includes('No bills yet') && !t.includes('Debt:') && !$('[data-a="paydebt"]'), 'empty bills, no debt, nothing missing');
  phone.handle('slPhoneData', Object.assign({}, data, { weekly: wk, has: Object.assign({}, data.has, { weekly: false }) }));
  assert.ok(!text().includes('Weekly costs'), 'the part switched off: no card');
  phone.handle('slPhoneData', Object.assign({}, data, { weekly: Object.assign({}, wk, { enabled: false }) }));
  assert.ok(!text().includes('Weekly costs'), 'disabled: no card');
  phone.handle('slPhoneData', data);
}
click('home');
click('open', 'cab');
click('taxi', 'junkyard');
assert.ok(calls.includes('taxi("junkyard")'), 'cab ordered');
// #21: the cab's places by category; dealers by the price tier of their cars
phone.handle('slPhoneData', Object.assign({}, data, { places: [{ id: 'junkyard', name: 'Junkyard', kind: 'junkyard' }, { id: 'g1', name: 'Alder Garage', kind: 'garage' }, { id: 'sh', name: 'Corner Shop', kind: 'shop' },
  { id: 'd1', name: 'Posh Motors', kind: 'dealer', tier: 'high', tierLabel: 'Premium' }, { id: 'd2', name: 'Cheap Cars', kind: 'dealer', tier: 'low', tierLabel: 'Budget' }] }));
const cabNames = () => Array.from(phone.root.querySelectorAll('.slp-row b')).map((b) => b.textContent);
assert.strictEqual(cabNames().length, 5, 'All: every place');
click('mtab', 'cab|garage');
assert.deepStrictEqual(cabNames(), ['Alder Garage'], 'Garages');
click('mtab', 'cab|dealer');
assert.deepStrictEqual(cabNames().sort(), ['Cheap Cars', 'Posh Motors'], 'Dealers, with the tier chips');
assert.ok(text().includes('Premium') && text().includes('High') && text().includes('Junk'), 'the tier label shows and the tier chips are there');
click('mtab', 'cabtier|high');
assert.deepStrictEqual(cabNames(), ['Posh Motors'], 'Dealers, high tier');
click('mtab', 'cab|junk');
assert.deepStrictEqual(cabNames(), ['Junkyard'], 'Junkyards (no tier chips)');
click('mtab', 'cab|dealer'); click('mtab', 'cabtier|all'); click('mtab', 'cab|all');
click('home');
click('open', 'me');
assert.ok(text().includes('Street kid') && text().includes('needs 1500 reputation'), 'street cred page');
{
  // tier perks (sl_perks.perks()): the rank, what each opened, the next ones dimmed; nothing with the part off or no data
  const perks = { tier: 2, list: [{ id: 'garage', label: 'Garage discount', text: '10 % off garage upgrades', unlocked: true, tier: 1 }, { id: 'dealer', label: 'Dealer tier', text: 'The second dealer sells to you', unlocked: true, tier: 2 }, { id: 'sponsor', label: 'Sponsor slot', text: 'A sponsor can pay you weekly', unlocked: false, tier: 3 }] };
  phone.handle('slPhoneData', Object.assign({}, phone.state.data, { perks }));
  let tx = text();
  assert.ok(tx.includes('Tier perks') && tx.includes('Garage discount') && tx.includes('10 % off garage upgrades') && tx.includes('Open') && tx.includes('Rank 3') && tx.includes('Sponsor slot'), 'the perks, open and locked: ' + tx.slice(0, 200));
  phone.handle('slPhoneData', Object.assign({}, phone.state.data, { perks, has: Object.assign({}, phone.state.data.has, { perks: false }) }));
  assert.ok(!text().includes('Tier perks'), 'the part off: no card');
  phone.handle('slPhoneData', Object.assign({}, phone.state.data, { perks: undefined, has: Object.assign({}, phone.state.data.has, { perks: true }) }));
  assert.ok(!text().includes('Tier perks'), 'no data: no card');
}
phone.handle('slRivals', { rank: 2, rivals: [ { id: 'r05', name: 'Viktor "Nitro" Halasz', tier: 1, boss: true, crew: 'Ring Road Ghosts', car: 'Covet "Dodger"', meter: -80, word: 'blood', beaten: 3, youLost: 1 }, { id: 'r20', name: 'Dora Kovacs', tier: 3, crew: 'Riverbed Runners', car: 'Pickup', meter: 40, word: 'respect', beaten: 0, youLost: 2, locked: 'Viktor Halasz' } ] });
assert.ok(text().includes('Rivals') && text().includes('Boss 1') && text().includes('Bad blood') && text().includes('Won 3, lost 1') && text().includes('Respect') && text().includes('Beat Viktor Halasz to move up') && text().includes('Ring Road Ghosts'), 'the rivals show with crew, car, the meter word, the record and the lock');
phone.handle('slRivals', { rank: 2, rivals: [ { id: 'r05', name: 'Viktor Halasz', tier: 4, boss: true, crew: 'Ring Road Ghosts', meter: -80, word: 'blood', beaten: 3, youLost: 1, offer: { stake: 'pink', myCar: 'Covet 1.5', theirCar: 'Scintilla' } } ] });
assert.ok(text().includes('Pink slip offer: your Covet 1.5 against their Scintilla') && text().includes('Accept the pink slips') && text().includes('Race for money instead') && text().includes('Walk away'), 'a pink slip offer names both cars and has three answers');
click('rvyes', 'r05'); click('rvmoney', 'r05'); click('rvno', 'r05');
assert.ok(calls.includes('@sl_rivals.accept("r05")') && calls.includes('@sl_rivals.decline("r05",true)') && calls.includes('@sl_rivals.decline("r05",false)'), 'the three answers go to the game');

assert.ok(!text().includes('Rev counter'), 'the dashboard switches are in the Mods menu, not on the phone');
phone.handle('slPhoneData', data);

// back walks back through the pages, and out of the phone at the end
click('back');
assert.ok($('.slp-clock'), 'back to the home screen');
click('back');
assert.ok($('.slp-device.slp-away'), 'and into the pocket');

// my cars: drive another one, tow one home
phone.handle('slPhoneData', Object.assign({}, data, { fleet: [
  { id: 1, name: 'Covet', where: 'Out on the street', out: true, active: true, condition: 0.6, faults: ['radiator'], towFee: 230 },
  { id: 2, name: 'Pessima', where: 'In the garage', out: false, active: false, condition: 0.9, faults: [] }] }));
click('home');
click('open', 'garage');
assert.ok(text().includes('Needs: radiator') && text().includes('$230'), 'my cars');
click('tow', '1');
assert.ok(calls.includes('tow(1)'), 'tow asked for');
click('usecar', '2');
assert.ok(calls.includes('useCar(2)'), 'swap asked for');

// street cred: move garage and the ROC when they are open
phone.handle('slPhoneData', Object.assign({}, data, { nextGarage: { name: 'Club Garage 2', canMove: true }, roc: true, rocRound: 1, rocEntry: 50000 }));
click('home');
click('open', 'me');
click('move');
assert.ok(calls.includes('moveGarage()'), 'move garage');
assert.ok(text().includes('ROC round 2 of 3'), 'ROC round shown');
click('roc');
assert.ok(calls.includes('enterRoc()') && $('.slp-device.slp-away'), 'ROC entered, phone put away');

// a lot: browsing, the camera, buying
calls.length = 0;
phone.handle('slLotData', { open: true, mode: 'browse', name: 'Valo Junkyard', kindTitle: 'Used cars', kind: 'used', index: 2, count: 8, money: 3000,
  offer: { name: 'Covet', brand: 'Ibishu', title: 'Modified, needs work', condition: 0.42, damage: 0.3, mileage: 182000, faults: ['tyres'], mods: 3, price: 2400 } });
assert.ok(text().includes('Ibishu') && text().includes('182,000 km') && text().includes('Needs: tyres') && text().includes('3 parts') && text().includes('2 / 8'), 'the car on show');
click('lot', 'next()');
click('lot', 'buy()');
click('lot', 'testDrive()');
assert.deepStrictEqual(calls.slice(0, 3), ['@sl_lot.next()', '@sl_lot.buy()', '@sl_lot.testDrive()'], 'lot buttons go to the lot');
const catcher = $('.slp-catch');
catcher.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, button: 2, clientX: 100, clientY: 100 }));
win.dispatchEvent(new win.MouseEvent('mousemove', { clientX: 130, clientY: 95 }));
win.dispatchEvent(new win.MouseEvent('mouseup', {}));
assert.ok(calls.includes('@sl_lot.cameraDrag(30,-5)'), 'dragging turns the camera');
phone.handle('slLotData', { open: true, mode: 'browse', name: 'Valo Junkyard', kindTitle: 'Used cars', kind: 'used', index: 1, count: 8, money: 1000, offer: { name: 'X', price: 5000, faults: [] } });
assert.ok($('[data-v="buy()"].slp-off') && text().includes('Runs and drives'), 'cannot buy what you cannot pay for');
// T44: while the row is made the lot is a loading screen with a count; the car card comes when all is done
phone.handle('slLotData', { open: true, mode: 'browse', name: 'Jefferson Motors', kindTitle: 'New cars', kind: 'dealer', index: 1, count: 4, money: 9000, building: true,
  progress: { phase: 'cars', done: 2, total: 4 }, offer: { name: 'X', price: 5000, faults: [] } });
assert.ok($('.slp-lotload') && text().includes('Getting the cars out') && text().includes('Car 2 of 4') && text().includes('Jefferson Motors') && $('.slp-lotload .slp-lbar i').style.width === '50%', 'a lot being made: the loading screen with its count');
assert.ok(!$('[data-v="buy()"]') && !$('.slp-lotbtns'), 'no buy button, no card while it is made');
phone.handle('slLotData', { open: true, mode: 'browse', name: 'Jefferson Motors', kindTitle: 'New cars', kind: 'dealer', index: 1, count: 4, money: 9000, building: true,
  progress: { phase: 'bodywork', done: 1, total: 2 }, offer: { name: 'X', price: 5000, faults: [] } });
assert.ok(text().includes('Bodywork 1 of 2'), 'the second round is counted too');
calls.length = 0;
click('lot', 'close()');
assert.ok(calls.some(function (c) { return c.indexOf('close()') >= 0; }), 'the loading screen can be cancelled');
phone.handle('slLotData', { open: true, mode: 'browse', name: 'Jefferson Motors', kindTitle: 'New cars', kind: 'dealer', index: 1, count: 4, money: 9000, building: false, offer: { name: 'Roamer', price: 5000, faults: [] } });
assert.ok(!$('.slp-lotload') && $('[data-v="buy()"]') && text().includes('Roamer'), 'built: the loading screen is gone and the card shows');
// #58: the full car report on the lot's card
var rep58 = { condition: 45, label: 'Worn', mileage: 180000, damage: { amount: 30, label: 'Moderate' }, faults: ['brakes'], total: 1900, sections: [{ id: 'brakes', title: 'Brakes', condition: 30, label: 'Worn', estimate: 640, faults: ['brakes'], parts: [{ name: 'Pads and discs', condition: 20, label: 'Poor', fault: 'brakes' }, { name: 'Calipers and lines', condition: 40, label: 'Worn' }] }] };
phone.handle('slLotData', { open: true, mode: 'browse', name: 'Jefferson Motors', kindTitle: 'New cars', kind: 'dealer', index: 1, count: 4, money: 9000, building: false, offer: { name: 'Roamer', price: 5000, faults: ['brakes'], report: rep58 } });
assert.ok(text().includes('Show full car report') && !text().includes('Repair estimate'), 'the lot card offers the report, closed');
click('report', 'lot');
assert.ok($('.slp-repmodal') && text().includes('Brakes') && text().includes('Pads and discs') && text().includes('20% Poor') && text().includes('Moderate (30%)') && text().includes('$640') && text().includes('$1,900'), 'the report opens in a panel of its own and lists the parts by section, the damage and the repair estimates');
assert.ok($('.slp-repbody') && $('.slp-repbody').hasAttribute('bng-nav-scroll') && $('.slp-reppanel [data-a="reportclose"]'), 'the panel has a body that scrolls (also on the pad) and a close button');
assert.ok($('.slp-repsum[data-a="repsec"]'), 'every section is a collapsible row with its summary');
click('repsec', 'brakes');
assert.ok(!text().includes('Pads and discs') && text().includes('$640'), 'a section closes to its summary row (condition, worst fault, estimate)');
click('repsec', 'brakes');
assert.ok(text().includes('Pads and discs'), 'and opens again');
// the panel fits the screen: its CSS (width, max height, scrolling body) checked for 1280x720 and 1920x1080
(function () {
  const css = code.replace(/\\'/g, "'");
  const panel = css.match(/\.slp-reppanel\{([^}]*)\}/)[1], body = css.match(/\.slp-repbody\{([^}]*)\}/)[1];
  assert.ok(/max-height:80vh/.test(panel) && /width:min\((\d+)px,92vw\)/.test(panel) && /overflow-y:auto/.test(body) && /min-height:0/.test(body), 'panel: max-height 80vh, width min(Npx, 92vw), a scrolling body');
  const wpx = +panel.match(/width:min\((\d+)px,92vw\)/)[1];
  [[1280, 720], [1920, 1080]].forEach(function (vp) {
    const w = Math.min(wpx, 0.92 * vp[0]), h = 0.8 * vp[1];
    assert.ok(w <= vp[0] && h <= vp[1] && (vp[1] - h) / 2 >= 0, 'the panel (' + w + 'x' + h + ') is inside ' + vp.join('x'));
  });
})();
click('reportclose');
assert.ok(!$('.slp-repmodal') && !text().includes('Pads and discs'), 'and closes again');
phone.handle('slLotData', { open: true, mode: 'sell', name: 'Scrap & Salvage', kindTitle: 'Scrap yard', kind: 'scrap', sellCar: { name: 'Covet', price: 410 } });
assert.ok(text().includes('$410 for the Covet') && text().includes('Scrap it'), 'selling at the scrap yard');
phone.handle('slLotData', { open: true, mode: 'test', name: 'Valo Junkyard', testLeft: 95 });
assert.ok(text().includes('1:35 left'), 'test drive clock');
phone.handle('slLotData', { open: false });
assert.ok(!$('.slp-lot') && !$('.slp-hudtest'), 'lot closed');

// a meet and a race
phone.handle('slMeet', { open: true, name: 'Harbour car park', racers: [{ id: 'r05', name: 'Kat "Ghost" Holm', car: 'Sunburst', tier: 2, betMin: 300, betMax: 900, pinkTonight: false }] });
assert.ok(text().includes('Harbour car park') && text().includes('Sunburst') && text().includes('$300-$900'), 'the meet');
assert.ok(!$('[data-v="r05|pink"]'), 'no pink slips with somebody who is not up for them tonight');
phone.handle('slMeet', { open: true, name: 'Harbour car park', racers: [{ id: 'r05', name: 'Kat "Ghost" Holm', car: 'Sunburst', tier: 2, betMin: 300, betMax: 900, pinkTonight: true }] });
click('meet', 'r05|pink');
assert.ok(calls.includes('@sl_streets.meetChallenge("r05","pink")'), 'pink slips at the meet');
phone.handle('slMeet', { open: true, name: 'Harbour car park', theme: 'JDM night', racers: [], owners: [{ id: 'o1', name: 'Jin Tanaka', car: 'Covet', kind: 'tip' }, { id: 'o2', name: 'Bree Quinn', car: 'Pessima', kind: 'sale', talked: true }] });
assert.ok(text().includes('JDM night') && text().includes('Jin Tanaka') && text().includes('Covet') && text().includes('spoken to'), 'a themed meet lists the owners by their cars');
calls.length = 0;
click('meettalk', 'o1');
assert.ok(calls.includes('@sl_streets.meetTalk("o1")'), 'talk to an owner');
click('meetclose');
assert.ok(!$('.slp-meet'), 'meet menu closed');
phone.handle('slRace', { on: true, name: 'Kat "Ghost" Holm', stake: 'pink', bet: 0, destName: 'near Valo Junkyard', countdown: 3, mine: 1800, theirs: 1750, ahead: false });
assert.ok($('.slp-count').textContent === '3' && text().includes('Pink slips') && text().includes('Behind'), 'race display');
phone.handle('slRace', { on: false });
assert.ok(!$('.slp-race'), 'race over');

// leaving the career puts it away for good
phone.handle('slPhoneData', { active: false });
assert.ok(!$('.slp-device'), 'gone when the career stops');

// the gas station: pick a grade, fill up, buy into the trunk
phone.handle('slPhoneData', data);
calls.length = 0;
phone.handle('slStation', { open: true, name: 'South Gas', money: 900, car: 'Covet', tank: 0.25, inTank: 'Regular 91', litresToFull: 33,
  fuels: [{ id: 'regular', name: 'Regular 91', price: 1.45 }, { id: 'race', name: 'Race 102', price: 3.2 }],
  items: [{ id: 'oil', name: 'Engine oil (4 L)', price: 45 }], trunk: 1, trunkSlots: 6, washPrice: 15 });
assert.ok(text().includes('South Gas') && text().includes('33 L to fill') && text().includes('Race 102'), 'the pump');
click('fuelpick', 'race');
click('station', 'fill|race');
assert.ok(calls.includes('@sl_station.fill("race")'), 'filling with race fuel');
click('station', 'buy|oil');
assert.ok(calls.includes('@sl_station.buy("oil","race")'), 'oil into the trunk');
click('station', 'wash');
assert.ok(calls.includes('@sl_station.wash()') && text().includes('Car wash'), 'the pump offers a wash for a fee');
click('station', 'close');
assert.ok(!text().includes('South Gas'), 'driving on');

// with SLRR's art copied in, its icons replace the drawn ones where SLRR has one
phone.handle('slPhoneData', data);
phone.handle('slPhoneToggle');
click('home');
assert.ok(!phone.root.querySelector('img.slp-slrr'), 'drawn icons without SLRR art');
phone.handle('slArt');
assert.ok(phone.root.querySelector('img.slp-slrr[src$="cup.png"]') && phone.root.querySelector('img.slp-slrr[src$="dollar.png"]'), "SLRR's cup and dollar icons");
// the job board
phone.handle('slPhoneData', Object.assign({}, data, { jobs: { done: 2, earned: 640, offers: [
  { id: '5d:1', title: 'Part run', item: 'turbocharger', from: 'Redline Speed Shop', to: 'Club Garage 1', pay: 380, seconds: 240, metres: 2100, fragile: true } ] } }));
phone.act('home');
phone.act('open', 'jobs');
assert.ok(text().includes('Part run: turbocharger') && text().includes('Redline Speed Shop') && text().includes('2 jobs done'), 'the board lists the offer and the record');
{
  // a contract is an offer with terms (o.contract = { req, label, mult, basePay }): a tag, the terms, the normal pay as small text; the job you are on shows its terms
  const withContract = { jobs: { done: 2, earned: 640, offers: [{ id: 'k1', title: 'Contract: Courier', item: 'parcel', from: 'A', to: 'B', pay: 500, seconds: 200, contract: { req: 'rain', label: 'Deliver it in the rain', mult: 1.9, basePay: 260 } }] } };
  phone.handle('slPhoneData', Object.assign({}, data, withContract));
  let tx = text();
  assert.ok(tx.includes('Contract: Courier') && tx.includes('Deliver it in the rain') && tx.includes('Pays $500 if you keep the terms, $260 if you miss them'), 'the contract card: ' + tx.slice(0, 200));
  assert.ok(phone.root.querySelector('.slp-chip') && /Contract/.test(phone.root.querySelector('.slp-chip').textContent) && phone.root.querySelector('[data-a="jobtake"][data-v="k1"]'), 'a Contract tag and the usual Take it button');
  phone.handle('slPhoneData', Object.assign({}, data, { jobs: { done: 2, earned: 640, offers: [], active: { title: 'Contract: Courier', item: 'parcel', next: 'B', to: 'B', pay: 500, timeLeft: 95, contract: { req: 'rain', label: 'Deliver it in the rain', mult: 1.9 } } } }));
  assert.ok(text().includes('Deliver it in the rain') && text().includes('1:35 left'), 'the job you are on shows its terms');
  phone.handle('slPhoneData', Object.assign({}, data, { jobs: { done: 2, earned: 640, offers: [{ id: 'k2', title: 'Courier', item: 'parcel', from: 'A', to: 'B', pay: 100 }] } }));
  assert.ok(!text().includes('Pays $') && !phone.root.querySelector('.slp-chip.contract'), 'a plain job has no terms line');
  phone.handle('slPhoneData', Object.assign({}, data, { jobs: { done: 2, earned: 640, offers: [{ id: '5d:1', title: 'Part run', item: 'turbocharger', from: 'Redline Speed Shop', to: 'Club Garage 1', pay: 380, seconds: 240, metres: 2100, fragile: true }] } }));
}
calls.length = 0;
click('jobtake', '5d:1');
assert.ok(calls.some(function (c) { return c.indexOf('takeJob("5d:1")') >= 0; }), 'Take it calls takeJob');
phone.handle('slPhoneData', Object.assign({}, data, { jobs: { done: 2, earned: 640, offers: [], active: { title: 'Part run', item: 'turbocharger', next: 'Club Garage 1', to: 'Club Garage 1', pay: 380, timeLeft: 95 } } }));
assert.ok(text().includes('Next stop: Club Garage 1') && text().includes('1:35 left') && !text().includes('Take it'), 'the job you are on, with its clock');
// Revline: the used parts market
phone.handle('slPhoneData', Object.assign({}, data, { market: { deliveries: 1, listings: [
  { id: 'm1', name: 'Sport exhaust', model: 'covet', ask: 300, condition: 72, seller: 'Kenny', rating: 4, tells: [], delivery: 58, deposit: 30, hoursLeft: 40 },
  { id: 'm2', name: 'Turbo', model: 'covet', ask: 120, condition: 90, seller: 'Lex', rating: 1, tells: ['new account', 'deposit by transfer only'], deposit: 10, hoursLeft: 5 } ] } }));
phone.act('home');
phone.act('open', 'market');
assert.ok(text().includes('Sport exhaust') && text().includes('1 on the way') && text().includes('deposit by transfer only'), 'Revline lists the ads, the tells and deliveries');
assert.ok(!phone.root.querySelector('[data-v="m2|delivery"]') && phone.root.querySelector('[data-v="m1|delivery"]'), 'no delivery offered on a scam-looking ad');
calls.length = 0;
click('mkoffer', 'm1|270');
click('mkbuy', 'm1|pickup');
assert.ok(calls.some(function (c) { return c.indexOf('marketOffer("m1",270)') >= 0; }) && calls.some(function (c) { return c.indexOf('marketBuy("m1","pickup")') >= 0; }), 'offer and pick up call the market');
// Valo Classifieds and Swap & Bid
phone.handle('slPhoneData', Object.assign({}, data, { market: { deliveries: 0, listings: [],
  paper: { bought: false, edition: 3, hidden: 4, price: 2, listings: [ { id: 'p1', name: 'Bucket seat', model: 'covet', ask: 90, condition: 60, seller: 'Rudi', rating: 3, tells: [], delivery: 45, deposit: 10, hoursLeft: 12 } ] },
  auctions: [ { id: 'a1', name: 'Turbo kit', model: 'covet', bid: 400, next: 420, high: 'ai', condition: 80, hoursLeft: 9, delivery: 64 },
    { id: 'a2', name: 'Rims', model: 'covet', bid: 200, next: 210, high: 'you', condition: 70, hoursLeft: 2, delivery: 52 } ] } }));
phone.act('home');
phone.act('open', 'paper');
assert.ok(text().includes('Edition 3') && text().includes('Bucket seat') && text().includes('4 more in the printed copy') && text().includes('Buy the paper'), 'the paper: ads, the print-only count, the buy button');
calls.length = 0;
click('buypaper', '1');
assert.ok(calls.some(function (c) { return c.indexOf('buyPaper()') >= 0; }), 'buying the paper calls the market');
phone.act('home');
phone.act('open', 'bid');
assert.ok(text().includes('Turbo kit') && text().includes('(outbid)') && text().includes('(your bid)') && !phone.root.querySelector('[data-a="mkbid"][data-v="a2"]'), 'auctions: outbid and your own bid, no bid button on your own');
calls.length = 0;
click('mkbid', 'a1');
assert.ok(calls.some(function (c) { return c.indexOf('marketBid("a1")') >= 0; }), 'a bid calls the market');
// T39: every ad has a picture (the car it fits, with a category icon underneath), the part real name, its chapter and the car it fits
phone.handle('slPhoneData', Object.assign({}, data, { market: { deliveries: 0, listings: [
  { id: 'q1', name: 'Sport exhaust', model: 'covet', ask: 300, condition: 72, seller: 'Kenny', rating: 4, tells: [], delivery: 58, deposit: 30, hoursLeft: 40,
    category: 'engine', categoryTitle: 'Engine', chapter: 'Exhaust systems', fits: 'Ibishu Covet', preview: '/vehicles/covet/13s_M.png' },
  { id: 'q2', name: 'Front bumper', model: 'pessima', ask: 120, condition: 60, seller: 'Lex', rating: 3, tells: [], deposit: 12, hoursLeft: 9,
    category: 'body', categoryTitle: 'Body', chapter: 'Front bumpers', fits: 'Ibishu Pessima' } ],
  paper: { bought: true, edition: 1, hidden: 0, price: 2, listings: [ { id: 'q3', name: 'Rims', model: 'covet', ask: 90, condition: 60, seller: 'Rudi', rating: 3, tells: [], deposit: 9, hoursLeft: 12,
    category: 'running', categoryTitle: 'Running gear', chapter: 'Front rims', fits: 'Ibishu Covet', preview: '/vehicles/covet/13s_M.png' } ] },
  auctions: [ { id: 'q4', name: 'Turbo kit', model: 'covet', bid: 400, next: 420, high: 'ai', condition: 80, hoursLeft: 9, delivery: 64,
    category: 'engine', categoryTitle: 'Engine', chapter: 'Turbos & superchargers', fits: 'Ibishu Covet', preview: '/vehicles/covet/13s_M.png' } ],
  meet: { open: true, here: false, place: 'Tuning shop lot', listings: [ { id: 'q5', name: 'Bucket seat', model: 'covet', ask: 80, condition: 70, seller: 'Zsofi', rating: 2, hoursLeft: 30,
    category: 'interior', categoryTitle: 'Interior', chapter: 'Seats', fits: 'Ibishu Covet' } ] },
  mine: [ { id: 'y1', name: 'Hood', model: 'covet', channel: 'app', offers: [], category: 'body', categoryTitle: 'Body', chapter: 'Hoods', fits: 'Ibishu Covet', preview: '/vehicles/covet/13s_M.png' } ],
  shelf: [ { model: 'covet', id: 7, name: 'Racing brakes', estimate: 200, category: 'running', categoryTitle: 'Running gear', chapter: 'Front brakes', fits: 'Ibishu Covet' } ],
  cars: [ { id: 3, name: 'Sunburst', estimate: 5200, category: 'car' } ] } }));
function cardWith(word) { return Array.prototype.filter.call(phone.root.querySelectorAll('.slp-card'), function (c) { return c.textContent.indexOf(word) >= 0; })[0]; }
phone.act('home');
phone.act('open', 'market');
var ad1 = cardWith('Sport exhaust');
assert.ok(ad1 && ad1.textContent.includes('Exhaust systems') && ad1.textContent.includes('fits the Ibishu Covet') && ad1.textContent.includes('Engine'), 'a part ad: its real name, the catalog chapter, the car it fits, the category');
assert.ok(ad1.querySelector('.slp-pic img[src="/vehicles/covet/13s_M.png"]') && ad1.querySelector('.slp-pic .slp-pico svg') && ad1.querySelector('.slp-pbadge svg') && ad1.querySelector('.slp-pic img').getAttribute('onerror'), 'the picture is the fitting car, over a category icon that shows when the picture does not load');
var ad2 = cardWith('Front bumper');
assert.ok(ad2 && !ad2.querySelector('img') && ad2.querySelector('.slp-pic .slp-pico svg') && !ad2.textContent.includes('no picture') && ad2.textContent.includes('Front bumpers'), 'a part ad without a picture shows the category icon and no broken image');
var mine = cardWith('Your Hood'), shelf = cardWith('Racing brakes'), mycar = cardWith('Sunburst');
assert.ok(mine && mine.querySelector('.slp-pic img') && shelf && shelf.querySelector('.slp-pic .slp-pico svg') && shelf.textContent.includes('Front brakes') && mycar && mycar.querySelector('.slp-pic .slp-pico svg'), 'your listings, your shelf parts and your cars have a picture too');
phone.act('home');
phone.act('open', 'paper');
assert.ok(cardWith('Rims').querySelector('.slp-pic .slp-pico svg') && text().includes('Front rims') && text().includes('fits the Ibishu Covet'), 'the paper ads have a picture and the part facts');
phone.act('home');
phone.act('open', 'bid');
var lot1 = cardWith('Turbo kit');
assert.ok(lot1 && lot1.querySelector('.slp-pic img') && lot1.textContent.includes('Turbos & superchargers') && lot1.textContent.includes('fits the Ibishu Covet'), 'Swap & Bid: the part name, its chapter, the car it fits and a picture');
var stall = cardWith('Bucket seat');
assert.ok(stall && stall.querySelector('.slp-pic .slp-pico svg') && stall.textContent.includes('Seats'), 'the swap meet stalls have a picture and the chapter');
// selling your own parts on Revline
phone.handle('slPhoneData', Object.assign({}, data, { market: { deliveries: 0, listings: [], auctions: [], paper: {},
  mine: [ { id: 'y1', name: 'Stock exhaust', model: 'covet', channel: 'app', offers: [ { index: 1, amount: 140, buyer: 'Kenny' } ] } ],
  shelf: [ { model: 'covet', id: 7, name: 'Stock radiator', estimate: 90 } ] } }));
phone.act('home');
phone.act('open', 'market');
assert.ok(text().includes('Your Stock exhaust') && text().includes('Accept $140') && text().includes('Stock radiator') && text().includes('Auction it'), 'Revline: your listings with offers, and your shelf to sell from');
calls.length = 0;
click('mklist', 'covet|7|auction');
click('mkaccept', 'y1|1');
click('mkwithdraw', 'y1');
assert.ok(calls.some(function (c) { return c.indexOf('listPart("covet",7,"auction")') >= 0; }) && calls.some(function (c) { return c.indexOf('acceptOffer("y1",1)') >= 0; }) &&
  calls.some(function (c) { return c.indexOf('withdrawListing("y1")') >= 0; }), 'list, accept and withdraw call the market');
// the weekend swap meet
phone.handle('slPhoneData', Object.assign({}, data, { market: { deliveries: 0, listings: [], auctions: [], paper: {},
  meet: { open: true, here: true, place: 'Tuning shop lot', listings: [ { id: 's1', name: 'Coilovers', model: 'covet', ask: 220, condition: 75, seller: 'Gabor' } ] } } }));
phone.act('home');
phone.act('open', 'bid');
assert.ok(text().includes('Swap meet today') && text().includes('Coilovers') && text().includes("Gabor's stall"), 'the swap meet stalls show on the weekend');
calls.length = 0;
click('mkmeet', 's1');
assert.ok(calls.some(function (c) { return c.indexOf('buyAtMeet("s1")') >= 0; }), 'buying at a stall calls the market');
// cars on Revline: a private car ad the way the stock shop lists a car (picture, year, specs, seller, distance, delivery), its detail view, and selling yours
phone.handle('slPhoneData', Object.assign({}, data, { market: { deliveries: 0, auctions: [], paper: {}, mine: [], shelf: [],
  listings: [ { id: 'c1', name: 'Covet 1.5', model: 'covet', car: true, mileage: 182000, faults: 2, ask: 2400, condition: 55, seller: 'Big Tony', rating: 4, tells: [], deposit: 240, hoursLeft: 30,
    year: 2009, brand: 'Ibishu', preview: '/vehicles/covet/13s_M.png', metres: 3100, hours: 4, delivery: 180, faultList: ['battery', 'exhaust'],
    specs: { power: 66, weight: 995, transmission: 'Manual', drivetrain: 'FWD', fuel: 'Gasoline', body: 'Hatchback', topSpeed: 42.5 } },
    { id: 'c2', name: 'Pessima', model: 'pessima', car: true, mileage: 1000, faults: 0, ask: 900, condition: 90, seller: 'Kenny', rating: 3, tells: [], deposit: 90, hoursLeft: 10 } ],
  cars: [ { id: 3, name: 'Sunburst', estimate: 5200 } ] } }));
phone.act('home');
phone.act('open', 'market');
assert.ok(text().includes('2009 Covet 1.5') && text().includes('Ibishu') && text().includes('182,000 km') && text().includes('Manual') && text().includes('FWD') && text().includes('66 PS') && text().includes('2 faults'), 'a car ad: year, name, brand, mileage, transmission, drivetrain, power');
assert.ok(text().includes('Big Tony') && text().includes('3.1 km away') && text().includes('delivered in about 4 h') && text().includes('$2,400'), 'seller, distance, delivery time, price');
assert.ok(phone.root.querySelector('.slp-pic img[src="/vehicles/covet/13s_M.png"]') && phone.root.querySelector('.slp-card .slp-pic .slp-pico svg') && phone.root.querySelector('[data-v="c1|delivery"]') && text().includes('List car'), 'the config\'s picture (a car without one shows its icon), a car can be delivered, your car to list');
click('adview', 'c1');
assert.ok(text().includes('2009 Covet 1.5') && text().includes('Gasoline') && text().includes('Hatchback') && text().includes('153 km/h') && text().includes('Needs') && text().includes('battery, exhaust') && text().includes('to your garage in about 4 h') && text().includes('Deposit (pick up)'), 'the detail view: every spec, the fault list, delivery and deposit');
calls.length = 0;
click('mkbuy', 'c1|delivery');
assert.ok(calls.some(function (c) { return c.indexOf('marketBuy("c1","delivery")') >= 0; }), 'a car can be bought for delivery from its detail view');
click('back');
assert.ok(text().includes('Pessima'), 'back to the list');
{
  // the used-car check: the ad tells the history; the faults stay hidden until a paid check, then the found faults and their costs show
  const base = phone.state.data;
  const withCheck = (extra) => Object.assign({}, base, { market: Object.assign({}, base.market, { listings: base.market.listings.map((x) => (x.id === 'c1' ? Object.assign({}, x, extra) : x)) }) });
  phone.handle('slPhoneData', withCheck({ history: ['3 owners', 'No service history', 'No accident'], hidden: true, checkFee: 60, checked: false, faults: undefined, faultList: undefined, report: undefined }));
  assert.ok(text().includes('3 owners') && text().includes('No service history') && text().includes('show after a mechanic'), 'the history and the hidden-faults note');
  assert.ok(phone.root.querySelector('[data-a="mkcheck"][data-v="c1"]') && text().includes('Check the car') && text().includes('$60'), 'the check button with its fee');
  calls.length = 0;
  click('mkcheck', 'c1');
  assert.ok(calls.some((c) => c.indexOf('marketCheck("c1")') >= 0), 'the button asks the game for marketCheck("c1")');
  phone.handle('slPhoneData', withCheck({ history: ['3 owners'], hidden: undefined, checked: true, found: [{ label: 'Battery', cost: 120 }] }));
  assert.ok(text().includes('The mechanic found') && text().includes('Battery') && text().includes('$120') && !phone.root.querySelector('[data-a="mkcheck"]'), 'after the check: the faults with their costs, no button');
  phone.handle('slPhoneData', withCheck({ history: ['3 owners'], hidden: undefined, checked: true, found: [] }));
  assert.ok(text().includes('found no faults'), 'a clean car says so');
  // the full car report of a CHECKED, fault-free car (rc2: "Show full car report" showed nothing): Lua sends its empty lists as {}, the history stays on the card, the panel opens
  const cleanRep = { condition: 90, label: 'Good', mileage: 42000, damage: { amount: 0, label: 'None' }, faults: {}, total: 0,
    sections: [{ id: 'engine', title: 'Engine', condition: 90, label: 'Good', estimate: 0, faults: {}, parts: [{ name: 'Block', condition: 90, label: 'Good' }] }, { id: 'body', title: 'Body', condition: 88, label: 'Good', estimate: 0, faults: {}, parts: [{ name: 'Hood', condition: 88, label: 'Good' }] }] };
  phone.handle('slPhoneData', withCheck({ history: ['3 owners', 'Full service history'], hidden: undefined, checked: true, found: {}, report: cleanRep }));
  assert.ok(text().includes('3 owners') && text().includes('Full service history') && phone.root.querySelector('[data-a="report"][data-v="ad:c1"]'), 'a checked clean car: the history and the report button are on the ad');
  click('report', 'ad:c1');
  assert.ok(phone.root.querySelector('.slp-repmodal') && text().includes('Car report') && text().includes('90% Good') && text().includes('42,000 km'), 'the report panel opens for a clean checked car: ' + text().slice(0, 200));
  assert.ok(text().includes('3 owners') && text().includes('Full service history') && text().includes('Nothing more to report'), 'the panel always shows the history lines, and says when there is nothing more to report');
  click('reportclose');
  phone.handle('slPhoneData', base);
}
calls.length = 0;
click('mkcar', '3');
assert.ok(calls.some(function (c) { return c.indexOf('listCar("3")') >= 0; }), 'listing a car calls the market');
phone.handle('slStation', { open: true, name: 'Pump', money: 100, fuels: [], items: [] });
assert.ok(phone.root.querySelector('.slp-lot') && !phone.root.querySelector('.slp-ico .slp-lot'), 'with SLRR icons the panels stay outside the phone (icon markup closed)');
// Turf: districts and crews
phone.handle('slPhoneData', Object.assign({}, data, { turf: { held: 1, turfWar: false, districts: [
  { id: 'd1', name: 'The Docks', owner: 'You', yours: true, control: 50, here: true },
  { id: 'd2', name: 'Northside', owner: 'the North End crew', control: 75, home: 'the North End crew' } ],
  crews: [{ name: 'the North End crew', leader: 'Nina' }] } }));
phone.act('home');
phone.act('open', 'turf');
assert.ok(text().includes('The Docks') && text().includes('you are here') && text().includes('home of the North End crew') && text().includes('led by Nina'), 'Turf lists districts and crews');
// #48 the last race's replay on the Races page
phone.handle('slPhoneData', Object.assign({}, data, { replay: { name: 'Quarry sprint', saved: false } }));
phone.act('home');
phone.act('open', 'races');
calls.length = 0;
assert.ok(text().includes('Last race') && text().includes('Quarry sprint') && text().includes('Watch replay') && text().includes('Save clip'), 'the last race can be watched and saved');
click('watchreplay', '1');
click('saveclip', '1');
assert.ok(calls.includes('watchReplay()') && calls.includes('saveClip()'), 'the buttons ask the replay module');
phone.handle('slPhoneData', Object.assign({}, data, { replay: { name: 'Quarry sprint', saved: true } }));
assert.ok(text().includes('saved') && !text().includes('Save clip'), 'a saved clip offers no second save');
phone.handle('slPhoneData', data);
phone.act('home');
phone.act('open', 'turf');

// #55 Help: topics, then a page; the pages come from Lua once
const helpPages = [{ id: 'first', title: 'Your first hour', body: ['Get a car.', '- Buy one', '- Fix it'] }, { id: 'heat', title: 'Heat and the police', body: ['Heat is 1 to 5.'] }];
phone.act('home');
calls.length = 0;
phone.act('open', 'help');
assert.ok(calls.includes('requestHelp()') && text().includes('Loading the help'), 'opening Help asks for the pages');
phone.handle('slHelp', { pages: helpPages });
assert.ok(text().includes('Your first hour') && text().includes('Heat and the police'), 'the topics');
click('helppage', 'first');
assert.ok(text().includes('Get a car.') && phone.root.querySelectorAll('li').length === 2 && text().includes('Buy one'), 'a page: its paragraphs and bullets');
phone.act('back');
assert.ok(text().includes('Heat and the police'), 'back goes to the topics');
phone.act('home');
phone.act('open', 'turf');

// #51 the player-facing text comes from the strings table: another text shows at once, a missing key keeps its fallback
phone.act('home');
phone.handle('slStrings', { text: { 'app.races': 'Rennen', 'app.wait': 'Warten {1}' } });
assert.ok(text().includes('Rennen') && text().includes('Warten') && text().includes('Jobs'), 'the table changes the apps it has a text for, the rest keep their words');
phone.handle('slStrings', { text: {} });
assert.ok(text().includes('Races') && !text().includes('Rennen'), 'and back');
phone.act('open', 'turf');

// #51 text size: the setting scales the text, and a pad makes it at least Large; low levels carry a warning mark
const zoomOf = () => Number(win.document.querySelector('[data-zoom]').getAttribute('data-zoom'));
const realNow = win.Date.now;
win.Date.now = () => realNow() + 300000;                // (the pad inputs of the tests above are old by now)
phone.handle('slPhoneData', Object.assign({}, data, { textScale: 1 }));
assert.strictEqual(zoomOf(), 1, 'normal text size: 1');
phone.handle('slPhoneData', Object.assign({}, data, { textScale: 1.5 }));
assert.strictEqual(zoomOf(), 1.5, 'huge text size: 1.5');
phone.handle('slPhoneData', Object.assign({}, data, { textScale: 1 }));
win.Date.now = realNow;
win.document.dispatchEvent(new win.CustomEvent('ui_nav', { detail: { name: 'tab_r', value: 1 } }));
phone.handle('slPhoneData', Object.assign({}, data, { textScale: 1 }));
assert.strictEqual(zoomOf(), 1.25, 'a pad in use: at least Large');
// #51 colour-blind friendly colours: the setting puts a class on the phone's layer (the CSS does the blue/orange palette and the tick, cross and arrow marks); the pad focus ring is in the CSS
const cbLayer = () => win.document.querySelector('[data-zoom]');
phone.handle('slPhoneData', Object.assign({}, data, { colorBlind: true }));
assert.ok(cbLayer().classList.contains('slp-cb'), 'colour-blind setting on: the phone layer has slp-cb');
phone.handle('slPhoneData', Object.assign({}, data, { colorBlind: false }));
assert.ok(!cbLayer().classList.contains('slp-cb'), 'and off again');
{ const css = [...win.document.querySelectorAll('style')].map((e) => e.textContent).join(' ');
  assert.ok(css.includes('.slp-cb .slp-plus:before') && css.includes('.slp-cb .slp-minus:before') && css.includes('#56b4e9') && css.includes('#ffb454'), 'colour-blind CSS: marks beside good and bad figures, blue and orange');
  assert.ok(css.includes('[bng-nav-item]:focus') && css.includes('outline:3px solid #ffd54f'), 'the pad focus ring is always visible'); }
phone.handle('slPhoneData', data);
phone.act('home');
phone.act('open', 'turf');
// #42 the turf map: a circle for every district at its place, coloured by its owner, and where you are
assert.ok(!phone.root.querySelector('.slp-turfmap'), 'no positions, no map');
phone.handle('slPhoneData', Object.assign({}, data, { turf: { held: 1, turfWar: false, you: { x: 100, y: 100 }, districts: [
  { id: 'd1', name: 'Belasco City', owner: 'You', yours: true, control: 50, here: true, x: 0, y: 0 },
  { id: 'd2', name: 'Alder Dragway', owner: 'Riverbed Runners', crew: 'riverbed', control: 75, x: 1000, y: 800 },
  { id: 'd3', name: 'Industrial', owner: 'Ring Road Ghosts', crew: 'ringroad', control: 40, x: -600, y: 500 } ], crews: [] } }));
const map = phone.root.querySelector('.slp-turfmap');
assert.ok(map && map.querySelectorAll('circle[fill-opacity]').length === 3 && map.textContent.includes('Belasco City') && map.textContent.includes('Alder Dragway') && map.innerHTML.includes('#009e73') && map.innerHTML.includes('#0072b2') && map.innerHTML.includes('#cc79a7') && map.textContent.includes('R') && map.textContent.includes('G') && map.textContent.includes('✓') && map.querySelectorAll('circle[fill="none"]').length === 1, 'the map: three districts in colour-blind-safe colours, each with its own mark, and you');

// Hardcore game over
phone.handle('slPhoneData', { active: false });
phone.handle('slGameOver', { day: 12, money: 4300, rep: 640, title: 'Known face', races: 20, wins: 9, pinksWon: 1, cars: 2, achievements: 5, achievementsTotal: 24 });
assert.ok(text().includes('Game over') && text().includes('day 12') && text().includes('5 of 24'), 'game over shows what the career came to');
calls.length = 0;
click('gameover', 'new');
assert.ok(calls.includes('@sl_menuTile.startFromMenu(true)') && !text().includes('Game over'), 'and starts a new one');
// the garage's kit (X58)
phone.handle('slPhoneData', Object.assign({}, data, { upgrades: [{ id: 'lift', name: 'Two-post lift', price: 3000, desc: 'Engine work', has: false }, { id: 'dyno', name: 'Dyno', price: 6000, desc: 'Curves', has: true }] }));
phone.act('home');
phone.act('open', 'garage');
assert.ok(!text().includes('Two-post lift'), 'My cars shows cars only: no garage upgrades');
phone.act('home');
phone.act('open', 'garagekit');
calls.length = 0;
click('upgrade', 'lift');
assert.ok(text().includes('Two-post lift') && text().includes('In the garage') && calls.some(function (c) { return c.indexOf('upgrade("lift")') >= 0; }), 'garage upgrades listed and bought');
// gamepad (X51): buttons are navigable while seen, focus survives a re-render, B goes back
phone.handle('slPhoneData', Object.assign({}, data, { jobs: { done: 0, earned: 0, offers: [ { id: 'g1', title: 'Courier', item: 'parcel', from: 'A', to: 'B', pay: 100, seconds: 60 } ] } }));
phone.act('home');
if (phone.root.querySelector('.slp-device.slp-away')) phone.handle('slPhoneToggle');
phone.act('open', 'jobs');
const take = phone.root.querySelector('[data-a="jobtake"]');
assert.ok(take && take.hasAttribute('bng-nav-item') && take.getAttribute('tabindex') === '0', 'a button on an open phone is a gamepad nav item');
assert.ok(phone.root.querySelector('.slp-body').hasAttribute('bng-nav-scroll'), 'the page scrolls on the right stick');
take.focus();
phone.handle('slPhoneData', Object.assign({}, data, { jobs: { done: 0, earned: 0, offers: [ { id: 'g1', title: 'Courier', item: 'parcel', from: 'A', to: 'B', pay: 100, seconds: 60 } ] } }));
assert.ok(win.document.activeElement && win.document.activeElement.getAttribute('data-a') === 'jobtake', 'the focus survives a re-render');
win.document.dispatchEvent(new win.CustomEvent('ui_nav', { detail: { name: 'back', value: 1 } }));
assert.ok(!text().includes('Courier: parcel'), 'B on the pad goes back from the app');
phone.handle('slPhoneToggle');
const away = phone.root.querySelector('.slp-device [data-a]');
assert.ok(!away || (away.getAttribute('bng-no-nav') === 'true' && !away.hasAttribute('bng-nav-item')), 'a phone put away takes no gamepad focus');
// B and the right stick on a lot opened without the phone (a pad player at a lot, a dealer, a meet)
calls.length = 0;
phone.handle('slLotData', { open: true, mode: 'browse', name: 'Jefferson Motors', kindTitle: 'New cars', kind: 'dealer', index: 1, count: 4, money: 9000, offer: { name: 'X', price: 5000, faults: [] } });
assert.ok(phone.root.querySelector('.slp-lot [data-a="lot"]').hasAttribute('bng-nav-item'), 'a lot button is a gamepad nav item with the phone away');
const nav = (name, value) => win.document.dispatchEvent(new win.CustomEvent('ui_nav', { detail: { name, value } }));
nav('rotate_h_cam', 1); nav('rotate_v_cam', -1); nav('zoom_in', 1);
assert.ok(calls.includes('@sl_lot.cameraDrag(10,0)') && calls.includes('@sl_lot.cameraDrag(0,-8)') && calls.includes('@sl_lot.cameraZoom(1)'), 'the stick turns the lot camera, a zoom button zooms');
nav('back', 1);
assert.ok(calls.includes('@sl_lot.close()'), 'B leaves the lot');
phone.handle('slLotData', { open: false });
// B68: closing the phone while an app is open: the next opening is the home screen
if (!phone.state.open) phone.handle('slPhoneToggle');
phone.act('open', 'partmarket');
assert.ok(text().includes('Revline'), 'an app is open');
phone.handle('slPhoneToggle');
phone.handle('slPhoneToggle');
assert.ok(phone.state.open && text().includes('Car market') && text().includes('Part market') && !text().includes('Swap & Bid'), 'closed and opened again: the home screen, not the app');
phone.act('home');
// the two marketplaces: cars (dealers + private ads), parts (Revline, Swap & Bid, the paper, the catalog)
phone.handle('slPhoneData', Object.assign({}, data, { market: { deliveries: 1, auctions: [{ id: 'a1', name: 'Coilovers', model: 'covet', bid: 100, next: 110, condition: 80, hoursLeft: 5, high: 'ai', delivery: 30 }], paper: { listings: [], edition: 2, price: 2 },
  mine: [{ id: 'y1', name: 'Stock exhaust', model: 'covet', channel: 'app', offers: [] }, { id: 'y2', name: 'My Sunburst', model: 'sunburst', channel: 'app', carId: 3, offers: [] }],
  shelf: [{ model: 'covet', id: 7, name: 'Stock radiator', estimate: 90 }], cars: [{ id: 3, name: 'Sunburst', estimate: 5200 }],
  listings: [
    { id: 'p1', name: 'Sport exhaust', model: 'covet', ask: 300, condition: 70, seller: 'Gabor', rating: 3, tells: [], deposit: 30, hoursLeft: 12, delivery: 20 },
    { id: 'c1', name: 'Covet 1.5', model: 'covet', car: true, mileage: 100, faults: 0, ask: 2400, condition: 55, seller: 'Big Tony', rating: 4, tells: [], deposit: 240, hoursLeft: 30, delivery: 180, year: 2009, specs: {} }] } }));
phone.act('home');
if (!phone.state.open) phone.handle('slPhoneToggle');
calls.length = 0;
phone.act('open', 'carmarket');
assert.ok(calls.includes('@sl_dealers.list()') && text().includes('Car market') && text().includes('Dealers') && text().includes('Private ads'), 'the Car market asks for the dealers and has the Dealers and Private ads tabs');
phone.handle('slLaptopDealers', { dealers: [{ id: 'jeff', name: 'Jefferson Motors', metres: 4200, count: 5 }], coming: [{ name: 'Covet', hours: 3 }] });
assert.ok(text().includes('Jefferson Motors') && text().includes('4.2 km away') && text().includes('5 cars today') && text().includes('in about 3 h'), 'dealers: name, distance, cars today, what is on its way');
click('mdealer', 'jeff');
assert.ok(calls.includes('@sl_dealers.offers("jeff")'), 'a dealer asks for its cars');
phone.handle('slLaptopOffers', { dealer: 'jeff', name: 'Jefferson Motors', money: 9000, offers: [{ id: 'jeff:1', name: 'Bolide', brand: 'Bruckell', year: 2012, mileage: 20, condition: 1, price: 7000, faults: [], seller: 'Jefferson Motors', metres: 4200, hours: 3,
  preview: '/vehicles/bolide/sport.png', specs: { power: 310, weight: 1250, transmission: 'Manual', drivetrain: 'RWD', fuel: 'Gasoline', topSpeed: 75 } }] });
assert.ok(text().includes('2012 Bolide') && text().includes('310 PS') && text().includes('arrives in about 3 h') && phone.root.querySelector('.slp-pic img[src="/vehicles/bolide/sport.png"]'), 'a dealer\'s car: picture, year, specs, delivery');
click('moffer', 'jeff:1');
assert.ok(text().includes('Gasoline') && text().includes('270 km/h') && text().includes('to your garage in about 3 h'), 'its detail view');
calls.length = 0;
click('mbuy', 'jeff|jeff:1');
assert.ok(calls.includes('@sl_dealers.buy("jeff","jeff:1")'), 'Buy asks the dealers');
win.document.dispatchEvent(new win.CustomEvent('ui_nav', { detail: { name: 'back', value: 1 } }));
assert.ok(text().includes('2012 Bolide') && !text().includes('Gasoline'), 'B goes back from the detail to the dealer\'s cars');
win.document.dispatchEvent(new win.CustomEvent('ui_nav', { detail: { name: 'back', value: 1 } }));
assert.ok(text().includes('Jefferson Motors') && text().includes('cars today'), 'and to the dealers');
click('mtab', 'cars|ads');
assert.ok(text().includes('Covet 1.5') && !text().includes('Sport exhaust') && text().includes('My Sunburst') && text().includes('List car') && !text().includes('Stock radiator'), 'Private ads: the car ads and your cars to sell, no parts');
// the car auctions tab: the lots, the bid / watch / sell buttons ask the game, the live view is switched on and off
calls.length = 0;
click('mtab', 'cars|auction');
assert.ok(calls.includes('@sl_carauctions.view(true)'), 'the auction tab tells the game a screen is watching the lots');
phone.handle('slAuctions', { money: 5000, lots: [
  { id: 'a1', name: 'Covet 1.5', grade: 'C', condition: 55, faults: ['brakes'], mileage: 120000, bid: 900, next: 950, high: 'ai', reserveMet: false, minutesLeft: 1500, delivery: 120, watched: false },
  { id: 'a2', name: 'Pickup', grade: 'A', condition: 90, faults: [], bid: 4000, next: 4200, high: 'you', reserveMet: true, minutesLeft: 45, delivery: 300, watched: true } ],
  mine: [{ id: 'm1', name: 'My Hopper', grade: 'B', condition: 75, faults: [], bid: 0, next: 300, reserve: 3500, reserveMet: false, minutesLeft: 600, mine: true }],
  sellable: [{ id: 7, name: 'Bluebuck', grade: 'D', fair: 2000 }] });
assert.ok(text().includes('Grade C') && text().includes('Reserve not met') && text().includes('Outbid') && text().includes('1 d 1 h') && text().includes('You are the highest bidder') && text().includes('Reserve met') && text().includes('45 min'), 'the phone shows grade, reserve state, leader and time left');
assert.ok(text().includes('Your reserve $3,500') && text().includes('Bluebuck') && text().includes('Reserve 80%'), 'your own lot and the cars you can put up');
click('abid', 'a1|950');
assert.ok(calls.includes('@sl_carauctions.bid("a1",950)'), 'Bid asks the game');
click('awatch', 'a1|1');
assert.ok(calls.includes('@sl_carauctions.watch("a1",true)'), 'Watch asks the game');
click('asell', '7|1600');
phone.handle('slAuctions', { money: 5000, lots: [], mine: [], sellable: [], live: { index: 2, total: 6, waiting: false, lot: { id: 'y12_2', name: 'Live Hopper', grade: 'B', condition: 75, faults: [], bid: 1200, next: 1260, high: 'ai', reserveMet: true, live: true, secondsLeft: 40, delivery: 0 } } });
assert.ok(text().includes('Live at the yard: lot 2 of 6') && text().includes('Live Hopper') && text().includes('Going in 40 s'), 'the live lot of the yard auction shows with its seconds left');
click('abid', 'y12_2|1260');
assert.ok(calls.includes('@sl_carauctions.bid("y12_2",1260)'), 'a live lot is bid on the same way');
assert.ok(calls.includes('@sl_carauctions.sell(7,1600)'), 'Sell at auction sends the car and the reserve');
// the yard's own screen: the bidding bar on the lot, with the live lot's card
phone.handle('slLotData', { open: true, mode: 'auction', name: 'Junkyard', kindTitle: 'Used cars', index: 2, count: 6, money: 5000, auction: { index: 2, total: 6, waiting: false, money: 5000,
  lot: { id: 'y12_2', name: 'Live Hopper', grade: 'B', condition: 75, bid: 1200, next: 1260, high: 'ai', reserveMet: true, live: true, secondsLeft: 33, report: null } } });
assert.ok(text().includes('Car auction') && text().includes('Lot 2 of 6') && text().includes('Live Hopper') && text().includes('Going in 33 s') && text().includes('Bid $1,260') && text().includes('Leave'), 'the yard shows the bidding bar on the lot screen');
click('abid', 'y12_2|1260');
assert.ok(calls.includes('@sl_carauctions.bid("y12_2",1260)'), 'the bar bids on the live lot');
phone.handle('slLotData', { open: false });
phone.act('home');
assert.ok(calls.includes('@sl_carauctions.view(false)'), 'home stops the live view');
phone.act('open', 'carmarket');
phone.act('home');
phone.act('open', 'partmarket');
assert.ok(text().includes('Revline') && text().includes('Swap & Bid') && text().includes('Classifieds') && text().includes('Catalog') && text().includes('Sport exhaust') && !text().includes('Covet 1.5'), 'the Part market: Revline parts, no car ads');
assert.ok(text().includes('Stock radiator') && text().includes('Stock exhaust') && !text().includes('My Sunburst'), 'and the parts to sell, your parts listings only');
click('mtab', 'parts|auctions');
assert.ok(text().includes('Coilovers') && text().includes('Bid $110'), 'Swap & Bid');
click('mtab', 'parts|paper');
assert.ok(text().includes('Edition 2'), 'the paper');
click('mtab', 'parts|catalog');
calls.length = 0;
click('pcatalog', '1');
assert.ok(text().includes('Wrench Works catalog') && calls.includes('catalog()'), 'the Wrench Works catalog opens in the garage');
phone.act('home');
// on foot in a garage's doorway: the cars panel (take out, work on, put away), reachable by the pad, B leaves it
phone.act('home');
if (phone.state.open) phone.handle('slPhoneToggle');      // (the phone is in the pocket: the panel opens without it)
phone.handle('slPhoneData', Object.assign({}, data, { fleet: [
  { id: 1, name: 'Sunburst', where: 'Out on the street', out: true, active: true, condition: 0.8, faults: [] },
  { id: 2, name: 'Covet', where: 'In the garage', out: false, condition: 0.5, faults: [] },
  { id: 3, name: 'Pessima', where: 'In the garage', out: false, impounded: 300, condition: 0.4, faults: [] }] }));
phone.handle('slLotData', { open: false }); phone.handle('slStation', { open: false });
phone.handle('slGarage', { open: true, name: 'Club Garage 1' });
assert.ok(phone.root.querySelector('.slp-lot') && text().includes('Club Garage 1') && text().includes('Your cars'), 'the doorway shows a cars panel');
assert.ok(text().includes('Work on it') && text().includes('Take out and work on it') && text().includes('Put away') && text().includes('Impounded'), 'work on one that is out, take out a stored one, put one away, an impounded one is marked');
assert.ok(phone.root.querySelector('.slp-lot [data-a="workon"]').hasAttribute('bng-nav-item'), 'the buttons are gamepad nav items with the phone away');
calls.length = 0;
click('despawn', '1');
click('workon', '2');
assert.ok(calls.includes('despawn(1)') && calls.includes('workOn(2)'), 'put away and work on call the career');
phone.handle('slGarage', { open: true, name: 'Club Garage 1' });
calls.length = 0;
win.document.dispatchEvent(new win.CustomEvent('ui_nav', { detail: { name: 'back', value: 1 } }));
assert.ok(calls.includes('closeGarage()') && !phone.root.querySelector('.slp-lot'), 'B leaves the panel');
// a car that is out can be put away from My cars
phone.handle('slPhoneToggle');
phone.act('open', 'garage');
assert.ok(phone.root.querySelector('[data-a="despawn"][data-v="1"]') && !phone.root.querySelector('[data-a="despawn"][data-v="2"]'), 'My cars: Put it away for a car that is out only');
phone.act('home');
// (no Settings app on the phone: every setting is in the pause menu's Mods menu)
assert.ok(!phone.root.querySelector('[data-a="open"][data-v="settings"]'), 'the phone has no Settings app');
phone.act('home');
// a fade is plain black: no SLRR loading picture, whatever the game sends
phone.handle('slFade', { on: true, pic: 'loading_city.png' });
assert.ok(phone.root.querySelector('.slp-fade.slp-in') && !(phone.root.querySelector('.slp-fade').getAttribute('style') || '').includes('url('), 'a fade has no picture');
phone.handle('slFade', { on: false });
// Camera and Gallery: the camera asks for a photo, the gallery lists the photos (the wallpapers marked), a photo sets the wallpapers
phone.act('home');
if (!phone.state.open) phone.handle('slPhoneToggle');
calls.length = 0;
phone.act('open', 'camera');
click('photo');
assert.ok(calls.includes('takePhoto()'), 'the camera button takes a photo');
phone.act('home');
phone.act('open', 'gallery');
assert.ok(calls.includes('photos()'), 'opening the Gallery asks for the photos');
assert.ok(/No photos yet/.test(phone.root.textContent), 'an empty gallery says so');
phone.handle('slPhotos', { photos: [{ file: '/settings/street_legal/photos/20261018_a.png', name: 'a' }, { file: '/settings/street_legal/photos/20261018_b.png', name: 'b' }], phone: '/settings/street_legal/photos/20261018_b.png' });
assert.strictEqual(phone.root.querySelectorAll('.slp-ph').length, 2, 'two thumbnails');
assert.strictEqual(phone.root.querySelectorAll('.slp-ph.slp-on').length, 1, 'the phone wallpaper is marked');
calls.length = 0;
click('photoopen', '/settings/street_legal/photos/20261018_a.png');
click('setwall', 'laptop|/settings/street_legal/photos/20261018_a.png');
click('setwall', 'phone|/settings/street_legal/photos/20261018_a.png');
click('setwall', 'both|');
assert.ok(calls.includes('setWallpaper("laptop","/settings/street_legal/photos/20261018_a.png")') && calls.includes('setWallpaper("phone","/settings/street_legal/photos/20261018_a.png")') && calls.includes('setWallpaper("both","")'), 'the wallpaper buttons');
phone.act('home');
phone.handle('slPhoneData', Object.assign({}, data, { wall: '/settings/street_legal/photos/20261018_a.png' }));
assert.ok(/20261018_a\.png/.test(phone.root.querySelector('.slp-wall').getAttribute('style') || ''), 'a photo wallpaper is the home screen');
// Contacts: the people you have met, a rival is listed once, Route to
phone.act('home');
if (!phone.state.open) phone.handle('slPhoneToggle');
calls.length = 0;
phone.act('open', 'contacts');
assert.ok(calls.includes('people()'), 'opening Contacts asks for the people');
phone.handle('slPeople', { people: [{ id: 'r01', name: 'Rival One', kind: 'rival', line: 'Nemesis - Ring Road Ghosts', placeId: 'g1' }, { id: 'dealer:d1', name: 'Hilltop Motors', kind: 'dealer', line: 'Dealer - High', placeId: 'd1' }, { id: 'r09', name: 'Boss', kind: 'crew', line: 'Leader of X' }] });
assert.ok(/People you have met/.test(phone.root.textContent) && /Nemesis - Ring Road Ghosts/.test(phone.root.textContent), 'the people section');
assert.strictEqual(phone.root.querySelectorAll('[data-a="route"]').length, 2, 'Route to only where the place is known');
assert.strictEqual(Array.from(phone.root.querySelectorAll('[data-a="contact"] b')).filter((e) => e.textContent === 'Rival One').length, 1, 'a rival is listed once in Contacts');
calls.length = 0;
click('route', 'd1');
assert.ok(calls.includes('routeTo("d1")'), 'Route to sets the route');
// the tyres of a car: a diagram with four tyres and a line per axle (sl_tyrecare.card); the Swap tyres panel at a meet
phone.act('home');
if (!phone.state.open) phone.handle('slPhoneToggle');
const tyreCard = { compound: 'road', replace: false, rows: [{ idx: 0, axle: 'front', side: 'left', frac: 0.9, stage: 'new', flat: false, blown: false }, { idx: 1, axle: 'front', side: 'right', frac: 0.5, stage: 'good', flat: true, blown: false },
  { idx: 2, axle: 'rear', side: 'left', frac: 0.1, stage: 'low', flat: false, blown: false }, { idx: 3, axle: 'rear', side: 'right', frac: 0, stage: 'blown', flat: false, blown: true }],
  axles: [{ axle: 'front', compound: 'road', frac: 0.5, stage: 'good', flat: true, replace: false }, { axle: 'rear', compound: 'road', frac: 0, stage: 'blown', flat: false, replace: true }],
  offers: [{ id: 'road', price: 0, current: false }, { id: 'slick', price: 640, current: false }, { id: 'performance', price: 420, current: true }] };
phone.handle('slPhoneData', Object.assign({}, phone.state.data, { active: true, fleet: [{ id: 7, name: 'Covet', where: 'Out on the street', seated: true, out: true, condition: 0.9, care: { battery: 0.9, oilLevel: 0.9, coolantLevel: 0.9, fuelLevel: 0.5, fuel: 'Regular', engineKm: 100, performance: 1, history: {} }, tyres: tyreCard }] }));
phone.act('open', 'garage');
assert.ok(phone.root.querySelectorAll('.slp-tyrecar rect[fill="#4caf7d"]').length === 1 && /Tyres/.test(phone.root.textContent), 'the tyre diagram with a coloured tyre');
assert.ok(/Front/.test(phone.root.textContent) && /Rear/.test(phone.root.textContent) && /50% tread/.test(phone.root.textContent) && /flat spot/.test(phone.root.textContent) && /blown/.test(phone.root.textContent), 'a line per axle with the tread, the stage and the flags');
assert.ok(/Tyre changes: at a garage or a track/.test(phone.root.textContent) && !phone.root.querySelector('[data-a="tyreswap"]'), 'away from a track the card says where tyre changes are');
tyreCard.swapAt = 'Pier';
phone.handle('slPhoneData', Object.assign({}, phone.state.data, { fleet: [{ id: 7, name: 'Covet', where: 'Out on the street', seated: true, out: true, condition: 0.9, care: { history: {} }, tyres: tyreCard }] }));
assert.ok(phone.root.querySelectorAll('[data-a="tyreswap"]').length === 2 && /Swap tyres/.test(phone.root.textContent), 'at a track or a meet place My cars offers the swap');
delete tyreCard.swapAt;
phone.handle('slPhoneData', Object.assign({}, phone.state.data, { fleet: [{ id: 9, name: 'Nameless', seated: true, out: true, condition: 1, care: { history: {} }, tyres: { compound: 'road', rows: [{ idx: 0, frac: 0.8, stage: 'new' }, { idx: 3, frac: 0.2, stage: 'worn' }], axles: [] } }] }));
assert.ok(phone.root.querySelectorAll('.slp-tyrecar rect[fill="#4caf7d"]').length === 1 && !/undefined|null|NaN/.test(phone.root.querySelector('.slp-tyres').textContent), 'a wheel without an axle or a side is drawn by its number');
phone.handle('slPhoneData', Object.assign({}, phone.state.data, { fleet: [{ id: 10, name: 'Hubs', seated: true, out: true, condition: 1, care: { history: {} }, tyres: { tracked: false, reason: 'no_tyres' } }] }));
assert.ok(/No tyres fitted/.test(phone.root.textContent) && !phone.root.querySelector('.slp-tyrecar') && !phone.root.querySelector('[data-a="tyreswap"]') && !/Tyre changes: at a garage/.test(phone.root.textContent), 'a car on bare rims says so, with no diagram and no swap');
calls.length = 0;
click('pcatalog', '1');
assert.ok(calls.includes('catalog()') || calls.some((c) => /catalog/.test(c)), 'Fit tyres opens the catalog');
phone.handle('slPhoneData', Object.assign({}, phone.state.data, { fleet: [{ id: 8, name: 'Other', where: 'Garage', condition: 1, care: { history: {} } }] }));
assert.ok(!phone.root.querySelector('.slp-tyrecar'), 'a car without tyre data shows no tyres');
{
  // the service card (sl_service.serviceOf): due or not, the wear factor, the sections, the two services; nothing when the part is off or no card came
  const car = (extra) => ({ id: 8, name: 'Other', where: 'Garage', condition: 1, care: { history: {} }, service: Object.assign({ due: true, km_since: 6200, km_interval: 5000, wearFactor: 1.4, count: 1,
    sections: [{ id: 'engine', label: 'Engine', condition: 0.3 }, { id: 'brakes', label: 'Brakes', condition: 0.8 }],
    options: [{ id: 'basic', label: 'Basic service', cost: 120, available: true, why: '' }, { id: 'full', label: 'Full overhaul', cost: 900, available: false, why: 'needs a workbench garage' }] }, extra) });
  phone.handle('slPhoneData', Object.assign({}, phone.state.data, { fleet: [car()] }));
  let t = phone.root.textContent;
  assert.ok(t.includes('Service due') && t.includes('6200 km since the last service (every 5000 km)') && t.includes('parts wear 1.4 times as fast'), 'due, the km and the wear factor: ' + t.slice(0, 300));
  assert.ok(t.includes('Engine') && t.includes('30%') && t.includes('Brakes') && t.includes('80%') && phone.root.querySelector('.slp-warn'), 'the sections, the low one marked');
  assert.ok(phone.root.querySelector('[data-a="service"][data-v="8|basic"]') && !phone.root.querySelector('[data-a="service"][data-v="8|full"]') && t.includes('$900'), 'an available service has a button, an unavailable one is shown without');
  const sb = phone.root.querySelector('[data-a="service"][data-v="8|basic"]');
  const lbl = sb.querySelector('.slp-lbl');
  assert.ok(sb.classList.contains('slp-stack') && lbl && lbl.textContent === 'Basic service' && sb.querySelector('small') && sb.querySelector('small').textContent.includes('$120') && !sb.querySelector('br'), 'a service button: the label in its own node, the note under it, no line break between flex items');
  const cssAll = [...win.document.querySelectorAll('style')].map((x) => x.textContent).join('');
  assert.ok(/\.slp-btn\.slp-stack\{flex-direction:column;height:auto/.test(cssAll), 'the stacked button CSS: a column as tall as it needs (not a 40 px pill)');
  assert.ok(!/class="slp-btn[^"]*"[^>]*>[^<]*<br><small>/.test(code), 'no button puts a line break and a note between flex items any more');
  calls.length = 0;
  click('service', '8|basic');
  assert.ok(calls.includes('service(8,"basic")'), 'the button asks the game for service(8,"basic"): ' + calls.join(' '));
  phone.handle('slPhoneData', Object.assign({}, phone.state.data, { fleet: [car({ due: false, wearFactor: 1 })] }));
  t = phone.root.textContent;
  assert.ok(!t.includes('Service due') && !t.includes('times as fast') && t.includes('Service'), 'not due: no warning');
  phone.handle('slPhoneData', Object.assign({}, phone.state.data, { fleet: [car()], has: Object.assign({}, phone.state.data.has, { service: false }) }));
  assert.ok(!phone.root.textContent.includes('since the last service'), 'the part switched off: no card');
  phone.handle('slPhoneData', Object.assign({}, phone.state.data, { fleet: [{ id: 8, name: 'Other', where: 'Garage', condition: 1, care: { history: {} } }], has: Object.assign({}, phone.state.data.has, { service: true }) }));
  assert.ok(!phone.root.textContent.includes('since the last service'), 'no card from the game: nothing shown');
}
phone.handle('slPhoneData', Object.assign({}, phone.state.data, { fleet: [{ id: 7, name: 'Covet', seated: true, out: true, condition: 0.9, tyres: tyreCard }] }));
phone.handle('slMeet', { open: true, name: 'Pier', owners: [], racers: [], money: 1000 });
assert.ok(/Swap tyres/.test(phone.root.textContent) && phone.root.querySelectorAll('[data-a="tyreswap"]').length === 2 && !phone.root.querySelector('[data-a="tyreswap"][data-v="performance"]'), 'the meet offers the other sets, not the one on the car');
assert.ok(/\$640/.test(phone.root.textContent), 'with the price');
calls.length = 0;
click('tyreswap', 'slick');
assert.ok(calls.includes('@sl_tyrecare.swap("slick")'), 'a tap swaps the tyres through sl_tyrecare');
phone.handle('slMeet', { open: false });
// Map: groups with distances, a tap sets the route, the home shortcut, clear route
phone.act('home');
if (!phone.state.open) phone.handle('slPhoneToggle');
calls.length = 0;
phone.act('open', 'map');
assert.ok(calls.includes('mapPlaces()'), 'opening the Map asks for the places');
assert.ok(phone.root.querySelector('.slp-mapcv') && calls.includes('@sl_mapsfeed.use("phone", true)'), 'the Map opens on the live map and turns the feed on');
assert.ok(phone.root.querySelector('.slp-device.slp-land'), 'the Map tab turns the phone to landscape');
calls.length = 0;
click('mtab', 'map|list');
assert.ok(calls.includes('@sl_mapsfeed.use("phone", false)') && !phone.root.querySelector('.slp-mapcv'), 'the List tab turns the feed off');
assert.ok(phone.root.querySelector('[data-a="mtab"]'), 'the List tab keeps the tab bar, so the Map tab can be reached again');
assert.ok(!phone.root.querySelector('.slp-device.slp-land'), 'the List tab is portrait again');
assert.ok(/no places yet/.test(phone.root.textContent), 'an empty map says so');
phone.handle('slMap', { groups: [{ kind: 'garage', places: [{ id: 'g1', name: 'Home', dist: 120 }] }, { kind: 'meet', places: [{ id: 'm1', name: 'Pier meet', dist: 2300 }, { id: 'm2', name: 'Far meet' }] }], route: null });
assert.strictEqual(phone.root.querySelectorAll('[data-a="route"]').length, 3, 'a row for each place');
assert.ok(/120 m/.test(phone.root.textContent) && /2\.3 km/.test(phone.root.textContent), 'distances in m and km');
assert.ok(Array.from(phone.root.querySelectorAll('.slp-seth')).map((e) => e.textContent).join() === 'Garages,Car meets', 'grouped by kind');
assert.ok(!phone.root.querySelector('[data-a="clearroute"]'), 'no Clear route without a route');
calls.length = 0;
click('route', 'm1');
assert.ok(calls.includes('routeTo("m1")'), 'tapping a place sets the route');
phone.handle('slMap', { groups: [{ kind: 'garage', places: [{ id: 'g1', name: 'Home', dist: 120 }] }], route: { id: 'g1', name: 'Home' } });
assert.ok(phone.root.querySelector('[data-a="clearroute"]') && /Route: Home/.test(phone.root.textContent), 'the route and Clear route');
click('clearroute', '1');
assert.ok(calls.includes('clearRoute()'), 'Clear route');
phone.act('home');
calls.length = 0;
click('routegarage', '1');
assert.ok(calls.includes('routeGarage()'), 'Route to my garage on the home screen');
{
  // the speed traps and zones (sl_traps.summary()): nearest first, target, best (met = marked), times, reward or Paid; nothing with the part off or no data
  const traps = { list: [{ id: 't2', name: 'Speed trap 2', kind: 'trap', target: 150, best: 182, count: 3, paid: true, metres: 4200, pay: 250 }, { id: 'z1', name: 'Speed zone 1', kind: 'zone', target: 90, best: 0, count: 0, paid: false, metres: 800, pay: 400 }] };
  phone.handle('slPhoneData', Object.assign({}, data, { traps }));
  phone.act('home');
  assert.ok(phone.root.querySelector('[data-a="open"][data-v="traps"]'), 'the Speed traps app is on the home screen');
  phone.act('open', 'traps');
  const tx = text();
  assert.ok(tx.includes('Speed zone 1') && tx.includes('Speed trap 2') && tx.indexOf('Speed zone 1') < tx.indexOf('Speed trap 2'), 'the nearest first');
  assert.ok(tx.includes('150 km/h') && tx.includes('182 km/h') && tx.includes('\u2714') && tx.includes('Paid') && tx.includes('$400') && tx.includes('800 m away') && tx.includes('4.2 km away') && tx.includes('Zone') && tx.includes('Trap'), 'target, best with the met mark, paid or the reward, distance, kind: ' + tx.slice(0, 300));
  phone.handle('slPhoneData', Object.assign({}, data, { traps: { list: [] } }));
  assert.ok(text().includes('No traps on this map yet.'), 'an empty list says so');
  phone.act('home');
  phone.handle('slPhoneData', Object.assign({}, data, { traps, has: Object.assign({}, data.has, { traps: false }) }));
  assert.ok(!phone.root.querySelector('[data-a="open"][data-v="traps"]'), 'the part off: no app');
  phone.handle('slPhoneData', data);
  assert.ok(!phone.root.querySelector('[data-a="open"][data-v="traps"]'), 'no data: no app');
}
{
  // the danger zones (sl_danger.summary()) share the Speed traps page: the jump ladder card and the drift zones; the page works with one of them, both, or none
  const danger = { drift: [{ id: 'd1', name: 'Drift zone 1', target: 3000, best: 3500, count: 2, paid: true, metres: 5200, pay: 300 }, { id: 'd2', name: 'Drift zone 2', target: 5000, best: 0, count: 0, paid: false, metres: 900, pay: 500 }], jump: { best: 38.4, count: 5, next: 50, prize: 400 } };
  phone.handle('slPhoneData', Object.assign({}, data, { danger }));
  phone.act('home');
  assert.ok(phone.root.querySelector('[data-a="open"][data-v="traps"]'), 'the app shows with danger data alone');
  phone.act('open', 'traps');
  let tx = text();
  assert.ok(tx.includes('Danger zones') && tx.includes('Longest jump') && tx.includes('38 m') && tx.includes('Next prize $400 at 50 m'), 'the jump card: ' + tx.slice(0, 300));
  assert.ok(tx.indexOf('Drift zone 2') < tx.indexOf('Drift zone 1') && tx.includes('3000 points') && tx.includes('\u2714') && tx.includes('$500') && tx.includes('Paid') && tx.includes('900 m away'), 'the drift zones, nearest first, with target, met mark, reward or Paid, distance');
  phone.handle('slPhoneData', Object.assign({}, data, { danger: { drift: [], jump: { best: 60, count: 9, next: null, prize: 400 } } }));
  assert.ok(text().includes('Every prize is paid'), 'all four rungs paid');
  phone.handle('slPhoneData', Object.assign({}, data, { danger, traps: { list: [{ id: 't1', name: 'Speed trap 1', kind: 'trap', target: 150, best: 0, count: 0, paid: false, metres: 100, pay: 250 }] } }));
  tx = text();
  assert.ok(tx.includes('Speed trap 1') && tx.includes('Danger zones') && tx.includes('Drift zone 1'), 'both on one page');
  phone.handle('slPhoneData', Object.assign({}, data, { danger, has: Object.assign({}, data.has, { danger: false }) }));
  assert.ok(!phone.root.querySelector('[data-a="open"][data-v="traps"]'), 'the part off: no app');
  phone.handle('slPhoneData', data);
}
{
  // the UI style kit: Reduce motion (option slReduceMotion, data.reduceMotion) and the focus band
  const layer = () => phone.root.querySelector('.slp-layer') || phone.root;
  phone.handle('slPhoneData', Object.assign({}, data, { reduceMotion: true }));
  assert.ok(phone.root.classList.contains('slp-rm') || phone.root.querySelector('.slp-rm'), 'Reduce motion puts the slp-rm class on the phone');
  phone.handle('slPhoneData', Object.assign({}, data, { reduceMotion: false }));
  assert.ok(!phone.root.classList.contains('slp-rm') && !phone.root.querySelector('.slp-rm'), 'and takes it off');
  const css = win.document.querySelector('style').textContent;
  assert.ok(/\.slp-rm \.slp-device,\.slp-rm \*[^}]*transition:none!important;animation:none!important/.test(css) && /prefers-reduced-motion:reduce\)\{.*\.slp-root \*,\.slp-root \*:before/.test(css), 'both the option and the system setting stop every transition and animation');
  assert.ok(/outline:3px solid #ffd54f!important;outline-offset:2px;box-shadow:0 0 0 2px #0d0b12/.test(css), 'the focus ring is 3 px with a dark band');
  assert.ok(/reduceMotion\)\) return null/.test(code), 'with Reduce motion the K slide is the plain open and close');
}
{
  // brand sponsorships (sl_sponsor.summary()): the offer with Accept / Decline, the deal with its terms and strikes, the standing bars; nothing with the part off or no data
  const sponsors = { current: { brand: 'ironline', name: 'Ironline Racing', kind: 'maker', since: 30, retainer: 300, discount: 0.1, terms: { wins: 2, car: true }, weekWins: 1, carRaces: 3, strikes: 1, daysToReview: 4 },
    offer: { brand: 'revline', name: 'Revline Parts', retainer: 450, discount: 0.15, terms: { wins: 2 }, expiresIn: 2 },
    standing: [{ brand: 'ironline', name: 'Ironline Racing', kind: 'maker', standing: 72, nextAt: 100 }, { brand: 'revline', name: 'Revline Parts', kind: 'aftermarket', standing: 40, nextAt: 100 }] };
  phone.handle('slPhoneData', Object.assign({}, data, { sponsors }));
  phone.act('home');
  assert.strictEqual(phone.root.querySelector('[data-a="open"][data-v="sponsors"] .slp-badge').textContent, '1', 'the Sponsors app shows a badge for an offer');
  phone.act('open', 'sponsors');
  let tx = text();
  assert.ok(tx.includes('Offer: Revline Parts') && tx.includes('$450 a week') && tx.includes('15 %') && tx.includes('Win 2 races a week') && tx.includes('Expires in 2 d'), 'the offer: ' + tx.slice(0, 300));
  assert.ok(phone.root.querySelector('[data-a="spnaccept"]') && phone.root.querySelector('[data-a="spndecline"]'), 'Accept and Decline');
  assert.ok(tx.includes('Ironline Racing') && tx.includes('Maker') && tx.includes('$300 a week') && tx.includes('10 %') && tx.includes('Win 2 races a week (1 of 2)') && tx.includes('Race in a car with their parts (3)'), 'the deal with this week\u2019s progress');
  assert.ok(tx.includes('\u26A0 1 / 2') && tx.includes('Review in 4 d'), 'strikes with a mark, and the review');
  assert.ok(tx.includes('72 / 100') && tx.includes('40 / 100') && tx.includes('Brands that know you'), 'the standing list');
  calls.length = 0;
  click('spnaccept', '1'); click('spndecline', '1'); click('spnquit', '1');
  assert.ok(!calls.includes('sponsorQuit()') && text().includes('Leave Ironline Racing? You will not get the old sponsor back'), 'the first press only asks, in plain words');
  click('spnquit', '0'); assert.ok(!text().includes('You will not get'), 'Cancel closes the question');
  click('spnquit', '1'); click('spnquit', '1');
  assert.ok(calls.includes('sponsorAccept()') && calls.includes('sponsorDecline()') && calls.includes('sponsorQuit()'), 'the three actions: ' + calls.join(' '));
  phone.handle('slPhoneData', Object.assign({}, data, { sponsors: { current: null, offer: null, standing: [] } }));
  assert.ok(text().includes('No sponsor yet'), 'no deal, no offer: it says so');
  phone.act('home');
  assert.ok(!phone.root.querySelector('[data-a="open"][data-v="sponsors"] .slp-badge'), 'no badge without an offer');
  phone.handle('slPhoneData', Object.assign({}, data, { sponsors, has: Object.assign({}, data.has, { sponsors: false }) }));
  assert.ok(!phone.root.querySelector('[data-a="open"][data-v="sponsors"]'), 'the part off: no app');
  phone.handle('slPhoneData', data);
  assert.ok(!phone.root.querySelector('[data-a="open"][data-v="sponsors"]'), 'no data: no app');
}
{
  // the Calendar app (sl_calendar.summary(), tools/calendar_fixture.js is the contract): tabs, the agenda with its cards, the week strip, the series, the event page and its actions
  const fixture = require('./calendar_fixture.js');
  phone.handle('slPhoneData', Object.assign({}, data, { calendar: fixture }));
  phone.act('home');
  assert.ok(phone.root.querySelector('[data-a="open"][data-v="calendar"]'), 'the Calendar app is on the home screen');
  assert.strictEqual(phone.root.querySelector('[data-a="open"][data-v="calendar"] .slp-badge').textContent, '1', 'its badge is the open invitations');
  phone.act('open', 'calendar');
  let tx = text();
  assert.ok(tx.includes('Agenda') && tx.includes('Week') && tx.includes('Series'), 'three tabs');
  assert.ok(tx.includes('Benny') && tx.includes('Bring a car for gravel') && tx.includes('Expires in 2 d'), 'the invitation on top');
  assert.ok(tx.indexOf('Johnson Valley off-road, round 2') < tx.indexOf('Dockyards night heat') && tx.indexOf('Dockyards night heat') < tx.indexOf('NGRC Utah Rally: SS1 River'), 'events in day order');
  assert.ok(tx.includes('Tomorrow 15:00') && tx.includes('Dockyards 3-lap sprint'), 'when: Tomorrow with the time: ' + tx.slice(0, 500));
  assert.ok(/Sun, day 42 08:00/.test(tx) || /Sat, day 42 08:00/.test(tx) || /day 42 08:00/.test(tx), 'a weekday and the day number: ' + tx.slice(0, 500));
  assert.ok(tx.includes('Travel to Utah: $800 and 6 h') && tx.includes('round 1 of 4') && tx.includes('Purse by place, up to $3,000') && tx.includes('$800'), 'travel, round, reward as text and as money');
  assert.ok(tx.includes('A gravel or rally car') && tx.includes('\u26A0'), 'an unmet requirement is marked');
  assert.ok(tx.includes('Entered') && tx.includes('Done') && tx.includes('Missed'), 'status words');
  click('caltab', 'week');
  assert.strictEqual(phone.root.querySelectorAll('[data-a="calday"]').length, 7, 'seven days');
  click('calday', '41');
  tx = text();
  assert.ok(tx.includes('Dockyards 3-lap sprint') && tx.includes('Swap meet') && !tx.includes('NGRC Utah Rally: SS1 River') && tx.includes('Show all days'), 'a day shows its events only');
  click('calday', '');
  assert.ok(text().includes('NGRC Utah Rally: SS1 River'), 'all days again');
  click('caltab', 'series');
  tx = text();
  assert.ok(tx.includes('Johnson Valley off-road') && tx.includes('2 / 5') && tx.includes('17') && tx.includes('Next round: day 44'), 'the series card');
  click('caltab', 'agenda');
  click('calopen', 'utah-rally:3:r1');
  tx = text();
  assert.ok(tx.includes('NGRC Utah Rally: SS1 River') && phone.root.querySelector('[data-a="caltravel"][data-v="utah-rally:3:r1"]') && tx.includes('Go there') && tx.includes('You cannot enter yet'), 'a travel event offers Go there, refused while the requirement is unmet, with the reason');
  assert.ok(phone.root.querySelector('.slp-btn.slp-off[data-a="caltravel"]'), 'the Go there button is dimmed');
  calls.length = 0;
  click('calremind', 'utah-rally:3:r1|false');
  assert.ok(calls.some((c) => c.indexOf('calendarRemind("utah-rally:3:r1",false)') >= 0), 'Reminder: on turns it off: ' + calls.join(' '));
  click('caldecline', 'utah-rally:3:r1');
  assert.ok(calls.some((c) => c.indexOf('calendarDecline("utah-rally:3:r1")') >= 0), 'Decline asks the game');
  phone.handle('slPhoneData', Object.assign({}, data, { calendar: Object.assign({}, fixture, { events: fixture.events.map((e) => (e.id === 'utah-rally:3:r1' ? Object.assign({}, e, { requires: { label: 'A gravel or rally car', met: true } }) : e)) }) }));
  click('calopen', 'utah-rally:3:r1');
  calls.length = 0;
  click('caltravel', 'utah-rally:3:r1');
  assert.ok(calls.some((c) => c.indexOf('travelPick("utah-rally:3:r1")') >= 0), 'with the requirement met, Go there opens the pick-cars screen');
  click('back');
  click('calopen', 'weekend:dock-3:5');
  assert.ok(phone.root.querySelector('[data-a="calenter"][data-v="weekend:dock-3:5"]'), 'a home event is entered directly');
  calls.length = 0;
  click('calenter', 'weekend:dock-3:5');
  assert.ok(calls.some((c) => c.indexOf('calendarEnter("weekend:dock-3:5")') >= 0), 'Enter asks the game');
  click('back');
  assert.ok(text().includes('Dockyards night heat'), 'back to the agenda');
  phone.act('home');
  phone.handle('slPhoneData', Object.assign({}, data, { calendar: fixture, has: Object.assign({}, data.has, { calendar: false }) }));
  assert.ok(!phone.root.querySelector('[data-a="open"][data-v="calendar"]'), 'the part off: no app');
  phone.handle('slPhoneData', Object.assign({}, data, { calendar: { today: fixture.today, events: [], series: [], invites: [] } }));
  phone.act('open', 'calendar');
  assert.ok(text().includes('Nothing planned.'), 'an empty calendar says so');
  click('caltab', 'series');
  assert.ok(text().includes('No series running'), 'no series says so');
  phone.act('home');
  phone.handle('slPhoneData', data);
}
{
  // the trip (tools/travel_fixture.js is the contract): the pick-cars screen, the Event hub, a trip leaves only the apps that work away from home
  const tf = require('./travel_fixture.js');
  const base = Object.assign({}, data);
  phone.act('home');
  phone.handle('slPhoneData', Object.assign({}, base, { travelPick: tf.options }));
  let tx = text();
  assert.ok(tx.includes('NGRC Utah Rally') && tx.includes('Subaru Impreza GC8') && tx.includes('Gravel tyres') && tx.includes('Too low for the stages') && tx.includes('Pick up to 3 cars'), 'the pick screen: ' + tx.slice(0, 300));
  assert.ok(!phone.root.querySelector('[data-a="pickcar"][data-v="c3"]'), 'a car that does not fit cannot be picked');
  assert.ok(phone.root.querySelector('.slp-btn.slp-off[data-a="pickconfirm"]'), 'Confirm is dimmed with no car');
  calls.length = 0;
  click('pickconfirm', '1');
  assert.ok(calls.length === 0, 'nothing sent with no car');
  click('pickcar', 'c1'); click('pickcar', '2'); click('pickcar', '2'); click('pickcar', '2');      // (a numeric id: the second press takes it off again)
  tx = text();
  assert.ok(tx.includes('$800') && tx.includes('$200') && tx.includes('6 h') && tx.includes('$1,200'), 'total = fee + each car: ' + tx.slice(0, 500));
  click('pickconfirm', '1');
  assert.ok(calls.includes('travelConfirm("utah-rally:3:r1",["c1","2"],false)'), 'Confirm: ' + calls.join(' '));
  click('pickback');
  assert.ok(calls.includes('travelClose()'), 'Back closes the screen');
  assert.ok(!text().includes('Pick up to'), 'Back leaves the screen even while the data stays (Lua did not answer)');
  phone.handle('slPhoneData', Object.assign({}, base, { travelPick: tf.options }));
  assert.ok(!text().includes('Pick up to'), 'a push of the same screen stays dismissed');
  phone.handle('slPhoneData', base);
  phone.handle('slPhoneData', Object.assign({}, base, { travelPick: tf.options }));
  assert.ok(text().includes('Pick up to'), 'a screen opened again after the data cleared shows again');
  phone.handle('slPhoneData', Object.assign({}, base, { travelPick: Object.assign({}, tf.options, { loaner: { name: 'Rental Hatch', deposit: 300 }, cars: [] }) }));
  click('pickloaner', '1');
  assert.ok(text().includes('Borrow Rental Hatch') && text().includes('Deposit $300') && text().includes('$1,100'), 'a loaner when no car fits, with its deposit in the total');
  calls.length = 0; click('pickconfirm', '1');
  assert.ok(calls.includes('travelConfirm("utah-rally:3:r1",[],true)'), 'the loaner goes');
  phone.handle('slPhoneData', Object.assign({}, base, { travelPick: Object.assign({}, tf.options, { refuse: 'Not during a race.' }) }));
  assert.ok(text().includes('Not during a race.') && !phone.root.querySelector('[data-a="pickconfirm"]'), 'a refusal shows its reason and nothing to confirm');
  phone.handle('slPhoneData', base);
  assert.ok(!text().includes('Pick up to'), 'closed with the data gone');
  phone.act('home');
  assert.ok(!phone.root.querySelector('[data-a="open"][data-v="event"]'), 'no Event app at home');
  phone.handle('slPhoneData', Object.assign({}, base, { visit: tf.visit, hub: tf.hub }));
  assert.ok(phone.root.querySelector('[data-a="open"][data-v="event"]') && !phone.root.querySelector('[data-a="open"][data-v="races"]') && !phone.root.querySelector('[data-a="open"][data-v="garagekit"]') && !phone.root.querySelector('[data-a="open"][data-v="cab"]') &&
    phone.root.querySelector('[data-a="open"][data-v="garage"]') && phone.root.querySelector('[data-a="open"][data-v="bank"]') && phone.root.querySelector('[data-a="open"][data-v="messages"]'), 'on a trip: the Event app, the cars, money, talk; no races, home garage or cab');
  phone.act('open', 'event');
  tx = text();
  assert.ok(tx.includes('Round 2 of 4') && tx.includes('Utah') && tx.includes('You can stay until day 45') && tx.includes('Stage times: fastest wins') && tx.includes('Next: SS2 Canyon') && tx.includes('Day 43 10:00') && tx.includes('\u2714 SS1 River') && tx.includes('K. Ward') && tx.includes('25 pts') && tx.includes('4:15.9') && tx.includes('Standings') && tx.includes('Subaru Impreza GC8'), 'the hub: ' + tx.slice(0, 600));
  calls.length = 0;
  click('hubstart', '1');
  assert.ok(calls.includes('hubStart()'), 'Start');
  click('hubhome', '1');
  assert.ok(!calls.includes('hubHome()') && text().includes('The rounds you have not run count as missed'), 'Go home asks first, in plain words (the core\u2019s own note)');
  click('hubhome', '0'); assert.ok(!text().includes('counts as missed'), 'Cancel closes it');
  click('hubhome', '1'); click('hubhome', '1');
  assert.ok(calls.includes('hubHome()'), 'the second press goes home');
  phone.handle('slPhoneData', Object.assign({}, base, { visit: tf.visit, hub: Object.assign({}, tf.hub, { canStart: false, startWhy: 'Not before 10:00' }) }));
  assert.ok(phone.root.querySelector('.slp-btn.slp-off[data-a="hubstart"]') && text().includes('Not before 10:00'), 'a round that cannot start yet says why');
  phone.handle('slPhoneData', Object.assign({}, base, { visit: tf.visit, hub: Object.assign({}, tf.hub, { event: Object.assign({}, tf.hub.event, { status: 'done' }) }) }));
  assert.ok(text().includes('The series is over') && !phone.root.querySelector('[data-a="hubstart"]') && phone.root.querySelector('[data-a="hubhome"]'), 'a finished series: no Start, Go home stays');
  phone.act('home');
  phone.handle('slPhoneData', data);
}
// BUGS_1018 #9: the phone's own focus never scrolls the screen (a plain focus() brought the Home button into view and left the home grid 171 px down); jsdom has no scrolling, so the call is what is checked
assert.ok(/target\.focus\(\{ preventScroll: true \}\)/.test(code) && !/target\.focus\(\)/.test(code), 'the phone focuses its controls with preventScroll');
{
  // the trophy list on Street cred (tools/trophies_fixture.js): newest first, kind and day, the place; no card without the list
  const tf = require('./trophies_fixture.js');
  phone.act('home');
  phone.handle('slPhoneData', Object.assign({}, data, { trophies: tf }));
  phone.act('open', 'me');
  let tx = text();
  assert.ok(tx.includes('Trophies: 3') && tx.includes('NGRC Utah Rally') && tx.includes('Series') && tx.includes('day 58') && tx.includes('1st') && tx.includes('2nd') && tx.includes('Invitational'), 'the trophies: ' + tx.slice(0, 300));
  assert.ok(tx.indexOf('NGRC Utah Rally') < tx.indexOf('Hirochi invitational') && tx.indexOf('Hirochi invitational') < tx.indexOf('Dockyards 3-lap sprint'), 'newest first');
  phone.handle('slPhoneData', Object.assign({}, data, { trophies: [] }));
  assert.ok(text().includes('Trophies: 0') && text().includes('No trophies yet'), 'an empty list says so');
  phone.handle('slPhoneData', data);
  assert.ok(!text().includes('Trophies:'), 'no list: no card');
  phone.act('home');
}
{
  // the home championship on the Series tab (tools/season_fixture.js)
  const sf = require('./season_fixture.js');
  phone.act('home');
  phone.handle('slPhoneData', Object.assign({}, data, { calendar: require('./calendar_fixture.js'), season: sf }));
  phone.act('open', 'calendar');
  click('caltab', 'series');
  let tx = text();
  assert.ok(tx.includes('Home championship, season 2') && tx.includes('Days 40 to 58') && tx.includes('$2,000 for the champion') && tx.includes('you are 2nd') && tx.includes('Titles won: 1') && tx.includes('Home championship, season 1'), 'the season card: ' + tx.slice(0, 400));
  assert.ok(tx.includes('Dockyards sprint') && tx.includes('Place 2, 8 pts') && tx.includes('Hill duel night, Saturday 21:00') && tx.includes('Missed') && tx.includes('Next') && tx.includes('Day 58'), 'six rounds with their states');
  assert.ok(tx.includes('Standings') && tx.includes('K. Ward') && tx.includes('26 pts') && tx.includes('Mia the Mechanic of the Pier Street Garage Crew'), 'the table, with a long name');
  assert.ok(!phone.root.querySelector('[data-a="seasonenter"]'), 'entered: no Enter button');
  phone.handle('slPhoneData', Object.assign({}, data, { calendar: require('./calendar_fixture.js'), season: Object.assign({}, sf, { season: Object.assign({}, sf.season, { entered: false, canEnter: true, position: null }) }) }));
  calls.length = 0; click('seasonenter', '1');
  assert.ok(calls.includes('seasonEnter()') && !phone.root.querySelector('.slp-btn.slp-off[data-a="seasonenter"]'), 'Enter while it can be entered');
  phone.handle('slPhoneData', Object.assign({}, data, { calendar: require('./calendar_fixture.js'), season: Object.assign({}, sf, { season: Object.assign({}, sf.season, { entered: false, canEnter: false }) }) }));
  assert.ok(phone.root.querySelector('.slp-btn.slp-off[data-a="seasonenter"]'), 'dimmed when it cannot');
  phone.handle('slPhoneData', Object.assign({}, data, { calendar: require('./calendar_fixture.js'), season: Object.assign({}, sf, { season: null }) }));
  assert.ok(text().includes('No season running') && text().includes('$2,000'), 'no season: the card says so');
  phone.handle('slPhoneData', Object.assign({}, data, { calendar: require('./calendar_fixture.js') }));
  assert.ok(!text().includes('Home championship'), 'no data: no card');
  phone.act('home');
  phone.handle('slPhoneData', data);
}
console.log('phone test passed');

// a page to look at: the phone in several states side by side
const out = process.argv.indexOf('--html');
if (out > 0) {
  const shots = [];
  const views = [['home'], ['contacts'], ['contact', 'r01'], ['call'], ['thread', 'r01'], ['races'], ['me'], ['garage']];
  views.forEach((view) => {
    const d2 = new JSDOM('<!doctype html><html><body></body></html>', { runScripts: 'outside-only' });
    d2.window.__slPhoneTest = true;
    d2.window.eval(code);
    const p = d2.window.__slPhoneCreate(d2.window.document, () => {}, clock);
    p.handle('slPhoneData', data);
    p.handle('slPhoneToggle');
    if (view[0] === 'call') {
      p.act('call', 'r01');
      p.handle('slPhoneCall', { id: 'r01', answered: true, greeting: 'Yeah? Who is this?', options: ['race', 'high', 'pink'] });
      now += 3000; p.act('noop');
      p.state.call.phase = 'talking'; p.state.call.greeting = 'Yeah? Who is this?'; p.state.call.options = ['race', 'high', 'pink'];
      p.act('noop');
    } else if (view[0] === 'contact' || view[0] === 'thread') {
      p.act('open', view[0] === 'contact' ? 'contacts' : 'messages');
      p.act(view[0], view[1]);
    } else if (view[0] !== 'home') {
      p.act('open', view[0]);
    }
    const device = p.root.querySelector('.slp-device');
    device.style.cssText = 'position:relative;right:auto;bottom:auto;transform:none;display:inline-block;margin:16px;vertical-align:top';
    shots.push(device.outerHTML);
    if (!shots.css) shots.css = p.root.querySelector('style').textContent;
  });
  const page = '<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0;background:#3a3a40;width:2700px}' + shots.css +
    '.slp-root{position:static}</style></head><body><div class="slp-root" style="position:static;pointer-events:auto">' + shots.join('') + '</div></body></html>';
  fs.writeFileSync(process.argv[out + 1], page);
  console.log('wrote ' + process.argv[out + 1]);
}
// the app header (.slp-bar) must stay in the page flow above the scroll area: the letterbox bars once shared its class and made it absolute (the body scrolled over the back button)
{
  const css = require('fs').readFileSync(require('path').join(__dirname, '..', 'mod', 'ui', 'modModules', 'slPhone', 'slPhone.js'), 'utf8');
  assert.ok(!/\.slp-bar\s*\{[^}]*position:\s*absolute/.test(css) && /\.slp-bar\{[^}]*z-index:2/.test(css) && /\.slp-body\{[^}]*overflow-y:auto/.test(css), 'the header is fixed above a scroll body');
  console.log('phone header test passed');
}
// K with the Maps HUD app on screen: the phone slides out of the app and back (Web Animations stubbed, no layout in jsdom); any problem leaves the plain open and close
{
  const P = win.HTMLElement.prototype, origRect = P.getBoundingClientRect, origW = Object.getOwnPropertyDescriptor(P, 'offsetWidth'), origH = Object.getOwnPropertyDescriptor(P, 'offsetHeight');
  P.getBoundingClientRect = function () { return this.classList && this.classList.contains('slp-device') ? { left: 900, top: 100, right: 1260, bottom: 860, width: 360, height: 760 } : origRect.call(this); };
  Object.defineProperty(P, 'offsetWidth', { configurable: true, get() { return this.classList && this.classList.contains('slp-device') ? 360 : 0; } });
  Object.defineProperty(P, 'offsetHeight', { configurable: true, get() { return this.classList && this.classList.contains('slp-device') ? 760 : 0; } });
  const anims = [], hid = [];
  P.animate = function (frames, opts) { const a = { frames, opts, onfinish: null, cancelled: false, cancel() { this.cancelled = true; } }; anims.push(a); return a; };
  const hudRect = { left: 100, top: 500, width: 500, height: 250 };
  win.slMapsHud = { rect: () => hudRect, setHidden: (b) => hid.push(b) };
  const close = () => { if (phone.root.querySelector('.slp-device:not(.slp-away)')) phone.handle('slPhoneToggle'); };
  close(); while (anims.length) anims.pop(); advance(600); hid.length = 0;
  phone.handle('slPhoneToggle');
  assert.ok(anims.length === 1 && /rotate\(-90deg\)/.test(anims[0].frames[0].transform) && /^translate\(/.test(anims[0].frames[1].transform) && hid[hid.length - 1] === true, 'opening with the app on screen turns the phone out of it and hides the app');
  anims[0].onfinish();
  phone.handle('slPhoneToggle');
  assert.ok(anims.length === 2 && anims[1].opts.fill === 'forwards' && phone.root.querySelector('.slp-device:not(.slp-away)'), 'closing plays the animation back first, the phone stays until it ends');
  anims[1].onfinish();
  assert.ok(phone.root.querySelector('.slp-device.slp-away') && hid[hid.length - 1] === false, 'when it ends the phone closes and the app shows again');
  // a game side that ends the phone (data.active false) while it is open must show the app again
  phone.handle('slPhoneToggle');
  assert.ok(hid[hid.length - 1] === true && phone.root.querySelector('.slp-device:not(.slp-away)'), 'open again, the app hidden');
  phone.handle('slPhoneData', Object.assign({}, data, { active: false }));
  assert.ok(hid[hid.length - 1] === false && !phone.root.querySelector('.slp-device:not(.slp-away)'), 'the game closed the phone: the app is shown again, not left hidden');
  phone.handle('slPhoneData', data);
  const isOpen = () => !!phone.root.querySelector('.slp-device:not(.slp-away)');
  const finishAll = () => { for (let k = 0; k < 4; k++) { anims.forEach((a) => { if (a.onfinish) { const f = a.onfinish; a.onfinish = null; f(); } }); advance(600); } };
  finishAll();
  if (isOpen()) { phone.handle('slPhoneToggle'); finishAll(); }
  assert.ok(!isOpen() && hid[hid.length - 1] === false, 'closed and the app shown, ready for the presses');
  // K, K, K from closed: three toggles leave it OPEN (the last press counts: presses during a slide are queued)
  let before = anims.length;
  phone.handle('slPhoneToggle'); phone.handle('slPhoneToggle'); phone.handle('slPhoneToggle');
  finishAll();
  assert.ok(isOpen() && hid[hid.length - 1] === true && anims.length === before + 1, 'three presses from closed end open, with no extra slide: ' + isOpen() + ' ' + (anims.length - before));
  // K, K, K from open: closed
  phone.handle('slPhoneToggle'); phone.handle('slPhoneToggle'); phone.handle('slPhoneToggle');
  finishAll();
  assert.ok(!isOpen() && hid[hid.length - 1] === false, 'three presses from open end closed');
  // K, K from closed: closed again; two presses from open: open again
  phone.handle('slPhoneToggle'); phone.handle('slPhoneToggle'); finishAll();
  assert.ok(!isOpen(), 'two presses from closed end closed');
  phone.handle('slPhoneToggle'); finishAll();
  assert.ok(isOpen(), 'open');
  before = anims.length;
  phone.handle('slPhoneToggle'); phone.handle('slPhoneToggle'); finishAll();
  assert.ok(isOpen() && hid[hid.length - 1] === true, 'two presses from open end open: the close was pressed again while it ran');
  const cancelled = anims.filter((a) => a.cancelled).length;
  assert.ok(cancelled >= 1, 'the closing slide was cancelled and the phone slid in again');
  // an old slide's callback does nothing once a newer one runs
  const old = anims[anims.length - 1];
  if (old.onfinish) old.onfinish();
  advance(600);
  assert.ok(isOpen(), 'a stale finish leaves the open phone alone');
  phone.handle('slPhoneToggle'); finishAll();
  assert.ok(!isOpen(), 'closed for the next cases');
  // a second close while one is running, a cut-short animation, no app, the switch off, reduced motion
  phone.handle('slPhoneToggle'); advance(600);                     // open (the slide in never reports: the guard timer ends it)
  phone.handle('slPhoneToggle'); advance(600);                     // close (the slide out never reports either)
  assert.ok(phone.root.querySelector('.slp-device.slp-away'), 'an animation that never reports back still closes (500 ms)');
  const n = anims.length;
  delete win.slMapsHud; phone.handle('slPhoneToggle'); phone.handle('slPhoneToggle');
  assert.ok(anims.length === n && phone.root.querySelector('.slp-device.slp-away'), 'no Maps app on screen: the plain open and close');
  win.slMapsHud = { rect: () => hudRect, setHidden: (b) => hid.push(b) };
  phone.handle('slMapsOptions', { style: 'street', slide: false });
  phone.handle('slPhoneToggle'); phone.handle('slPhoneToggle');
  assert.ok(anims.length === n && phone.root.querySelector('.slp-device.slp-away'), 'the Mods switch off: the plain open and close');
  phone.handle('slMapsOptions', { style: 'street', slide: true });
  win.slMapsHud = { rect: () => { throw new Error('gone'); }, setHidden: () => {} };
  phone.handle('slPhoneToggle'); phone.handle('slPhoneToggle');
  assert.ok(phone.root.querySelector('.slp-device.slp-away'), 'an app that throws leaves the plain close');
  delete win.slMapsHud; delete P.animate; P.getBoundingClientRect = origRect;
  if (origW) Object.defineProperty(P, 'offsetWidth', origW); if (origH) Object.defineProperty(P, 'offsetHeight', origH);
  console.log('phone K slide test passed');
}
// the parts of the game that are switched off lose their apps and the HUD pill (the data says what is on)
{
  const off = { races: false, jobs: false, market: false, bank: false, maps: false, hudpill: false };
  phone.handle('slPhoneData', Object.assign({}, data, { has: off }));
  assert.ok(/display:none/.test((phone.root.querySelector('.slp-pill') || { getAttribute: () => '' }).getAttribute('style') || ''), 'the HUD pill is hidden with the HUD pill switched off');
  if (!phone.root.querySelector('.slp-device:not(.slp-away)')) phone.handle('slPhoneToggle');
  phone.act('home');
  const apps = Array.from(phone.root.querySelectorAll('.slp-app')).map((a) => a.getAttribute('data-v'));
  for (const id of ['races', 'jobs', 'carmarket', 'partmarket', 'bank', 'map']) assert.ok(!apps.includes(id), id + ' is not shown while its part is off');
  assert.ok(apps.includes('garage') && apps.includes('me') && apps.includes('cab'), 'the other apps stay');
  phone.handle('slPhoneData', Object.assign({}, data, { has: Object.assign({}, off, { races: true, jobs: true, market: true, bank: true, maps: true, hudpill: true, classifieds: true }) }));
  phone.act('home');
  const on = Array.from(phone.root.querySelectorAll('.slp-app')).map((a) => a.getAttribute('data-v'));
  for (const id of ['races', 'jobs', 'carmarket', 'bank', 'map']) assert.ok(on.includes(id), id + ' is back when its part is on');
  phone.handle('slPhoneData', data);
  console.log('phone parts off test passed');
}
// phone skins: a skin sets the look (its style, the app colours and icons); Classic (no skin) puts the classic look back, with no extra style left
{
  if (!phone.root.querySelector('.slp-device:not(.slp-away)')) phone.handle('slPhoneToggle');
  phone.act('home');
  const homeIcon = (id) => { const a = phone.root.querySelector('.slp-app[data-v="' + id + '"] .slp-ico'); return a ? a.innerHTML : null; };
  const homeColour = (id) => { const a = phone.root.querySelector('.slp-app[data-v="' + id + '"] .slp-ico'); return a ? a.style.background : null; };
  const skinStyle = () => Array.from(phone.root.querySelectorAll('style')).map((e) => e.textContent).slice(1).join('');
  const classicIcon = homeIcon('map'), classicColour = homeColour('map');
  assert.ok(classicIcon && skinStyle() === '', 'classic: a map icon and no skin style');
  phone.handle('slPhoneSkin', { id: 'slate', css: '.slp-root .slp-ico{border-radius:16px}', icons: { map: '<svg viewBox="0 0 24 24"><path d="M1 1"/></svg>', zzz: '<svg/>' }, appColors: { map: '#112233' } });
  phone.act('home');
  assert.ok(skinStyle().includes('border-radius:16px'), 'the skin style is in the page');
  assert.ok(homeIcon('map').includes('M1 1'), 'the skin icon is on the home grid');
  assert.ok(/rgb\(17, 34, 51\)|#112233/i.test(homeColour('map')), 'the skin colour is on the tile');
  assert.ok(homeIcon('camera') && !homeIcon('camera').includes('M1 1'), 'an app the skin does not name keeps its classic icon');
  phone.handle('slPhoneSkin', { id: 'classic' });
  phone.act('home');
  assert.strictEqual(homeIcon('map'), classicIcon, 'classic icon back');
  assert.strictEqual(homeColour('map'), classicColour, 'classic colour back');
  assert.strictEqual(skinStyle(), '', 'no extra style left');
  phone.handle('slPhoneSkin', { id: 'bad', css: 'a</style><script>x</script>' });
  assert.ok(!skinStyle().includes('</style'), 'a closing style tag is removed');
  phone.handle('slPhoneSkin', { id: 'classic' });
  console.log('phone skin test passed');
}
// free roam (no career): data.freeroam with data.apps keeps only those apps (grid and dock), hides the career line and the tutorial, and an app it does not have goes home
{
  if (!phone.root.querySelector('.slp-device:not(.slp-away)')) phone.handle('slPhoneToggle');
  const fr = { active: true, freeroam: true, apps: ['map', 'cab'], hour: 14, minute: 5, day: 1, mapName: 'West Coast', night: false, weather: { text: 'Clear', wet: false }, has: { maps: true, races: false, bank: false, jobs: false, clubs: false, crews: false, market: false } };
  phone.handle('slPhoneData', fr);
  phone.act('home');
  const ids = () => Array.from(phone.root.querySelectorAll('.slp-app')).map((a) => a.getAttribute('data-v'));
  assert.deepStrictEqual(ids().sort(), ['cab', 'map'], 'free roam shows only the apps it was given (the grid and the dock): ' + ids());
  assert.ok(!phone.root.querySelector('.slp-chip') && !phone.root.querySelector('.slp-tut'), 'no career line, no route-to-garage, no tutorial in free roam');
  assert.ok(/Clear/.test(text()) && /14:05/.test(text()), 'the clock and the weather are there');
  phone.act('open', 'races');
  assert.ok(phone.state.app === 'home', 'an app free roam does not have lands on the home screen');
  phone.act('open', 'map');
  assert.ok(phone.state.app === 'map', 'an app it has opens');
  for (const app of ['bank', 'messages', 'thread', 'ad', 'helppage', 'contact', 'photo', 'market', 'paper', 'bid']) {
    phone.handle('slPhoneGo', { app });
    assert.ok(phone.state.app === 'home', 'a deep link to ' + app + ' lands on the home screen');
  }
  phone.act('openthread', 'r01');
  assert.ok(phone.state.app === 'home' && phone.state.stack.length === 0, 'an openthread action ends on the home screen with no stack');
  phone.handle('slPhoneGo', { app: 'map' });
  assert.ok(phone.state.app === 'map', 'the map still opens by a deep link');
  phone.handle('slPhoneGo', { app: 'cab' });
  assert.ok(phone.state.app === 'cab', 'the cab still opens by a deep link');
  // a Back that would pop an app pushed before the free roam flag came: it lands on home, not on that app
  phone.handle('slPhoneData', data);
  phone.act('home'); phone.act('open', 'bank'); phone.act('open', 'messages');
  phone.handle('slPhoneData', fr);
  phone.act('back');
  assert.ok(phone.state.app === 'home' && phone.state.stack.length === 0, 'a Back after the flag arrived does not return to an app free roam does not have: ' + phone.state.app);
  phone.handle('slPhoneData', data);
  phone.act('home');
  assert.ok(ids().includes('races') || ids().includes('garage'), 'a career phone shows its apps again');
  console.log('phone free roam test passed');
}
// the home grid scrolls (wheel) and the dock never leaves the screen: the grid shrinks, the dock does not; the phone is scaled to fit the window height
{
  const css = require('fs').readFileSync(require('path').join(__dirname, '..', 'mod', 'ui', 'modModules', 'slPhone', 'slPhone.js'), 'utf8');
  assert.ok(/\.slp-grid\{[^}]*overflow-y:auto/.test(css) && /\.slp-grid\{[^}]*min-height:0/.test(css) && /\.slp-dock\{flex:none/.test(css) && /\.slp-home\{[^}]*min-height:0/.test(css), 'home grid scrolls, dock fixed');
  assert.ok(/\(h - 40\) \/ 760/.test(css), 'phone height is clamped to the window');
  console.log('phone fit test passed');
}
