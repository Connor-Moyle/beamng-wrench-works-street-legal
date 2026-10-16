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
  active: true, money: 12400, rep: 140, title: 'Street kid', titleRep: 100, nextRep: 300, day: 9, hour: 21, minute: 5, garage: 'Industrial Garage', cars: 2, stats: { races: 4, wins: 3 },
  fleet: [
    { id: 1, name: 'Sunburst 2.0 Sport S AWD', where: 'At the garage', condition: 0.8, value: 8900, active: true, faults: [] },
    { id: 2, name: 'Covet', where: 'Out on the street', condition: 0.5, value: 2100, out: true, towFee: 120, faults: ['battery'] },
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
assert.deepStrictEqual(icons.map((i) => i.textContent), ['Part customization', 'Tuning', 'My cars', 'My parts', 'Dealers', 'Bank / insurance', 'Street cred'], 'one desktop icon per function, labelled');
assert.ok(icons.every((i) => i.querySelector('svg') && i.hasAttribute('bng-nav-item') && i.getAttribute('tabindex') === '0'), 'each icon has a picture and is a gamepad nav item');
assert.ok($('.sll-icons').hasAttribute('bng-nav-scroll'), 'the icon column scrolls on the right stick');
assert.ok(text().includes('My garage') && text().includes('Sunburst 2.0 Sport S AWD'), 'the car widget, a small window of its own');
assert.ok($('.sll-task') && $('[data-a="start"]') && text().includes('Start') && text().includes('Street kid') && text().includes('21:05') && text().includes('Day 9') && text().includes('$12,400'), 'the taskbar: Start, and the tray with rank, clock, day and money');
assert.ok($$('.sll-task [data-a]').every((e) => e.hasAttribute('bng-nav-item')), 'the taskbar is reachable by the pad');
assert.ok($$('.sll-icon.sll-off').length === 0, 'nothing is greyed for a car at the garage');

// ---- selecting and opening an icon as in Windows
click('tile', 'vehicleInventory', 1);
assert.ok($(sel('tile', 'vehicleInventory')).classList.contains('sll-sel') && !wins().length, 'one mouse click selects an icon');
calls.length = 0;
click('tile', 'vehicleInventory', 2);
assert.ok(wins().length === 1 && titles()[0] === 'My cars' && calls.includes('@sl_phone.request()'), 'a double click opens it in a window (and asks for fresh data)');
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
assert.ok(calls.includes('@sl_phone.useCar(2)') && calls.includes('@sl_phone.tow(2)'), 'drive this one, tow it home');
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
assert.ok($('.sll-menu') && items.length === 7 && items.every((i) => i.querySelector('svg') && i.hasAttribute('bng-nav-item')), 'Start lists every app with its icon');
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
assert.ok(calls.includes('@sl_dealers.list()') && titles()[0] === 'Dealers', 'Dealers asks for the dealer list');
laptop.handle('slLaptopDealers', { dealers: [{ id: 'jeff', name: 'Jefferson Motors', metres: 4200, count: 5 }, { id: 'quarry', name: 'Quarryside', metres: 800, count: 1 }], coming: [{ name: 'Covet', hours: 3 }] });
assert.ok(text().includes('Jefferson Motors') && text().includes('4.2 km away') && text().includes('5 cars today') && text().includes('800 m away') && text().includes('1 car today'), 'dealers: name, distance, number of cars');
assert.ok(text().includes('On the way to your garage') && text().includes('in about 3 h'), 'and what is on its way');
click('dealer', 'jeff');
assert.ok(calls.includes('@sl_dealers.offers("jeff")'), 'a dealer asks for its cars');
laptop.handle('slLaptopOffers', { dealer: 'jeff', name: 'Jefferson Motors', money: 9000, offers: [
  { id: 'jeff:dealer-3-1', name: 'Bolide', brand: 'Bruckell', year: 2012, title: 'New', mileage: 20, condition: 1, price: 7000, faults: [], seller: 'Jefferson Motors', metres: 4200, hours: 3,
    preview: '/vehicles/bolide/sport.png', specs: { power: 310, weight: 1250, transmission: 'Manual', drivetrain: 'RWD', fuel: 'Gasoline', body: 'Coupe', topSpeed: 75 } },
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
assert.ok(text().includes('Quarryside') && calls.includes('@sl_dealers.list()') && titles()[0] === 'Dealers', 'B goes back to the dealers');
nav('back');
assert.ok(!wins().length, 'and then closes the window');

// ---- the wallpaper
open({ wallpaper: '/settings/street_legal/wallpaper.jpg' });
assert.ok(($('.sll-wall').getAttribute('style') || '').indexOf('/settings/street_legal/wallpaper.jpg') >= 0, 'the player\'s own Windows wallpaper is the desktop picture');
open();
assert.ok(!/url\(/.test($('.sll-wall').getAttribute('style') || ''), 'without one, the built-in wallpaper');

// ---- the game closes it (the player drove away)
laptop.handle('slLaptopClose', {});
assert.ok($('.sll-screen.sll-gone'), 'the game can close it');

// ---- no car yet / an office computer without a car band
laptop.handle('slPhoneData', Object.assign({}, data, { fleet: [], cars: 0 }));
laptop.handle('slLaptopOpen', { name: 'Office', lists: false, groups: [{ id: 'general', title: 'General', tiles: [tile('vehicleShop', 'Dealers', true, null, 'dealers'), tile('partShop', 'Part customization', false, 'Use a computer in a garage for this.')] }], parts: [] });
assert.ok(!text().includes('My garage') && text().includes('Dealers'), 'an office computer has no garage widget');
click('tile', 'partShop');
assert.ok(text().includes('Part customization: Use a computer in a garage for this.'), 'and says where the parts shop is');
laptop.handle('slLaptopOpen', { name: 'Garage', lists: true, groups: [{ id: 'car', title: 'Vehicle management', tiles: [tile('tuning', 'Tuning', false, 'You have no car yet.')] }], parts: [] });
assert.ok(text().includes('No car yet'), 'no car: the widget says so');
click('tile', 'tuning');
assert.ok(text().includes('Tuning: You have no car yet.'), 'and the icon says why');

console.log('laptop test passed');
