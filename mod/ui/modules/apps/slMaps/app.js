// Street Legal Maps, the HUD app. The drawing is the global module slMapsDraw (ui/modModules/slMapsDraw), shared with the phone's Map app.
// A HUD app (the game's app editor places and resizes it): our phone, sideways, with the live map. The game side is sl/mapsfeed.lua.
var draw = function () { return window.slMapsDraw.draw.apply(null, arguments); };
if (typeof angular !== 'undefined') angular.module('beamng.apps').directive('slMaps', [function () {
  var TEMPLATE = '<div class="slm-phone"><div class="slm-status"><span class="slm-name">Maps</span><span class="slm-icons"><i class="slm-sig"></i><i class="slm-bat"></i></span></div><div class="slm-screen"><canvas class="slm-canvas"></canvas></div></div>';
  var CSS = '.slm-phone{position:absolute;left:0;top:0;right:0;bottom:0;box-sizing:border-box;padding:7px 8px 7px 22px;background:#0b0b0d;border-radius:26px;box-shadow:0 0 0 2px #2a2a2e,0 10px 30px rgba(0,0,0,.55);display:flex;flex-direction:column;font-family:Roboto,"Noto Sans","Segoe UI",Arial,sans-serif;pointer-events:none}' +
    '.slm-status{flex:0 0 auto;display:flex;justify-content:space-between;align-items:center;height:16px;margin-bottom:3px;padding:0 10px;color:#e6e1e5;font-size:10px}' +
    '.slm-icons{display:inline-flex;gap:5px;align-items:center}.slm-sig{display:inline-block;width:10px;height:8px;background:linear-gradient(135deg,transparent 50%,#e6e1e5 50%)}.slm-bat{display:inline-block;width:14px;height:7px;border:1px solid #e6e1e5;border-radius:2px;background:linear-gradient(90deg,#e6e1e5 70%,transparent 70%)}' +
    '.slm-screen{position:relative;flex:1 1 auto;min-height:0;border-radius:18px;overflow:hidden;background:#f2efe9}.slm-canvas{display:block;width:100%;height:100%}';
  var TILE = 256;
  return {
    restrict: 'EA', replace: true, template: TEMPLATE,
    link: function ($scope, element) {
      var style = document.createElement('style'); style.textContent = CSS; element[0].appendChild(style);
      var canvas = element[0].querySelector('canvas'), ctx = canvas.getContext('2d');
      var MPP = 2, opts = { style: 'street', headingUp: false, speed: true };
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
      function speedOf(p) { return p && { now: p.speed || 0, limit: p.limit || null, mph: !!p.mph, sign: p.mph ? 'us' : 'round' }; }
      function frame() {
        var w = canvas.clientWidth, h = canvas.clientHeight;
        if (!w || !h || !pose) return;
        if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; dirty = true; }
        var keys = around(pose.x, pose.y, w * MPP * 0.75, h * MPP * 0.75), key = keys.join(';');
        ask(keys);
        if (key !== lastKey || dirty) {                       // the road list is rebuilt only when the tiles in view change
          lastKey = key; dirty = false; roads = [];
          keys.forEach(function (k) { if (tiles[k]) roads = roads.concat(Array.isArray(tiles[k]) ? tiles[k] : []); });
        }
        var data = { roads: roads, route: route, pins: places.map(function (p) { return { x: p.x, y: p.y, name: p.name, kind: p.kind }; }), player: pose, speed: opts.speed === false ? null : speedOf(pose) };
        draw(ctx, w, h, data, { cx: pose.x, cy: pose.y, mpp: MPP, rot: opts.headingUp ? -(pose.heading || 0) : 0, skin: opts.style });
      }
      var timer = setInterval(frame, 100);                    // 10 fps
      $scope.$on('slMapsTiles', function (ev, d) { var t = (d && d.tiles) || {}; Object.keys(t).forEach(function (k) { tiles[k] = t[k]; dirty = true; }); });
      $scope.$on('slMapsOptions', function (ev, d) { opts = d || opts; if (d && d.mpp) MPP = d.mpp; dirty = true; lastKey = ''; });
      $scope.$on('slMapsPose', function (ev, d) { pose = d; });
      $scope.$on('slMapsRoute', function (ev, d) { route = (d && d.route) || []; });
      $scope.$on('slMapsPlaces', function (ev, d) { places = (d && d.places) || []; });
      // the phone's K transition starts from this rectangle and hides the app while the phone is up (slPhone.js: window.slMapsHud)
      window.slMapsHud = {
        rect: function () { var r = element[0].getBoundingClientRect(); return element[0].offsetParent !== null && r.width ? { left: r.left, top: r.top, width: r.width, height: r.height } : null; },
        setHidden: function (b) { element[0].style.visibility = b ? 'hidden' : ''; }
      };
      bngApi.engineLua('sl_mapsfeed.use("hud", true)');
      $scope.$on('$destroy', function () { clearInterval(timer); delete window.slMapsHud; bngApi.engineLua('sl_mapsfeed.use("hud", false)'); });
    }
  };
}]);
