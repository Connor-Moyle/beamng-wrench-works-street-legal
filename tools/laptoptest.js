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
  tile('vehicleShop', 'Dealers', false, 'Coming soon.'), tile('insurances', 'Bank / insurance', true, null, 'bank'), tile('playerAbstract', 'Street cred', true, null, 'cred')] };
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
assert.ok($('.sll-body').hasAttribute('bng-nav-scroll'), 'the body scrolls on the right stick');
assert.ok($$('.sll-tile.sll-off').length === 1, 'only Dealers is greyed for a car at the garage');

// a garage tile sends the chosen car into the garage in its mode
calls.length = 0;
click('tile', 'tuning');
assert.ok(calls.includes('@sl_computer.enterGarage("tune",1)') && !$('[data-a="back"]'), 'Tuning: the garage opens on car 1 in tune mode');
click('tile', 'partShop');
assert.ok(calls.includes('@sl_computer.enterGarage("catalog",1)'), 'Part customization: the catalog');
// a greyed tile says why and goes nowhere
click('tile', 'vehicleShop');
assert.ok(text().includes('Dealers: Coming soon.') && calls.length === 2, 'a greyed tile gives its reason and sends nothing');

// the car band: next / previous car, and tab_l / tab_r on the pad
click('car', '1');
assert.ok(text().includes('Covet') && text().includes('Out on the street'), 'the next car');
assert.ok($$('.sll-tile.sll-off').length === 3, 'the car away from the garage has its garage tiles greyed');
calls.length = 0;
click('tile', 'tuning');
assert.ok(text().includes('Tuning: Bring the car into the garage first.') && calls.length === 0, 'and the tile says why, sending nothing');
nav('tab_l');
assert.ok(text().includes('Sunburst 2.0 Sport S AWD'), 'tab_l on the pad: the car before');
nav('tab_r');
assert.ok(text().includes('Covet'), 'tab_r on the pad: the next car');

// My cars: the phone's list
calls.length = 0;
click('tile', 'vehicleInventory');
assert.ok(calls.includes('@sl_phone.request()') && $('[data-a="back"]'), 'a page asks for fresh data and has a back button');
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
