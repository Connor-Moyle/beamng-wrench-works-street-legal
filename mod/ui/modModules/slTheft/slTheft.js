// Street Legal Racing - the car theft screens (docs/THEFT_CONTRACT.md, Graph docs/CAR_THEFT.md): the lock (pins, or the slim jim), the bypass box, the wires and the fob, as one UI module with the kit's look.
// A global UI module like the phone and the scenes. The Lua side (sl/theft.lua) sends 'slTheftGame' with a spec { vid, stage: lock|box|wires|fob, stages, era, tool, model, name, noise, difficulty } when a stage
// starts; this module answers ONCE per stage with sl_theft.gameResult(vid, stage, ok, noise) (noise 0..1 made by the stage: a dropped pin 0.12, a wrong wire 0.2, a second crank 0.15, a fail 0.5) and calls
// sl_theft.cancel() for Escape, the Give up button or the time running out. The game then sends the next stage or seats the player. The mini-games are mouse driven (every drag also works with a pad's
// pointer); the rules that decide them are pure functions (window.__slTheftLogic) so tools/theft_test.js can prove them without a browser. Only opacity and transform are animated, a tick every 250 ms
// updates the timer, nothing runs per frame. createTheft() is plain DOM, so it can be tried outside the game.

(function () {
  'use strict';

  var W = 800, H = 440;          // the playing field (an SVG viewBox); the screen scales it
  var TEXT = {
    'theft.lock': 'Lift the pins', 'theft.lock_hint': 'Drag a pin up to its sweet spot and let go. A pin dropped from the wrong height makes noise.',
    'theft.slimjim': 'Slim jim', 'theft.slimjim_hint': 'Press the hook, slide it along the channel through every ring in order. Touching the walls makes noise.',
    'theft.box': 'Fit the bypass box', 'theft.box_hint': 'Drag the box onto the plug of the harness.',
    'theft.wires': 'Hot-wire', 'theft.wires_cut': 'Cut the marked wires: drag across them. Cut a wrong one and it makes noise.',
    'theft.wires_join': 'Join the battery to the ignition: drag from the battery terminal to the ignition terminal.',
    'theft.wires_crank': 'Touch the starter and hold to crank. Let go early and the next try is louder.',
    'theft.fob': 'Capture the fob', 'theft.fob_wait': 'Wait for the pattern, press Capture while it shows.', 'theft.fob_match': 'Match the three sliders to the captured pattern, then Confirm.',
    'theft.capture': 'Capture', 'theft.confirm': 'Confirm', 'theft.giveup': 'Give up', 'theft.noise': 'Noise', 'theft.time': 'Time', 'theft.set': 'set', 'theft.cut': 'cut',
    'theft.ok': 'Done', 'theft.failed': 'Failed', 'theft.step': 'Stage {1} of {2}', 'theft.windows_left': 'Pattern shows left: {1}', 'theft.hold': 'Hold…', 'theft.cloner': 'The cloner matches it for you.',
    'theft.tool': 'Tool: {1}', 'theft.bat': 'BAT', 'theft.ign': 'IGN', 'theft.cutme': 'CUT', 'theft.starter': 'STARTER'
  };
  function T(key, a, b) { var t = (window.__slTheftStrings && window.__slTheftStrings[key]) || TEXT[key] || key; return t.replace('{1}', a === undefined ? '' : a).replace('{2}', b === undefined ? '' : b); }

  // ------------------------------------------------------------------ pure rules (tested in tools/theft_test.js)

  // a small seeded generator so a stage is the same for the same car (and a test is repeatable)
  function rng(seed) { var s = (seed >>> 0) || 1; return function () { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; }; }
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

  // the pins: each has a sweet spot (a centre and a half height on a track 0..1, 1 = fully up); harder = a narrower band
  function makePins(n, seed) {
    var r = rng(seed), out = [];
    for (var i = 0; i < n; i++) out.push({ centre: 0.3 + r() * 0.6, half: n >= 6 ? 0.05 : 0.065, set: false });
    return out;
  }
  function releasePin(pin, level) { return Math.abs(level - pin.centre) <= pin.half; }

  // the slim jim: rings along a channel the hook must pass in order; the channel is a polyline, the wall distance the half width
  function makeChannel(n, seed) {
    var r = rng(seed + 7), pts = [], x0 = 90, step = (W - 180) / Math.max(1, n);
    for (var i = 0; i <= n; i++) pts.push({ x: x0 + step * i, y: 120 + r() * (H - 240) });
    return { points: pts, half: 30, tolerance: 22 };
  }
  function distToSegment(p, a, b) {
    var dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy;
    var t = l2 ? clamp(((p.x - a.x) * dx + (p.y - a.y) * dy) / l2, 0, 1) : 0;
    return Math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy));
  }
  function distToPolyline(p, pts) { var d = Infinity; for (var i = 0; i < pts.length - 1; i++) d = Math.min(d, distToSegment(p, pts[i], pts[i + 1])); return d; }

  // the wires: n run across the field as smooth curves (sampled to a polyline), `cut` of them carry the CUT tag
  var TAGS = ['BAT', 'IGN', 'ACC', 'STR', 'LGT', 'FUEL', 'HORN', 'FAN', 'ABS'];
  var COLOURS = ['#e57373', '#64b5f6', '#81c784', '#ffd54f', '#ba68c8', '#4dd0e1', '#ff8a65', '#a1887f', '#f06292'];
  function makeWires(n, cut, seed) {
    var r = rng(seed + 13), wires = [], lane = (H - 160) / Math.max(1, n);
    var order = []; for (var i = 0; i < n; i++) order.push(i);
    for (var k = order.length - 1; k > 0; k--) { var j = Math.floor(r() * (k + 1)); var t = order[k]; order[k] = order[j]; order[j] = t; }
    var tagged = {}; for (var c = 0; c < Math.min(cut, n); c++) tagged[order[c]] = true;
    for (var w = 0; w < n; w++) {
      var y = 90 + lane * (w + 0.5), amp = 14 + r() * 22, ph = r() * 6.28, pts = [];
      for (var s = 0; s <= 40; s++) { var x = 150 + (W - 300) * s / 40; pts.push({ x: x, y: y + Math.sin(ph + s / 40 * 6.28) * amp }); }
      wires.push({ id: w, tag: TAGS[w % TAGS.length], colour: COLOURS[w % COLOURS.length], cut: false, marked: !!tagged[w], points: pts });
    }
    return wires;
  }
  function segmentsCross(a1, a2, b1, b2) {
    function ccw(p, q, r2) { return (r2.y - p.y) * (q.x - p.x) - (q.y - p.y) * (r2.x - p.x); }
    var d1 = ccw(a1, a2, b1), d2 = ccw(a1, a2, b2), d3 = ccw(b1, b2, a1), d4 = ccw(b1, b2, a2);
    return ((d1 > 0) !== (d2 > 0)) && ((d3 > 0) !== (d4 > 0));
  }
  // which wires a drag path crosses (a path is a list of points); wires already cut are ignored
  function wiresCrossed(path, wires) {
    var hit = {};
    for (var i = 0; i < path.length - 1; i++) {
      for (var w = 0; w < wires.length; w++) {
        if (wires[w].cut || hit[wires[w].id]) continue;
        for (var s = 0; s < wires[w].points.length - 1; s++) if (segmentsCross(path[i], path[i + 1], wires[w].points[s], wires[w].points[s + 1])) { hit[wires[w].id] = true; break; }
      }
    }
    return wires.filter(function (x) { return hit[x.id]; });
  }

  // the fob: a pattern of six bars (0..1) shown in `windows` flashes; the three sliders are the pattern's thirds (0..100). Matching is within 7 points.
  function makePattern(seed) { var r = rng(seed + 29), bars = []; for (var i = 0; i < 6; i++) bars.push(0.15 + r() * 0.8); return bars; }
  function targetsOf(bars) { return [0, 1, 2].map(function (k) { return Math.round((bars[k * 2] + bars[k * 2 + 1]) / 2 * 100); }); }
  function sliderMatch(values, targets) { return values.every(function (v, i) { return Math.abs(v - targets[i]) <= 7; }); }
  function closeness(v, target) { var d = Math.abs(v - target); return d <= 7 ? 'good' : d <= 20 ? 'near' : 'far'; }

  var LOGIC = { rng: rng, makePins: makePins, releasePin: releasePin, makeChannel: makeChannel, distToPolyline: distToPolyline, makeWires: makeWires, wiresCrossed: wiresCrossed, makePattern: makePattern, targetsOf: targetsOf, sliderMatch: sliderMatch, closeness: closeness, segmentsCross: segmentsCross };
  if (typeof window !== 'undefined') window.__slTheftLogic = LOGIC;

  // ------------------------------------------------------------------ the screen

  var CSS = '.slt-root{position:fixed;left:0;top:0;right:0;bottom:0;z-index:70;display:none;align-items:center;justify-content:center;background:rgba(8,6,12,.82);color:#e6e1e5;font-family:"Segoe UI","Roboto","Noto Sans",sans-serif;-webkit-user-select:none;user-select:none}' +
    '.slt-root.slt-on{display:flex}.slt-box{width:min(940px,94vw);background:#141218;border-radius:18px;box-shadow:0 20px 60px rgba(0,0,0,.6);padding:14px 16px;display:flex;flex-direction:column;gap:8px}' +
    '.slt-head{display:flex;align-items:center;gap:12px}.slt-title{font-size:20px;flex:1}.slt-sub{font-size:13px;color:#cac4d0}.slt-hint{font-size:14px;color:#cac4d0;min-height:20px}' +
    '.slt-bars{display:flex;gap:16px}.slt-bar{flex:1;font-size:12px;color:#938f99}.slt-bar i{display:block;height:8px;border-radius:4px;background:#2b2930;margin-top:3px;overflow:hidden;position:relative}.slt-bar b{position:absolute;left:0;top:0;bottom:0;border-radius:4px;background:#a8c7fa;transition:width .25s linear}' +
    '.slt-noise b{background:#f2b8b5}.slt-btn{display:inline-flex;align-items:center;justify-content:center;height:40px;padding:0 20px;border-radius:20px;background:#3a3f4b;color:#d7e3ff;font-size:14px;font-weight:500;cursor:pointer;border:none}' +
    '.slt-btn.slt-go{background:#a8c7fa;color:#062e6f}.slt-btn.slt-off{opacity:.4;pointer-events:none}.slt-btn:focus,.slt-btn:focus-visible{outline:3px solid #ffd54f;outline-offset:2px;box-shadow:0 0 0 2px #0d0b12}' +
    '.slt-field{width:100%;height:auto;max-height:calc(100vh - 210px);background:#1d1b22;border-radius:14px;touch-action:none;display:block}.slt-field text{fill:#e6e1e5;font-size:15px;font-family:inherit}.slt-field .slt-dim{fill:#938f99}' +
    '.slt-foot{display:flex;gap:10px;align-items:center;justify-content:space-between}.slt-result{font-size:16px;font-weight:500}.slt-good{color:#6dd58c}.slt-bad{color:#f2b8b5}' +
    '.slt-pin-handle{cursor:grab}.slt-hot{cursor:pointer}';

  var NS = 'http://www.w3.org/2000/svg';

  function createTheft(doc, clock, lua) {
    var root = doc.createElement('div');
    root.className = 'slt-root';
    root.innerHTML = '<style>' + CSS + '</style><div class="slt-box"><div class="slt-head"><div class="slt-title"></div><div class="slt-sub"></div></div><div class="slt-hint"></div>' +
      '<div class="slt-bars"><div class="slt-bar slt-time"><span></span><i><b style="width:100%"></b></i></div><div class="slt-bar slt-noise"><span></span><i><b style="width:0"></b></i></div></div>' +
      '<svg class="slt-field" viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="xMidYMid meet"></svg><div class="slt-foot"><div class="slt-result"></div><div><span class="slt-extra"></span> <div class="slt-btn slt-giveup" tabindex="0" role="button"></div></div></div></div>';
    doc.body.appendChild(root);
    var q = function (s) { return root.querySelector(s); };
    var svg = q('.slt-field');
    var st = null, tickTimer = null, endTimer = null, answered = false;

    function el(name, attrs, parent) { var e = doc.createElementNS(NS, name); Object.keys(attrs || {}).forEach(function (k) { e.setAttribute(k, attrs[k]); }); if (parent) parent.appendChild(e); return e; }
    function clear() { while (svg.firstChild) svg.removeChild(svg.firstChild); }
    // a screen point to the field's units (the SVG is scaled to its box; in a page with no layout the numbers are the field's already)
    function local(ev) {
      var r = svg.getBoundingClientRect ? svg.getBoundingClientRect() : null;
      if (r && r.width > 0) return { x: (ev.clientX - r.left) * W / r.width, y: (ev.clientY - r.top) * H / r.height };
      return { x: ev.clientX, y: ev.clientY };
    }

    function noiseNow() { return clamp(st.noise, 0, 1); }
    function paintBars() {
      var left = st ? Math.max(0, st.timeLeft) / st.total : 0;
      q('.slt-time span').textContent = T('theft.time');
      q('.slt-time b').style.width = (left * 100).toFixed(0) + '%';
      q('.slt-noise span').textContent = T('theft.noise');
      q('.slt-noise b').style.width = (st ? noiseNow() * 100 : 0).toFixed(0) + '%';
    }
    function say(text, cls) { var r = q('.slt-result'); r.textContent = text || ''; r.className = 'slt-result' + (cls ? ' ' + cls : ''); }
    function hint(text) { q('.slt-hint').textContent = text || ''; }

    // the answer, once per stage: ok, the noise it made (a fail makes 0.5 at least)
    function finish(ok) {
      if (!st || answered) return;
      answered = true;
      var noise = ok ? Math.min(1, st.noise) : Math.max(0.5, Math.min(1, st.noise));
      say(ok ? T('theft.ok') : T('theft.failed'), ok ? 'slt-good' : 'slt-bad');
      lua('sl_theft.gameResult(' + Number(st.spec.vid) + ',' + JSON.stringify(st.spec.stage) + ',' + (ok ? 'true' : 'false') + ',' + noise.toFixed(2) + ')');
      stopTick();
      endTimer = clock.set(function () { hide(); }, 600);
    }
    function cancel() {
      if (!st || answered) return;
      answered = true;
      lua('sl_theft.cancel()');
      stopTick();
      hide();
    }
    function hide() { root.classList.remove('slt-on'); clear(); st = null; if (endTimer) { clock.clear(endTimer); endTimer = null; } }
    function stopTick() { if (tickTimer) { clock.clear(tickTimer); tickTimer = null; } }
    function tick() {
      if (!st || answered) return;
      st.timeLeft -= 0.25;
      if (st.onTick) st.onTick(0.25);
      paintBars();
      if (st.timeLeft <= 0) { cancel(); return; }
      tickTimer = clock.set(tick, 250);
    }

    // a drag: mousedown on a target starts it, the move and the up are heard on the whole document (the pointer may leave the field)
    var drag = null;
    function startDrag(onMove, onUp) { drag = { move: onMove, up: onUp }; }
    doc.addEventListener('mousemove', function (ev) { if (drag && st) drag.move(local(ev)); });
    doc.addEventListener('mouseup', function (ev) { if (drag && st) { var d = drag; drag = null; d.up(local(ev)); } else drag = null; });
    doc.addEventListener('keydown', function (ev) { if (st && (ev.key === 'Escape' || ev.keyCode === 27)) { ev.preventDefault(); cancel(); } }, true);
    q('.slt-giveup').addEventListener('click', function () { cancel(); });

    // ---------------------------------------------------------------- stage: the lock (pins)
    function buildLock(spec) {
      var n = Number(spec.difficulty.pins) || 4, pins = makePins(n, Number(spec.vid) || 1), slimjim = spec.tool === 'slimjim';
      if (slimjim) return buildSlimJim(spec, n);
      st.pins = pins; st.drops = 0;
      hint(T('theft.lock_hint'));
      var gap = (W - 120) / n, top = 60, bottom = H - 70, track = bottom - top, group = el('g', {}, svg);
      pins.forEach(function (pin, i) {
        var x = 60 + gap * (i + 0.5), g = el('g', { class: 'slt-pin' }, group);
        el('rect', { x: x - 16, y: top, width: 32, height: track, rx: 16, fill: '#2b2930' }, g);
        var band = el('rect', { x: x - 20, y: bottom - (pin.centre + pin.half) * track, width: 40, height: pin.half * 2 * track, rx: 6, fill: 'none', stroke: '#6dd58c', 'stroke-width': 2, 'stroke-dasharray': '4 4', opacity: 0.0, class: 'slt-band' }, g);
        var handle = el('circle', { cx: x, cy: bottom - 4, r: 17, fill: '#a8c7fa', class: 'slt-pin-handle', 'data-pin': i }, g);
        var label = el('text', { x: x, y: H - 30, 'text-anchor': 'middle', class: 'slt-dim' }, g); label.textContent = '#' + (i + 1);
        pin.el = { handle: handle, band: band, x: x };
        handle.addEventListener('mousedown', function () {
          if (pin.set) return;
          startDrag(function (p) { var yy = clamp(p.y, top, bottom - 4); handle.setAttribute('cy', yy); var lv = clamp((bottom - 4 - yy) / (track - 4), 0, 1); handle.setAttribute('fill', Math.abs(lv - pin.centre) <= pin.half * 2.2 ? '#ffd54f' : '#a8c7fa'); },      // (warm when you are close: the feel of a pin about to bind)
            function (p) {
              var level = clamp((bottom - 4 - clamp(p.y, top, bottom - 4)) / (track - 4), 0, 1);
              // the sweet spot is shown faintly once you hold near it: hint of the band by distance (a click of feedback), not by showing it from the start
              if (releasePin(pin, level)) { pin.set = true; handle.setAttribute('cy', bottom - (pin.centre) * track); handle.setAttribute('fill', '#6dd58c'); band.setAttribute('opacity', 0.9); say(pins.filter(function (x) { return x.set; }).length + ' / ' + n + ' ' + T('theft.set')); if (pins.every(function (x) { return x.set; })) finish(true); }
              else { handle.setAttribute('cy', bottom - 4); st.noise += 0.12; st.drops++; paintBars(); if (st.drops > n + 2) finish(false); }
            });
        });
      });
      q('.slt-extra').textContent = '';
    }

    // ---------------------------------------------------------------- stage: the lock with the slim jim
    function buildSlimJim(spec, n) {
      var ch = makeChannel(n, Number(spec.vid) || 1);
      st.ch = ch; st.next = 1; st.drops = 0;
      hint(T('theft.slimjim_hint'));
      var path = ch.points.map(function (p) { return p.x + ',' + p.y; }).join(' ');
      el('polyline', { points: path, fill: 'none', stroke: '#2b2930', 'stroke-width': ch.half * 2, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' }, svg);
      el('polyline', { points: path, fill: 'none', stroke: '#3a3f4b', 'stroke-width': 2, 'stroke-dasharray': '6 6' }, svg);
      var rings = [];
      for (var i = 1; i < ch.points.length; i++) rings.push(el('circle', { cx: ch.points[i].x, cy: ch.points[i].y, r: 16, fill: 'none', stroke: '#a8c7fa', 'stroke-width': 3 }, svg));
      var hook = el('circle', { cx: ch.points[0].x, cy: ch.points[0].y, r: 15, fill: '#ffd54f', class: 'slt-pin-handle', 'data-hook': 1 }, svg);
      st.hook = hook;
      hook.addEventListener('mousedown', function () {
        startDrag(function (p) {
          hook.setAttribute('cx', p.x); hook.setAttribute('cy', p.y);
          if (distToPolyline(p, ch.points) > ch.half) { st.noise += 0.12; st.drops++; st.next = 1; hook.setAttribute('cx', ch.points[0].x); hook.setAttribute('cy', ch.points[0].y); rings.forEach(function (r) { r.setAttribute('stroke', '#a8c7fa'); }); drag = null; paintBars(); if (st.drops > n + 2) finish(false); return; }
          var target = ch.points[st.next];
          if (target && Math.hypot(p.x - target.x, p.y - target.y) <= ch.tolerance) { rings[st.next - 1].setAttribute('stroke', '#6dd58c'); st.next++; if (st.next >= ch.points.length) { drag = null; finish(true); } }
        }, function () { if (!answered) { st.next = 1; hook.setAttribute('cx', ch.points[0].x); hook.setAttribute('cy', ch.points[0].y); rings.forEach(function (r) { r.setAttribute('stroke', '#a8c7fa'); }); } });
      });
    }

    // ---------------------------------------------------------------- stage: the bypass box
    function buildBox(spec) {
      hint(T('theft.box_hint'));
      el('rect', { x: W - 230, y: H / 2 - 50, width: 110, height: 100, rx: 10, fill: '#2b2930', stroke: '#938f99', 'stroke-width': 3 }, svg);
      var plug = { x: W - 175, y: H / 2 };
      for (var i = 0; i < 4; i++) el('rect', { x: plug.x - 30 + i * 16, y: plug.y - 20, width: 10, height: 40, rx: 3, fill: '#49454f' }, svg);
      var harness = el('path', { d: 'M ' + (W - 230) + ' ' + (H / 2) + ' C ' + (W - 330) + ' ' + (H / 2) + ' ' + (W - 330) + ' 60 ' + (W - 430) + ' 60', fill: 'none', stroke: '#938f99', 'stroke-width': 8, 'stroke-linecap': 'round' }, svg);
      var g = el('g', { class: 'slt-pin-handle', 'data-box': 1 }, svg);
      var rect = el('rect', { x: 0, y: 0, width: 110, height: 70, rx: 10, fill: '#a8c7fa' }, g);
      var label = el('text', { x: 55, y: 40, 'text-anchor': 'middle', fill: '#062e6f' }, g); label.textContent = 'BOX'; label.setAttribute('style', 'fill:#062e6f');
      var pos = { x: 90, y: H - 130 };
      g.setAttribute('transform', 'translate(' + pos.x + ',' + pos.y + ')');
      st.box = { pos: pos, plug: plug };
      g.addEventListener('mousedown', function () {
        startDrag(function (p) { pos.x = clamp(p.x - 55, 0, W - 110); pos.y = clamp(p.y - 35, 0, H - 70); g.setAttribute('transform', 'translate(' + pos.x + ',' + pos.y + ')'); },
          function () { if (Math.hypot(pos.x + 55 - plug.x, pos.y + 35 - plug.y) <= 40) { g.setAttribute('transform', 'translate(' + (plug.x - 55) + ',' + (plug.y - 35) + ')'); finish(true); } });
      });
    }

    // ---------------------------------------------------------------- stage: the wires (cut, join, crank)
    function buildWires(spec) {
      var n = Number(spec.difficulty.wires) || 5, cut = Number(spec.difficulty.cut) || 3;
      st.wires = makeWires(n, cut, Number(spec.vid) || 1); st.phase = 'cut'; st.crank = 0; st.cranks = 0; st.joined = false;
      var wg = el('g', {}, svg), shown = [];
      function drawWires() {
        wg.innerHTML = '';
        st.wires.forEach(function (w) {
          var pts = w.points.map(function (p) { return p.x + ',' + p.y; }).join(' ');
          if (w.cut) {
            var mid = Math.floor(w.points.length / 2), a = w.points.slice(0, mid - 1).map(function (p) { return p.x + ',' + p.y; }).join(' '), b = w.points.slice(mid + 2).map(function (p) { return p.x + ',' + p.y; }).join(' ');
            el('polyline', { points: a, fill: 'none', stroke: w.colour, 'stroke-width': 7, 'stroke-linecap': 'round' }, wg); el('polyline', { points: b, fill: 'none', stroke: w.colour, 'stroke-width': 7, 'stroke-linecap': 'round' }, wg);
          } else el('polyline', { points: pts, fill: 'none', stroke: w.colour, 'stroke-width': 7, 'stroke-linecap': 'round', 'data-wire': w.id }, wg);
          var tag = el('g', { transform: 'translate(' + (w.points[0].x - 70) + ',' + (w.points[0].y - 11) + ')' }, wg);
          el('rect', { width: 62, height: 22, rx: 6, fill: w.marked ? '#f2b8b5' : '#2b2930' }, tag);
          var tx = el('text', { x: 31, y: 16, 'text-anchor': 'middle' }, tag); tx.textContent = w.marked ? T('theft.cutme') : w.tag; tx.setAttribute('style', 'font-size:12px;fill:' + (w.marked ? '#410002' : '#e6e1e5'));
        });
      }
      drawWires();
      hint(T('theft.wires_cut'));
      var trail = el('polyline', { points: '', fill: 'none', stroke: '#ffd54f', 'stroke-width': 3, 'stroke-linecap': 'round', opacity: 0.8 }, svg);
      var overlay = el('rect', { x: 0, y: 0, width: W, height: H, fill: 'transparent', 'data-cutlayer': 1 }, svg);
      var path = [];
      overlay.addEventListener('mousedown', function (ev) {
        if (st.phase !== 'cut') return;
        path = [local(ev)];
        startDrag(function (p) { path.push(p); trail.setAttribute('points', path.map(function (a) { return a.x + ',' + a.y; }).join(' ')); },
          function (p) {
            path.push(p); trail.setAttribute('points', '');
            wiresCrossed(path, st.wires).forEach(function (w) { w.cut = true; if (!w.marked) st.noise += 0.2; });
            drawWires(); paintBars();
            var left = st.wires.filter(function (w) { return w.marked && !w.cut; }).length;
            if (left === 0) startJoin();
            else if (st.wires.filter(function (w) { return !w.marked && w.cut; }).length > 2) finish(false);
            else say(left + ' ' + T('theft.cut') + '…');
          });
      });
      function startJoin() {
        st.phase = 'join'; hint(T('theft.wires_join')); overlay.setAttribute('pointer-events', 'none');
        var bat = { x: 120, y: H - 60 }, ign = { x: W - 120, y: H - 60 };
        el('circle', { cx: bat.x, cy: bat.y, r: 20, fill: '#e57373', 'data-battery': 1, class: 'slt-hot' }, svg);
        var bt = el('text', { x: bat.x, y: bat.y + 36, 'text-anchor': 'middle' }, svg); bt.textContent = T('theft.bat');
        el('circle', { cx: ign.x, cy: ign.y, r: 20, fill: '#2b2930', stroke: '#e6e1e5', 'stroke-width': 3, 'data-ignition': 1 }, svg);
        var it = el('text', { x: ign.x, y: ign.y + 36, 'text-anchor': 'middle' }, svg); it.textContent = T('theft.ign');
        var lead = el('line', { x1: bat.x, y1: bat.y, x2: bat.x, y2: bat.y, stroke: '#e57373', 'stroke-width': 7, 'stroke-linecap': 'round' }, svg);
        var tip = svg.querySelector('[data-battery]');
        tip.addEventListener('mousedown', function () {
          startDrag(function (p) { lead.setAttribute('x2', p.x); lead.setAttribute('y2', p.y); },
            function (p) { if (Math.hypot(p.x - ign.x, p.y - ign.y) <= 34) { lead.setAttribute('x2', ign.x); lead.setAttribute('y2', ign.y); st.joined = true; startCrank(); } else { lead.setAttribute('x2', bat.x); lead.setAttribute('y2', bat.y); } });
        });
      }
      function startCrank() {
        st.phase = 'crank'; hint(T('theft.wires_crank'));
        var cx = W / 2, cy = H / 2 + 10, g = el('g', { class: 'slt-hot', 'data-starter': 1 }, svg);
        el('circle', { cx: cx, cy: cy, r: 46, fill: '#3a3f4b', stroke: '#a8c7fa', 'stroke-width': 4 }, g);
        var ring = el('circle', { cx: cx, cy: cy, r: 58, fill: 'none', stroke: '#6dd58c', 'stroke-width': 6, 'stroke-dasharray': (2 * Math.PI * 58).toFixed(1), 'stroke-dashoffset': (2 * Math.PI * 58).toFixed(1), transform: 'rotate(-90 ' + cx + ' ' + cy + ')' }, svg);
        var tx = el('text', { x: cx, y: cy + 5, 'text-anchor': 'middle' }, g); tx.textContent = T('theft.starter');
        g.addEventListener('mousedown', function () {
          st.holding = true; st.crank = 0; say(T('theft.hold'));
          st.onTick = function (dt) { if (!st.holding) return; st.crank += dt; ring.setAttribute('stroke-dashoffset', ((1 - Math.min(1, st.crank / 1.2)) * 2 * Math.PI * 58).toFixed(1)); if (st.crank >= 1.2) { st.holding = false; finish(true); } };
          startDrag(function () {}, function () { if (!answered && st.holding) { st.holding = false; st.crank = 0; st.cranks++; st.noise += st.cranks > 1 ? 0.15 : 0; ring.setAttribute('stroke-dashoffset', (2 * Math.PI * 58).toFixed(1)); paintBars(); say(''); } });
        });
      }
    }

    // ---------------------------------------------------------------- stage: the fob
    function buildFob(spec) {
      var d = spec.difficulty, windows = Number(d.windows) || 2, cloner = spec.tool === 'cloner';
      st.pattern = makePattern(Number(spec.vid) || 1); st.targets = targetsOf(st.pattern); st.windowsLeft = windows; st.showing = false; st.captured = false; st.wrong = 0; st.values = [50, 50, 50]; st.sinceShow = 0;
      hint(T('theft.fob_wait'));
      var bars = [];
      for (var i = 0; i < 6; i++) bars.push(el('rect', { x: 130 + i * 90, y: 60, width: 60, height: 150, rx: 8, fill: '#2b2930' }, svg));
      var btn = el('g', { class: 'slt-hot', 'data-capture': 1 }, svg);
      el('rect', { x: W / 2 - 80, y: 250, width: 160, height: 48, rx: 24, fill: '#a8c7fa' }, btn);
      var bt = el('text', { x: W / 2, y: 281, 'text-anchor': 'middle' }, btn); bt.textContent = T('theft.capture'); bt.setAttribute('style', 'fill:#062e6f;font-weight:500');
      function show(on) {
        st.showing = on;
        bars.forEach(function (b, i) { b.setAttribute('height', on ? Math.round(st.pattern[i] * 150) : 150); b.setAttribute('y', on ? 60 + 150 - Math.round(st.pattern[i] * 150) : 60); b.setAttribute('fill', on ? '#a8c7fa' : '#2b2930'); });
      }
      st.show = show;
      // the pattern flashes for 1.4 s, then waits 1.6 s, `windows` times
      st.onTick = function (dt) {
        if (st.captured || st.windowsLeft < 0) return;
        st.sinceShow += dt;
        if (!st.showing && st.sinceShow >= 1.5 && st.windowsLeft > 0) { st.windowsLeft--; st.sinceShow = 0; show(true); say(T('theft.windows_left', st.windowsLeft)); }
        else if (st.showing && st.sinceShow >= 1.5) { st.sinceShow = 0; show(false); if (st.windowsLeft === 0 && !st.captured) finish(false); }
      };
      btn.addEventListener('mousedown', function () {
        if (st.captured || !st.showing) return;
        st.captured = true; show(false);
        if (cloner) { say(T('theft.cloner')); finish(true); return; }
        buildMatch(btn);
      });
      function buildMatch(btnEl) {
        hint(T('theft.fob_match')); svg.removeChild(btnEl);
        st.sliders = [];
        [0, 1, 2].forEach(function (k) {
          var y = 90 + k * 80, x0 = 150, len = W - 300, g = el('g', {}, svg);
          el('rect', { x: x0, y: y - 6, width: len, height: 12, rx: 6, fill: '#2b2930' }, g);
          var knob = el('circle', { cx: x0 + len * 0.5, cy: y, r: 16, fill: '#a8c7fa', class: 'slt-pin-handle', 'data-slider': k }, g);
          var lab = el('text', { x: x0 + len + 24, y: y + 5, class: 'slt-dim' }, g); lab.textContent = '50';
          knob.addEventListener('mousedown', function () {
            startDrag(function (p) { var v = Math.round(clamp((p.x - x0) / len, 0, 1) * 100); st.values[k] = v; knob.setAttribute('cx', x0 + len * v / 100); lab.textContent = String(v); knob.setAttribute('fill', { good: '#6dd58c', near: '#ffd54f', far: '#a8c7fa' }[closeness(v, st.targets[k])]); }, function () {});
          });
        });
        var ok = el('g', { class: 'slt-hot', 'data-confirm': 1 }, svg);
        el('rect', { x: W / 2 - 80, y: 340, width: 160, height: 48, rx: 24, fill: '#a8c7fa' }, ok);
        var ct = el('text', { x: W / 2, y: 371, 'text-anchor': 'middle' }, ok); ct.textContent = T('theft.confirm'); ct.setAttribute('style', 'fill:#062e6f;font-weight:500');
        ok.addEventListener('mousedown', function () { if (sliderMatch(st.values, st.targets)) finish(true); else { st.wrong++; st.noise += 0.1; paintBars(); if (st.wrong >= 3) finish(false); } });
      }
    }

    // ---------------------------------------------------------------- opening a stage
    function show(spec) {
      if (!spec || !spec.stage) return;
      if (endTimer) { clock.clear(endTimer); endTimer = null; }
      stopTick(); clear(); drag = null; answered = false;
      var stages = spec.stages || [spec.stage], at = Math.max(1, stages.indexOf(spec.stage) + 1), total = Math.max(5, (Number(spec.difficulty && spec.difficulty.seconds) || 30) / stages.length);
      st = { spec: spec, noise: Number(spec.noise) || 0, total: total, timeLeft: total };
      var titles = { lock: spec.tool === 'slimjim' ? T('theft.slimjim') : T('theft.lock'), box: T('theft.box'), wires: T('theft.wires'), fob: T('theft.fob') };
      q('.slt-title').textContent = titles[spec.stage] || spec.stage;
      q('.slt-sub').textContent = (spec.name ? spec.name + ' · ' : '') + T('theft.step', at, stages.length) + (spec.tool ? ' · ' + T('theft.tool', spec.tool) : '');
      q('.slt-giveup').textContent = T('theft.giveup');
      say('');
      root.classList.add('slt-on');
      paintBars();
      ({ lock: buildLock, box: buildBox, wires: buildWires, fob: buildFob }[spec.stage] || function () {})(spec);
      tickTimer = clock.set(tick, 250);
    }

    function handle(name, data) {
      if (name === 'slTheftGame' && data) show(data);
      else if (name === 'slTheftEnd') { if (st && !answered) { answered = true; } hide(); }
    }
    return { handle: handle, root: root, svg: svg, state: function () { return st; }, cancel: cancel, active: function () { return !!st; } };
  }

  if (typeof window !== 'undefined') window.__slTheftCreate = createTheft;

  if (typeof angular !== 'undefined' && typeof window !== 'undefined' && !window.__slTheftTest) {
    angular.module('slTheft', []).run(['$rootScope', function ($rootScope) {
      if (window.__slTheft) return;
      var clock = { now: function () { return Date.now(); }, set: function (f, ms) { return setTimeout(f, ms); }, clear: function (t) { clearTimeout(t); } };
      var t = createTheft(document, clock, function (cmd) { if (window.bngApi) window.bngApi.engineLua('if sl_theft then ' + cmd + ' end'); });
      window.__slTheft = t;
      ['slTheftGame', 'slTheftEnd'].forEach(function (name) { $rootScope.$on(name, function (ev, data) { t.handle(name, data); }); });
    }]);
  }
})();
