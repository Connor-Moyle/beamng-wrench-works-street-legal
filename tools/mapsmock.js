// Renders mocks of the Maps app skins (Street, Cruise, Atlas; day and night) with made-up roads: node tools/mapsmock.js out.png
const { createCanvas } = require('canvas');
const fs = require('fs');
const D = require('../mod/ui/modModules/slMapsDraw/slMapsDraw.js');
const W = 440, H = 250, PAD = 10;
const roads = [];
for (let i = -6; i <= 6; i++) { roads.push({ k: 'street', p: [i * 120, -700, i * 120 + (i % 3) * 20, 700] }); roads.push({ k: 'minor', p: [-700, i * 90, 700, i * 90 + (i % 2) * 30] }); }
roads.push({ k: 'arterial', p: [-700, 60, -200, 40, 200, 120, 700, 100] }, { k: 'arterial', p: [-60, -700, -20, 0, 80, 700] });
roads.push({ k: 'highway', p: [-700, -330, -100, -280, 300, -380, 700, -300] });
const data = (speed) => ({
  roads, areas: [{ k: 'park', p: [120, 130, 330, 130, 330, 260, 120, 260] }, { k: 'water', p: [-700, -420, -200, -450, 200, -400, 700, -440, 700, -560, -700, -560] }],
  route: [0, 0, 8, 60, 80, 90, 200, 120, 260, 190, 330, 200],
  pins: [{ x: 330, y: 200 }, { x: -180, y: 70 }, { x: 150, y: -120 }],
  labels: [{ x: -90, y: 85, text: 'Harbor Ave' }, { x: 220, y: 175, text: 'Pine Park' }, { x: -40, y: -300, text: 'Route 1' }],
  player: { x: 0, y: 0, heading: 0.5 }, speed
});
const cells = [['street', false, { now: 17, limit: 18, mph: true, sign: 'us' }], ['cruise', false, { now: 24, limit: 18, mph: true, sign: 'us' }], ['atlas', false, { now: 12, limit: 13.4, mph: false, sign: 'round' }],
  ['street', true, { now: 17, limit: 18, mph: true, sign: 'us' }], ['cruise', true, { now: 24, limit: 18, mph: true, sign: 'us' }], ['atlas', true, { now: 12, limit: null, mph: false, sign: 'round' }]];
const cv = createCanvas(PAD + 3 * (W + PAD), PAD + 2 * (H + PAD)), ctx = cv.getContext('2d');
ctx.fillStyle = '#0b0b0d'; ctx.fillRect(0, 0, cv.width, cv.height);
cells.forEach(([skin, night, speed], n) => {
  ctx.save(); ctx.translate(PAD + (n % 3) * (W + PAD), PAD + Math.floor(n / 3) * (H + PAD)); ctx.beginPath(); ctx.rect(0, 0, W, H); ctx.clip();
  D.draw(ctx, W, H, data(speed), { cx: 40, cy: 30, mpp: 1.3, rot: 0, skin, night });
  const C = D.skinOf({ skin, night }), ch = C.chrome;
  ctx.fillStyle = ch.bar; ctx.shadowColor = ch.shadow; ctx.shadowBlur = 6;
  ctx.beginPath(); ctx.moveTo(14 + ch.radius, 12); ctx.arcTo(14 + 220, 12, 14 + 220, 12 + 32, ch.radius); ctx.arcTo(14 + 220, 12 + 32, 14, 12 + 32, ch.radius); ctx.arcTo(14, 12 + 32, 14, 12, ch.radius); ctx.arcTo(14, 12, 14 + 220, 12, ch.radius); ctx.fill(); ctx.shadowBlur = 0;
  ctx.fillStyle = ch.barText; ctx.font = '13px Arial'; ctx.textAlign = 'left'; ctx.fillText(C.title + ' ' + (night ? 'night' : 'day') + ' - search places', 30, 33);
  ['Garages', 'Shops', 'Fuel'].forEach((t, i) => { const x = 14 + i * 74; ctx.fillStyle = ch.chip; ctx.shadowColor = ch.shadow; ctx.shadowBlur = 4; ctx.fillRect(x, 52, 68, 22); ctx.shadowBlur = 0; ctx.fillStyle = ch.chipText; ctx.font = '11px Arial'; ctx.fillText(t, x + 8, 67); });
  ctx.restore();
});
fs.writeFileSync(process.argv[2] || 'maps_skins.png', cv.toBuffer('image/png'));
console.log('mock written');
