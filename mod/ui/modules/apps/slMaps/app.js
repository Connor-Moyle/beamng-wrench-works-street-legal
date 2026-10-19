// Street Legal Maps: the drawing of the map. Pure canvas 2D, no game calls, so tools/mapsmock.js runs it outside the game.
// Own drawing in a light road-map style (soft beige ground, white and yellow roads with a grey casing, green parks, blue water,
// a blue route line, red teardrop pins, a blue location dot with a heading cone). No third-party logo, name or icon.
// data = { roads: [{ k: 'minor'|'street'|'arterial'|'highway', p: [x, y, x, y, ...] }], areas: [{ k: 'park'|'water', p: [x, y, ...] }],
//          route: [x, y, ...], pins: [{ x, y, name }], player: { x, y, heading (rad, 0 = north, clockwise) }, labels: [{ x, y, text }] }
// view = { cx, cy (world metres at the centre), mpp (metres per pixel), rot (rad: 0 = north up; heading-up passes the player heading) }
(function (root) {
  'use strict';
  var COLORS = {
    ground: '#f2efe9', park: '#cfe8c3', water: '#a9d3f5', label: '#5f6368', labelHalo: '#ffffff',
    casing: '#d3cfc6', minor: '#ffffff', street: '#ffffff', arterial: '#fff4cc', arterialCasing: '#e0c46a', highway: '#fbd36b', highwayCasing: '#d9a02a',
    route: '#2f6fe4', routeCasing: '#1b4fb0', pin: '#d93a2e', pinDark: '#a52a20', dot: '#2f6fe4', cone: 'rgba(47,111,228,0.28)'
  };
  var WIDTH = { minor: 3, street: 4.5, arterial: 6, highway: 8 };          // pixel widths at the nominal zoom
  var ORDER = ['minor', 'street', 'arterial', 'highway'];

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
  function widthFor(k, mpp) { return Math.max(1.5, Math.min(WIDTH[k] * 2.4, WIDTH[k] * 1.2 / Math.max(0.5, mpp) + 2)); }

  function draw(ctx, w, h, data, view) {
    var pt = project(view, w, h), i, k, j;
    ctx.fillStyle = COLORS.ground; ctx.fillRect(0, 0, w, h);
    ctx.lineJoin = 'round'; ctx.lineCap = 'round';
    (data.areas || []).forEach(function (a) {
      line(ctx, pt, a.p); ctx.closePath(); ctx.fillStyle = a.k === 'water' ? COLORS.water : COLORS.park; ctx.fill();
    });
    var roads = data.roads || [];
    for (j = 0; j < 2; j++) {                                  // all casings first, then all fills, so crossings join cleanly
      for (i = 0; i < ORDER.length; i++) {
        k = ORDER[i];
        ctx.strokeStyle = j === 0 ? (k === 'highway' ? COLORS.highwayCasing : k === 'arterial' ? COLORS.arterialCasing : COLORS.casing) : COLORS[k];
        ctx.lineWidth = widthFor(k, view.mpp) + (j === 0 ? 2.5 : 0);
        for (var r = 0; r < roads.length; r++) if (roads[r].k === k) { line(ctx, pt, roads[r].p); ctx.stroke(); }
      }
    }
    if (data.route && data.route.length > 3) {
      line(ctx, pt, data.route); ctx.strokeStyle = COLORS.routeCasing; ctx.lineWidth = 9; ctx.stroke();
      ctx.strokeStyle = COLORS.route; ctx.lineWidth = 6; ctx.stroke();
    }
    ctx.font = '600 11px Roboto, "Noto Sans", "Segoe UI", Arial, sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    (data.labels || []).forEach(function (l) {
      var q = pt(l.x, l.y); ctx.lineWidth = 3; ctx.strokeStyle = COLORS.labelHalo; ctx.strokeText(l.text, q[0], q[1]); ctx.fillStyle = COLORS.label; ctx.fillText(l.text, q[0], q[1]);
    });
    (data.pins || []).forEach(function (p) {
      var q = pt(p.x, p.y);
      if (q[0] < -20 || q[1] < -30 || q[0] > w + 20 || q[1] > h + 20) return;
      ctx.beginPath(); ctx.moveTo(q[0], q[1]); ctx.bezierCurveTo(q[0] - 13, q[1] - 14, q[0] - 11, q[1] - 30, q[0], q[1] - 30);
      ctx.bezierCurveTo(q[0] + 11, q[1] - 30, q[0] + 13, q[1] - 14, q[0], q[1]); ctx.closePath();
      ctx.fillStyle = COLORS.pin; ctx.fill(); ctx.strokeStyle = COLORS.pinDark; ctx.lineWidth = 1; ctx.stroke();
      ctx.beginPath(); ctx.arc(q[0], q[1] - 20, 4, 0, Math.PI * 2); ctx.fillStyle = '#ffffff'; ctx.fill();
    });
    if (data.player) {
      var q = pt(data.player.x, data.player.y), a = (data.player.heading || 0) + (view.rot || 0);
      ctx.save(); ctx.translate(q[0], q[1]); ctx.rotate(a);
      ctx.beginPath(); ctx.moveTo(0, 0); ctx.arc(0, 0, 46, -Math.PI / 2 - 0.5, -Math.PI / 2 + 0.5); ctx.closePath(); ctx.fillStyle = COLORS.cone; ctx.fill();
      ctx.restore();
      ctx.beginPath(); ctx.arc(q[0], q[1], 9, 0, Math.PI * 2); ctx.fillStyle = '#ffffff'; ctx.shadowColor = 'rgba(0,0,0,0.35)'; ctx.shadowBlur = 4; ctx.fill(); ctx.shadowBlur = 0;
      ctx.beginPath(); ctx.arc(q[0], q[1], 6.5, 0, Math.PI * 2); ctx.fillStyle = COLORS.dot; ctx.fill();
    }
  }
  var api = { draw: draw, COLORS: COLORS, project: project };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.slMapsDraw = api;
})(typeof window !== 'undefined' ? window : this);

// ---- the app ----------------------------------------------------------------------------------------------------------------
// A HUD app (the game's app editor places and resizes it): our phone, sideways, with the live map. The game side is sl/mapsfeed.lua.
if (typeof angular !== 'undefined') angular.module('beamng.apps').directive('slMaps', ['bngApi', function (bngApi) {
  var TEMPLATE = '<div class="slm-phone"><div class="slm-status"><span class="slm-name">Maps</span><span class="slm-icons"><i class="slm-sig"></i><i class="slm-bat"></i></span></div><div class="slm-screen"><canvas class="slm-canvas"></canvas></div></div>';
  var CSS = '.slm-phone{position:absolute;left:0;top:0;right:0;bottom:0;box-sizing:border-box;padding:7px 8px 7px 22px;background:#0b0b0d;border-radius:26px;box-shadow:0 0 0 2px #2a2a2e,0 10px 30px rgba(0,0,0,.55);display:flex;flex-direction:column;font-family:Roboto,"Noto Sans","Segoe UI",Arial,sans-serif;pointer-events:none}' +
    '.slm-status{flex:0 0 auto;display:flex;justify-content:space-between;align-items:center;height:16px;margin-bottom:3px;padding:0 10px;color:#e6e1e5;font-size:10px}' +
    '.slm-icons{display:inline-flex;gap:5px;align-items:center}.slm-sig{display:inline-block;width:10px;height:8px;background:linear-gradient(135deg,transparent 50%,#e6e1e5 50%)}.slm-bat{display:inline-block;width:14px;height:7px;border:1px solid #e6e1e5;border-radius:2px;background:linear-gradient(90deg,#e6e1e5 70%,transparent 70%)}' +
    '.slm-screen{position:relative;flex:1 1 auto;min-height:0;border-radius:18px;overflow:hidden;background:#f2efe9}.slm-canvas{display:block;width:100%;height:100%}';
  var TILE = 256, MPP = 2;
  return {
    restrict: 'EA', replace: true, template: TEMPLATE,
    link: function ($scope, element) {
      var style = document.createElement('style'); style.textContent = CSS; element[0].appendChild(style);
      var canvas = element[0].querySelector('canvas'), ctx = canvas.getContext('2d');
      var tiles = {}, asked = {}, places = [], route = [], pose = null, lastKey = '', roads = [], dirty = true;
      function ask(keys) {
        var want = keys.filter(function (k) { return !tiles[k] && !asked[k]; });
        if (!want.length) return;
        want.forEach(function (k) { asked[k] = true; });
        bngApi.engineLua('sl_mapsfeed.tiles(' + bngApi.serializeToLua(want) + ')');
      }
      function around(x, y, halfW, halfH) {
        var keys = [], x0 = Math.floor((x - halfW) / TILE), x1 = Math.floor((x + halfW) / TILE), y0 = Math.floor((y - halfH) / TILE), y1 = Math.floor((y + halfH) / TILE);
        for (var tx = x0; tx <= x1; tx++) for (var ty = y0; ty <= y1; ty++) keys.push(tx + ',' + ty);
        return keys;
      }
      function frame() {
        var w = canvas.clientWidth, h = canvas.clientHeight;
        if (!w || !h || !pose) return;
        if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; dirty = true; }
        var keys = around(pose.x, pose.y, w * MPP * 0.75, h * MPP * 0.75), key = keys.join(';');
        ask(keys);
        if (key !== lastKey || dirty) {                       // the road list is rebuilt only when the tiles in view change
          lastKey = key; dirty = false; roads = [];
          keys.forEach(function (k) { if (tiles[k]) roads = roads.concat(tiles[k]); });
        }
        var data = { roads: roads, route: route, pins: places.map(function (p) { return { x: p.x, y: p.y, name: p.name }; }), player: pose };
        draw(ctx, w, h, data, { cx: pose.x, cy: pose.y, mpp: MPP, rot: 0 });
      }
      var timer = setInterval(frame, 100);                    // 10 fps
      $scope.$on('slMapsTiles', function (ev, d) { var t = (d && d.tiles) || {}; Object.keys(t).forEach(function (k) { tiles[k] = t[k]; dirty = true; }); });
      $scope.$on('slMapsPose', function (ev, d) { pose = d; });
      $scope.$on('slMapsRoute', function (ev, d) { route = (d && d.route) || []; });
      $scope.$on('slMapsPlaces', function (ev, d) { places = (d && d.places) || []; });
      bngApi.engineLua('sl_mapsfeed.active(true)');
      $scope.$on('$destroy', function () { clearInterval(timer); bngApi.engineLua('sl_mapsfeed.active(false)'); });
    }
  };
}]);
