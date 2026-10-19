// The Maps drawing without a canvas: a recording context. node tools/mapsdraw_test.js
const assert = require('assert');
const D = require('../mod/ui/modModules/slMapsDraw/slMapsDraw.js');
function rec() {
  const log = { fills: [], texts: [] };
  const ctx = new Proxy({}, {
    get(t, k) {
      if (k === 'log') return log;
      if (k === 'measureText') return (s) => ({ width: String(s).length * 6 });
      if (k === 'createLinearGradient' || k === 'createRadialGradient') return () => ({ addColorStop() {} });
      if (k === 'fill') return () => log.fills.push(t.fillStyle);
      if (k === 'fillText' || k === 'strokeText') return (s) => { if (k === 'fillText') log.texts.push(String(s)); };
      return t[k] !== undefined ? t[k] : () => {};
    },
    set(t, k, v) { t[k] = v; return true; },
  });
  return ctx;
}
const base = { roads: [], pins: [{ x: 0, y: 40, name: 'Pier Garage', kind: 'garage' }, { x: 30, y: 40, name: 'Mystery', kind: 'other' }], player: { x: 0, y: 0, heading: 0 } };
let c = rec();
D.draw(c, 400, 250, base, { cx: 0, cy: 0, mpp: 1.5, rot: 0 });
assert.ok(c.log.fills.includes('#3b82f6'), 'a garage pin has its own colour');
assert.ok(c.log.fills.includes(D.skinOf({}).pinColor), 'an unknown kind keeps the skin colour');
assert.ok(c.log.texts.includes('Pier Garage') && c.log.texts.includes('Mystery'), 'pin names show when zoomed in');
c = rec();
D.draw(c, 400, 250, base, { cx: 0, cy: 0, mpp: 6, rot: 0 });
assert.ok(!c.log.texts.includes('Pier Garage'), 'no pin names when zoomed out');
c = rec();
D.draw(c, 400, 250, Object.assign({}, base, { speed: { now: 20, limit: 13.4, mph: true, sign: 'us' } }), { cx: 0, cy: 0, mpp: 1.5, rot: 0 });
assert.ok(c.log.texts.includes('45') && c.log.texts.includes('30'), 'the speed and the limit show in mph: ' + c.log.texts.join(','));
c = rec();
D.draw(c, 400, 250, Object.assign({}, base, { speed: { now: 20, limit: null, mph: false, sign: 'round' } }), { cx: 0, cy: 0, mpp: 1.5, rot: 0 });
assert.ok(c.log.texts.includes('72'), 'km/h without a limit shows only the speed');
c = rec();
D.draw(c, 400, 250, Object.assign({}, base, { speed: { now: 20, limit: Infinity, mph: true, sign: 'us' } }), { cx: 0, cy: 0, mpp: 1.5, rot: 0 });
assert.ok(!c.log.texts.includes('Infinity') && !c.log.texts.includes('NaN'), 'an infinite limit shows no sign: ' + c.log.texts.join(','));
console.log('maps draw test passed');
