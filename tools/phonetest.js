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
phone.handle('slMenu', { show: true, installed: true, summary: 'Day 4, $12300, Street kid' });
pressCareer();
calls.length = 0;
click('menustart', 'new');
assert.ok(!calls.length && text().includes('Click again'), 'starting over asks first');
click('menustart', 'new');
assert.ok(calls.includes('@sl_menuTile.startFromMenu(true)'), 'then starts over');
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

// K takes it out: home screen with the time, the day and badges
phone.handle('slPhoneToggle');
assert.ok(!$('.slp-device.slp-away'), 'K takes it out');
assert.ok(calls.includes('request()'), 'opening asks for fresh data');
assert.ok(text().includes('21:05') && text().includes('Day 2'), 'clock and day on the home screen');
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
click('cancel', 'r01:1');
assert.ok(calls.includes('cancel("r01:1")'), 'calling one off');
click('home');
click('open', 'bank');
assert.ok(text().includes('-$45') && text().includes('+$300'), 'bank statement');
click('home');
click('open', 'cab');
click('taxi', 'junkyard');
assert.ok(calls.includes('taxi("junkyard")'), 'cab ordered');
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
  items: [{ id: 'oil', name: 'Engine oil (4 L)', price: 45 }], trunk: 1, trunkSlots: 6 });
assert.ok(text().includes('South Gas') && text().includes('33 L to fill') && text().includes('Race 102'), 'the pump');
click('fuelpick', 'race');
click('station', 'fill|race');
assert.ok(calls.includes('@sl_station.fill("race")'), 'filling with race fuel');
click('station', 'buy|oil');
assert.ok(calls.includes('@sl_station.buy("oil","race")'), 'oil into the trunk');
click('station', 'close');
assert.ok(!text().includes('South Gas'), 'driving on');

// with SLRR's art copied in, its icons replace the drawn ones where SLRR has one
phone.handle('slPhoneData', data);
phone.handle('slPhoneToggle');
click('home');
assert.ok(!phone.root.querySelector('img.slp-slrr'), 'drawn icons without SLRR art');
phone.handle('slArt');
assert.ok(phone.root.querySelector('img.slp-slrr[src$="cup.png"]') && phone.root.querySelector('img.slp-slrr[src$="dollar.png"]'), "SLRR's cup and dollar icons");
phone.handle('slStation', { open: true, name: 'Pump', money: 100, fuels: [], items: [] });
assert.ok(phone.root.querySelector('.slp-lot') && !phone.root.querySelector('.slp-ico .slp-lot'), 'with SLRR icons the panels stay outside the phone (icon markup closed)');
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
