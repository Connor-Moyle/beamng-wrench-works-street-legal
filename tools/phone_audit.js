// Audits the phone's pages in headless Chrome (real layout, real CSS) with the fixture of tools/phonetest.js, normal and with every name made long: elements outside the screen, boxes that overflow,
// small tap targets, text under 4.5:1 contrast, pages with nothing to read. Findings are advice for the UI style kit, not a test (it exits 0): node tools/phone_audit.js
// (built from tools/phone_shots.js, whose header follows) Renders pages of the phone in headless Chrome (real layout, the real CSS) with the fixture of tools/phonetest.js and saves one PNG per page, to LOOK at them for the UI style kit
// (docs/UI_STYLE.md): spacing, cards, rows, colours, focus. Needs Google Chrome (set CHROME for another path).
//   node tools/phone_shots.js <outdir> [app ...]        (default apps: home bank me jobs garage market)
const fs = require('fs'), os = require('os'), path = require('path'), assert = require('assert');
const { spawnSync } = require('child_process');

const CHROME = process.env.CHROME || ['C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe', '/usr/bin/google-chrome', '/usr/bin/chromium'].find((p) => fs.existsSync(p));
if (!CHROME) { console.log('phone shots skipped: no Chrome found (set CHROME)'); process.exit(0); }

const code = fs.readFileSync(path.join(__dirname, '..', 'mod/ui/modModules/slPhone/slPhone.js'), 'utf8');
const src = fs.readFileSync(path.join(__dirname, 'phonetest.js'), 'utf8');
const m = src.match(/\r?\nconst data = (\{[\s\S]*?\r?\n\});\r?\n/);
assert.ok(m, 'the phonetest fixture was not found');
// the extra data the newer pages draw
const calendar = JSON.stringify(require('./calendar_fixture.js'));
const season = JSON.stringify(require('./season_fixture.js'));
// every tools/<name>_fixture.js is the data of one page (the key is the name; travel_fixture has its own shape): drop one in for a new page and the audit covers it
const fixtures = {};
fs.readdirSync(__dirname).filter((f) => /_fixture\.js$/.test(f) && f !== 'travel_fixture.js').forEach((f) => { fixtures[f.replace(/_fixture\.js$/, '')] = require('./' + f); });
const fixturesJson = JSON.stringify(fixtures);
const extra = `{ season: ${season}, calendar: ${calendar}, weekly: { enabled: true, week: 3, dayOfWeek: 5, nextBillDay: 2, debt: 120, bills: [{ id: 'rent', label: 'Garage rent', amount: 150, due: 2 }, { id: 'ins', label: 'Insurance', amount: 80, due: 0 }], history: [{ week: 2, income: 900, costs: 400, net: 500 }, { week: 1, income: 100, costs: 300, net: -200 }] },
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
  var fx = ${fixturesJson};
  Object.keys(fx).forEach(function (k) { data[k] = fx[k]; });
  Object.keys(extra).forEach(function (k) { data[k] = extra[k]; });
  var STRESS = location.hash.indexOf('stress') >= 0;
  var KEYS = { name: 1, title: 1, label: 1, desc: 1, text: 1, where: 1, place: 1, from: 1, to: 1, item: 1, brand: 1, model: 1, car: 1, crew: 1, owner: 1, seller: 1, dealer: 1 };
  function longer(v, depth) {
    if (Array.isArray(v)) return v.map(function (x) { return longer(x, depth + 1); });
    if (v && typeof v === 'object') { var o = {}; Object.keys(v).forEach(function (k) { o[k] = (typeof v[k] === 'string' && KEYS[k] && v[k].length > 2 && v[k].length < 60) ? v[k] + ' of the Extremely Long Name Garage Crew' : longer(v[k], depth + 1); }); return o; }
    return v;
  }
  if (STRESS) data = longer(data, 0);
  var trip = ${JSON.stringify(require('./travel_fixture.js'))};
  var clock = { now: function () { return Date.now(); }, set: function (f, ms) { return setTimeout(f, ms); }, clear: function (t) { clearTimeout(t); } };
  var phone = window.__slPhoneCreate(document, function () {}, clock);
  document.body.appendChild(phone.root);
  phone.handle('slPhoneData', data);
  phone.handle('slPhoneToggle');
  function rgba(c) { var m = /rgba?\(([^)]+)\)/.exec(c); if (!m) return null; var p = m[1].split(',').map(parseFloat); return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 }; }
  function lum(c) { function f(v) { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); } return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b); }
  function bgOf(el) {
    var layers = [], n = el;
    while (n && n.nodeType === 1) { var cs = getComputedStyle(n); if (cs.backgroundImage && cs.backgroundImage !== 'none') return null; var b = rgba(cs.backgroundColor); if (b && b.a > 0) { layers.push(b); if (b.a >= 1) break; } n = n.parentElement; }
    var base = { r: 20, g: 18, b: 24 };
    layers.reverse().forEach(function (l) { base = { r: base.r * (1 - l.a) + l.r * l.a, g: base.g * (1 - l.a) + l.g * l.a, b: base.b * (1 - l.a) + l.b * l.a }; });
    return base;
  }
  function audit(id) {
    var dev = phone.root.querySelector('.slp-device') || phone.root, dr = dev.getBoundingClientRect(), issues = [], seen = {};
    function add(kind, el, extra) { var t = (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 50); var key = kind + t; if (seen[key]) return; seen[key] = 1; if (issues.length < 40) issues.push(kind + ': ' + t + (extra ? ' [' + extra + ']' : '') + ' <' + el.tagName.toLowerCase() + ' ' + (el.className || '') + '>'); }
    var all = dev.querySelectorAll('*');
    for (var i = 0; i < all.length; i++) {
      var el = all[i]; if (el.closest('style') || el.tagName === 'STYLE' || el.closest('svg')) continue;
      var r = el.getBoundingClientRect(); if (r.width === 0 || r.height === 0) continue;
      var cs = getComputedStyle(el);
      if (cs.visibility === 'hidden' || cs.display === 'none') continue;
      var inScroll = false; for (var q = el.parentElement; q && q !== dev; q = q.parentElement) { var qs = getComputedStyle(q); if (qs.overflowX === 'auto' || qs.overflowX === 'scroll') { inScroll = true; break; } }
      if (!inScroll && (r.right > dr.right + 1 || r.left < dr.left - 1)) add('outside the screen', el, Math.round(r.right - dr.right) + 'px');      // (a strip that scrolls sideways is allowed to run on)
      if (el.scrollWidth > el.clientWidth + 1 && cs.overflowX !== 'auto' && cs.overflowX !== 'scroll' && !(cs.textOverflow === 'ellipsis' && cs.overflowX === 'hidden') && el.clientWidth > 0 && cs.display !== 'inline') add('overflows its box', el, el.scrollWidth + '>' + el.clientWidth);      // (an ellipsis is the design for a long name)
      var sc = dev.offsetWidth ? dr.width / dev.offsetWidth : 1;      // (the phone is scaled to its window: sizes in CSS pixels)
      if (el.hasAttribute('data-a') && r.height / sc < 30 && r.width / sc < 30) add('small tap target', el, Math.round(r.width / sc) + 'x' + Math.round(r.height / sc));
      var own = ''; el.childNodes.forEach(function (n) { if (n.nodeType === 3) own += n.textContent; });
      if (own.trim().length > 1) {
        var fg = rgba(cs.color), bg = bgOf(el);
        if (fg && bg) { if (fg.a < 1) fg = { r: fg.r * fg.a + bg.r * (1 - fg.a), g: fg.g * fg.a + bg.g * (1 - fg.a), b: fg.b * fg.a + bg.b * (1 - fg.a) }; var L1 = lum(fg), L2 = lum(bg), ratio = (Math.max(L1, L2) + 0.05) / (Math.min(L1, L2) + 0.05), px = parseFloat(cs.fontSize); if (ratio < (px >= 18 ? 3 : 4.5) && cs.opacity > 0.5) add('low contrast', el, ratio.toFixed(1) + ':1 at ' + px + 'px'); }
      }
    }
    var body = phone.root.querySelector('.slp-body'); var txt = (body ? body.textContent : dev.textContent).trim();
    if (txt.length < 12) issues.push('empty page: nothing to read (' + txt.length + ' characters)');
    return { page: id, issues: issues };
  }
  var APPS = ['home', 'races', 'garage', 'garagekit', 'bank', 'me', 'sponsors', 'calendar', 'traps', 'jobs', 'wait', 'help', 'map', 'camera', 'gallery', 'club', 'turf', 'carmarket', 'partmarket', 'messages', 'contacts', 'phone', 'cab', 'health'];
  var results = [];
  APPS.forEach(function (id) { try { phone.act('home'); if (id !== 'home') phone.act('open', id); results.push(audit(id)); } catch (e) { results.push({ page: id, issues: ['could not open: ' + e.message] }); } });
  ['week', 'series'].forEach(function (tab) { try { phone.act('home'); phone.act('open', 'calendar'); phone.act('caltab', tab); results.push(audit('calendar:' + tab)); } catch (e) { results.push({ page: 'calendar:' + tab, issues: ['could not open: ' + e.message] }); } });
  try { phone.act('home'); phone.handle('slPhoneData', Object.assign({}, data, { visit: trip.visit, hub: trip.hub })); phone.act('open', 'event'); results.push(audit('event')); } catch (e) { results.push({ page: 'event', issues: ['could not open: ' + e.message] }); }
  try { phone.act('home'); phone.handle('slPhoneData', Object.assign({}, data, { travelPick: trip.options })); results.push(audit('pick')); } catch (e) { results.push({ page: 'pick', issues: ['could not open: ' + e.message] }); }
  var pre = document.createElement('pre'); pre.id = 'audit'; pre.textContent = JSON.stringify(results); document.body.appendChild(pre);
})();`;
const html = '<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;width:100%;height:100%;background:#303030}</style></head><body><script>' + harness.replace(/<\/script>/g, '<\\/script>') + '</script></body></html>';
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'phone-audit-'));
const file = path.join(dir, 'page.html');
fs.writeFileSync(file, html);
let bad = 0;
for (const mode of ['normal', 'stress']) {
  const r = spawnSync(CHROME, ['--headless=new', '--disable-gpu', '--no-sandbox', '--window-size=520,860', '--virtual-time-budget=4000', '--user-data-dir=' + path.join(dir, 'p-' + mode), '--dump-dom', 'file:///' + file.split(path.sep).join('/') + '#' + mode], { encoding: 'utf8', timeout: 90000, maxBuffer: 64 * 1024 * 1024 });
  const m2 = /<pre id="audit">([\s\S]*?)<\/pre>/.exec(r.stdout || '');
  if (!m2) { console.log(mode + ': the page did not answer ' + (r.stderr || '').slice(0, 200)); bad++; continue; }
  const results = JSON.parse(m2[1].replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&'));
  console.log('== ' + mode + (mode === 'stress' ? ' (every name made long)' : ''));
  for (const p of results) { if (p.issues.length) { bad += p.issues.length; console.log('  ' + p.page + ':'); p.issues.forEach((x) => console.log('    ' + x)); } }
}
console.log(bad ? 'phone audit: ' + bad + ' findings' : 'phone audit: clean');
