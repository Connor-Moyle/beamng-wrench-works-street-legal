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

// the map's navigator picture turns with the car: west half red, east half blue, 2 km square round the origin
{
  const { createCanvas } = require('canvas');
  const art = createCanvas(64, 64), ag = art.getContext('2d');
  ag.fillStyle = '#ff0000'; ag.fillRect(0, 0, 32, 64); ag.fillStyle = '#0000ff'; ag.fillRect(32, 0, 32, 64);
  const dom3 = new JSDOM('<!doctype html><html><body></body></html>', { runScripts: 'outside-only', pretendToBeVisual: true, resources: 'usable' });
  dom3.window.__slHudTest = true;
  dom3.window.eval(code);
  const h3 = dom3.window.__slHudCreate(dom3.window.document);
  h3.handle('slHudMap', { segs: [], places: [], picture: { url: art.toDataURL(), x0: -1000, y0: 1000, x1: 1000, y1: -1000 } });
  const colourAt = (heading, x) => {                     // x: 0..1 across the map
    h3.handle('slHud', Object.assign({}, frame, { heading, target: null }));
    const c = h3.root.querySelector('.slh-map');
    const d = c.getContext('2d').getImageData(Math.round(x * c.width), Math.round(c.height / 2), 1, 1).data;
    return d[0] > d[2] ? 'red' : 'blue';
  };
  setTimeout(() => {
    assert.strictEqual(colourAt(0, 0.2) + colourAt(0, 0.8), 'redblue', 'facing north: west on the left');
    assert.strictEqual(colourAt(Math.PI, 0.2) + colourAt(Math.PI, 0.8), 'bluered', 'facing south: west on the right');
    console.log('hud picture test passed');
  }, 300);
}

console.log('hud test passed');

// --png <dir>: draw a frame (with SLRR's textures when tools/slrr_ui.py has copied them) and save each canvas
const i = process.argv.indexOf('--png');
if (i > 0) {
  const dir = process.argv[i + 1];
  const slrr = path.join(__dirname, '..', 'mod/ui/modModules/slHud/slrr');
  const dom2 = new JSDOM('<!doctype html><html><body></body></html>', { runScripts: 'outside-only', pretendToBeVisual: true, resources: 'usable' });
  dom2.window.__slHudTest = true;
  dom2.window.eval(code);
  const load = (name) => new Promise((res) => {
    const img = dom2.window.document.createElement('img');
    img.onload = () => res(img); img.onerror = () => res(null);
    img.src = 'file:///' + path.join(slrr, name).replace(/\\/g, '/');
  });
  Promise.all([load('general_gauge.png'), load('osd.png')]).then(([gauge, osd]) => {
    const h2 = dom2.window.__slHudCreate(dom2.window.document, { gauge, osd });
    h2.handle('slHud', frame);
    for (const c of h2.root.querySelectorAll('canvas')) {
      fs.writeFileSync(path.join(dir, c.className.split(' ')[0] + '.png'), Buffer.from(c.toDataURL('image/png').split(',')[1], 'base64'));
    }
    console.log('drew with SLRR textures:', !!gauge, !!osd);
  });
}
