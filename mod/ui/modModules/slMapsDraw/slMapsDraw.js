// Street Legal Maps: the drawing of the map. Pure canvas 2D, no game calls, so tools/mapsmock.js runs it outside the game.
// Own drawing, own names: three map skins (Street, Cruise, Atlas), each with a day and a night variant. No third-party logo, name or icon.
// data = { roads: [{ k: 'minor'|'street'|'arterial'|'highway', p: [x, y, x, y, ...] }], areas: [{ k: 'park'|'water', p: [x, y, ...] }],
//          route: [x, y, ...], pins: [{ x, y, name }], player: { x, y, heading (rad, 0 = north, clockwise) }, labels: [{ x, y, text }],
//          speed: { now (m/s), limit (m/s or null), mph (bool), sign ('us'|'round') } }
// view = { cx, cy (world metres at the centre), mpp (metres per pixel), rot (rad: 0 = north up), skin: 'street'|'cruise'|'atlas', night: bool }
(function (root) {
  'use strict';
  var FONT = 'Roboto, "Noto Sans", "Segoe UI", Arial, sans-serif';
  // a skin is a table of colours and shape choices; `night` overrides the colours it names
  var SKINS = {
    street: {                                                   // the light road-map look: beige ground, white and yellow roads, blue route, red teardrop pins
      title: 'Street', width: { minor: 3, street: 4.5, arterial: 6, highway: 8 }, routeWidth: 6, casing: 2.5, labelFont: '600 11px ' + FONT, marker: 'dot', pin: 'drop',
      ground: '#f2efe9', park: '#cfe8c3', water: '#a9d3f5', label: '#5f6368', labelHalo: '#ffffff',
      roadCasing: '#d3cfc6', minor: '#ffffff', street: '#ffffff', arterial: '#fff4cc', arterialCasing: '#e0c46a', highway: '#fbd36b', highwayCasing: '#d9a02a',
      route: '#2f6fe4', routeCasing: '#1b4fb0', pinColor: '#d93a2e', pinDark: '#a52a20', dot: '#2f6fe4', cone: 'rgba(47,111,228,0.28)',
      chrome: { bar: '#ffffff', barText: '#5f6368', chip: '#ffffff', chipText: '#3c4043', shadow: 'rgba(0,0,0,0.3)', radius: 20 },
      night: { ground: '#242f3e', park: '#263c3a', water: '#17263c', label: '#9aa5b5', labelHalo: '#242f3e', roadCasing: '#1b2432', minor: '#38465a', street: '#46556b', arterial: '#6b5d3a', arterialCasing: '#3b3420', highway: '#8a6d2f', highwayCasing: '#4a3a16',
        chrome: { bar: '#303a4a', barText: '#b0b8c4', chip: '#303a4a', chipText: '#d2d8e0', shadow: 'rgba(0,0,0,0.5)', radius: 20 } }
    },
    cruise: {                                                   // bright and playful: a chunky route, a cartoon car marker, round chips, a dark night mode
      title: 'Cruise', width: { minor: 3.5, street: 5.5, arterial: 7.5, highway: 10 }, routeWidth: 11, casing: 3, labelFont: '700 11px ' + FONT, marker: 'car', pin: 'bubble',
      ground: '#dff3ea', park: '#b7e3a1', water: '#8fd3f4', label: '#2c5a63', labelHalo: '#ffffff',
      roadCasing: '#bcd5cb', minor: '#ffffff', street: '#ffffff', arterial: '#ffe9a8', arterialCasing: '#e5b94c', highway: '#ffb86b', highwayCasing: '#d77f1f',
      route: '#33c1ff', routeCasing: '#1478b8', pinColor: '#ff6b8b', pinDark: '#c2375a', dot: '#33c1ff', cone: 'rgba(51,193,255,0.3)',
      chrome: { bar: '#ffffff', barText: '#4a6b73', chip: '#ffffff', chipText: '#1f4a55', shadow: 'rgba(20,80,100,0.35)', radius: 22 },
      night: { ground: '#1d2b3a', park: '#21483f', water: '#173a56', label: '#9ad6e6', labelHalo: '#1d2b3a', roadCasing: '#16202c', minor: '#35506a', street: '#41607d', arterial: '#7a6a3a', arterialCasing: '#3a3018', highway: '#a8682a', highwayCasing: '#4a2c0e',
        chrome: { bar: '#2a3b4e', barText: '#a9d3df', chip: '#2a3b4e', chipText: '#d8eef4', shadow: 'rgba(0,0,0,0.5)', radius: 22 } }
    },
    atlas: {                                                    // soft pastel ground, thin roads, a clean frosted panel look
      title: 'Atlas', width: { minor: 1.6, street: 2.6, arterial: 4, highway: 5.5 }, routeWidth: 5, casing: 1.2, labelFont: '500 11px ' + FONT, marker: 'arrow', pin: 'flag',
      ground: '#f4f1ee', park: '#dcecd2', water: '#cfe4f3', label: '#6b6b70', labelHalo: '#f4f1ee',
      roadCasing: '#e1ddd8', minor: '#ffffff', street: '#ffffff', arterial: '#fdfaf0', arterialCasing: '#ead9a8', highway: '#f7e3a3', highwayCasing: '#e0c06c',
      route: '#3b82f6', routeCasing: '#2f66c8', pinColor: '#ef5350', pinDark: '#b3322f', dot: '#3b82f6', cone: 'rgba(59,130,246,0.22)',
      chrome: { bar: 'rgba(250,250,252,0.82)', barText: '#6b6b70', chip: 'rgba(250,250,252,0.82)', chipText: '#3a3a3f', shadow: 'rgba(0,0,0,0.18)', radius: 14 },
      night: { ground: '#2b2d33', park: '#2e3a33', water: '#26384a', label: '#a0a2aa', labelHalo: '#2b2d33', roadCasing: '#22242a', minor: '#3e4048', street: '#4a4c55', arterial: '#5a5642', arterialCasing: '#2f2c20', highway: '#6e6238', highwayCasing: '#3a3318',
        chrome: { bar: 'rgba(48,50,58,0.85)', barText: '#a8aab2', chip: 'rgba(48,50,58,0.85)', chipText: '#dcdde2', shadow: 'rgba(0,0,0,0.5)', radius: 14 } }
    }
  };
  var ORDER = ['minor', 'street', 'arterial', 'highway'];

  // the skin's colours for day or night (night names only what differs)
  function skinOf(view) {
    var s = SKINS[view && view.skin] || SKINS.street;
    if (!(view && view.night) || !s.night) return s;
    var o = {}, k;
    for (k in s) o[k] = s[k];
    for (k in s.night) o[k] = s.night[k];
    return o;
  }

  function project(view, w, h) {
    var c = Math.cos(view.rot || 0), s = Math.sin(view.rot || 0);
    return function (x, y) {
      var dx = (x - view.cx) / view.mpp, dy = -(y - view.cy) / view.mpp;      // north is up the screen
      return [w / 2 + dx * c - dy * s, h / 2 + dx * s + dy * c];
    };
  }
  function line(ctx, pt, p) {
    ctx.beginPath();
    for (var i = 0; i + 1 < p.length; i += 2) { var q = pt(p[i], p[i + 1]); if (i === 0) ctx.moveTo(q[0], q[1]); else ctx.lineTo(q[0], q[1]); }
  }
  function widthFor(C, k, mpp) { var w = C.width[k]; return Math.max(1.2, Math.min(w * 2.4, w * 1.2 / Math.max(0.5, mpp) + w * 0.45)); }

  function drawMarker(ctx, C, q, a) {
    ctx.save(); ctx.translate(q[0], q[1]); ctx.rotate(a);
    ctx.beginPath(); ctx.moveTo(0, 0); ctx.arc(0, 0, 46, -Math.PI / 2 - 0.5, -Math.PI / 2 + 0.5); ctx.closePath(); ctx.fillStyle = C.cone; ctx.fill();
    if (C.marker === 'car') {                                 // a chunky cartoon car seen from above
      ctx.fillStyle = '#ffffff'; ctx.shadowColor = 'rgba(0,0,0,0.35)'; ctx.shadowBlur = 5;
      ctx.beginPath(); ctx.moveTo(0, -15); ctx.quadraticCurveTo(10, -12, 10, 0); ctx.lineTo(10, 10); ctx.quadraticCurveTo(10, 15, 5, 15); ctx.lineTo(-5, 15); ctx.quadraticCurveTo(-10, 15, -10, 10); ctx.lineTo(-10, 0); ctx.quadraticCurveTo(-10, -12, 0, -15); ctx.fill(); ctx.shadowBlur = 0;
      ctx.fillStyle = C.dot; ctx.beginPath(); ctx.moveTo(0, -11); ctx.quadraticCurveTo(7, -9, 7, -1); ctx.lineTo(-7, -1); ctx.quadraticCurveTo(-7, -9, 0, -11); ctx.fill();
      ctx.fillStyle = C.pinColor; ctx.fillRect(-7, 9, 4, 3); ctx.fillRect(3, 9, 4, 3);
    } else if (C.marker === 'arrow') {                        // a clean navigation arrow
      ctx.shadowColor = 'rgba(0,0,0,0.35)'; ctx.shadowBlur = 4; ctx.fillStyle = C.dot;
      ctx.beginPath(); ctx.moveTo(0, -14); ctx.lineTo(10, 11); ctx.lineTo(0, 5); ctx.lineTo(-10, 11); ctx.closePath(); ctx.fill(); ctx.shadowBlur = 0;
      ctx.strokeStyle = '#ffffff'; ctx.lineWidth = 2; ctx.stroke();
    } else {                                                  // a blue dot with a white ring
      ctx.beginPath(); ctx.arc(0, 0, 9, 0, Math.PI * 2); ctx.fillStyle = '#ffffff'; ctx.shadowColor = 'rgba(0,0,0,0.35)'; ctx.shadowBlur = 4; ctx.fill(); ctx.shadowBlur = 0;
      ctx.beginPath(); ctx.arc(0, 0, 6.5, 0, Math.PI * 2); ctx.fillStyle = C.dot; ctx.fill();
    }
    ctx.restore();
  }
  // pins by kind (a garage, a parts shop, a meet, a gas station...): the colour; any other kind keeps the skin's own
  var PIN_KIND = { garage: '#3b82f6', shop: '#f59e0b', meet: '#8b5cf6', gas: '#10b981', race: '#ef4444', track: '#ef4444', dealer: '#14b8a6', rumour: '#938f99' };
  // a rumour: an area (a dashed circle of p.r metres, never the exact spot) with a question mark, in the muted grey of the style kit (the mark, not only the colour, says what it is)
  function drawRumour(ctx, C, q, p, view) {
    var r = Math.max(12, (p.r || 200) / (view.mpp || 1));
    ctx.save();
    ctx.beginPath(); ctx.arc(q[0], q[1], r, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(147,143,153,0.16)'; ctx.fill();
    if (ctx.setLineDash) ctx.setLineDash([6, 5]);
    ctx.strokeStyle = PIN_KIND.rumour; ctx.lineWidth = 2; ctx.stroke();
    if (ctx.setLineDash) ctx.setLineDash([]);
    ctx.beginPath(); ctx.arc(q[0], q[1], 9, 0, Math.PI * 2); ctx.fillStyle = '#211f26'; ctx.fill(); ctx.strokeStyle = '#e6e1e5'; ctx.lineWidth = 1.5; ctx.stroke();
    ctx.fillStyle = '#e6e1e5'; ctx.font = '700 12px ' + FONT; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText('?', q[0], q[1] + 0.5);
    ctx.restore();
  }
  function drawPin(ctx, C, q, color) {
    ctx.beginPath();
    if (C.pin === 'bubble') { ctx.arc(q[0], q[1] - 14, 11, 0, Math.PI * 2); }
    else if (C.pin === 'flag') { ctx.rect(q[0] - 1, q[1] - 28, 2, 28); ctx.moveTo(q[0] + 1, q[1] - 28); ctx.lineTo(q[0] + 15, q[1] - 22); ctx.lineTo(q[0] + 1, q[1] - 16); ctx.closePath(); }
    else { ctx.moveTo(q[0], q[1]); ctx.bezierCurveTo(q[0] - 13, q[1] - 14, q[0] - 11, q[1] - 30, q[0], q[1] - 30); ctx.bezierCurveTo(q[0] + 11, q[1] - 30, q[0] + 13, q[1] - 14, q[0], q[1]); ctx.closePath(); }
    ctx.fillStyle = color || C.pinColor; ctx.fill(); ctx.strokeStyle = C.pinDark; ctx.lineWidth = 1; ctx.stroke();
    if (C.pin !== 'flag') { ctx.beginPath(); ctx.arc(q[0], q[1] - (C.pin === 'bubble' ? 14 : 20), 4, 0, Math.PI * 2); ctx.fillStyle = '#ffffff'; ctx.fill(); }
  }

  // the speed limit sign and the speed bubble, bottom left of the map. speed = { now, limit, mph, sign }; speeds in m/s, shown in the player's unit
  function drawSpeed(ctx, w, h, C, speed) {
    if (!speed) return;
    var k = speed.mph ? 2.23694 : 3.6, now = Math.round((speed.now || 0) * k), lim = (isFinite(speed.limit) && speed.limit > 0 && speed.limit < 100) ? Math.round(speed.limit * k / 5) * 5 : null;      // (no sign for none or an unlimited road)
    var over = lim !== null && now > lim, x = 14, y = h - 14, round = speed.sign === 'round';
    // the sign
    ctx.save(); ctx.translate(x, y - 66);
    ctx.shadowColor = 'rgba(0,0,0,0.3)'; ctx.shadowBlur = 5;
    if (round) {
      ctx.beginPath(); ctx.arc(26, 33, 26, 0, Math.PI * 2); ctx.fillStyle = '#ffffff'; ctx.fill(); ctx.shadowBlur = 0;
      ctx.beginPath(); ctx.arc(26, 33, 22, 0, Math.PI * 2); ctx.lineWidth = 5; ctx.strokeStyle = '#d32f2f'; ctx.stroke();
      ctx.fillStyle = '#111'; ctx.font = '700 ' + (lim !== null && String(lim).length > 2 ? 17 : 21) + 'px ' + FONT; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(lim !== null ? String(lim) : '--', 26, 34);
    } else {
      ctx.beginPath(); ctx.rect(0, 0, 46, 64); ctx.fillStyle = '#ffffff'; ctx.fill(); ctx.shadowBlur = 0;
      ctx.lineWidth = 2; ctx.strokeStyle = '#111'; ctx.strokeRect(3, 3, 40, 58);
      ctx.fillStyle = '#111'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.font = '700 9px ' + FONT; ctx.fillText('SPEED', 23, 13); ctx.fillText('LIMIT', 23, 23);
      ctx.font = '700 ' + (lim !== null && String(lim).length > 2 ? 22 : 28) + 'px ' + FONT; ctx.fillText(lim !== null ? String(lim) : '--', 23, 45);
    }
    ctx.restore();
    // the speed bubble: white, red when over the limit
    ctx.save(); ctx.translate(x + 60, y - 50);
    ctx.shadowColor = 'rgba(0,0,0,0.3)'; ctx.shadowBlur = 5;
    ctx.beginPath(); ctx.arc(24, 24, 24, 0, Math.PI * 2); ctx.fillStyle = over ? '#d32f2f' : (C.chrome ? C.chrome.bar : '#ffffff'); ctx.fill(); ctx.shadowBlur = 0;
    ctx.fillStyle = over ? '#ffffff' : (C.chrome ? C.chrome.chipText : '#222'); ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.font = '700 20px ' + FONT; ctx.fillText(String(now), 24, 21);
    ctx.font = '500 9px ' + FONT; ctx.fillText(speed.mph ? 'mph' : 'km/h', 24, 36);
    ctx.restore();
  }

  function draw(ctx, w, h, data, view) {
    var C = skinOf(view), pt = project(view, w, h), i, k, j;
    ctx.fillStyle = C.ground; ctx.fillRect(0, 0, w, h);
    ctx.lineJoin = 'round'; ctx.lineCap = 'round';
    (data.areas || []).forEach(function (a) {
      line(ctx, pt, a.p); ctx.closePath(); ctx.fillStyle = a.k === 'water' ? C.water : C.park; ctx.fill();
    });
    var roads = data.roads || [];
    for (j = 0; j < 2; j++) {                                  // all casings first, then all fills, so crossings join cleanly
      for (i = 0; i < ORDER.length; i++) {
        k = ORDER[i];
        ctx.strokeStyle = j === 0 ? (k === 'highway' ? C.highwayCasing : k === 'arterial' ? C.arterialCasing : C.roadCasing) : C[k];
        ctx.lineWidth = widthFor(C, k, view.mpp) + (j === 0 ? C.casing : 0);
        for (var r = 0; r < roads.length; r++) if (roads[r].k === k) { line(ctx, pt, roads[r].p); ctx.stroke(); }
      }
    }
    if (data.route && data.route.length > 3) {
      line(ctx, pt, data.route); ctx.strokeStyle = C.routeCasing; ctx.lineWidth = C.routeWidth + 3; ctx.stroke();
      ctx.strokeStyle = C.route; ctx.lineWidth = C.routeWidth; ctx.stroke();
    }
    ctx.font = C.labelFont; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    (data.labels || []).forEach(function (l) {
      var q = pt(l.x, l.y); ctx.lineWidth = 3; ctx.strokeStyle = C.labelHalo; ctx.strokeText(l.text, q[0], q[1]); ctx.fillStyle = C.label; ctx.fillText(l.text, q[0], q[1]);
    });
    (data.pins || []).forEach(function (p) {
      var q = pt(p.x, p.y);
      if (q[0] < -20 || q[1] < -30 || q[0] > w + 20 || q[1] > h + 20) return;
      if (p.kind === 'rumour') { drawRumour(ctx, C, q, p, view); return; }
      drawPin(ctx, C, q, PIN_KIND[p.kind]);
      if (p.name && view.mpp <= 3) {                           // the name under the pin when zoomed in
        ctx.font = C.labelFont; ctx.textAlign = 'center'; ctx.textBaseline = 'top';
        ctx.lineWidth = 3; ctx.strokeStyle = C.labelHalo; ctx.strokeText(p.name, q[0], q[1] + 3); ctx.fillStyle = C.label; ctx.fillText(p.name, q[0], q[1] + 3);
      }
    });
    if (data.player) drawMarker(ctx, C, pt(data.player.x, data.player.y), (data.player.heading || 0) + (view.rot || 0));
    drawSpeed(ctx, w, h, C, data.speed);
  }
  var api = { draw: draw, SKINS: SKINS, skinOf: skinOf, project: project, drawSpeed: drawSpeed };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.slMapsDraw = api;
  // the game loads every folder of ui/modModules as an angular module of the same name: an empty one keeps the whole UI from failing to boot
  if (typeof angular !== 'undefined') angular.module('slMapsDraw', []);
})(typeof window !== 'undefined' ? window : this);
