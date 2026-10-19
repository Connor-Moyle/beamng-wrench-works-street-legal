// Renders a mock of the Maps app (landscape phone) with made-up roads to a PNG: node tools/mapsmock.js out.png
const { createCanvas } = require('canvas');
const fs = require('fs');
const D = require('../mod/ui/modules/apps/slMaps/mapdraw.js');
const W = 900, H = 440;
const cv = createCanvas(W, H), ctx = cv.getContext('2d');
// a made-up town: a grid of streets, two arterials, a highway, a park, a river
const roads = [];
for (let i = -6; i <= 6; i++) { roads.push({ k: 'street', p: [i * 120, -700, i * 120 + (i % 3) * 20, 700] }); roads.push({ k: 'minor', p: [-700, i * 90, 700, i * 90 + (i % 2) * 30] }); }
roads.push({ k: 'arterial', p: [-700, 60, -200, 40, 200, 120, 700, 100] }, { k: 'arterial', p: [-60, -700, -20, 0, 80, 700] });
roads.push({ k: 'highway', p: [-700, -330, -100, -280, 300, -380, 700, -300] });
const data = {
  roads, areas: [{ k: 'park', p: [120, 130, 330, 130, 330, 260, 120, 260] }, { k: 'water', p: [-700, -420, -200, -450, 200, -400, 700, -440, 700, -560, -700, -560] }],
  route: [0, 0, 8, 60, 80, 90, 200, 120, 260, 190, 330, 200],
  pins: [{ x: 330, y: 200, name: 'Hospital' }, { x: -180, y: 70, name: 'Garage' }, { x: 150, y: -120, name: 'Dealer' }],
  labels: [{ x: -90, y: 85, text: 'Harbor Ave' }, { x: 220, y: 175, text: 'Pine Park' }, { x: -40, y: -300, text: 'Route 1' }],
  player: { x: 0, y: 0, heading: 0.5 }
};
// the phone frame, landscape
ctx.fillStyle = '#0b0b0d'; ctx.fillRect(0, 0, W, H);
ctx.save(); ctx.translate(14, 14); ctx.beginPath(); ctx.rect(0, 0, W - 28, H - 28); ctx.clip();
D.draw(ctx, W - 28, H - 28, data, { cx: 40, cy: 30, mpp: 1.1, rot: 0 });
// search bar and chips in the same light style
ctx.fillStyle = '#ffffff'; ctx.shadowColor = 'rgba(0,0,0,0.3)'; ctx.shadowBlur = 6;
ctx.fillRect(14, 14, 360, 40); ctx.shadowBlur = 0;
ctx.fillStyle = '#5f6368'; ctx.font = '14px Arial'; ctx.textAlign = 'left'; ctx.fillText('Search places', 52, 39);
['Garages', 'Shops', 'Fuel', 'Hospital'].forEach((t, i) => { const x = 14 + i * 96; ctx.fillStyle = '#fff'; ctx.shadowColor = 'rgba(0,0,0,0.25)'; ctx.shadowBlur = 4; ctx.fillRect(x, 64, 88, 28); ctx.shadowBlur = 0; ctx.fillStyle = '#3c4043'; ctx.font = '12px Arial'; ctx.fillText(t, x + 12, 82); });
// zoom buttons
ctx.fillStyle = '#fff'; ctx.shadowColor = 'rgba(0,0,0,0.3)'; ctx.shadowBlur = 5; ctx.fillRect(W - 28 - 54, H - 28 - 110, 40, 80); ctx.shadowBlur = 0;
ctx.fillStyle = '#3c4043'; ctx.font = '22px Arial'; ctx.textAlign = 'center'; ctx.fillText('+', W - 28 - 34, H - 28 - 82); ctx.fillText('-', W - 28 - 34, H - 28 - 44);
ctx.restore();
fs.writeFileSync(process.argv[2] || 'maps_mock.png', cv.toBuffer('image/png'));
console.log('mock written');
