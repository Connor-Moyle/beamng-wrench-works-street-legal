// Runs the laptop (ui/modModules/slLaptop/slLaptop.js) in a simulated page and checks what it shows, how a gamepad
// reaches it and what it asks the game for. Needs jsdom:  npm i jsdom   then   node tools/laptoptest.js
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
const click = (a, v) => $('[data-a="' + a + '"]' + (v === undefined ? '' : '[data-v="' + v + '"]')).dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
const nav = (name, value) => win.document.dispatchEvent(new win.CustomEvent('ui_nav', { detail: { name, value: value === undefined ? 1 : value } }));

// what sl/core/laptop.lua gives a garage computer once the player has a car (the car tiles wait: L3/L4)
const tile = (id, label, enabled, reason, page, mode) => ({ id, label, enabled, reason, page, mode });
const general = { id: 'general', title: 'General', tiles: [
  tile('vehicleInventory', 'My cars', true, null, 'cars'), tile('partInventory', 'My parts', true, null, 'parts'),
  tile('vehicleShop', 'Dealers', true, null, 'dealers'), tile('insurances', 'Bank / insurance', true, null, 'bank'), tile('playerAbstract', 'Street cred', true, null, 'cred')] };
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
  active: true, money: 12400, rep: 140, title: 'Street kid', titleRep: 100, nextRep: 300, day: 9, garage: 'Industrial Garage', cars: 2, stats: { races: 4, wins: 3 },
  fleet: [
    { id: 1, name: 'Sunburst 2.0 Sport S AWD', where: 'At the garage', condition: 0.8, value: 8900, active: true, faults: [] },
    { id: 2, name: 'Covet', where: 'Out on the street', condition: 0.5, value: 2100, out: true, towFee: 120, faults: ['battery'] },
  ],
  bank: { limit: 6000, rate: 0.02, premium: 90, deductible: 200 }, ledger: [{ label: 'Race', amount: 300 }, { label: 'Parts', amount: -80 }],
  achievements: { earned: 1, total: 2, list: [{ title: 'First win', desc: 'Win a race', day: 3 }, { title: 'King', desc: 'Win all' }] },
};

// nothing shows before it is opened
assert.ok($('.sll-screen.sll-gone'), 'the laptop starts closed');
laptop.handle('slPhoneData', data);
assert.ok($('.sll-screen.sll-gone'), 'phone data alone does not open it');
assert.ok($$('[data-a]').every((e) => e.getAttribute('bng-no-nav') === 'true' || !e.hasAttribute('bng-nav-item')), 'a closed laptop takes no gamepad focus');

// "Use the laptop": the home screen
laptop.handle('slLaptopOpen', Object.assign({}, view, { parts: [] }));
assert.ok(!$('.sll-screen.sll-gone'), 'it opens');
['Commercial Garage', 'Vehicle management', 'General', 'Part customization', 'Tuning', 'My cars', 'My parts', 'Dealers', 'Bank / insurance', 'Street cred', '$12,400', 'Day 9'].forEach((s) => assert.ok(text().includes(s), 'home shows ' + s));
assert.ok(text().includes('Sunburst 2.0 Sport S AWD'), 'the chosen car in the car band');
const tiles = $$('.sll-tile');
assert.ok(tiles.length === 7 && tiles.every((t) => t.hasAttribute('bng-nav-item') && t.getAttribute('tabindex') === '0'), 'every tile is a gamepad nav item');
assert.ok($('.sll-desk').hasAttribute('bng-nav-scroll'), 'the desktop scrolls on the right stick');
assert.ok($('.sll-task') && text().includes('Start') && text().includes('Shut down') && text().includes('Street kid') && text().includes('Day 9') && text().includes('$12,400'), 'the taskbar: Start, rank, day, money, Shut down');
assert.ok(!$('.sll-win') && !$('.sll-menu'), 'no window and no Start menu on the bare desktop');
assert.ok($$('.sll-task [data-a]').every((e) => e.hasAttribute('bng-nav-item')), 'the taskbar is reachable by the pad');
assert.ok($$('.sll-tile.sll-off').length === 0, 'nothing is greyed for a car at the garage');

// a garage tile sends the chosen car into the garage in its mode
calls.length = 0;
click('tile', 'tuning');
assert.ok(calls.includes('@sl_computer.enterGarage("tune",1)') && !$('[data-a="back"]'), 'Tuning: the garage opens on car 1 in tune mode');
click('tile', 'partShop');
assert.ok(calls.includes('@sl_computer.enterGarage("catalog",1)'), 'Part customization: the catalog');
// the stock dealers: the same cars as the lots, bought remotely
calls.length = 0;
click('tile', 'vehicleShop');
assert.ok(calls.includes('@sl_dealers.list()') && $('[data-a="back"]'), 'Dealers asks for the dealer list');
laptop.handle('slLaptopDealers', { dealers: [{ id: 'jeff', name: 'Jefferson Motors', metres: 4200, count: 5 }, { id: 'quarry', name: 'Quarryside', metres: 800, count: 1 }], coming: [{ name: 'Covet', hours: 3 }] });
assert.ok(text().includes('Jefferson Motors') && text().includes('4.2 km away') && text().includes('5 cars today') && text().includes('800 m away') && text().includes('1 car today'), 'dealers: name, distance, number of cars');
assert.ok(text().includes('On the way to your garage') && text().includes('in about 3 h'), 'and what is on its way');
click('dealer', 'jeff');
assert.ok(calls.includes('@sl_dealers.offers("jeff")'), 'a dealer asks for its cars');
laptop.handle('slLaptopOffers', { dealer: 'jeff', name: 'Jefferson Motors', money: 9000, offers: [
  { id: 'jeff:dealer-3-1', name: 'Bolide', title: 'New', mileage: 20, condition: 1, price: 7000, faults: [] },
  { id: 'jeff:dealer-3-2', name: 'Pessima', title: 'Tired', mileage: 150000, condition: 0.4, price: 9900, faults: ['battery'] }] });
assert.ok(text().includes('Bolide') && text().includes('20 km') && text().includes('condition 100%') && text().includes('Buy · $7,000') || text().includes('Buy · $7,000'), 'offer cards: name, mileage, condition, price');
assert.ok(text().includes('Needs: battery') && $$('.sll-btn.sll-off').length === 1, 'faults are listed and a car you cannot pay for is dimmed');
click('buy', 'jeff|jeff:dealer-3-1');
assert.ok(calls.includes('@sl_dealers.buy("jeff","jeff:dealer-3-1")'), 'Buy asks for that car');
laptop.handle('slPhoneToast', { text: 'The Bolide will be at your garage in about 3 hours.' });
assert.ok(text().includes('will be at your garage in about 3 hours'), 'the answer shows');
laptop.handle('slLaptopOffers', { dealer: 'jeff', name: 'Jefferson Motors', money: 2000, offers: [{ id: 'jeff:dealer-3-2', name: 'Pessima', mileage: 1, condition: 1, price: 9900, faults: [] }] });
const names = $$('.sll-card h4').map((h) => h.textContent);
assert.ok(!names.some((n) => n.includes('Bolide')) && names.some((n) => n.includes('Pessima')), 'a bought car is gone from the list');
calls.length = 0;
nav('back');
assert.ok(text().includes('Quarryside') && calls.includes('@sl_dealers.list()'), 'B goes back to the dealers');
nav('back');
assert.ok(text().includes('Vehicle management'), 'and then home');

// the car band: next / previous car, and tab_l / tab_r on the pad
click('car', '1');
assert.ok(text().includes('Covet') && text().includes('Out on the street'), 'the next car');
assert.ok($$('.sll-tile.sll-off').length === 2, 'the car away from the garage has its garage tiles greyed');
calls.length = 0;
click('tile', 'tuning');
assert.ok(text().includes('Tuning: Bring the car into the garage first.') && calls.length === 0, 'and the tile says why, sending nothing');
nav('tab_l');
assert.ok(text().includes('Sunburst 2.0 Sport S AWD'), 'tab_l on the pad: the car before');
nav('tab_r');
assert.ok(text().includes('Covet'), 'tab_r on the pad: the next car');

// the Start menu: every tile again; B shuts the menu first
click('start');
assert.ok($('.sll-menu') && $$('.sll-mi').length === 7 && $('.sll-menu').textContent.includes('Vehicle management') && $('.sll-menu').textContent.includes('Street cred'), 'Start lists the tiles by group');
assert.ok($$('.sll-mi').every((e) => e.hasAttribute('bng-nav-item')) && $$('.sll-tile').every((e) => !e.hasAttribute('bng-nav-item')), 'with the menu up the pad moves in the menu, not on the desktop behind it');
nav('back');
assert.ok(!$('.sll-menu') && !$('.sll-screen.sll-gone'), 'B closes the Start menu first, not the laptop');
click('start');
click('tile', 'vehicleInventory');
assert.ok(!$('.sll-menu') && $('.sll-win') && $('.sll-title').textContent.includes('My cars'), 'a Start menu item opens its window and shuts the menu');
click('back');
assert.ok(!$('.sll-win'), 'the X in the title bar closes the window');

// My cars: the phone's list, in a window
calls.length = 0;
click('tile', 'vehicleInventory');
assert.ok(calls.includes('@sl_phone.request()') && $('[data-a="back"]') && $('.sll-title').textContent.includes('My cars') && $('.sll-taskwin').textContent.includes('My cars'), 'a page is a window with a title bar and a taskbar button, asking for fresh data');
assert.ok($$('.sll-tile').every((e) => !e.hasAttribute('bng-nav-item')) && $$('.sll-win [data-a]').every((e) => e.hasAttribute('bng-nav-item')), 'with a window open the pad moves in the window');
assert.ok(text().includes('Drive this one') && text().includes('Tow it home') && text().includes('Needs: battery'), 'cars: use, tow, faults');
click('usecar', '2');
assert.ok(calls.includes('@sl_phone.useCar(2)'), 'drive this one');
click('tow', '2');
assert.ok(calls.includes('@sl_phone.tow(2)'), 'tow it home');
laptop.handle('slPhoneToast', { text: 'A tow truck is on its way.' });
assert.ok(text().includes('A tow truck is on its way.'), 'the answer shows on the laptop');
click('back');
assert.ok($('.sll-tile') && !text().includes('Drive this one'), 'back returns to the home screen');

// My parts: the Wrench Works shelf
calls.length = 0;
click('tile', 'partInventory');
assert.ok(calls.includes('@sl_computer.parts()') && text().includes('The shelf in your garage is empty'), 'parts asks the shelf; empty says so');
laptop.handle('slLaptopParts', { parts: [{ car: 'Covet', name: 'Sport exhaust', count: 2, value: 340 }] });
assert.ok(text().includes('Covet') && text().includes('Sport exhaust') && text().includes('$340'), 'a shelf part is listed under its car');

// Bank / insurance
nav('back');
click('tile', 'insurances');
assert.ok(text().includes('Balance') && text().includes('Borrow') && text().includes('Insurance') && text().includes('+$300') && text().includes('-$80'), 'bank: balance, loan, insurance, ledger');
calls.length = 0;
click('borrow', '3000');
click('insure', 'true');
assert.ok(calls.includes('@sl_phone.borrow(3000)') && calls.includes('@sl_phone.insure(true)'), 'borrow and insure');

// Street cred
nav('back');
click('tile', 'playerAbstract');
assert.ok(text().includes('Street kid') && text().includes('140 reputation') && text().includes('Achievements 1 / 2') && text().includes('First win'), 'street cred');

// B: back a page, then out; Escape too; the game's pause menu never sees it
let leaked = 0;
win.document.addEventListener('ui_nav', () => { leaked++; });
nav('back');
assert.ok(text().includes('Vehicle management') && !text().includes('Achievements'), 'B on a page goes back to the home screen');
calls.length = 0;
nav('back');
assert.ok($('.sll-screen.sll-gone') && calls.includes('@sl_computer.close()'), 'B on the home screen closes the laptop');
assert.ok(leaked === 0, 'B never reached the game (its pause menu stays shut)');
nav('back');
assert.ok($('.sll-screen.sll-gone'), 'a closed laptop leaves B alone');

// the Lua side closes it (driven away from the computer), and Close works with the mouse
laptop.handle('slLaptopOpen', Object.assign({}, view, { parts: [] }));
assert.ok(!$('.sll-screen.sll-gone'), 'opens again');
laptop.handle('slLaptopClose', {});
assert.ok($('.sll-screen.sll-gone'), 'the game can close it');
laptop.handle('slLaptopOpen', Object.assign({}, view, { parts: [] }));
click('close');
assert.ok($('.sll-screen.sll-gone'), 'Close closes it');

// no car yet / an office computer without a car band
laptop.handle('slPhoneData', Object.assign({}, data, { fleet: [], cars: 0 }));
laptop.handle('slLaptopOpen', { name: 'Office', lists: false, groups: [{ id: 'general', title: 'General', tiles: [tile('vehicleShop', 'Dealers', false, 'Coming soon.')] }], parts: [] });
assert.ok(!text().includes('Vehicle management') && text().includes('Dealers'), 'an office computer has no car band');
laptop.handle('slLaptopOpen', { name: 'Garage', lists: true, groups: [{ id: 'car', title: 'Vehicle management', tiles: [tile('tuning', 'Tuning', false, 'You have no car yet.')] }], parts: [] });
assert.ok(text().includes('No car yet'), 'no car: the car band says so');
click('tile', 'tuning');
assert.ok(text().includes('Tuning: You have no car yet.'), 'and the tile says why');

console.log('laptop test passed');
