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
// D4: the day or night and the heat
assert.ok(gone('.slh-status'), 'no career, no status');
hud.handle('slHud', Object.assign({}, frame, { phase: 'night', heat: 3 }));
assert.ok(!gone('.slh-status') && hud.root.querySelector('.slh-status').textContent.includes('Night') && hud.root.querySelectorAll('.slh-heat i').length === 2, 'night, heat 3: three of five lit');
hud.handle('slHud', Object.assign({}, frame, { phase: 'day', heat: 0 }));
assert.ok(hud.root.querySelector('.slh-status').textContent.includes('Day') && !hud.root.querySelector('.slh-heat'), 'day without heat: no heat meter');
{ const node = hud.root.querySelector('.slh-status span'); hud.handle('slHud', Object.assign({}, frame, { phase: 'day', heat: 0 })); assert.ok(hud.root.querySelector('.slh-status span') === node, 'the same status again does not rebuild it (UI smoothness)'); hud.handle('slHud', Object.assign({}, frame, { phase: 'night', heat: 1 })); assert.ok(hud.root.querySelector('.slh-status span') !== node, 'a changed status is rebuilt'); hud.handle('slHud', Object.assign({}, frame, { phase: 'day', heat: 0 })); }
// #51 the words come from Lua (labels), the heat is a number as well as flames, the text size scales the HUD's text
hud.handle('slHud', Object.assign({}, frame, { phase: 'night', heat: 2, atRisk: 80, labels: { day: 'Tag', night: 'Nacht', heat: 'Hitze {1}', atRisk: '+{1} Ruf' }, settings: Object.assign({}, frame.settings, { textScale: 1.5 }) }));
const stText = hud.root.querySelector('.slh-status').textContent;
assert.ok(stText.includes('Nacht') && stText.includes('2') && stText.includes('+80 Ruf') && hud.root.querySelector('.slh-heat').getAttribute('title') === 'Hitze 2', 'status: the labels, the heat number, the risk');
assert.strictEqual(hud.root.getAttribute('data-zoom'), '1.5', 'the text size scales the HUD');
hud.handle('slHud', Object.assign({}, frame, { phase: 'night', heat: 0, settings: frame.settings }));

// #49 the performance box: shown by the slPerf event, whatever the HUD does, hidden when it says so
const perfGone = () => hud.root.ownerDocument.querySelector('.slh-perf').classList.contains('slh-gone');
assert.ok(perfGone(), 'off by default');
hud.handle('slPerf', { show: true, lines: ['16.7 ms  60 fps', 'worst 40 ms (10 s)'] });
assert.ok(!perfGone() && hud.root.ownerDocument.querySelector('.slh-perf').textContent.includes('worst 40 ms'), 'the numbers show');
hud.handle('slPerf', { show: false });
assert.ok(perfGone(), 'and go');

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

// tiles: the whole level (red) first, the city (blue, 600 m round the origin) on top of it
{
  const { createCanvas } = require('canvas');
  const tile = (colour) => { const c = createCanvas(8, 8), g = c.getContext('2d'); g.fillStyle = colour; g.fillRect(0, 0, 8, 8); return c.toDataURL(); };
  const dom4 = new JSDOM('<!doctype html><html><body></body></html>', { runScripts: 'outside-only', pretendToBeVisual: true, resources: 'usable' });
  dom4.window.__slHudTest = true;
  dom4.window.eval(code);
  const h4 = dom4.window.__slHudCreate(dom4.window.document);
  h4.handle('slHudMap', { segs: [], places: [], pictures: [
    { url: tile('#ff0000'), x0: -5000, y0: 5000, x1: 5000, y1: -5000 },
    { url: tile('#0000ff'), x0: -600, y0: 600, x1: 600, y1: -600 } ] });
  const centre = (x, y) => {
    h4.handle('slHud', Object.assign({}, frame, { x, y, heading: 0, target: null }));
    const c = h4.root.querySelector('.slh-map');
    const d = c.getContext('2d').getImageData(Math.round(c.width / 2), Math.round(c.height / 2) + 40, 1, 1).data;
    return d[0] > d[2] ? 'red' : 'blue';
  };
  setTimeout(() => {
    assert.strictEqual(centre(0, 0), 'blue', 'in the city: the city tile, on top');
    assert.strictEqual(centre(3000, -3000), 'red', 'out of town: the whole-level tile');
    console.log('hud tiles test passed');
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
