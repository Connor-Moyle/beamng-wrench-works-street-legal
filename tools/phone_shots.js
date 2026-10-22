// Renders pages of the phone in headless Chrome (real layout, the real CSS) with the fixture of tools/phonetest.js and saves one PNG per page, to LOOK at them for the UI style kit
// (docs/UI_STYLE.md): spacing, cards, rows, colours, focus. Needs Google Chrome (set CHROME for another path).
//   node tools/phone_shots.js <outdir> [app ...]        (default apps: home bank me jobs garage market)
const fs = require('fs'), os = require('os'), path = require('path'), assert = require('assert');
const { spawnSync } = require('child_process');

const CHROME = process.env.CHROME || ['C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe', '/usr/bin/google-chrome', '/usr/bin/chromium'].find((p) => fs.existsSync(p));
if (!CHROME) { console.log('phone shots skipped: no Chrome found (set CHROME)'); process.exit(0); }
const out = path.resolve(process.argv[2] || path.join(os.tmpdir(), 'phone-shots'));
const apps = process.argv.slice(3).length ? process.argv.slice(3) : ['home', 'bank', 'me', 'jobs', 'garage', 'market'];
fs.mkdirSync(out, { recursive: true });

const code = fs.readFileSync(path.join(__dirname, '..', 'mod/ui/modModules/slPhone/slPhone.js'), 'utf8');
const src = fs.readFileSync(path.join(__dirname, 'phonetest.js'), 'utf8');
const m = src.match(/\r?\nconst data = (\{[\s\S]*?\r?\n\});\r?\n/);
assert.ok(m, 'the phonetest fixture was not found');
// the extra data the newer pages draw
const calendar = JSON.stringify(require('./calendar_fixture.js'));
const justice = JSON.stringify(require('./justice_fixture.js'));
const extra = `{ justice: ${justice}, calendar: ${calendar}, weekly: { enabled: true, week: 3, dayOfWeek: 5, nextBillDay: 2, debt: 120, bills: [{ id: 'rent', label: 'Garage rent', amount: 150, due: 2 }, { id: 'ins', label: 'Insurance', amount: 80, due: 0 }], history: [{ week: 2, income: 900, costs: 400, net: 500 }, { week: 1, income: 100, costs: 300, net: -200 }] },
  perks: { tier: 2, list: [{ id: 'g', label: 'Garage discount', text: '10 % off garage upgrades', unlocked: true, tier: 1 }, { id: 'd', label: 'Dealer tier', text: 'The second dealer sells to you', unlocked: true, tier: 2 }, { id: 's', label: 'Sponsor slot', text: 'A sponsor can pay you weekly', unlocked: false, tier: 3 }] },
  needs: { meters: [{ id: 'food', value: 72, stage: 'ok', word: 'fed' }, { id: 'water', value: 28, stage: 'handicap', word: 'parched' }, { id: 'rest', value: 9, stage: 'problem', word: 'exhausted' }], wellFed: false, effects: { blur: 0.3, lag: 0.05, tremor: 0, sleepy: true }, items: [{ id: 'drink', name: 'Drink', price: 2 }, { id: 'meal', name: 'Meal', price: 12 }], canEat: true, canNap: false, showMeters: false },
  traps: { list: [{ id: 't2', name: 'Speed trap 2', kind: 'trap', target: 150, best: 182, count: 3, paid: true, metres: 4200, pay: 250 }, { id: 'z1', name: 'Speed zone 1', kind: 'zone', target: 90, best: 0, count: 0, paid: false, metres: 800, pay: 400 }] },
  jobs: { done: 2, earned: 640, offers: [{ id: 'k1', title: 'Contract: Courier', item: 'parcel', from: 'A', to: 'B', pay: 500, seconds: 200, contract: { req: 'rain', label: 'Deliver it in the rain', mult: 1.9, basePay: 260 } }, { id: '5d:1', title: 'Part run', item: 'turbocharger', from: 'Redline Speed Shop', to: 'Club Garage 1', pay: 380, seconds: 240, metres: 2100, fragile: true }] } }`;
const harness = `
window.__slPhoneTest = true;
${code}
(function () {
  var data = ${m[1]};
  var extra = ${extra};
  Object.keys(extra).forEach(function (k) { data[k] = extra[k]; });
  var hash = (location.hash.slice(1) || 'home').split(':'), app = hash[0];
  var trip = ${JSON.stringify(require('./travel_fixture.js'))};
  if (app === 'event') { data.visit = trip.visit; data.hub = trip.hub; }
  if (app === 'pick') data.travelPick = trip.options;
  var clock = { now: function () { return Date.now(); }, set: function (f, ms) { return setTimeout(f, ms); }, clear: function (t) { clearTimeout(t); } };
  var phone = window.__slPhoneCreate(document, function () {}, clock);
  document.body.appendChild(phone.root);
  phone.handle('slPhoneData', data);
  phone.handle('slPhoneToggle');
  if (app !== 'home') { phone.act('home'); phone.act('open', app); if (hash[1] === 'week' || hash[1] === 'series') phone.act('caltab', hash[1]); if (hash[1] === 'event') phone.act('calopen', 'utah-rally:3:r1'); }
  document.title = 'ready';
})();`;
const html = '<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;width:100%;height:100%;background:#303030}</style></head><body><script>' + harness.replace(/<\/script>/g, '<\\/script>') + '</script></body></html>';
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'phone-shots-'));
const file = path.join(dir, 'page.html');
fs.writeFileSync(file, html);
for (const app of apps) {
  const png = path.join(out, app.replace(':', '_') + '.png');
  const r = spawnSync(CHROME, ['--headless=new', '--disable-gpu', '--no-sandbox', '--hide-scrollbars', '--window-size=520,860', '--virtual-time-budget=3000', '--user-data-dir=' + path.join(dir, 'p-' + app.replace(':', '_')), '--screenshot=' + png, 'file:///' + file.split(path.sep).join('/') + '#' + app], { encoding: 'utf8', timeout: 60000 });
  console.log(app + ': ' + (fs.existsSync(png) ? png : 'no shot ' + (r.stderr || '').slice(0, 120)));
}
