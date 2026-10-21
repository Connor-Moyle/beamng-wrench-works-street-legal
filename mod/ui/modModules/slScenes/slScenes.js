// Street Legal Racing - cinematic moments: the full-screen scene the game plays when the night starts or the day starts (docs/TRANSITIONS.md).
// A global UI module like the phone and the HUD. The Lua side (lua/ge/extensions/sl/scenes.lua) sends 'slScene' with { kind: 'night' | 'day', title, subtitle, hold,
// reduce, fadeIn, fadeOut, skipHint } to start one and { kind: 'end' } to clear it; the world changes behind the dark screen in between. Any key or click skips it
// (after 0.4 s). With reduce set (the Reduce motion option) the scene is a still title card. Only opacity and transform are animated (CSS keyframes, no canvas, no
// timers per frame), so it costs a low-end PC next to nothing. createScenes() is plain DOM, so it can be tried outside the game (tools/scenes_test.js).

(function () {
  'use strict';

  // the city: buildings (x, width, height in 1000 x 300 units); the windows are small squares on them, lit one after another
  var BUILDINGS = [[20, 70, 120], [100, 55, 180], [165, 80, 100], [255, 60, 210], [325, 90, 140], [425, 50, 170], [485, 75, 110], [570, 65, 230], [645, 85, 150],
    [740, 55, 120], [805, 80, 190], [895, 70, 130]];

  function windowsHtml() {
    var out = [], n = 0;
    BUILDINGS.forEach(function (b, bi) {
      for (var wy = 0; wy < Math.floor((b[2] - 14) / 26); wy++) {
        for (var wx = 0; wx < Math.floor((b[1] - 8) / 18); wx++) {
          n++;
          if ((n * 7 + bi * 3) % 5 === 0) continue;                                        // (some stay dark)
          out.push('<rect class="sls-w" style="animation-delay:' + (((n * 37) % 100) / 100 * 1.3).toFixed(2) + 's" x="' + (b[0] + 6 + wx * 18) + '" y="' + (300 - b[2] + 10 + wy * 26) + '" width="8" height="12"/>');
        }
      }
    });
    return out.join('');
  }

  function cityHtml() {
    var blocks = BUILDINGS.map(function (b) { return '<rect x="' + b[0] + '" y="' + (300 - b[2]) + '" width="' + b[1] + '" height="' + b[2] + '"/>'; }).join('');
    return '<svg class="sls-city" viewBox="0 0 1000 300" preserveAspectRatio="xMidYMax slice"><g class="sls-blocks">' + blocks + '</g><g class="sls-lights">' + windowsHtml() + '</g></svg>';
  }

  var CSS = [
    '.sls-root{position:fixed;left:0;top:0;right:0;bottom:0;z-index:70;pointer-events:none;opacity:0;visibility:hidden;background:#000;overflow:hidden;font-family:"Segoe UI","Roboto","Noto Sans",sans-serif;color:#e6e1e5}',
    '.sls-root.sls-on{visibility:visible;pointer-events:auto;cursor:pointer}',
    '.sls-root.sls-shown{opacity:1;transition:opacity var(--sls-in,.5s) ease-in}',
    '.sls-root.sls-leaving{opacity:0;transition:opacity var(--sls-out,.6s) ease-out}',
    '.sls-sky,.sls-stars,.sls-orb,.sls-city,.sls-text{position:absolute}',
    '.sls-sky{left:0;top:0;right:0;bottom:0;opacity:0}',
    '.sls-night .sls-sky{background:linear-gradient(#0a0920 0%,#1b1b4a 55%,#c2542d 100%)}',
    '.sls-day .sls-sky{background:linear-gradient(#f2b27a 0%,#9bc4e8 60%,#d7ecff 100%)}',
    '.sls-stars{left:0;top:0;right:0;height:60%;opacity:0;background-image:radial-gradient(2px 2px at 12% 20%,#fff,transparent),radial-gradient(1.5px 1.5px at 30% 55%,#fff,transparent),radial-gradient(2px 2px at 47% 15%,#fff,transparent),radial-gradient(1.5px 1.5px at 63% 40%,#fff,transparent),radial-gradient(2px 2px at 78% 22%,#fff,transparent),radial-gradient(1.5px 1.5px at 90% 52%,#fff,transparent),radial-gradient(1.5px 1.5px at 22% 35%,#fff,transparent),radial-gradient(1.5px 1.5px at 70% 8%,#fff,transparent)}',
    '.sls-orb{left:68%;top:20%;width:9vmin;height:9vmin;border-radius:50%;opacity:0;transform:translateY(40vh)}',
    '.sls-night .sls-orb{background:radial-gradient(circle at 35% 35%,#fffbe8,#d9d4b8 60%,#a8a58c);box-shadow:0 0 6vmin 1vmin rgba(255,252,230,.35)}',
    '.sls-day .sls-orb{background:radial-gradient(circle,#fff6c9,#ffd35a 65%);box-shadow:0 0 10vmin 3vmin rgba(255,200,80,.5)}',
    '.sls-city{left:0;right:0;bottom:0;width:100%;height:46%}',
    '.sls-blocks rect{fill:#0b0a12}',
    '.sls-day .sls-blocks rect{fill:#2d3140}',
    '.sls-w{fill:#ffd98a;opacity:0}',
    '.sls-text{left:0;right:0;top:30%;text-align:center;pointer-events:none}',
    '.sls-title{margin:0;font-size:9vmin;font-weight:300;letter-spacing:.15em;text-transform:uppercase;opacity:0;text-shadow:0 .4vmin 3vmin rgba(0,0,0,.6)}',
    '.sls-sub{margin:1.6vmin 0 0 0;font-size:2.8vmin;letter-spacing:.12em;color:#cac4d0;opacity:0}',
    '.sls-hint{position:absolute;left:0;right:0;bottom:3vmin;text-align:center;font-size:1.9vmin;color:#938f99;opacity:0}',
    /* the motion: opacity and transform only */
    '.sls-play .sls-stars{animation:sls-fade 1s ease-out .7s both}',
    '.sls-day.sls-play .sls-stars{animation:none;opacity:0}',
    '.sls-play .sls-orb{animation:sls-rise 2.2s cubic-bezier(.2,.8,.25,1) .6s both}',
    '.sls-night.sls-play .sls-w{animation:sls-on .5s ease-out both}',
    '.sls-day.sls-play .sls-w{animation:sls-off .6s ease-in both}',
    '.sls-city{transform-origin:50% 100%}.sls-sky{transform-origin:50% 100%}',
    '.sls-play .sls-city{animation:sls-push 3.6s ease-out both}',
    '.sls-play .sls-sky{animation:sls-fade .9s ease-out .35s both,sls-drift 3.6s ease-out both}',
    '.sls-play .sls-title{animation:sls-title 1.2s cubic-bezier(.2,.8,.25,1) 1.3s both}',
    '.sls-play .sls-sub{animation:sls-fade .8s ease-out 1.9s both}',
    '.sls-play .sls-hint{animation:sls-fade .6s ease-out 1.2s both}',
    '@keyframes sls-fade{from{opacity:0}to{opacity:1}}',
    '@keyframes sls-push{from{transform:scale(1)}to{transform:scale(1.12)}}',
    '@keyframes sls-drift{from{transform:scale(1)}to{transform:scale(1.05)}}',
    '@keyframes sls-rise{from{opacity:0;transform:translateY(40vh)}to{opacity:1;transform:translateY(0)}}',
    '@keyframes sls-on{from{opacity:0}to{opacity:.95}}',
    '@keyframes sls-off{from{opacity:.95}to{opacity:0}}',
    '@keyframes sls-title{from{opacity:0;transform:translateY(2vmin) scale(1.12)}to{opacity:1;transform:translateY(0) scale(1)}}',
    /* the short moments: bars and a big title over the live game (nothing is darkened, the game goes on) */
    '.sls-banner{position:fixed;left:0;top:0;right:0;bottom:0;z-index:69;pointer-events:none;visibility:hidden;font-family:"Segoe UI","Roboto","Noto Sans",sans-serif;--sls-tone:#e6e1e5}',
    '.sls-banner.sls-bn-on{visibility:visible}',
    '.sls-bn-bad{--sls-tone:#f2b8b5}.sls-bn-good{--sls-tone:#6dd58c}.sls-bn-warn{--sls-tone:#ffd54f}.sls-bn-plain{--sls-tone:#e6e1e5}',
    '.sls-cb.sls-bn-good{--sls-tone:#56b4e9}.sls-cb.sls-bn-bad{--sls-tone:#ffb454}',
    '.sls-bn-bar{position:absolute;left:0;right:0;height:7vh;background:#000;opacity:0}',
    '.sls-bn-t{top:0}.sls-bn-b{bottom:0}',
    '.sls-bn-text{position:absolute;left:0;right:0;top:36%;text-align:center;opacity:0}',
    '.sls-bn-title{margin:0;font-size:11vmin;font-weight:600;letter-spacing:.08em;text-transform:uppercase;color:var(--sls-tone);text-shadow:0 .5vmin 3vmin rgba(0,0,0,.7)}',
    '.sls-bn-bad .sls-bn-title:before{content:"\\25BC "}.sls-bn-good .sls-bn-title:before{content:"\\2714 "}.sls-bn-warn .sls-bn-title:before{content:"\\26A0 "}',
    '.sls-bn-sub{margin:1.2vmin 0 0 0;font-size:3vmin;letter-spacing:.1em;color:#e6e1e5;text-shadow:0 .3vmin 2vmin rgba(0,0,0,.7)}',
    '.sls-bn-line{width:18vmin;height:.6vmin;margin:1.6vmin auto 0 auto;background:var(--sls-tone);transform-origin:50% 50%}',
    '.sls-bn-on .sls-bn-bar{animation:sls-fade .35s ease-out both}',
    '.sls-bn-on .sls-bn-t{animation:sls-bar-t .35s cubic-bezier(.2,.9,.25,1) both}.sls-bn-on .sls-bn-b{animation:sls-bar-b .35s cubic-bezier(.2,.9,.25,1) both}',
    '.sls-bn-on .sls-bn-text{animation:sls-bn-in .45s cubic-bezier(.2,.9,.25,1) .1s both}',
    '.sls-bn-on .sls-bn-line{animation:sls-line .5s ease-out .3s both}',
    '.sls-bn-leave .sls-bn-bar,.sls-bn-leave .sls-bn-text{animation:sls-bn-out .4s ease-in both}',
    '@keyframes sls-bar-t{from{opacity:1;transform:translateY(-100%)}to{opacity:1;transform:translateY(0)}}',
    '@keyframes sls-bar-b{from{opacity:1;transform:translateY(100%)}to{opacity:1;transform:translateY(0)}}',
    '@keyframes sls-bn-in{from{opacity:0;transform:scale(1.35)}to{opacity:1;transform:scale(1)}}',
    '@keyframes sls-line{from{transform:scaleX(0)}to{transform:scaleX(1)}}',
    '@keyframes sls-bn-out{from{opacity:1}to{opacity:0}}',
    '.sls-bn-reduce .sls-bn-bar{display:none}.sls-bn-reduce.sls-bn-on .sls-bn-text{animation:sls-fade .2s ease-out both}.sls-bn-reduce .sls-bn-line{animation:none!important}',
    '@media (prefers-reduced-motion:reduce){.sls-banner .sls-bn-bar{display:none}.sls-banner *{animation-duration:.01s!important;animation-delay:0s!important}}',
    /* reduce motion: a still card, no sky, no city, no movement */
    '.sls-reduce .sls-sky,.sls-reduce .sls-stars,.sls-reduce .sls-orb,.sls-reduce .sls-city{display:none}',
    '.sls-reduce.sls-play .sls-title{animation:sls-fade .4s ease-out .1s both}',
    '.sls-reduce.sls-play .sls-sub{animation:sls-fade .4s ease-out .3s both}',
    '.sls-reduce.sls-play .sls-hint{animation:sls-fade .4s ease-out .5s both}',
    '.sls-reduce .sls-text{top:40%}',
    '@media (prefers-reduced-motion:reduce){.sls-root .sls-sky,.sls-root .sls-stars,.sls-root .sls-orb,.sls-root .sls-city{display:none}.sls-root *{animation-duration:.01s!important;animation-delay:0s!important}}',
  ].join('\n');

  function createScenes(doc, clock, lua) {
    clock = clock || { now: function () { return Date.now(); }, set: function (f, ms) { return setTimeout(f, ms); }, clear: function (t) { clearTimeout(t); } };
    lua = lua || function () {};
    var style = doc.createElement('style');
    style.textContent = CSS;
    doc.head.appendChild(style);
    var root = doc.createElement('div');
    root.className = 'sls-root';
    root.innerHTML = '<div class="sls-sky"></div><div class="sls-stars"></div><div class="sls-orb"></div>' + cityHtml() +
      '<div class="sls-text"><h1 class="sls-title"></h1><p class="sls-sub"></p></div><div class="sls-hint"></div>';
    doc.body.appendChild(root);
    var banner = doc.createElement('div');
    banner.className = 'sls-banner';
    banner.innerHTML = '<div class="sls-bn-bar sls-bn-t"></div><div class="sls-bn-bar sls-bn-b"></div><div class="sls-bn-text"><h2 class="sls-bn-title"></h2><p class="sls-bn-sub"></p><div class="sls-bn-line"></div></div>';
    doc.body.appendChild(banner);
    var bnTimer = null, bnShownAt = 0, bnKind = null;
    var q = function (sel) { return root.querySelector(sel); };
    var shownAt = 0, hideTimer = null, kind = null;

    function bannerHide() {
      if (!bnKind) return;
      clock.clear(bnTimer);
      bnKind = null;
      banner.classList.add('sls-bn-leave');
      bnTimer = clock.set(function () { banner.className = 'sls-banner'; }, 450);
    }
    function bannerShow(d) {
      clock.clear(bnTimer);
      bnKind = d.style || 'plain';
      banner.className = 'sls-banner sls-bn-' + (d.tone || 'plain') + (d.reduce ? ' sls-bn-reduce' : '') + (root.classList.contains('sls-cb') ? ' sls-cb' : '');
      banner.querySelector('.sls-bn-title').textContent = d.title || '';
      var sub = banner.querySelector('.sls-bn-sub');
      sub.textContent = d.subtitle || '';
      sub.style.display = d.subtitle ? '' : 'none';
      bnShownAt = clock.now();
      void banner.offsetWidth;
      banner.classList.add('sls-bn-on');
      bnTimer = clock.set(bannerHide, Math.max(300, (Number(d.hold) || 2) * 1000));
    }

    function skip() {
      if (bnKind && clock.now() - bnShownAt >= 400) { bannerHide(); return true; }      // (a banner has no game side: any key puts it away)
      if (!kind || clock.now() - shownAt < 400) return false;     // (too early: a key still held from the menu must not cancel it)
      lua('sl_scenes.skip()');
      return true;
    }

    function show(d) {
      clock.clear(hideTimer);
      kind = d.kind === 'day' ? 'day' : 'night';
      root.className = 'sls-root sls-' + kind + (d.reduce ? ' sls-reduce' : '');
      root.style.setProperty('--sls-in', (Number(d.fadeIn) || 0.5) + 's');
      root.style.setProperty('--sls-out', (Number(d.fadeOut) || 0.6) + 's');
      q('.sls-title').textContent = d.title || '';
      q('.sls-sub').textContent = d.subtitle || '';
      q('.sls-hint').textContent = d.skipHint || '';
      shownAt = clock.now();
      root.classList.add('sls-on');
      void root.offsetWidth;                                       // (so the fade starts from the dark: the class change below is a transition)
      root.classList.add('sls-shown');
      root.classList.add('sls-play');
    }

    function end() {
      if (!kind) return;
      root.classList.remove('sls-shown');
      root.classList.add('sls-leaving');
      var out = (parseFloat(root.style.getPropertyValue('--sls-out')) || 0.6) * 1000;
      kind = null;
      hideTimer = clock.set(function () { root.className = 'sls-root'; }, out + 100);
    }

    function handle(name, data) {
      if (name !== 'slScene' || !data) return;
      if (data.kind === 'banner') bannerShow(data); else if (data.kind === 'end') end(); else show(data);
    }

    ['keydown', 'mousedown', 'touchstart'].forEach(function (ev) {
      doc.addEventListener(ev, function () { skip(); }, true);
    });
    return { handle: handle, root: root, banner: banner, skip: skip, active: function () { return kind; }, bannerActive: function () { return bnKind; } };
  }

  if (typeof window !== 'undefined') window.__slScenesCreate = createScenes;

  if (typeof angular !== 'undefined' && typeof window !== 'undefined' && !window.__slScenesTest) {
    angular.module('slScenes', []).run(['$rootScope', function ($rootScope) {
      if (window.__slScenes) return;
      var scenes = createScenes(document, null, function (cmd) { if (window.bngApi) window.bngApi.engineLua('if sl_scenes then ' + cmd + ' end'); });
      window.__slScenes = scenes;
      $rootScope.$on('slScene', function (ev, data) { scenes.handle('slScene', data); });
    }]);
  }
})();
