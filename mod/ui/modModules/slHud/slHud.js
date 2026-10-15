// Street Legal Racing - the SLRR dashboard: rev counter and speedometer (round dials, white on
// black, a red needle, the gear and the speed in digits), a road map that turns with the car, and
// a damage diagram (six body zones, the tyres, the engine). Each part can be switched off from the
// phone (Street cred > Dashboard). A global UI module, like the phone; the Lua side is
// lua/ge/extensions/sl/hud.lua, which sends 'slHud' about fifteen times a second while driving.
// createHud() is plain DOM + canvas, so it can be tried outside the game.

(function () {
  'use strict';

  var CSS = [
    '.slh-root{position:fixed;left:0;top:0;right:0;bottom:0;pointer-events:none;z-index:40;font-family:"Overpass","Roboto",sans-serif}',
    '.slh-gone{display:none!important}',
    '.slh-dials{position:absolute;right:1.6vw;bottom:2vh;display:flex;gap:10px;align-items:flex-end}',
    '.slh-dials canvas{width:190px;height:190px}',
    '.slh-left{position:absolute;left:1.6vw;bottom:2vh;display:flex;gap:10px;align-items:flex-end}',
    '.slh-left canvas.slh-map{width:200px;height:200px}',
    '.slh-left canvas.slh-dmg{width:86px;height:150px}',
  ].join('\n');

  var ZONES = ['FL', 'FR', 'ML', 'MR', 'RL', 'RR'];
  var PLACE_COLOURS = { garage: '#ff7a00', junkyard: '#4aa3ff', dealer: '#4aa3ff', scrapyard: '#9aa4b2', meet: '#c46bff' };

  // SLRR's own textures (copied from the player's SLRR by tools/slrr_ui.py): where each piece sits
  var SPRITES = {
    speedo: { sx: 328, sy: 119, s: 482, max: 360 },      // km/h, 0 bottom-left round to 360 bottom-right
    tacho: { sx: 12, sy: 440, s: 386, max: 9000 },       // rpm
    gear: { sx: 402, sy: 606, w: 412, h: 218 },
    car: { sx: 4, sy: 4, w: 74, h: 184 },                // the damage outline, in osd.png
  };

  // assets: { gauge: Image, osd: Image } - SLRR's textures, or nothing (then everything is drawn)
  function createHud(doc, assets) {
    assets = assets || {};
    var ready = function (img) { return img && img.complete && img.naturalWidth > 0; };
    var root = doc.createElement('div');
    root.className = 'slh-root slh-gone';
    var style = doc.createElement('style');
    style.textContent = CSS;
    root.appendChild(style);

    function canvas(cls, w, h) {
      var c = doc.createElement('canvas');
      c.className = cls;
      c.width = w * 2; c.height = h * 2;               // drawn at twice the size: sharp on any screen
      return c;
    }
    var left = doc.createElement('div'); left.className = 'slh-left';
    var dials = doc.createElement('div'); dials.className = 'slh-dials';
    var mapC = canvas('slh-map', 200, 200), dmgC = canvas('slh-dmg', 86, 150);
    var tachoC = canvas('slh-tacho', 190, 190), speedoC = canvas('slh-speedo', 190, 190), gearC = canvas('slh-gear', 120, 64);
    gearC.classList.add('slh-gone');
    left.appendChild(mapC); left.appendChild(dmgC);
    dials.appendChild(tachoC); dials.appendChild(gearC); dials.appendChild(speedoC);
    root.appendChild(left); root.appendChild(dials);
    doc.body.appendChild(root);

    var settings = { enabled: true, speedo: true, tacho: true, map: true, damage: true, units: 'kmh' };
    var roads = null;         // { segs: [x1,y1,x2,y2,...], grid: { 'cx|cy': [index...] }, places }
    var CELL = 150;

    function setRoads(data) {
      var segs = data.segs || [], grid = {};
      for (var i = 0; i + 3 < segs.length; i += 4) {
        var cx = Math.floor((segs[i] + segs[i + 2]) / 2 / CELL), cy = Math.floor((segs[i + 1] + segs[i + 3]) / 2 / CELL);
        var key = cx + '|' + cy;
        (grid[key] = grid[key] || []).push(i);
      }
      roads = { segs: segs, grid: grid, places: data.places || [] };
    }

    // ---------------------------------------------------------------- SLRR's own dial: its face, a needle on it
    function slrrDial(c, sp, value, digits) {
      var g = c.getContext('2d'), W = c.width, r = W / 2;
      g.clearRect(0, 0, W, W);
      g.save();
      g.beginPath(); g.arc(r, r, r - 1, 0, Math.PI * 2); g.clip();          // just this dial, not the edge of its neighbour
      g.drawImage(assets.gauge, sp.sx, sp.sy, sp.s, sp.s, 0, 0, W, W);
      g.restore();
      if (digits != null) {                                                  // in the dial's own window, as SLRR shows the speed
        g.font = 'bold ' + Math.round(r * 0.2) + 'px Overpass, Roboto, sans-serif';
        g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillStyle = '#141414';
        g.fillText(digits, r, r * 1.74);
      }
      var a0 = Math.PI * 0.75, a1 = Math.PI * 2.25;
      var na = a0 + (a1 - a0) * Math.max(0, Math.min(1, value / sp.max));
      g.save();
      g.translate(r, r);
      g.rotate(na);
      g.beginPath(); g.moveTo(-r * 0.12, -r * 0.03); g.lineTo(r * 0.78, -r * 0.01); g.lineTo(r * 0.78, r * 0.01); g.lineTo(-r * 0.12, r * 0.03); g.closePath();
      g.fillStyle = '#ff4a12'; g.shadowColor = 'rgba(0,0,0,0.6)'; g.shadowBlur = 6; g.fill();
      g.restore();
      g.beginPath(); g.arc(r, r, r * 0.17, 0, Math.PI * 2); g.fillStyle = '#9c9ca0'; g.fill();     // the cap, over the needle's root
    }

    function slrrGear(text, speedText) {
      var g = gearC.getContext('2d'), sp = SPRITES.gear, W = gearC.width, H = gearC.height;
      g.clearRect(0, 0, W, H);
      g.drawImage(assets.gauge, sp.sx, sp.sy, sp.w, sp.h, 0, 0, W, H);
      g.textAlign = 'center'; g.textBaseline = 'middle';
      g.font = 'bold ' + Math.round(H * 0.62) + 'px Overpass, Roboto, sans-serif';
      g.fillStyle = text === 'R' ? '#e01b1b' : '#1a1a1a';
      g.fillText(text, W * 0.62, H * 0.52);
    }

    // ---------------------------------------------------------------- a round dial
    function dial(c, value, max, opts) {
      var g = c.getContext('2d'), W = c.width, r = W / 2;
      g.clearRect(0, 0, W, W);
      g.save();
      g.translate(r, r);
      // face
      g.beginPath(); g.arc(0, 0, r - 4, 0, Math.PI * 2);
      var face = g.createRadialGradient(0, -r * 0.3, r * 0.1, 0, 0, r);
      face.addColorStop(0, '#2a2a2e'); face.addColorStop(1, '#070708');
      g.fillStyle = face; g.fill();
      g.lineWidth = 6; g.strokeStyle = '#8c8c94'; g.stroke();
      var a0 = Math.PI * 0.75, a1 = Math.PI * 2.25;           // 270 degrees, from bottom-left round to bottom-right
      var ang = function (v) { return a0 + (a1 - a0) * Math.max(0, Math.min(1, v / max)); };
      // red zone
      if (opts.red) {
        g.beginPath(); g.arc(0, 0, r * 0.82, ang(opts.red), a1);
        g.lineWidth = r * 0.09; g.strokeStyle = '#d4141c'; g.stroke();
      }
      // ticks and numbers
      var step = opts.step, minor = step / (opts.minor || 5);
      g.fillStyle = '#f2f2f2'; g.strokeStyle = '#f2f2f2';
      g.font = 'bold ' + Math.round(r * 0.15) + 'px Overpass, Roboto, sans-serif';
      g.textAlign = 'center'; g.textBaseline = 'middle';
      for (var v = 0; v <= max + 1e-6; v += minor) {
        var a = ang(v), major = Math.abs(v / step - Math.round(v / step)) < 1e-6;
        var r1 = r * (major ? 0.7 : 0.76), r2 = r * 0.86;
        g.beginPath(); g.moveTo(Math.cos(a) * r1, Math.sin(a) * r1); g.lineTo(Math.cos(a) * r2, Math.sin(a) * r2);
        g.lineWidth = major ? 4 : 2; g.stroke();
        if (major) g.fillText(String(Math.round(v / (opts.labelDiv || 1))), Math.cos(a) * r * 0.55, Math.sin(a) * r * 0.55);
      }
      // caption and digits
      g.font = Math.round(r * 0.11) + 'px Overpass, Roboto, sans-serif';
      g.fillStyle = '#9a9aa2';
      g.fillText(opts.caption, 0, -r * 0.28);
      if (opts.digits != null) {
        g.font = 'bold ' + Math.round(r * 0.24) + 'px Overpass, Roboto, sans-serif';
        g.fillStyle = opts.digitsColour || '#ffffff';
        g.fillText(opts.digits, 0, r * 0.62);
      }
      // needle
      var na = ang(value);
      g.rotate(na);
      g.beginPath(); g.moveTo(-r * 0.14, -r * 0.035); g.lineTo(r * 0.8, -r * 0.012); g.lineTo(r * 0.8, r * 0.012); g.lineTo(-r * 0.14, r * 0.035); g.closePath();
      g.fillStyle = '#ff2a1a'; g.fill();
      g.rotate(-na);
      g.beginPath(); g.arc(0, 0, r * 0.08, 0, Math.PI * 2); g.fillStyle = '#1a1a1c'; g.fill();
      g.lineWidth = 3; g.strokeStyle = '#555'; g.stroke();
      g.restore();
    }

    function gearText(gear) {
      if (gear === undefined || gear === null) return '';
      if (typeof gear === 'number') return gear === 0 ? 'N' : (gear < 0 ? 'R' : String(gear));
      return String(gear).toUpperCase();
    }

    // ---------------------------------------------------------------- the map, turning with the car
    function drawMap(d) {
      var g = mapC.getContext('2d'), W = mapC.width, r = W / 2, scale = r / 170;     // about 170 m to the edge
      g.clearRect(0, 0, W, W);
      g.save();
      g.beginPath(); g.arc(r, r, r - 3, 0, Math.PI * 2); g.closePath();
      g.fillStyle = 'rgba(8,10,14,0.82)'; g.fill();
      g.clip();
      var h = d.heading || 0, fx = Math.sin(h), fy = Math.cos(h), rx = Math.cos(h), ry = -Math.sin(h);
      var px = d.x, py = d.y;
      function sx(x, y) { return r + ((x - px) * rx + (y - py) * ry) * scale; }
      function sy(x, y) { return r - ((x - px) * fx + (y - py) * fy) * scale; }
      if (roads) {
        g.strokeStyle = '#c9ccd2'; g.lineWidth = 5; g.lineCap = 'round';
        g.beginPath();
        var c0x = Math.floor(px / CELL), c0y = Math.floor(py / CELL), segs = roads.segs;
        for (var i = -2; i <= 2; i++) {
          for (var j = -2; j <= 2; j++) {
            var list = roads.grid[(c0x + i) + '|' + (c0y + j)];
            if (!list) continue;
            for (var k = 0; k < list.length; k++) {
              var s = list[k];
              g.moveTo(sx(segs[s], segs[s + 1]), sy(segs[s], segs[s + 1]));
              g.lineTo(sx(segs[s + 2], segs[s + 3]), sy(segs[s + 2], segs[s + 3]));
            }
          }
        }
        g.stroke();
        roads.places.forEach(function (p) {
          var x = sx(p.x, p.y), y = sy(p.x, p.y);
          var dd = Math.sqrt((x - r) * (x - r) + (y - r) * (y - r));
          if (dd > r - 14) { x = r + (x - r) * (r - 14) / dd; y = r + (y - r) * (r - 14) / dd; }   // far away: on the rim
          g.beginPath(); g.arc(x, y, 9, 0, Math.PI * 2);
          g.fillStyle = PLACE_COLOURS[p.kind] || '#e0e0e0'; g.fill();
          g.lineWidth = 2; g.strokeStyle = '#000'; g.stroke();
        });
      }
      if (d.target) {
        var tx = sx(d.target.x, d.target.y), ty = sy(d.target.x, d.target.y);
        var td = Math.sqrt((tx - r) * (tx - r) + (ty - r) * (ty - r));
        if (td > r - 12) { tx = r + (tx - r) * (r - 12) / td; ty = r + (ty - r) * (r - 12) / td; }
        g.beginPath(); g.arc(tx, ty, 11, 0, Math.PI * 2); g.fillStyle = '#ff2a1a'; g.fill();
      }
      // you: an arrow pointing up
      g.beginPath(); g.moveTo(r, r - 16); g.lineTo(r + 11, r + 12); g.lineTo(r, r + 6); g.lineTo(r - 11, r + 12); g.closePath();
      g.fillStyle = '#ffd400'; g.fill(); g.lineWidth = 2; g.strokeStyle = '#000'; g.stroke();
      g.restore();
      g.beginPath(); g.arc(r, r, r - 3, 0, Math.PI * 2); g.lineWidth = 5; g.strokeStyle = '#8c8c94'; g.stroke();
      // north
      var nx = r + (0 * rx + 1 * ry) * (r - 16), ny = r - (0 * fx + 1 * fy) * (r - 16);
      g.font = 'bold 22px Overpass, Roboto, sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
      g.fillStyle = '#ff2a1a'; g.fillText('N', nx, ny);
    }

    // ---------------------------------------------------------------- damage: the car from above
    function damageColour(v) {
      if (!(v > 0.04)) return '#2fbf4f';
      if (v < 0.25) return '#e6d21e';
      if (v < 0.5) return '#ff8a1e';
      return '#e01b1b';
    }
    function drawDamage(d) {
      var g = dmgC.getContext('2d'), W = dmgC.width, H = dmgC.height;
      g.clearRect(0, 0, W, H);
      g.fillStyle = 'rgba(8,10,14,0.82)';
      g.fillRect(0, 0, W, H);
      var bx = W * 0.22, by = H * 0.1, bw = W * 0.56, bh = H * 0.72;
      var body = d.body || {}, tyres = d.tyres || {};
      // tyres
      [['FL', bx - 12, by + bh * 0.12], ['FR', bx + bw, by + bh * 0.12], ['RL', bx - 12, by + bh * 0.72], ['RR', bx + bw, by + bh * 0.72]].forEach(function (t) {
        g.fillStyle = tyres[t[0]] ? '#e01b1b' : '#3a3a40';
        g.fillRect(t[1], t[2], 12, bh * 0.16);
      });
      // six zones: front, middle, rear; left and right (as seen from above, front up)
      ZONES.forEach(function (z) {
        var row = z[0] === 'F' ? 0 : (z[0] === 'M' ? 1 : 2), col = z[1] === 'L' ? 0 : 1;
        g.fillStyle = damageColour(body[z]);
        g.fillRect(bx + col * bw / 2 + 2, by + row * bh / 3 + 2, bw / 2 - 4, bh / 3 - 4);
      });
      if (ready(assets.osd)) {
        var sp = SPRITES.car;                                 // SLRR's own car outline over the zones
        g.drawImage(assets.osd, sp.sx, sp.sy, sp.w, sp.h, bx - W * 0.06, by - H * 0.02, bw + W * 0.12, bh + H * 0.04);
      } else {
        g.lineWidth = 3; g.strokeStyle = '#8c8c94';
        g.strokeRect(bx, by, bw, bh);
      }
      // engine
      g.font = 'bold 22px Overpass, Roboto, sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
      g.fillStyle = d.engine === 2 ? '#e01b1b' : (d.engine === 1 ? '#ff8a1e' : '#2fbf4f');
      g.fillText('ENGINE', W / 2, H * 0.92);
    }

    // ---------------------------------------------------------------- what Lua says
    function show(part, el) { el.classList.toggle('slh-gone', !settings[part]); }

    function handle(name, data) {
      data = data || {};
      if (name === 'slHudSettings') { for (var k in data) settings[k] = data[k]; return; }
      if (name === 'slHudMap') { setRoads(data); return; }
      if (name !== 'slHud') return;
      if (!data.show) { root.classList.add('slh-gone'); return; }
      if (data.settings) for (var k2 in data.settings) settings[k2] = data.settings[k2];
      root.classList.remove('slh-gone');
      show('tacho', tachoC); show('speedo', speedoC); show('map', mapC); show('damage', dmgC);
      var mph = settings.units === 'mph';
      var speed = Math.abs(data.speed || 0) * (mph ? 2.23694 : 3.6);
      var slrr = ready(assets.gauge);
      gearC.classList.toggle('slh-gone', !(slrr && settings.tacho));
      if (settings.speedo && slrr && !mph) {
        slrrDial(speedoC, SPRITES.speedo, speed, String(Math.round(speed)));
      } else if (settings.speedo) {
        var top = mph ? 160 : 280;
        dial(speedoC, speed, top, { step: mph ? 20 : 40, minor: mph ? 4 : 4, caption: mph ? 'MPH' : 'KM/H', digits: String(Math.round(speed)) });
      }
      if (settings.tacho && slrr) {
        slrrDial(tachoC, SPRITES.tacho, data.rpm || 0);
        slrrGear(gearText(data.gear));
      } else if (settings.tacho) {
        var redline = data.maxRpm > 1000 ? data.maxRpm : 7000;
        var max = Math.max(6000, Math.ceil((redline + 500) / 1000) * 1000);
        dial(tachoC, data.rpm || 0, max, { step: 1000, minor: 4, labelDiv: 1000, red: redline, caption: 'RPM x1000',
          digits: gearText(data.gear), digitsColour: (data.rpm || 0) > redline * 0.97 ? '#ff2a1a' : '#ffd400' });
      }
      if (settings.map) drawMap(data);
      if (settings.damage) drawDamage(data);
    }

    return { handle: handle, root: root, settings: settings };
  }

  if (typeof window !== 'undefined') window.__slHudCreate = createHud;

  if (typeof angular !== 'undefined' && typeof window !== 'undefined' && !window.__slHudTest) {
    angular.module('slHud', []).run(['$rootScope', function ($rootScope) {
      if (window.__slHud) return;
      var base = '/ui/modModules/slHud/slrr/';
      var img = function (name) { var i = new Image(); i.src = base + name; return i; };
      var hud = createHud(document, { gauge: img('general_gauge.png'), osd: img('osd.png') });
      window.__slHud = hud;
      ['slHud', 'slHudMap', 'slHudSettings'].forEach(function (name) {
        $rootScope.$on(name, function (ev, data) { hud.handle(name, data); });
      });
      if (window.bngApi) window.bngApi.engineLua('if sl_hud then sl_hud.request() end');
    }]);
  }
})();
