// Writes one HTML page per shop kind with the real screen (ui/modModules/slShop/slShop.js) and sample goods, to look at in a browser or to screenshot:
//   node tools/shop_preview.js <out folder>      then   chrome --headless --screenshot=tyre.png --window-size=1280,760 <out>/tyre.html
const fs = require('fs'), path = require('path');
const out = process.argv[2] || 'shop_preview';
fs.mkdirSync(out, { recursive: true });
const code = fs.readFileSync(path.join(__dirname, '..', 'mod/ui/modModules/slShop/slShop.js'), 'utf8');
const tyre = { kind: 'tyre', title: 'Tyre shop', name: 'Torres on 5th', goods: 'tyres', screen: 'catalogue', money: 1840, theme: { accent: '#f2b84b', pattern: 'tread', icon: 'tyre' },
  keeper: { name: 'Gus', line: 'Tread tells the truth.' }, sel: 'performance', cart: { performance: 1 },
  stock: [['road', 'Road', 'Road', 357], ['performance', 'Performance', 'Road', 635], ['winter', 'Winter', 'Weather', 480], ['intermediate', 'Intermediate', 'Weather', 700], ['fullwet', 'Full wet', 'Weather', 700], ['offroad', 'Off-road', 'Off-road', 520], ['mud', 'Mud', 'Off-road', 600], ['rally', 'Rally', 'Off-road', 780], ['semislick', 'Semi-slick', 'Track', 900], ['slick', 'Slick', 'Track', 1100], ['drag', 'Drag', 'Track', 800]]
    .map((r) => ({ id: r[0], name: r[1], group: r[2], price: r[3], was: r[0] === 'road' ? 360 : undefined, desc: r[0] === 'performance' ? 'A sticky road tyre: more grip, wears faster. Fitted on all four wheels.' : undefined })), services: [] };
const paint = { kind: 'paint', title: 'Paint and body', name: 'Spray Kings', goods: 'services', screen: 'services', money: 940, theme: { accent: '#9b8cf0', pattern: 'spray', icon: 'paint' }, keeper: { name: 'Dee', line: 'Dents are free to look at.' }, stock: [],
  services: [{ id: 'buff', name: 'Buff out scratches', price: 80, minutes: 30, desc: 'Polishes light scratches away. Dents are not touched.' }, { id: 'respray', name: 'Full respray', price: 620, minutes: 240, desc: 'Strips and sprays the whole car in the colour you pick.' }, { id: 'wax', name: 'Wax and polish', price: 40, minutes: 20 }, { id: 'dent', name: 'Panel repair', price: 190, minutes: 90, desc: 'Bumps out one dented panel.' }] };
const exhaust = { kind: 'exhaust', title: 'Exhaust shop', name: 'Pipe Dreams', goods: 'catalog', screen: 'catalogue', money: 940, theme: { accent: '#e9855b', pattern: 'pipes', icon: 'exhaust' }, keeper: { name: 'Rosa', line: 'It should sound like a promise.' },
  stock: [{ id: 'cat', name: 'Cat-back, stainless', group: 'Cat-back', price: 420, cond: 1 }, { id: 'headers', name: 'Long-tube headers', group: 'Headers', price: 560, cond: 1 }, { id: 'usedcat', name: 'Cat-back, used', group: 'Cat-back', price: 180, cond: 0.55 }, { id: 'muff', name: 'Straight-through muffler', group: 'Mufflers', price: 240, cond: 1 }], services: [] };
tyre.tagline = 'Tyres fitted while you wait'; tyre.words = { add: 'Choose these', buy: 'Fit them' };
tyre.stock.forEach((it) => { it.specs = [{ label: 'Dry grip', text: it.id === 'performance' ? '1.05' : '1.00', bar: it.id === 'performance' ? 0.5 : 0.4 }, { label: 'Wet grip', text: '0.80', bar: 0.67 }, { label: 'Tread', text: '8 mm', bar: 0.53 }, { label: 'Works best at', text: '20 to 85 C' }, { label: 'Loose ground', text: '0.90', bar: 0.69 }]; });
paint.words = { add: 'Book', buy: 'Pay and book' }; paint.tagline = 'Paint and bodywork';
[['#c0392b', 0], ['#2c3e50', 1], ['#27ae60', 2], ['#f1c40f', 3]].forEach((c) => { paint.services[c[1]].swatch = c[0]; });
exhaust.words = { add: 'Add to basket', buy: 'Pay' }; exhaust.sel = 'headers'; exhaust.cart = { headers: 1 };
exhaust.stock.forEach((it, i) => { it.specs = [{ label: 'Sound', text: ['Mild', 'Loud', 'Mild', 'Very loud'][i], bar: [0.3, 0.7, 0.35, 0.95][i] }, { label: 'Flow', text: ['+6%', '+11%', '+6%', '+9%'][i], bar: [0.4, 0.8, 0.4, 0.65][i] }, { label: 'Weight', text: ['-4 kg', '-2 kg', '-4 kg', '-6 kg'][i] }]; });
const tuner = { kind: 'tuner', title: 'Tuner', name: 'Dyno Dan', tagline: 'Dyno and setup', goods: 'services', screen: 'services', money: 940, theme: { accent: '#5fb7e6', pattern: 'dyno', icon: 'gauge' }, words: { add: 'Reserve', buy: 'Pay and reserve' }, stock: [],
  services: [{ id: 'dyno', name: 'Dyno run', price: 90, minutes: 20, desc: 'Power and torque of your car on the rollers.', curve: [20, 55, 90, 125, 150, 160, 148, 120] }, { id: 'align', name: 'Alignment', price: 70, minutes: 40, desc: 'Toe, camber and caster set to your numbers.' }, { id: 'tune', name: 'Engine map', price: 260, minutes: 90, desc: 'A map written for your parts.', curve: [30, 70, 110, 150, 170, 175, 160, 130] }] };
const dealer = { kind: 'dealerparts', title: 'Dealer parts', name: 'Jefferson Motors', tagline: 'Genuine parts', goods: 'catalog', screen: 'catalogue', money: 2400, theme: { accent: '#8ab4f8', pattern: 'badge', icon: 'badge' }, words: { add: 'Add to basket', buy: 'Order' }, sel: 'p2', cart: { p2: 1 },
  stock: [['p1', 'Sport exhaust, cat-back', 'Exhaust', 572], ['p2', 'Front bumper, factory', 'Front bumper', 640], ['p3', 'Hood, factory', 'Hood', 780], ['p4', 'Rear spoiler', 'Wing', 450]].map((r) => ({ id: r[0], name: r[1], group: r[2], price: r[3], brand: 'Ibishu', count: 4 })), services: [] };
const dealerNone = Object.assign(JSON.parse(JSON.stringify(dealer)), { stock: [], sel: undefined, cart: undefined, note: 'Nothing fits your Pickup: this counter sells parts of Bruckell, Gavril, Ibishu only.' });
const kinds = { tyre, paint, exhaust, tuner, dealer, dealer_none: dealerNone };
for (const k of Object.keys(kinds)) {
  const d = kinds[k];
  const html = '<!doctype html><meta charset="utf-8"><body style="margin:0;background:#0d0b12"><script>window.__slShopTest=true;</script><script>' + code.replace(/<\/script/g, '<\/script') + '</script><script>' +
    'var s=window.__slShopCreate(document,function(c){console.log(c)});s.handle("slShopOpen",' + JSON.stringify(d) + ');' + (d.sel ? 's.act("pick","' + d.sel + '");s.act("add","' + d.sel + '");' : '') + '</script>';
  fs.writeFileSync(path.join(out, k + '.html'), html);
}
console.log('wrote', Object.keys(kinds).map((k) => path.join(out, k + '.html')).join(', '));
