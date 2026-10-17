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
assert.ok(text().includes('Needs the Wrench Works: Valo City map'), 'tells you when the map is missing');
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
phone.handle('slPhoneData', Object.assign({}, data, { hud: { enabled: true, speedo: true, tacho: true, map: false, damage: true, units: 'mph', freeroam: false } }));
assert.ok(text().includes('Dashboard') && text().includes('Rev counter') && text().includes('mph'), 'dashboard switches');
calls.length = 0;
click('hud', 'map');
assert.ok(calls.includes('@sl_hud.toggle("map")'), 'switching the map');
phone.handle('slPhoneData', Object.assign({}, data, { hud: { enabled: false, speedo: true, tacho: true, map: true, damage: true, units: 'kmh', freeroam: false } }));
assert.ok(text().includes('Dashboard') && !text().includes('Rev counter'), 'switched off: only the main switch');
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
assert.ok(text().includes('Hide car report') && text().includes('Brakes') && text().includes('Pads and discs') && text().includes('20% Poor') && text().includes('Moderate (30%)') && text().includes('$640') && text().includes('$1,900'), 'the report lists the parts by section, the damage and the repair estimates');
click('report', 'lot');
assert.ok(!text().includes('Pads and discs'), 'and closes again');
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
// Settings, Android style: every setting in its group, a switch / stepper + slider / list each, a developer button at the bottom
phone.act('home');
if (!phone.state.open) phone.handle('slPhoneToggle');
calls.length = 0;
phone.act('open', 'settings');
assert.ok(calls.includes('settings()'), 'opening Settings asks for the list');
phone.handle('slSettings', { defs: [
  { key: 'unlimitedMoney', group: 'Money', title: 'Unlimited money', type: 'bool', value: false, desc: 'Outside career mode.' },
  { key: 'priceMultiplier', group: 'Money', title: 'Part prices', type: 'range', min: 0, max: 3, step: 0.05, value: 1, unit: 'x' },
  { key: 'paintPrice', group: 'Money', title: 'Respray price', type: 'number', min: 0, max: 100000, step: 50, value: 300 },
  { key: 'slNotify', group: 'Street Legal', title: 'Text pop-ups', type: 'choice', value: 'all', options: [{ id: 'all', label: 'Every text' }, { id: 'important', label: 'Racers only' }, { id: 'off', label: 'None' }] },
  { key: 'slPolice', group: 'Street Legal', title: 'Police', type: 'bool', value: true }] });
const heads = Array.from(phone.root.querySelectorAll('.slp-seth')).map((h) => h.textContent);
assert.deepStrictEqual(heads, ['Money', 'Street Legal', 'Settings', 'Developer'], 'settings are grouped, with the reset and the developer section last');
assert.ok(phone.root.querySelectorAll('.slp-sw').length === 2 && phone.root.querySelector('.slp-sw.slp-swon') && text().includes('Unlimited money') && text().includes('Outside career mode.'), 'a bool is a switch (on shows lit)');
assert.ok(phone.root.querySelector('input.slp-range[data-key="priceMultiplier"]') && text().includes('1 x') && text().includes('Racers only') === false && text().includes('Every text'), 'a range has a slider and its value, a list its current choice');
calls.length = 0;
click('settoggle', 'unlimitedMoney');
click('settoggle', 'slPolice');
assert.ok(calls.includes('setSetting("unlimitedMoney",true)') && calls.includes('setSetting("slPolice",false)'), 'a switch flips the setting');
click('setstep', 'priceMultiplier|1');
click('setstep', 'paintPrice|-1');
assert.ok(calls.includes('setSetting("priceMultiplier",1.05)') && calls.includes('setSetting("paintPrice",250)'), '+ and - step a number by its step');
click('setstep', 'priceMultiplier|-1');
click('setchoice', 'slNotify|1');
click('setchoice', 'slNotify|-1');
assert.ok(calls.includes('setSetting("slNotify","important")') && calls.includes('setSetting("slNotify","off")'), 'a list steps to the next / previous choice (wrapping)');
const slider = phone.root.querySelector('input.slp-range');
slider.value = '2.5';
slider.dispatchEvent(new win.Event('change', { bubbles: true }));
assert.ok(calls.includes('setSetting("priceMultiplier",2.5)'), 'a slider let go sets the setting');
assert.ok(phone.root.querySelector('.slp-settings-all') === null && Array.from(phone.root.querySelectorAll('.slp-set')).every((e) => true), 'the rows exist');
assert.ok(phone.root.querySelector('[data-a="setstep"]').hasAttribute('bng-nav-item') && phone.root.querySelector('[data-a="settoggle"]').hasAttribute('bng-nav-item'), 'the controls are gamepad nav items');
calls.length = 0;
click('setreset');
click('devmoney');
assert.ok(calls.includes('setSetting("__reset",true)') && calls.includes('devMoney()'), 'reset, and the developer button gives all the money');
const dev = phone.root.querySelector('[data-a="devmoney"]');
assert.ok(dev && text().lastIndexOf('Developer') > text().lastIndexOf('Street Legal') && text().indexOf('Give all the money') > text().lastIndexOf('Respray price'), 'the developer section is at the very bottom');
phone.act('home');
// a fade is plain black: no SLRR loading picture, whatever the game sends
phone.handle('slFade', { on: true, pic: 'loading_city.png' });
assert.ok(phone.root.querySelector('.slp-fade.slp-in') && !(phone.root.querySelector('.slp-fade').getAttribute('style') || '').includes('url('), 'a fade has no picture');
phone.handle('slFade', { on: false });
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
