// Runs the cinematic moments module (ui/modModules/slScenes/slScenes.js) in a simulated page: what it shows, when it can be skipped, how it ends.  node tools/scenes_test.js
// (jsdom has no animation: the motion itself is proved in a real browser by tools/scenes_proof.js)
const fs = require('fs'), path = require('path'), assert = require('assert');
const { JSDOM } = require('jsdom');

const code = fs.readFileSync(path.join(__dirname, '..', 'mod/ui/modModules/slScenes/slScenes.js'), 'utf8');
const dom = new JSDOM('<!doctype html><html><head></head><body></body></html>', { runScripts: 'outside-only' });
const win = dom.window;
win.__slScenesTest = true;
win.eval(code);

let now = 0, timers = [];
const clock = { now: () => now, set: (f, ms) => { const t = { at: now + ms, f }; timers.push(t); return t; }, clear: (t) => { timers = timers.filter((x) => x !== t); } };
const advance = (ms) => { now += ms; const due = timers.filter((t) => t.at <= now); timers = timers.filter((t) => t.at > now); due.forEach((t) => t.f()); };
const sent = [];
const S = win.__slScenesCreate(win.document, clock, (c) => sent.push(c));
const r = S.root;
const night = { kind: 'night', title: 'Night', subtitle: 'Day 4: the street is awake', skipHint: 'Press any key to skip', hold: 3.4, fadeIn: 0.5, fadeOut: 0.6, reduce: false };

assert.ok(!r.classList.contains('sls-on') && S.active() === null, 'nothing on the screen at the start');
S.handle('slScene', night);
assert.ok(r.classList.contains('sls-on') && r.classList.contains('sls-night') && r.classList.contains('sls-play') && !r.classList.contains('sls-reduce'), 'the night scene is on');
assert.strictEqual(r.querySelector('.sls-title').textContent, 'Night');
assert.strictEqual(r.querySelector('.sls-sub').textContent, 'Day 4: the street is awake');
assert.strictEqual(r.querySelector('.sls-hint').textContent, 'Press any key to skip');
assert.ok(r.querySelectorAll('.sls-w').length > 40, 'the city has its lit windows: ' + r.querySelectorAll('.sls-w').length);
assert.strictEqual(r.style.getPropertyValue('--sls-in'), '0.5s');
assert.strictEqual(S.active(), 'night');

// skipping: too early does nothing, later it asks the game
advance(100);
assert.strictEqual(S.skip(), false, 'too early to skip');
win.document.dispatchEvent(new win.Event('keydown'));
assert.deepStrictEqual(sent, [], 'a key in the first moments does not skip');
advance(500);
win.document.dispatchEvent(new win.Event('keydown'));
assert.deepStrictEqual(sent, ['sl_scenes.skip()'], 'a key after 0.4 s asks the game to skip');
win.document.dispatchEvent(new win.Event('mousedown'));
assert.strictEqual(sent.length, 2, 'a click asks as well');

// the end: it leaves, then clears
S.handle('slScene', { kind: 'end' });
assert.ok(r.classList.contains('sls-leaving') && !r.classList.contains('sls-shown') && S.active() === null, 'it fades out');
advance(800);
assert.strictEqual(r.className, 'sls-root', 'and is gone');
S.handle('slScene', { kind: 'end' });                        // (an end with nothing on the screen does nothing)

// the day scene, and the reduced-motion one: a still card
S.handle('slScene', Object.assign({}, night, { kind: 'day', title: 'Morning', subtitle: 'Day 5 begins', reduce: true, hold: 1.2 }));
assert.ok(r.classList.contains('sls-day') && r.classList.contains('sls-reduce') && r.querySelector('.sls-title').textContent === 'Morning', 'the day scene, reduced');
const css = win.document.querySelector('style').textContent;
assert.ok(/\.sls-reduce \.sls-sky[^}]*display:none/.test(css) && /prefers-reduced-motion/.test(css), 'reduce motion hides the sky and the city, and the system setting is honoured');
const frames = css.match(/@keyframes [^{]+\{(?:[^{}]*\{[^{}]*\})*[^{}]*\}/g) || [];
assert.ok(frames.length >= 5 && frames.every((f) => !/(letter-spacing|width|height|top|left|right|bottom|margin|padding|font)/.test(f.replace(/@keyframes [^{]+/, ''))), 'only opacity and transform are animated (' + frames.length + ' keyframes)');
console.log('scenes test passed');
