// Proves the cinematic moments' motion in a REAL browser engine, frame by frame (headless Chrome): the night scene darkens the screen, the sky and the moon come in, the city's
// lights come on one after another, the title card appears; the scene clears when the game says so; a reduced-motion scene is a still card; any key after 0.4 s asks the game to skip.
// jsdom (tools/scenes_test.js) has no animation, so it only checks the logic; this checks the motion.   node tools/scenes_proof.js   (needs Google Chrome; set CHROME for another path)
const fs = require('fs'), os = require('os'), path = require('path'), assert = require('assert');
const { spawn } = require('child_process');
const http = require('http');

const CHROME = process.env.CHROME || ['C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', '/usr/bin/google-chrome', '/usr/bin/chromium'].find((p) => fs.existsSync(p));
if (!CHROME) { console.log('scenes proof skipped: no Chrome found (set CHROME)'); process.exit(0); }

const code = fs.readFileSync(path.join(__dirname, '..', 'mod/ui/modModules/slScenes/slScenes.js'), 'utf8');
const harness = `
window.__slScenesTest = true;
${code}
(function () {
  var asked = [], frames = [], phase = 'night', t0 = 0, sampler = null;
  var S = window.__slScenesCreate(document, null, function (c) { asked.push(c); });
  var root = S.root;
  function q(sel) { return root.querySelector(sel); }
  function sample() {
    var cs = function (el) { return getComputedStyle(el); };
    var lit = 0, ws = root.querySelectorAll('.sls-w');
    for (var i = 0; i < ws.length; i++) if (parseFloat(cs(ws[i]).opacity) > 0.5) lit++;
    frames.push({ phase: phase, t: Math.round(performance.now() - t0), root: parseFloat(cs(root).opacity), vis: cs(root).visibility, sky: parseFloat(cs(q('.sls-sky')).opacity), skyShown: cs(q('.sls-sky')).display !== 'none',
      title: parseFloat(cs(q('.sls-title')).opacity), sub: parseFloat(cs(q('.sls-sub')).opacity), lit: lit, windows: ws.length, orb: cs(q('.sls-orb')).transform });
  }
  function run(name, data, ms, then) { phase = name; t0 = performance.now(); S.handle('slScene', data); sampler = setInterval(sample, 33); setTimeout(function () { clearInterval(sampler); then(); }, ms); }
  var night = { kind: 'night', title: 'Night', subtitle: 'Day 4: the street is awake', skipHint: 'Press any key to skip', hold: 3.4, fadeIn: 0.5, fadeOut: 0.6, reduce: false };
  setTimeout(function () {
    run('night', night, 3000, function () {
      document.dispatchEvent(new Event('keydown'));                                   // (3 s in: after the 0.4 s guard)
      phase = 'leaving'; t0 = performance.now(); S.handle('slScene', { kind: 'end' }); sampler = setInterval(sample, 33);
      setTimeout(function () {
        clearInterval(sampler);
        run('reduced', Object.assign({}, night, { reduce: true, hold: 1.4, title: 'Night' }), 1500, function () {
          fetch('http://127.0.0.1:' + window.__port + '/result', { method: 'POST', mode: 'no-cors', body: JSON.stringify({ frames: frames, asked: asked }) });
        });
      }, 1100);
    });
  }, 300);
})();`;
const html = '<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;width:100%;height:100%;background:#444}</style></head><body><script>' + harness.replace(/<\/script>/g, '<\\/script>') + '</script></body></html>';
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'scenes-proof-'));
const file = path.join(dir, 'page.html');
let chrome;
const server = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => { body += c; });
  req.on('end', () => { res.end('ok'); chrome.kill(); server.close(); try { check(JSON.parse(body)); } catch (e) { console.error(e.message); process.exitCode = 1; } });
});
server.listen(0, '127.0.0.1', () => {
  fs.writeFileSync(file, html.replace('<script>', '<script>window.__port = ' + server.address().port + ';'));
  chrome = spawn(CHROME, ['--headless=new', '--disable-gpu', '--no-sandbox', '--window-size=1280,720', '--user-data-dir=' + path.join(dir, 'profile'), 'file:///' + file.split(path.sep).join('/')], { stdio: 'ignore' });
  setTimeout(() => { console.error('no result from the page in 40 s'); chrome.kill(); server.close(); process.exitCode = 1; }, 40000).unref();
});

function check(out) {
  const F = out.frames;
  const at = (phase, ms) => F.filter((f) => f.phase === phase && f.t >= ms).shift();
  const night = F.filter((f) => f.phase === 'night');
  assert.ok(night.length > 50, 'frames of the night scene: ' + night.length);
  // the screen goes dark first (the fade in, 0.5 s), then the sky, the moon, the lights, the title
  assert.ok(night[0].root < 0.9, 'the scene starts from the clear picture: ' + night[0].root);
  assert.ok(at('night', 700).root > 0.97, 'the screen is dark under the scene by 0.7 s: ' + at('night', 700).root);
  assert.ok(at('night', 300).sky < 0.5 && at('night', 1500).sky > 0.95, 'the sky comes in after the fade: ' + at('night', 300).sky + ' -> ' + at('night', 1500).sky);
  assert.ok(at('night', 600).title < 0.1 && at('night', 1500).title > 0.05 && at('night', 2800).title > 0.95, 'the title comes in late and ends fully visible: ' + at('night', 600).title + ', ' + at('night', 1500).title + ', ' + at('night', 2800).title);
  assert.ok(at('night', 2800).sub > 0.9, 'the subtitle follows: ' + at('night', 2800).sub);
  const lit = night.map((f) => f.lit);
  assert.ok(lit[0] < 3 && lit[lit.length - 1] > 0.8 * night[0].windows * 0.8, 'the city lights come on: ' + lit[0] + ' -> ' + lit[lit.length - 1] + ' of ' + night[0].windows);
  for (let i = 1; i < lit.length; i++) assert.ok(lit[i] >= lit[i - 1] - 1, 'the lights only come on, never off (frame ' + i + ': ' + lit[i - 1] + ' -> ' + lit[i] + ')');
  assert.ok(new Set(lit).size > 8, 'they come on one after another, not all at once: ' + new Set(lit).size + ' different counts');
  assert.ok(night[0].orb !== night[night.length - 1].orb, 'the moon moves');
  // the skip: a key after 0.4 s asks the game
  assert.deepStrictEqual(out.asked, ['sl_scenes.skip()'], 'a key at 3 s asked the game to skip once: ' + JSON.stringify(out.asked));
  // the end: it fades out and is gone
  const leaving = F.filter((f) => f.phase === 'leaving');
  assert.ok(leaving[0].root > 0.9 && leaving[leaving.length - 1].root < 0.02 && leaving[leaving.length - 1].vis === 'hidden', 'it fades out and is gone: ' + leaving[0].root + ' -> ' + leaving[leaving.length - 1].root + ' ' + leaving[leaving.length - 1].vis);
  // reduced motion: a still card, no sky, title there quickly
  const red = F.filter((f) => f.phase === 'reduced');
  assert.ok(red.length > 20 && red.every((f) => !f.skyShown), 'the reduced scene has no sky');
  assert.ok(at('reduced', 900).title > 0.95 && at('reduced', 900).lit === 0, 'the reduced scene shows its title by 0.9 s with no moving lights: ' + at('reduced', 900).title);
  console.log('scenes proof passed: ' + night.length + ' frames of the night scene (dark by 0.7 s, ' + new Set(lit).size + ' light steps, title at 100% by 2.8 s), ' + leaving.length + ' frames leaving, ' + red.length + ' reduced');
}
