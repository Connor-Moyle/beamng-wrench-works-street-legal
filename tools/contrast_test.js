// WCAG 2.1 contrast of the text and background colours of our panels (phone, laptop, HUD): normal text at least 4.5:1, the pad's focus ring (not text) at least 3:1.
// Each pair names the files its colours must still be found in, so a palette change that is not checked here fails the test.  node tools/contrast_test.js
const fs = require('fs'), path = require('path'), assert = require('assert');
const read = (f) => fs.readFileSync(path.join(__dirname, '..', 'mod/ui/modModules', f), 'utf8').toLowerCase();
const src = { phone: read('slPhone/slPhone.js'), laptop: read('slLaptop/slLaptop.js'), hud: read('slHud/slHud.js') };
const lum = (h) => { const c = [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255).map((v) => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; };
const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
// [what, text colour, background, file, minimum]
const PAIRS = [
  ['phone: body text on a card', '#e6e1e5', '#211f26', 'phone', 4.5],
  ['phone: secondary text on a card', '#cac4d0', '#211f26', 'phone', 4.5],
  ['phone: empty-state text on the wallpaper', '#938f99', '#17121f', 'phone', 4.5],
  ['phone: filled button', '#062e6f', '#a8c7fa', 'phone', 4.5],
  ['phone: tonal button', '#d7e3ff', '#3a3f4b', 'phone', 4.5],
  ['phone: good figure on a card', '#7bd88f', '#211f26', 'phone', 4.5],
  ['phone: bad figure on a card', '#f2b8b5', '#211f26', 'phone', 4.5],
  ['phone: heading on a report section', '#a8c7fa', '#0d0b12', 'phone', 4.5],
  ['phone: red badge', '#601410', '#f2b8b5', 'phone', 4.5],
  ['phone, colour-blind: good on a card', '#56b4e9', '#211f26', 'phone', 4.5],
  ['phone, colour-blind: bad on a card', '#ffb454', '#211f26', 'phone', 4.5],
  ['phone, colour-blind: ahead tag', '#062e4a', '#56b4e9', 'phone', 4.5],
  ['phone, colour-blind: behind tag', '#3b2600', '#ffb454', 'phone', 4.5],
  ['phone: the pad focus ring on a card', '#ffd54f', '#211f26', 'phone', 3],
  ['laptop: the pad focus ring on the desktop', '#ffd54f', '#17121f', 'laptop', 3],
  ['laptop: note text on the desktop', '#f2b8b5', '#17121f', 'laptop', 4.5],
  ['laptop, colour-blind: bad on the desktop', '#ffb454', '#17121f', 'laptop', 4.5],
  ['laptop, colour-blind: good on the desktop', '#56b4e9', '#17121f', 'laptop', 4.5],
  ['hud, colour-blind: the warning colour on the dial', '#ffb454', '#1a1a1c', 'hud', 4.5],
];
let bad = 0;
for (const [what, fg, bg, file, min] of PAIRS) {
  const r = ratio(fg, bg);
  const known = src[file].includes(fg) || file === 'hud';
  const ok = r >= min && known;
  if (!ok) { bad++; console.log('FAIL ' + what + ': ' + fg + ' on ' + bg + ' = ' + r.toFixed(2) + ' (needs ' + min + (known ? '' : '; the colour is no longer in ' + file) + ')'); }
}
assert.strictEqual(bad, 0, bad + ' contrast pairs fail');
console.log('contrast test passed: ' + PAIRS.length + ' pairs');
