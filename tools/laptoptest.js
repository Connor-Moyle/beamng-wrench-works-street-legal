// Runs the laptop (ui/modModules/slLaptop/slLaptop.js) in a simulated page and checks the Windows-style desktop it draws (wallpaper, icons,
// windows with title bars, taskbar, Start menu), how a gamepad reaches it and what it asks the game for.
// Needs jsdom:  npm i jsdom   then   node tools/laptoptest.js
const fs = require('fs'), path = require('path'), assert = require('assert');
const { JSDOM } = require('jsdom');

const code = fs.readFileSync(path.join(__dirname, '..', 'mod/ui/modModules/slLaptop/slLaptop.js'), 'utf8');
const dom = new JSDOM('<!doctype html><html><body></body></html>', { runScripts: 'outside-only', pretendToBeVisual: true });
const win = dom.window;
win.__slLaptopTest = true;
win.eval(code);

const calls = [];
const laptop = win.__slLaptopCreate(win.document, (c) => calls.push(c));
const $ = (sel) => laptop.root.querySelector(sel);
const $$ = (sel) => Array.from(laptop.root.querySelectorAll(sel));
const text = () => laptop.root.textContent;
const sel = (a, v) => '[data-a="' + a + '"]' + (v === undefined ? '' : '[data-v="' + v + '"]');
// a click as the mouse sends it (detail = the click count) or as the pad's A / Enter does (no count)
const click = (a, v, detail) => $(sel(a, v)).dispatchEvent(new win.MouseEvent('click', { bubbles: true, detail: detail || 0 }));
const nav = (name, value) => win.document.dispatchEvent(new win.CustomEvent('ui_nav', { detail: { name, value: value === undefined ? 1 : value } }));
const wins = () => $$('.sll-win');
const titles = () => $$('.sll-win .sll-title b').map((b) => b.textContent);
const taskbtns = () => $$('.sll-taskwin').map((t) => t.textContent);

// what sl/core/laptop.lua gives a garage computer once the player has a car
const tile = (id, label, enabled, reason, page, mode) => ({ id, label, enabled, reason, page, mode });
const general = { id: 'general', title: 'General', tiles: [
  tile('vehicleInventory', 'My cars', true, null, 'cars'), tile('partInventory', 'My parts', true, null, 'parts'),
  tile('vehicleShop', 'Car market', true, null, 'dealers'), tile('partsMarket', 'Part market', true, null, 'partmarket'), tile('insurances', 'Bank / insurance', true, null, 'bank'), tile('playerAbstract', 'Street cred', true, null, 'cred')] };
// car 1 stands at this garage (its tiles work), car 2 does not (the reason is shown)
const view = {
  name: 'Commercial Garage', lists: true,
  groups: [general],
  byCar: {
    1: [{ id: 'car', title: 'Vehicle management', tiles: [tile('partShop', 'Part customization', true, null, null, 'catalog'), tile('tuning', 'Tuning', true, null, null, 'tune')] }, general],
    2: [{ id: 'car', title: 'Vehicle management', tiles: [tile('partShop', 'Part customization', false, 'Bring the car into the garage first.', null, 'catalog'), tile('tuning', 'Tuning', false, 'Bring the car into the garage first.', null, 'tune')] }, general],
  },
};
const data = {
  active: true, money: 12400, rep: 140, title: 'Street kid', titleRep: 100, nextRep: 300, day: 9, hour: 21, minute: 5, garage: 'Industrial Garage', cars: 2, stats: { races: 4, wins: 3 },
  fleet: [
    { id: 1, name: 'Sunburst 2.0 Sport S AWD', where: 'At the garage', condition: 0.8, value: 8900, active: true, faults: [] },
    { id: 2, name: 'Covet', where: 'Out on the street', condition: 0.5, value: 2100, out: true, towFee: 120, faults: ['battery'],
      report: { condition: 50, label: 'Fair', mileage: 90000, damage: { amount: 0, label: 'None' }, faults: ['battery'], total: 420, sections: [{ id: 'engine', title: 'Engine', condition: 41, label: 'Worn', estimate: 420, faults: ['battery'], parts: [{ name: 'Battery cell', condition: 20, label: 'Poor', fault: 'battery' }] }] } },
  ],
  bank: { limit: 6000, rate: 0.02, premium: 90, deductible: 200 }, ledger: [{ label: 'Race', amount: 300 }, { label: 'Parts', amount: -80 }],
  achievements: { earned: 1, total: 2, list: [{ title: 'First win', desc: 'Win a race', day: 3 }, { title: 'King', desc: 'Win all' }] },
};
const open = (extra) => laptop.handle('slLaptopOpen', Object.assign({}, view, { parts: [] }, extra || {}));

// ---- closed: nothing shows, nothing takes the pad
assert.ok($('.sll-screen.sll-gone'), 'the laptop starts closed');
laptop.handle('slPhoneData', data);
assert.ok($('.sll-screen.sll-gone'), 'phone data alone does not open it');
assert.ok($$('[data-a]').every((e) => e.getAttribute('bng-no-nav') === 'true' || !e.hasAttribute('bng-nav-item')), 'a closed laptop takes no gamepad focus');

// ---- the desktop
open();
assert.ok(!$('.sll-screen.sll-gone'), 'it opens');
assert.ok($('.sll-wall') && !wins().length && !$('.sll-menu'), 'a wallpaper, no window and no Start menu yet');
assert.ok(!/url\(/.test($('.sll-wall').getAttribute('style') || ''), 'no Windows wallpaper copied: the built-in gradient');
const icons = $$('.sll-icon');
assert.deepStrictEqual(icons.map((i) => i.textContent), ['Part customization', 'Tuning', 'My cars', 'My parts', 'Car market', 'Part market', 'Bank / insurance', 'Street cred'], 'one desktop icon per function, labelled');
assert.ok(icons.every((i) => i.querySelector('svg') && i.hasAttribute('bng-nav-item') && i.getAttribute('tabindex') === '0'), 'each icon has a picture and is a gamepad nav item');
assert.ok($('.sll-icons').hasAttribute('bng-nav-scroll'), 'the icon column scrolls on the right stick');
assert.ok(text().includes('My garage') && text().includes('Sunburst 2.0 Sport S AWD'), 'the car widget, a small window of its own');
assert.ok($('.sll-task') && $('[data-a="start"]') && text().includes('Start') && text().includes('Street kid') && text().includes('21:05') && text().includes('Day 9') && text().includes('$12,400'), 'the taskbar: Start, and the tray with rank, clock, day and money');
assert.ok($$('.sll-task [data-a]').every((e) => e.hasAttribute('bng-nav-item')), 'the taskbar is reachable by the pad');
assert.ok($$('.sll-icon.sll-off').length === 0, 'nothing is greyed for a car at the garage');

// ---- selecting and opening an icon as in Windows
calls.length = 0;
click('tile', 'vehicleInventory', 1);
assert.ok(wins().length === 1 && titles()[0] === 'My cars' && calls.includes('@sl_phone.request()'), 'one mouse click opens an icon in a window (and asks for fresh data)');
{ const keep = $('.sll-win'); laptop.handle('slPhoneData', data); assert.ok($('.sll-win') === keep, 'the same data again does not rebuild the screen (a click between press and release would be lost)'); }
// a real mouse click on a desktop icon is press, release, click, and the game sends fresh data in between (the screen must not be rebuilt under the pointer)
{
  click('winclose', 'cars');
  const icon = $(sel('tile', 'vehicleInventory'));
  const ev = (t) => icon.dispatchEvent(new win.MouseEvent(t, { bubbles: true, detail: 1 }));
  ev('mousedown'); laptop.handle('slPhoneData', laptop.state.data); ev('mouseup'); ev('click');
  assert.ok(wins().length === 1 && titles()[0] === 'My cars', 'press, fresh data, release, click: the icon opens its window on the first click');
}
click('winclose', 'cars');
assert.ok(!wins().length, 'the window closes');
click('tile', 'vehicleInventory');
assert.ok(wins().length === 1, 'the pad\'s A (a click with no count) opens an icon at once');

// ---- the window
const w1 = $('.sll-win');
assert.ok(w1.classList.contains('sll-top') && w1.querySelector('.sll-title svg') && w1.querySelector('.sll-title b').textContent === 'My cars', 'a window: title bar with its icon and title');
['winmin', 'winmax', 'winclose'].forEach((a) => assert.ok(w1.querySelector(sel(a, 'cars')), 'title bar button ' + a));
assert.ok(w1.querySelector('.sll-grip'), 'a resize grip');
assert.ok(text().includes('Drive this one') && text().includes('Tow it home') && text().includes('Needs: battery'), 'cars: use, tow, faults');
calls.length = 0;
click('usecar', '2');
click('tow', '2');
click('despawn', '2');
assert.ok(calls.includes('@sl_phone.useCar(2)') && calls.includes('@sl_phone.tow(2)') && calls.includes('@sl_phone.despawn(2)'), 'drive this one, tow it home, put it away (a car that is out)');
assert.ok(!$('[data-a="despawn"][data-v="1"]') || data.fleet[0].out, 'a stored car has no Put it away');
laptop.handle('slPhoneToast', { text: 'A tow truck is on its way.' });
assert.ok(text().includes('A tow truck is on its way.'), 'the answer shows in the window');
assert.deepStrictEqual(taskbtns(), ['My cars'], 'a taskbar button for the open window');
assert.ok($('.sll-taskwin').classList.contains('sll-on'), 'highlighted while it has the focus');
assert.ok($$('.sll-icon').every((e) => !e.hasAttribute('bng-nav-item')) && $$('.sll-win.sll-top [data-a]').every((e) => e.hasAttribute('bng-nav-item')), 'with a window on top the pad moves in the window, not on the desktop behind it');

// ---- several windows: focus, minimise, restore, maximise, close
click('tile', 'insurances');
assert.deepStrictEqual(titles(), ['My cars', 'Bank / insurance'], 'a second window opens beside the first');
assert.ok($$('.sll-win')[1].classList.contains('sll-top') && !$$('.sll-win')[0].classList.contains('sll-top'), 'the newest has the focus');
assert.ok(text().includes('Balance') && text().includes('Borrow') && text().includes('Insurance') && text().includes('+$300') && text().includes('-$80'), 'bank: balance, loan, insurance, ledger');
calls.length = 0;
click('borrow', '3000');
click('insure', 'true');
assert.ok(calls.includes('@sl_phone.borrow(3000)') && calls.includes('@sl_phone.insure(true)'), 'borrow and insure');
click('focus', 'cars');
assert.ok($$('.sll-win')[1].classList.contains('sll-top') && $$('.sll-win')[1].getAttribute('data-win') === 'cars', 'a click on a title bar brings that window to the front');
click('task', 'cars');
assert.ok(titles().length === 1 && taskbtns().length === 2, 'the focused window\'s taskbar button minimises it (its button stays)');
click('task', 'cars');
assert.ok(titles().length === 2 && $$('.sll-win')[1].getAttribute('data-win') === 'cars', 'and a click on it again brings it back');
click('winmin', 'cars');
assert.ok(titles().length === 1, 'the minimise button hides the window');
click('task', 'cars');
click('winmax', 'cars');
assert.ok($('.sll-win[data-win="cars"]').classList.contains('sll-max'), 'maximise fills the desktop');
click('winmax', 'cars');
assert.ok(!$('.sll-win[data-win="cars"]').classList.contains('sll-max'), 'and restores it');
assert.ok($('.sll-win[data-win="cars"]').textContent.includes('Show full car report'), 'my cars offer the report (with the wear since you bought it)');
click('report', 'car:2');
assert.ok($('.sll-repmodal') && $('.sll-repmodal').textContent.includes('Battery cell') && $('.sll-repmodal').textContent.includes('$420'), 'a car of mine reports its parts and the repair estimate in a panel');
assert.ok($('.sll-repbody') && $('.sll-repbody').hasAttribute('bng-nav-scroll') && $('.sll-reppanel [data-a="reportclose"]') && $('.sll-repsum[data-a="repsec"]'), 'the laptop panel scrolls, has a close button and collapsible sections');
(function () {
  const panel = code.match(/\.sll-reppanel\{([^}]*)\}/)[1], body = code.match(/\.sll-repbody\{([^}]*)\}/)[1];
  assert.ok(/max-height:80vh/.test(panel) && /width:min\((\d+)px,92vw\)/.test(panel) && /overflow-y:auto/.test(body), 'laptop panel: max-height 80vh, width capped, a scrolling body');
  const wpx = +panel.match(/width:min\((\d+)px,92vw\)/)[1];
  [[1280, 720], [1920, 1080]].forEach(function (vp) { assert.ok(Math.min(wpx, 0.92 * vp[0]) <= vp[0] && 0.8 * vp[1] <= vp[1], 'laptop panel inside ' + vp.join('x')); });
})();
click('reportclose');
assert.ok(!$('.sll-repmodal'), 'the laptop report closes');
click('winclose', 'bank');
assert.deepStrictEqual(taskbtns(), ['My cars'], 'closing a window removes its taskbar button');

// ---- B: the top window, then the next, then the laptop
click('tile', 'playerAbstract');
assert.ok(text().includes('Street kid') && text().includes('140 reputation') && text().includes('Achievements 1 / 2') && text().includes('First win'), 'street cred');
let leaked = 0;
win.document.addEventListener('ui_nav', () => { leaked++; });
nav('back');
assert.deepStrictEqual(titles(), ['My cars'], 'B closes the top window');
nav('back');
assert.ok(!wins().length, 'and the next');
calls.length = 0;
nav('back');
assert.ok($('.sll-screen.sll-gone') && calls.includes('@sl_computer.close()'), 'B on a bare desktop shuts the laptop down');
assert.ok(leaked === 0, 'B never reached the game (its pause menu stays shut)');
nav('back');
assert.ok($('.sll-screen.sll-gone'), 'a closed laptop leaves B alone');

// ---- the Start menu
open();
click('start');
const items = $$('.sll-mi');
assert.ok($('.sll-menu') && items.length === 8 && items.every((i) => i.querySelector('svg') && i.hasAttribute('bng-nav-item')), 'Start lists every app with its icon');
assert.ok($('.sll-menu').textContent.includes('Vehicle management') && $('.sll-menu').textContent.includes('Street cred') && $('.sll-menu').textContent.includes('Shut down'), 'by group, with Shut down');
assert.ok($$('.sll-icon').every((e) => !e.hasAttribute('bng-nav-item')), 'with the menu up the pad moves in the menu');
nav('back');
assert.ok(!$('.sll-menu') && !$('.sll-screen.sll-gone'), 'B shuts the Start menu first, not the laptop');
click('start');
click('tile', 'vehicleInventory');
assert.ok(!$('.sll-menu') && wins().length === 1, 'a Start menu item opens its window and shuts the menu');
click('winclose', 'cars');
click('start');
calls.length = 0;
click('close');
assert.ok($('.sll-screen.sll-gone') && calls.includes('@sl_computer.close()'), 'Shut down in the Start menu closes the laptop');

// ---- the garage icons
open();
calls.length = 0;
click('tile', 'tuning');
assert.ok(calls.includes('@sl_computer.enterGarage("tune",1)') && !wins().length, 'Tuning: the garage opens on car 1 in tune mode');
click('tile', 'partShop');
assert.ok(calls.includes('@sl_computer.enterGarage("catalog",1)'), 'Part customization: the catalog');
click('car', '1');
assert.ok(text().includes('Covet') && text().includes('Out on the street'), 'the next car in the garage widget');
assert.ok($$('.sll-icon.sll-off').length === 2, 'the car away from the garage has its garage icons greyed');
calls.length = 0;
click('tile', 'tuning');
assert.ok($('.sll-balloon') && $('.sll-balloon').textContent.includes('Tuning: Bring the car into the garage first.') && calls.length === 0, 'a greyed icon says why in a balloon, sending nothing');
nav('tab_l');
assert.ok(text().includes('Sunburst 2.0 Sport S AWD'), 'tab_l on the pad: the car before');
nav('tab_r');
assert.ok(text().includes('Covet'), 'tab_r on the pad: the next car');

// ---- My parts
calls.length = 0;
click('tile', 'partInventory');
assert.ok(calls.includes('@sl_computer.parts()') && text().includes('The shelf in your garage is empty'), 'parts asks the shelf; empty says so');
laptop.handle('slLaptopParts', { parts: [{ car: 'Covet', name: 'Sport exhaust', count: 2, value: 340 }] });
assert.ok(text().includes('Covet') && text().includes('Sport exhaust') && text().includes('$340'), 'a shelf part is listed under its car');
click('winclose', 'parts');

// ---- the Dealers window and its steps
calls.length = 0;
click('tile', 'vehicleShop');
assert.ok(calls.includes('@sl_dealers.list()') && titles()[0] === 'Car market', 'The Car market asks for the dealer list');
laptop.handle('slLaptopDealers', { dealers: [{ id: 'jeff', name: 'Jefferson Motors', metres: 4200, count: 5 }, { id: 'quarry', name: 'Quarryside', metres: 800, count: 1 }], coming: [{ name: 'Covet', hours: 3 }] });
assert.ok(text().includes('Jefferson Motors') && text().includes('4.2 km away') && text().includes('5 cars today') && text().includes('800 m away') && text().includes('1 car today'), 'dealers: name, distance, number of cars');
assert.ok(text().includes('On the way to your garage') && text().includes('in about 3 h'), 'and what is on its way');
click('dealer', 'jeff');
assert.ok(calls.includes('@sl_dealers.offers("jeff")'), 'a dealer asks for its cars');
laptop.handle('slLaptopOffers', { dealer: 'jeff', name: 'Jefferson Motors', money: 9000, offers: [
  { id: 'jeff:dealer-3-1', name: 'Bolide', brand: 'Bruckell', year: 2012, title: 'New', mileage: 20, condition: 1, price: 7000, faults: [], seller: 'Jefferson Motors', metres: 4200, hours: 3,
    preview: '/vehicles/bolide/sport.png', specs: { power: 310, weight: 1250, transmission: 'Manual', drivetrain: 'RWD', fuel: 'Gasoline', body: 'Coupe', topSpeed: 75 }, report: { condition: 45, label: 'Worn', mileage: 180000, damage: { amount: 30, label: 'Moderate' }, faults: ['brakes'], total: 1900, sections: [{ id: 'brakes', title: 'Brakes', condition: 30, label: 'Worn', estimate: 640, faults: ['brakes'], parts: [{ name: 'Pads and discs', condition: 20, label: 'Poor', fault: 'brakes' }, { name: 'Calipers and lines', condition: 40, label: 'Worn' }] }] } },
  { id: 'jeff:dealer-3-2', name: 'Pessima', title: 'Tired', mileage: 150000, condition: 0.4, price: 9900, faults: ['battery'] }] });
assert.ok(titles()[0] === 'Jefferson Motors' && $('.sll-taskwin').textContent === 'Jefferson Motors', 'the window takes the dealer\'s name');
assert.ok(text().includes('2012 Bolide') && text().includes('Bruckell') && text().includes('20 km') && text().includes('Manual') && text().includes('RWD') && text().includes('310 PS') && text().includes('1,250 kg'), 'offer cards: year, name, brand, mileage, transmission, drivetrain, power, weight');
assert.ok(text().includes('4.2 km away') && text().includes('arrives in about 3 h') && text().includes('condition 100%') && text().includes('$7,000'), 'seller, distance, delivery time, condition, price');
assert.ok($('.sll-pic img') && $('.sll-pic img').getAttribute('src') === '/vehicles/bolide/sport.png', 'the card shows the config\'s preview picture');
assert.ok($$('.sll-pic')[1].textContent.includes('no picture'), 'a car without a picture says so');
assert.ok(text().includes('Needs: battery') && $$('.sll-btn.sll-off').length === 1, 'faults are listed and a car you cannot pay for is dimmed');
click('offer', 'jeff:dealer-3-1');
assert.ok(titles()[0] === '2012 Bolide' && $('.sll-detail .sll-pic img'), 'a card opens its detail view in the same window');
['Bruckell', '2012', '20 km', '310 PS', '1,250 kg', 'Manual', 'RWD', 'Gasoline', 'Coupe', '270 km/h', 'Jefferson Motors', '4.2 km', 'to your garage in about 3 h', '$7,000'].forEach((x) => assert.ok($('.sll-win').textContent.includes(x), 'detail shows ' + x));
assert.ok($('.sll-win').textContent.includes('Show full car report'), 'a detail view with a report offers it');
click('report', 'offer:jeff:dealer-3-1');
assert.ok($('.sll-repmodal').textContent.includes('Pads and discs') && $('.sll-repmodal').textContent.includes('$640') && $('.sll-repmodal').textContent.includes('Moderate (30%)'), 'the laptop report lists the parts, the damage and the estimate');
click('reportclose');
calls.length = 0;
click('buy', 'jeff|jeff:dealer-3-1');
assert.ok(calls.includes('@sl_dealers.buy("jeff","jeff:dealer-3-1")'), 'Buy in the detail view asks for that car');
laptop.handle('slPhoneToast', { text: 'The Bolide will be at your garage in about 3 hours.' });
assert.ok(text().includes('will be at your garage in about 3 hours'), 'the answer shows');
laptop.handle('slLaptopOffers', { dealer: 'jeff', name: 'Jefferson Motors', money: 2000, offers: [{ id: 'jeff:dealer-3-2', name: 'Pessima', mileage: 1, condition: 1, price: 9900, faults: [] }] });
assert.ok(text().includes('This car has gone'), 'a bought car\'s detail says it has gone');
click('back', 'dealers');
const names = $$('.sll-card h4').map((h) => h.textContent);
assert.ok(!names.some((n) => n.includes('Bolide')) && names.some((n) => n.includes('Pessima')), 'back to the list: a bought car is gone from it');
calls.length = 0;
nav('back');
assert.ok(text().includes('Quarryside') && calls.includes('@sl_dealers.list()') && titles()[0] === 'Car market', 'B goes back to the dealers');
nav('back');
assert.ok(!wins().length, 'and then closes the window');

// ---- the two marketplaces share the phone's data
laptop.handle('slPhoneData', Object.assign({}, laptop.state.data || {}, { market: { deliveries: 1, auctions: [{ id: 'a1', name: 'Coilovers', model: 'covet', bid: 100, next: 110, condition: 80, hoursLeft: 5, high: 'ai', delivery: 30 }], paper: { listings: [], edition: 2, price: 2 }, mine: [], shelf: [], cars: [],
  listings: [{ id: 'p1', name: 'Sport exhaust', model: 'covet', chapter: 'Exhaust systems', fits: 'Covet', categoryTitle: 'Engine', partPic: '/pics/exh.png', ask: 300, condition: 70, seller: 'Gabor', rating: 3, tells: [], deposit: 30, hoursLeft: 12, delivery: 20 },
    { id: 'c1', name: 'Covet 1.5', model: 'covet', car: true, faults: 0, ask: 2400, condition: 55, seller: 'Big Tony', rating: 4, tells: [], deposit: 240, hoursLeft: 30, delivery: 180, year: 2009, specs: {} }] } }));
click('tile', 'vehicleShop');
click('mtab', 'dealers|ads');
assert.ok(text().includes('Covet 1.5') && !text().includes('Sport exhaust'), 'Car market, Private ads: the car ads only');
// the car auctions tab: lots with grade and reserve state, the bid buttons ask the game, the watch list, selling a car, and the live view is told when the tab opens and shuts
calls.length = 0;
click('mtab', 'dealers|auction');
assert.ok(calls.includes('@sl_carauctions.view(true)'), 'the auction tab tells the game a screen is watching the lots');
laptop.handle('slAuctions', { money: 5000, lots: [
  { id: 'a1', name: 'Covet 1.5', grade: 'C', condition: 55, faults: ['brakes'], mileage: 120000, year: 2009, bid: 900, next: 950, high: 'ai', reserveMet: false, minutesLeft: 1500, delivery: 120, watched: false, preview: '/p.png',
    report: { condition: 55, label: 'Worn', mileage: 120000, damage: { amount: 10, label: 'Light' }, faults: ['brakes'], total: 600, sections: [{ id: 'brakes', title: 'Brakes', condition: 30, label: 'Worn', estimate: 300, faults: ['brakes'], parts: [] }] } },
  { id: 'a2', name: 'Pickup', grade: 'A', condition: 90, faults: [], bid: 4000, next: 4200, high: 'you', reserveMet: true, minutesLeft: 45, delivery: 300, watched: true } ],
  mine: [{ id: 'm1', name: 'My Hopper', grade: 'B', condition: 75, faults: [], bid: 0, next: 300, reserve: 3500, reserveMet: false, minutesLeft: 600, mine: true }],
  sellable: [{ id: 7, name: 'Bluebuck', grade: 'D', fair: 2000 }] });
assert.ok(text().includes('Covet 1.5') && text().includes('Grade C') && text().includes('Reserve not met') && text().includes('Outbid') && text().includes('1 d 1 h'), 'an auction lot shows the grade, the reserve state, who leads and the time left');
assert.ok(text().includes('Reserve met') && text().includes('You are the highest bidder') && text().includes('45 min') && text().includes('Watching (tap to stop)'), 'a lot you lead shows it, the minutes left and the watch');
assert.ok(text().includes('Your reserve $3,500') && text().includes('Your cars at auction') && text().includes('Bluebuck') && text().includes('Reserve 80%'), 'your own lots and the cars you can put up');
assert.ok(!$(sel('abid', 'a2|4200')), 'no bid button on a lot you already lead');
click('abid', 'a1|950');
assert.ok(calls.includes('@sl_carauctions.bid("a1",950)'), 'Bid asks the game with the next minimum');
click('abid', 'a1|990');
assert.ok(calls.includes('@sl_carauctions.bid("a1",990)'), 'Bid +10% asks with the raised amount');
click('awatch', 'a1|1');
assert.ok(calls.includes('@sl_carauctions.watch("a1",true)'), 'Watch asks the game');
click('asell', '7|1600');
assert.ok(calls.includes('@sl_carauctions.sell(7,1600)'), 'Sell at auction sends the car and the reserve');
click('report', 'auction:a1');
assert.ok($('.sll-repmodal') && $('.sll-repmodal').textContent.includes('Brakes'), 'a lot opens the same full car report');
click('reportclose');
laptop.handle('slAuctions', { money: 5000, lots: [], mine: [], sellable: [], live: { index: 2, total: 6, waiting: false, lot: { id: 'y12_2', name: 'Live Hopper', grade: 'B', condition: 75, faults: [], bid: 1200, next: 1260, high: 'ai', reserveMet: true, live: true, secondsLeft: 40, delivery: 0 } } });
assert.ok(text().includes('Live at the yard: lot 2 of 6') && text().includes('Live Hopper') && text().includes('Going in 40 s'), 'the live lot of the yard auction shows with its seconds left');
click('abid', 'y12_2|1260');
assert.ok(calls.includes('@sl_carauctions.bid("y12_2",1260)'), 'a live lot is bid on the same way');
click('mtab', 'dealers|dealers');
assert.ok(calls.includes('@sl_carauctions.view(false)'), 'leaving the tab stops the live view');
click('mtab', 'dealers|ads');
click('winclose', 'dealers');
click('tile', 'partsMarket');
assert.ok(titles()[0] === 'Part market' && text().includes('Sport exhaust') && !text().includes('Covet 1.5') && text().includes('Swap & Bid'), 'Part market: Revline parts, no car ads');
assert.ok(text().includes('Exhaust systems') && text().includes('fits the Covet') && !text().includes('for the covet') && $('.sll-win img.sll-partpic') && $('.sll-win .sll-pbadge'), 'a part card shows the chapter, the car it fits, the part picture and its category');
click('mtab', 'partmarket|auctions');
assert.ok(text().includes('Coilovers') && text().includes('Bid $110'), 'Swap & Bid lots');
calls.length = 0;
click('mtab', 'partmarket|catalog');
click('pcatalog', '1');
assert.ok(calls.includes('@sl_phone.catalog()'), 'the catalog button opens the Wrench Works catalog');
click('winclose', 'partmarket');


// ---- the wallpaper
open({ wallpaper: '/settings/street_legal/wallpaper.jpg' });
assert.ok(($('.sll-wall').getAttribute('style') || '').indexOf('/settings/street_legal/wallpaper.jpg') >= 0, 'the player\'s own Windows wallpaper is the desktop picture');
open();
assert.ok(!/url\(/.test($('.sll-wall').getAttribute('style') || ''), 'without one, the built-in wallpaper');

// ---- the Club window (#41): the same data as the phone's Club app
laptop.handle('slLaptopOpen', { name: 'Garage', lists: true, groups: [{ id: 'general', title: 'General', tiles: [tile('clubs', 'Club', true, null, 'club')] }], byCar: {}, parts: [] });
laptop.handle('slPhoneData', Object.assign({}, data, { club: { club: 'Club 1', season: 2, day: 3, days: 7, class: 'C', carClass: 'B', today: { night: { name: 'Quarry sprint', done: false }, day: { name: 'Time trial', done: false, open: true } },
  standings: [{ place: 1, name: 'Ana', points: 18 }, { place: 2, name: 'You', points: 16, you: true }] } }));
calls.length = 0;
click('tile', 'clubs');
assert.ok(titles()[0] === 'Club' && text().includes('season 2, day 3 of 7') && text().includes('Quarry sprint') && text().includes('Time trial') && text().includes('Ana') && text().includes('18'), 'the Club window: season, the day events and the standings');
click('league', 'night');
assert.ok(calls.includes('@sl_phone.enterLeague("night")'), 'Enter asks the club to enter the night league');
click('winclose', 'club');

// ---- Help (#55): the same pages as the phone's
laptop.handle('slLaptopOpen', { name: 'Garage', lists: true, groups: [{ id: 'general', title: 'General', tiles: [tile('help', 'Help', true, null, 'help')] }], byCar: {}, parts: [] });
calls.length = 0;
click('tile', 'help');
assert.ok(titles()[0] === 'Help' && calls.includes('@sl_phone.requestHelp()'), 'the Help window asks for the pages');
laptop.handle('slHelp', { pages: [{ id: 'first', title: 'Your first hour', body: ['Get a car.', '- Buy one'] }, { id: 'heat', title: 'Heat', body: ['Heat is 1 to 5.'] }] });
assert.ok(text().includes('Your first hour') && text().includes('Heat'), 'the topics');
click('helptopic', 'first');
assert.ok(text().includes('Get a car.') && text().includes('Buy one') && text().includes('All topics'), 'a page');
click('helpindex', '1');
assert.ok(text().includes('What would you like to know?'), 'back to the topics');
click('winclose', 'help');

// ---- #51 text size and the strings table
laptop.handle('slPhoneData', Object.assign({}, data, { textScale: 1.5 }));
assert.strictEqual(win.document.querySelector('[data-zoom]').getAttribute('data-zoom'), '1.5', 'the laptop scales its text with the setting');
laptop.handle('slPhoneData', data);
laptop.handle('slStrings', { text: { 'laptop.help': 'Hilfe' } });
click('tile', 'help');
assert.ok(text().includes('Hilfe'), 'a window title comes from the table');
click('winclose', 'help');
laptop.handle('slStrings', { text: {} });

// ---- the game closes it (the player drove away)
laptop.handle('slLaptopClose', {});
assert.ok($('.sll-screen.sll-gone'), 'the game can close it');

// ---- no car yet / an office computer without a car band
laptop.handle('slPhoneData', Object.assign({}, data, { fleet: [], cars: 0 }));
laptop.handle('slLaptopOpen', { name: 'Office', lists: false, groups: [{ id: 'general', title: 'General', tiles: [tile('vehicleShop', 'Car market', true, null, 'dealers'), tile('partsMarket', 'Part market', true, null, 'partmarket'), tile('partShop', 'Part customization', false, 'Use a computer in a garage for this.')] }], parts: [] });
assert.ok(!text().includes('My garage') && text().includes('Car market'), 'an office computer has no garage widget');
click('tile', 'partShop');
assert.ok(text().includes('Part customization: Use a computer in a garage for this.'), 'and says where the parts shop is');
laptop.handle('slLaptopOpen', { name: 'Garage', lists: true, groups: [{ id: 'car', title: 'Vehicle management', tiles: [tile('tuning', 'Tuning', false, 'You have no car yet.')] }], parts: [] });
assert.ok(text().includes('No car yet'), 'no car: the widget says so');
click('tile', 'tuning');
assert.ok(text().includes('Tuning: You have no car yet.'), 'and the icon says why');

// #51 colour-blind friendly colours and the pad focus ring
{ const layer = () => win.document.querySelector('[data-zoom]');
  laptop.handle('slPhoneData', Object.assign({}, laptop.state.data, { colorBlind: true }));
  assert.ok(layer().classList.contains('sll-cb'), 'colour-blind setting on: the laptop layer has sll-cb');
  laptop.handle('slPhoneData', Object.assign({}, laptop.state.data, { colorBlind: false }));
  assert.ok(!layer().classList.contains('sll-cb'), 'and off again');
  const css = [...win.document.querySelectorAll('style')].map((e) => e.textContent).join(' ');
  assert.ok(css.includes('.sll-cb .sll-plus:before') && css.includes('#56b4e9') && css.includes('#ffb454'), 'colour-blind CSS: marks and blue/orange');
  assert.ok(css.includes('[bng-nav-item]:focus') && css.includes('outline:3px solid #ffd54f'), 'the pad focus ring is always visible'); }
console.log('laptop test passed');
