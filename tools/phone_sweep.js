// Opens every app of the phone in a simulated page (with the fixture of phonetest.js and its markets / wait / settings data) and checks that nothing on any screen
// shows a broken value: [object ..], undefined, NaN, null, an unfilled {1}, a stray %s, a raw table. Needs jsdom:  node tools/phone_sweep.js
const fs = require('fs'), path = require('path'), assert = require('assert');
const { JSDOM } = require('jsdom');

const code = fs.readFileSync(path.join(__dirname, '..', 'mod/ui/modModules/slPhone/slPhone.js'), 'utf8');
const src = fs.readFileSync(path.join(__dirname, 'phonetest.js'), 'utf8');
const m = src.match(/\r?\nconst data = (\{[\s\S]*?\r?\n\});\r?\n/);
assert.ok(m, 'the phonetest fixture was not found');
const data = new Function('return ' + m[1])();

const dom = new JSDOM('<!doctype html><html><body></body></html>', { runScripts: 'outside-only', pretendToBeVisual: true });
const win = dom.window;
win.__slPhoneTest = true;
win.eval(code);
const calls = [];
const phone = win.__slPhoneCreate(win.document, (c) => calls.push(c), { now: () => 0, set: () => ({}), clear: () => {} });

const BAD = /\[object|undefined|NaN|\bnull\b|\{\d\}|%[sd]|function\s*\(|\$\{|table: 0x/;
const checked = [];
function check(label) {
  const t = phone.root.textContent;
  const hit = t.match(BAD);
  assert.ok(!hit, label + ' shows a broken value: "' + (hit && t.slice(Math.max(0, hit.index - 40), hit.index + 40)) + '"');
  checked.push(label);
}

// a richer fixture for the apps the phonetest one leaves bare
const full = Object.assign({}, data, {
  jobs: { active: null, offers: [], done: 0 }, upgrades: [{ id: 'lift', name: 'Two-post lift', price: 2000, desc: 'Gearbox work', has: false }],
  bank: { limit: 6000, rate: 0.03, premium: 80, premiumWhy: 'No claims in the last 28 days: the base premium.', deductible: 200 },
  weather: { state: 'rain', level: 'heavy', name: 'Rain', wet: true, text: 'Heavy rain today. Wet roads.' },
  market: { deliveries: 0, listings: [], auctions: [], mine: [], shelf: [], cars: [], paper: { edition: 1, listings: [], price: 2 }, meet: {} },
  fleet: [{ id: 1, name: 'Covet', where: 'In the garage', condition: 0.8, faults: [], look: 'Dusty, no scratches', out: false }], textScale: 1,
});
phone.handle('slPhoneData', full);
phone.handle('slPhoneToggle');
check('home');
const apps = [...phone.root.querySelectorAll('[data-a="open"]')].map((e) => e.getAttribute('data-v'));
assert.ok(apps.length >= 8, 'the home screen offers the apps: ' + apps.join(','));
for (const app of [...new Set(apps)]) {
  phone.act('home');
  phone.act('open', app);
  check('app ' + app);
  if (app === 'garage') assert.ok(phone.root.textContent.includes('Dusty, no scratches'), 'the My cars card shows how dirty and scratched the car is (Car Surface FX)');
  // and every tab / sub button of the app that only changes the page (not asks the game for anything)
  const tabs = [...phone.root.querySelectorAll('[data-a="mtab"],[data-a="cmtab"],[data-a="tab"]')];
  for (const t of tabs) {
    phone.act(t.getAttribute('data-a'), t.getAttribute('data-v'));
    check('app ' + app + ' tab ' + t.getAttribute('data-v'));
  }
}
// the test hook the game's run_lua script uses (sl_phone.go(app)) opens every app from wherever the phone is
for (const app of [...new Set(apps)]) { phone.handle('slPhoneGo', { app }); check('slPhoneGo ' + app); }
phone.handle('slPhoneGo', { app: 'home' }); check('slPhoneGo home');
// the game's own sub events: a toast, a call, a heads-up, then closing
phone.handle('slPhoneToast', { text: 'A tow truck is on its way.' });
check('a toast');
phone.act('home');
phone.handle('slPhoneToggle');
check('closed again');
phone.handle('slPhoneData', Object.assign({}, full, { phase: 'night', heat: 3 }));
check('the pill at night with heat');
console.log('phone sweep passed: ' + checked.length + ' screens (' + [...new Set(apps)].join(', ') + ')');
