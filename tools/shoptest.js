// Runs the shop screen (ui/modModules/slShop/slShop.js) in a simulated page and checks what it draws, how a gamepad reaches it, and the style rules of docs/UI_STYLE.md:
// every interactive element has data-a and bng-nav-item and a visible focus style, no text outside T(), and no motion when the player asks for less.
// Needs jsdom:  npm i jsdom   then   node tools/shoptest.js
const fs = require('fs'), path = require('path'), assert = require('assert');
const { JSDOM } = require('jsdom');

const code = fs.readFileSync(path.join(__dirname, '..', 'mod/ui/modModules/slShop/slShop.js'), 'utf8');
const dom = new JSDOM('<!doctype html><html><body></body></html>', { runScripts: 'outside-only', pretendToBeVisual: true });
const win = dom.window;
win.__slShopTest = true;
win.eval(code);

const calls = [];
const shop = win.__slShopCreate(win.document, (c) => calls.push(c));
const $ = (sel) => shop.root.querySelector(sel);
const $$ = (sel) => Array.from(shop.root.querySelectorAll(sel));
const sel = (a, v) => '[data-a="' + a + '"]' + (v === undefined ? '' : '[data-v="' + v + '"]');
const click = (a, v) => $(sel(a, v)).dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
const nav = (name) => win.dispatchEvent(new win.CustomEvent('ui_nav', { detail: { name, value: 1 } }));

// every key answers with a marker, so any text on screen without a marker is text that did not go through T()
shop.handle('slStrings', new Proxy({}, { get: (t, k) => (typeof k === 'string' ? '«' + k + '»' : undefined) }));

const tyreShop = {
  kind: 'tyre', title: 'Tyre shop', name: 'Torres on 5th', goods: 'tyres', screen: 'catalogue', money: 1200,
  theme: { accent: '#f2b84b', pattern: 'tread', icon: 'tyre' }, keeper: { name: 'Gus', line: 'Tread tells the truth.' },
  stock: [
    { id: 'road', name: 'Road', group: 'road', price: 357, was: 360 },
    { id: 'performance', name: 'Performance', group: 'road', price: 635, was: 640 },
    { id: 'winter', name: 'Winter', group: 'weather', price: 480, desc: 'Soft rubber for the cold.' },
    { id: 'slick', name: 'Slick', group: 'track', price: 1100, cond: 0.6, count: 1 },
  ],
  services: [],
};
shop.handle('slShopOpen', JSON.parse(JSON.stringify(tyreShop)));
assert(shop.root.classList.contains('slsh-open'), 'the screen is open');
assert.strictEqual($('.slsh-title b').textContent, 'Torres on 5th');
assert(/Gus/.test($('.slsh-title span').textContent), 'the keeper is in the header');
assert.strictEqual($('.slsh-panel').getAttribute('style').match(/--sl-accent:(#[0-9a-f]{6})/i)[1], '#f2b84b', 'the theme accent is on the panel');
assert(/\$1,200/.test($('.slsh-money').textContent), 'the money is shown');
assert.strictEqual($$('.slsh-card').length, 4, 'a card per item');
assert.deepStrictEqual($$('.slsh-cat').map((b) => b.firstChild.textContent).slice(1), ['road', 'weather', 'track'], 'the groups are the rail');
click('cat', 'road');
assert.strictEqual($$('.slsh-card').length, 2, 'a group filters the cards');
click('cat', 'all');
click('pick', 'winter');
assert(/Soft rubber/.test($('.slsh-detail').textContent), 'the detail pane shows the picked item');
click('add', 'winter'); click('pick', 'road'); click('add', 'road'); click('add', 'road');
assert(/\$1,194/.test($('.slsh-total').textContent), 'the basket totals: 480 + 2 x 357 = 1194: ' + $('.slsh-total').textContent);
assert(!$(sel('buy')).disabled, 'pay is on when the money is enough');
click('pick', 'slick'); click('add', 'slick'); click('add', 'slick');
assert(/count|stock/i.test($('.slsh-toast') ? $('.slsh-toast').textContent : '') && shop.state.cart.slick === 1, 'more than the stock is refused with a note');
assert($(sel('buy')).disabled, 'pay is off when the basket costs more than the money (1194 + 1100 > 1200)');
assert(/shops\.cannot_afford/.test($('.slsh-foot').textContent), 'and says why');
click('remove', 'slick');
click('buy');
assert.strictEqual(calls[calls.length - 1], '@sl_shops.buy("winter:1,road:2")', 'pay sends the basket: ' + calls[calls.length - 1]);

// the Lua side answers with the new state: the basket is empty again, the money is less
shop.handle('slShopOpen', Object.assign(JSON.parse(JSON.stringify(tyreShop)), { money: 6 }));
assert.strictEqual($$('.slsh-line').length, 0, 'a new state empties the basket');

// a shut shop
shop.handle('slShopOpen', Object.assign(JSON.parse(JSON.stringify(tyreShop)), { closed: 'Closed. Opens at 08:00.' }));
click('pick', 'road');
assert(/Closed/.test($('.slsh-closed').textContent), 'the closed note shows');
assert($(sel('add', 'road')).disabled && $(sel('buy')).disabled, 'a shut shop sells nothing');

// a services shop and the other themes
const paint = { kind: 'paint', title: 'Paint and body', name: 'Spray Kings', goods: 'services', screen: 'services', money: 500, theme: { accent: '#9b8cf0', pattern: 'spray', icon: 'paint' }, stock: [],
  services: [{ id: 'buff', name: 'Buff scratches', price: 80, minutes: 30, desc: 'Polishes light scratches out.' }, { id: 'wax', name: 'Wax', price: 40 }] };
shop.handle('slShopOpen', paint);
assert.strictEqual($$('.slsh-row').length, 2, 'a row per service');
click('add', 'buff');
assert(/\$80/.test($('.slsh-total').textContent) && $(sel('remove', 'buff')), 'booking puts it in the basket and the row offers Remove');
click('buy');
assert.strictEqual(calls[calls.length - 1], '@sl_shops.buy("buff:1")');
const parts = win.__slShopParts;
parts.themes.forEach((t) => assert(parts.patternSvg(t, '#123456').indexOf('#123456') > 0, 'pattern ' + t + ' uses the accent'));
['tyre', 'exhaust', 'wrench', 'engine', 'paint', 'gauge', 'spanner', 'star', 'badge'].forEach((i) => assert(parts.iconSvg(i).indexOf('<path') > 0 || parts.iconSvg(i).indexOf('<circle') > 0, 'icon ' + i));
// a catalogue shop with no stock says where parts come from
shop.handle('slShopOpen', { kind: 'exhaust', title: 'Exhaust shop', name: 'Pipe Dreams', goods: 'catalog', screen: 'catalogue', money: 100, theme: { accent: '#e9855b', pattern: 'pipes', icon: 'exhaust' }, stock: [], services: [] });
assert(/shops\.ui_catalog_note/.test($('.slsh-note').textContent), 'an empty catalogue shop explains itself');
// a bad accent colour falls back to the family accent (no style injection)
shop.handle('slShopOpen', Object.assign(JSON.parse(JSON.stringify(tyreShop)), { theme: { accent: 'red;x:y', pattern: 'nope', icon: 'nope' } }));
assert(/--sl-accent:#a8c7fa/.test($('.slsh-panel').getAttribute('style')), 'a bad accent is replaced');
// names from the data are escaped
shop.handle('slShopOpen', Object.assign(JSON.parse(JSON.stringify(tyreShop)), { name: '<img src=x onerror=alert(1)>' }));
assert(!$('.slsh-head img') && /<img/.test($('.slsh-title b').textContent), 'a shop name cannot inject markup');

// ---- text on an accent fill: --sl-deep on a light accent, white on a dark one, at least 4.5:1 for every built-in accent (and the ones in the sample data)
const core = fs.readFileSync(path.join(__dirname, '..', 'mod/lua/ge/extensions/sl/core/shops.lua'), 'utf8');
const accents = Array.from(new Set((core.match(/accent = '#[0-9a-fA-F]{6}'/g) || []).map((m) => m.slice(10, 17)).concat(['#f2b84b', '#9b8cf0', '#e9855b', '#a8c7fa'])));
assert(accents.length >= 9, 'the built-in accents were found: ' + accents.length);
const contrast = (a, b) => { const x = win.__slShopParts.luminance(a), y = win.__slShopParts.luminance(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
accents.forEach((a) => assert(contrast(a, win.__slShopParts.onAccent(a)) >= 4.5, 'text on ' + a + ' is ' + contrast(a, win.__slShopParts.onAccent(a)).toFixed(2) + ':1'));
shop.handle('slShopOpen', Object.assign(JSON.parse(JSON.stringify(tyreShop)), { colorBlind: true }));
assert(shop.root.classList.contains('slsh-cb') && /\.slsh-cb\{--sl-good:#56b4e9;--sl-bad:#ffb454\}/.test(shop.css), 'the colour-blind palette is the same as the phone, toggled by the data');
shop.handle('slShopOpen', JSON.parse(JSON.stringify(tyreShop)));
assert(!shop.root.classList.contains('slsh-cb'), 'and off again');
assert(/--sl-on-accent:#0d0b12/.test($('.slsh-panel').getAttribute('style')), 'amber gets the dark text');
assert.strictEqual($('.slsh-cat[data-v="all"] .slsh-count').textContent, '4', 'the rail counts the items');
assert(/box-shadow:0 0 0 2px var\(--sl-deep\)/.test(shop.css), 'the focus ring has a dark inner line so it shows on any accent');

// ---- the style rules
shop.handle('slShopOpen', JSON.parse(JSON.stringify(tyreShop)));
click('pick', 'winter'); click('add', 'winter');
const bad = $$('button').filter((b) => !b.hasAttribute('data-a') || !b.hasAttribute('bng-nav-item'));
assert.strictEqual(bad.length, 0, 'every button has data-a and bng-nav-item: ' + bad.map((b) => b.outerHTML.slice(0, 80)));
assert(/\.slsh-root \[data-a\]:focus[^{]*\{[^}]*outline:3px solid var\(--sl-focus\)/.test(shop.css), 'a visible focus style (3 px, --sl-focus)');
assert(/--sl-focus:#ffd54f/.test(shop.css) && /--sl-accent:#a8c7fa/.test(shop.css) && /--sl-surface1:#141218/.test(shop.css), 'the family tokens');
const noMotion = shop.css.split(/\r?\n/).filter((l) => !l.startsWith('@media (prefers-reduced-motion:no-preference)')).join(' ');      // (the guarded rules are the one line)
assert(!/transition\s*:|animation\s*:/.test(noMotion), 'motion only inside prefers-reduced-motion:no-preference');
assert(/prefers-reduced-motion:no-preference/.test(shop.css), 'the reduced-motion guard is there');
// no text outside T(): remove the markers, the data and the money; no word is left
const data = [tyreShop.name, 'Gus', 'Tread tells the truth.', 'Tyre shop', 'Road', 'Performance', 'Winter', 'Slick', 'road', 'weather', 'track', 'Soft rubber for the cold.', '<img src=x onerror=alert(1)>'];
let seen = $$('*').filter((e) => e.children.length === 0 && e.tagName !== 'STYLE').map((e) => e.textContent).join(' | ');
seen = seen.replace(/«[^»]*»/g, ' ');
data.forEach((d) => { seen = seen.split(d).join(' '); });
const words = seen.match(/[A-Za-z]{2,}/g) || [];
assert.strictEqual(words.length, 0, 'text not from T() or the data: ' + words.join(','));
$$('[aria-label]').forEach((e) => assert(/«/.test(e.getAttribute('aria-label')), 'aria-label goes through T()'));

// ---- the pad
const first = () => $$('[data-a]').filter((e) => !e.disabled);
win.document.activeElement && win.document.activeElement.blur && win.document.activeElement.blur();
nav('right');
assert(first().indexOf(win.document.activeElement) >= 0, 'right focuses a control');
const a0 = win.document.activeElement;
nav('right');
assert(win.document.activeElement !== a0, 'right moves on');
nav('left');
assert(win.document.activeElement === a0, 'left moves back');
const before = calls.length;
nav('back');
assert.strictEqual(calls[calls.length - 1], '@sl_shops.close()', 'B closes through the Lua side');
assert(!shop.root.classList.contains('slsh-open'), 'and the screen is shut');
shop.handle('slShopOpen', JSON.parse(JSON.stringify(tyreShop)));
win.document.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
assert(!shop.root.classList.contains('slsh-open'), 'Escape closes');
shop.handle('slShopClose', {});
assert(!shop.root.classList.contains('slsh-open'));
console.log('shop screen tests passed');
process.exit(0);
