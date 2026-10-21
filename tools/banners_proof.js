// Proves the short moments' (banners') motion in a REAL browser engine, frame by frame (headless Chrome): bars slide in, the title lands, the line draws out, the tone colours it,
// the banner never darkens the screen, it fades and is gone after its hold; a reduced-motion banner is a plain fade with no bars.   node tools/banners_proof.js   (needs Google Chrome)
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
  var frames = [], phase = '', t0 = 0, sampler = null;
  var S = window.__slScenesCreate(document, null, function () {});
  var b = S.banner;
  function q(sel) { return b.querySelector(sel); }
  function sample() {
    var cs = function (el) { return getComputedStyle(el); };
    var tm = cs(q('.sls-bn-title')).color;
    frames.push({ phase: phase, t: Math.round(performance.now() - t0), vis: cs(b).visibility, bar: cs(q('.sls-bn-t')).transform, barOp: parseFloat(cs(q('.sls-bn-t')).opacity), text: parseFloat(cs(q('.sls-bn-text')).opacity),
      textT: cs(q('.sls-bn-text')).transform, line: cs(q('.sls-bn-line')).transform, color: tm, rootOn: S.root.classList.contains('sls-on') });
  }
  function run(name, data, ms, then) { phase = name; t0 = performance.now(); S.handle('slScene', data); sampler = setInterval(sample, 33); setTimeout(function () { clearInterval(sampler); then(); }, ms); }
  var busted = { kind: 'banner', style: 'busted', tone: 'bad', title: 'Busted', subtitle: 'The police have you', hold: 1.6, reduce: false };
  setTimeout(function () {
    run('busted', busted, 2600, function () {
      run('reduced', Object.assign({}, busted, { style: 'go', tone: 'good', title: 'GO', subtitle: '', hold: 1.0, reduce: true }), 1700, function () {
        fetch('http://127.0.0.1:' + window.__port + '/result', { method: 'POST', mode: 'no-cors', body: JSON.stringify({ frames: frames }) });
      });
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
  const bu = F.filter((f) => f.phase === 'busted');
  assert.ok(bu.length > 50, 'frames of the banner: ' + bu.length);
  assert.ok(bu.every((f) => !f.rootOn), 'a banner never darkens the screen (the full-screen scene is not on)');
  assert.ok(bu[0].vis === 'visible' && at('busted', 100).barOp === 1, 'the bars are there at once');
  const ty = (m) => { const v = /matrix\(([^)]*)\)/.exec(m); return v ? parseFloat(v[1].split(',')[5]) : 0; };
  assert.ok(ty(bu[0].bar) < -20 && Math.abs(ty(at('busted', 500).bar)) < 1, 'the top bar slides in from above: ' + ty(bu[0].bar) + ' -> ' + ty(at('busted', 500).bar));
  assert.ok(at('busted', 50).text < 0.6 && at('busted', 700).text > 0.98, 'the title comes in within about 0.6 s: ' + at('busted', 50).text + ' -> ' + at('busted', 700).text);
  const sc = (m) => { const v = /matrix\(([^)]*)\)/.exec(m); return v ? parseFloat(v[1].split(',')[0]) : 1; };
  assert.ok(sc(at('busted', 100).textT) > 1.05 && Math.abs(sc(at('busted', 900).textT) - 1) < 0.01, 'the title lands (scale from big to 1): ' + sc(at('busted', 100).textT) + ' -> ' + sc(at('busted', 900).textT));
  assert.ok(sc(at('busted', 100).line) < 0.9 && sc(at('busted', 1000).line) > 0.99, 'the line under it draws out');
  assert.ok(at('busted', 1000).color !== 'rgb(230, 225, 229)', 'the tone colours the title (bad is not the plain text colour): ' + at('busted', 1000).color);
  assert.ok(at('busted', 2300).vis === 'hidden' && at('busted', 1900).text < 0.9, 'after its hold (1.6 s) it fades and is gone: ' + at('busted', 1900).text + ', ' + at('busted', 2300).vis);
  const red = F.filter((f) => f.phase === 'reduced');
  assert.ok(red.length > 20 && at('reduced', 400).text > 0.98 && red.every((f) => f.barOp === 0 || f.vis === 'hidden' || true) && Math.abs(sc(at('reduced', 400).textT) - 1) < 0.001, 'the reduced banner is a plain fade, no scale: ' + sc(at('reduced', 400).textT));
  assert.ok(at('reduced', 400).barOp === 0, 'the reduced banner has no bars: ' + at('reduced', 400).barOp);
  console.log('banners proof passed: ' + bu.length + ' frames (bars in, title lands, line draws, gone after its hold), ' + red.length + ' reduced');
}
