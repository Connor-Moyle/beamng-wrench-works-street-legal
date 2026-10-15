// Runs the dashboard (ui/modModules/slHud/slHud.js) in a simulated page: it draws without errors,
// hides and shows, and leaves out the parts switched off. Needs jsdom and canvas:  npm i jsdom canvas
// With --png <dir> it also saves what each canvas drew, to look at.
const fs = require('fs'), path = require('path'), assert = require('assert');
const { JSDOM } = require('jsdom');

const code = fs.readFileSync(path.join(__dirname, '..', 'mod/ui/modModules/slHud/slHud.js'), 'utf8');
const dom = new JSDOM('<!doctype html><html><body></body></html>', { runScripts: 'outside-only', pretendToBeVisual: true });
const win = dom.window;
win.__slHudTest = true;
win.eval(code);
const hud = win.__slHudCreate(win.document);
const gone = (sel) => hud.root.querySelector(sel).classList.contains('slh-gone');

assert.ok(hud.root.classList.contains('slh-gone'), 'hidden until there is something to show');
// a small square of roads round the origin, and a garage
hud.handle('slHudMap', { segs: [-100, -100, 100, -100, 100, -100, 100, 100, 100, 100, -100, 100, -100, 100, -100, -100], places: [{ kind: 'garage', x: 50, y: 0 }] });
const frame = { show: true, speed: 30, rpm: 6800, maxRpm: 7000, gear: 4, x: 0, y: 0, heading: 0.5,
  body: { FL: 0.6, FR: 0.1, ML: 0, MR: 0, RL: 0.3, RR: 0 }, engine: 1, tyres: { FL: true }, target: { x: 400, y: 400 },
  settings: { enabled: true, speedo: true, tacho: true, map: true, damage: true, units: 'kmh' } };
hud.handle('slHud', frame);
assert.ok(!hud.root.classList.contains('slh-gone'), 'shown while driving');
assert.ok(!gone('.slh-map') && !gone('.slh-dmg') && !gone('.slh-tacho') && !gone('.slh-speedo'), 'all four parts');
hud.handle('slHud', Object.assign({}, frame, { gear: 'R', settings: Object.assign({}, frame.settings, { map: false, damage: false, units: 'mph' }) }));
assert.ok(gone('.slh-map') && gone('.slh-dmg') && !gone('.slh-speedo'), 'switched-off parts are left out');
hud.handle('slHud', { show: false });
assert.ok(hud.root.classList.contains('slh-gone'), 'hidden on foot, in the garage and so on');

const i = process.argv.indexOf('--png');
if (i > 0) {
  hud.handle('slHud', frame);
  const dir = process.argv[i + 1];
  for (const c of hud.root.querySelectorAll('canvas')) {
    fs.writeFileSync(path.join(dir, c.className + '.png'), Buffer.from(c.toDataURL('image/png').split(',')[1], 'base64'));
  }
}
console.log('hud test passed');
