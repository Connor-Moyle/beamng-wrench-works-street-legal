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
const kinds = { tyre, paint, exhaust };
for (const k of Object.keys(kinds)) {
  const d = kinds[k];
  const html = '<!doctype html><meta charset="utf-8"><body style="margin:0;background:#0d0b12"><script>window.__slShopTest=true;</script><script>' + code.replace(/<\/script/g, '<\/script') + '</script><script>' +
    'var s=window.__slShopCreate(document,function(c){console.log(c)});s.handle("slShopOpen",' + JSON.stringify(d) + ');' + (d.sel ? 's.act("pick","' + d.sel + '");s.act("add","' + d.sel + '");' : '') + '</script>';
  fs.writeFileSync(path.join(out, k + '.html'), html);
}
console.log('wrote', Object.keys(kinds).map((k) => path.join(out, k + '.html')).join(', '));
