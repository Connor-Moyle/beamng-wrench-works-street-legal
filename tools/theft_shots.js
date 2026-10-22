// Renders the car theft screens (ui/modModules/slTheft/slTheft.js) in headless Chrome, one PNG per stage, to LOOK at them (docs/UI_STYLE.md). Needs Google Chrome (set CHROME for another path).
//   node tools/theft_shots.js <outdir> [lock box wires fob slimjim]
const fs = require('fs'), os = require('os'), path = require('path');
const { spawnSync } = require('child_process');
const CHROME = process.env.CHROME || ['C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe', '/usr/bin/google-chrome', '/usr/bin/chromium'].find((p) => fs.existsSync(p));
if (!CHROME) { console.log('theft shots skipped: no Chrome found (set CHROME)'); process.exit(0); }
const out = path.resolve(process.argv[2] || path.join(os.tmpdir(), 'theft-shots'));
const stages = process.argv.slice(3).length ? process.argv.slice(3) : ['lock', 'slimjim', 'box', 'wires', 'fob'];
fs.mkdirSync(out, { recursive: true });
const code = fs.readFileSync(path.join(__dirname, '..', 'mod/ui/modModules/slTheft/slTheft.js'), 'utf8');
const fx = require('./theft_fixture.js');
const harness = `window.__slTheftTest = true;\n${code}\n(function () {\n  var fx = ${JSON.stringify(fx)};\n  var clock = { now: function () { return Date.now(); }, set: function (f, ms) { return setTimeout(f, ms); }, clear: function (t) { clearTimeout(t); } };\n  var t = window.__slTheftCreate(document, clock, function () {});\n  var k = location.hash.slice(1);\n  var spec = k === 'slimjim' ? Object.assign({}, fx.lock, { tool: 'slimjim' }) : fx[k];\n  t.handle('slTheftGame', spec);\n  document.title = 'ready';\n})();`;
const html = '<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;width:100%;height:100%;background:#303030}</style></head><body><script>' + harness.replace(/<\/script>/g, '<\\/script>') + '</script></body></html>';
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'theft-shots-'));
const file = path.join(dir, 'page.html');
fs.writeFileSync(file, html);
for (const stage of stages) {
  const png = path.join(out, stage + '.png');
  const r = spawnSync(CHROME, ['--headless=new', '--disable-gpu', '--no-sandbox', '--hide-scrollbars', '--window-size=1000,640', '--virtual-time-budget=2000', '--user-data-dir=' + path.join(dir, 'p-' + stage), '--screenshot=' + png, 'file:///' + file.split(path.sep).join('/') + '#' + stage], { encoding: 'utf8', timeout: 60000 });
  console.log(stage + ': ' + (fs.existsSync(png) ? png : 'no shot ' + (r.stderr || '').slice(0, 120)));
}
