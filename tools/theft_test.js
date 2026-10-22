// Runs the car theft screens (ui/modModules/slTheft/slTheft.js) in a simulated page with the specs of tools/theft_fixture.js: the rules (pure), each stage played with the mouse, the answers sent once,
// Escape, the time running out.   node tools/theft_test.js     (the look is checked in a real browser by tools/phone_shots-style renders, not here)
const fs = require('fs'), path = require('path'), assert = require('assert');
const { JSDOM } = require('jsdom');

const code = fs.readFileSync(path.join(__dirname, '..', 'mod/ui/modModules/slTheft/slTheft.js'), 'utf8');
const fx = require('./theft_fixture.js');
const dom = new JSDOM('<!doctype html><html><head></head><body></body></html>', { runScripts: 'outside-only' });
const win = dom.window;
win.__slTheftTest = true;
win.eval(code);
const L = win.__slTheftLogic;

let now = 0, timers = [];
const clock = { now: () => now, set: (f, ms) => { const t = { at: now + ms, f }; timers.push(t); return t; }, clear: (t) => { timers = timers.filter((x) => x !== t); } };
const advance = (ms) => { for (let i = 0; i < ms / 250; i++) { now += 250; const due = timers.filter((t) => t.at <= now); timers = timers.filter((t) => t.at > now); due.forEach((t) => t.f()); } };
const sent = [];
const S = win.__slTheftCreate(win.document, clock, (c) => sent.push(c));
const doc = win.document;
const fire = (target, type, x, y) => target.dispatchEvent(new win.MouseEvent(type, { bubbles: true, clientX: x, clientY: y }));
const drag = (target, from, to) => { fire(target, 'mousedown', from.x, from.y); fire(doc.body, 'mousemove', to.x, to.y); fire(doc.body, 'mouseup', to.x, to.y); };
const q = (s) => S.root.querySelector(s);

// ---- the rules
assert.deepStrictEqual(L.makePins(4, 7).map((p) => p.centre), L.makePins(4, 7).map((p) => p.centre), 'the same car has the same pins');
assert.ok(L.makePins(6, 1)[0].half < L.makePins(4, 1)[0].half, 'more pins, narrower sweet spots');
const pin = { centre: 0.6, half: 0.06 };
assert.ok(L.releasePin(pin, 0.62) && L.releasePin(pin, 0.54) && !L.releasePin(pin, 0.7) && !L.releasePin(pin, 0.4), 'a release inside the band sets the pin, outside drops it');
const straight = { id: 1, cut: false, points: [{ x: 0, y: 100 }, { x: 100, y: 100 }, { x: 200, y: 100 }] };
const other = { id: 2, cut: false, points: [{ x: 0, y: 300 }, { x: 200, y: 300 }] };
assert.deepStrictEqual(L.wiresCrossed([{ x: 100, y: 50 }, { x: 100, y: 150 }], [straight, other]).map((w) => w.id), [1], 'a drag across one wire cuts only that wire');
assert.deepStrictEqual(L.wiresCrossed([{ x: 100, y: 50 }, { x: 100, y: 350 }], [straight, other]).map((w) => w.id), [1, 2], 'across two cuts both');
assert.deepStrictEqual(L.wiresCrossed([{ x: 100, y: 120 }, { x: 100, y: 180 }], [straight, other]), [], 'a drag that misses cuts nothing');
straight.cut = true;
assert.deepStrictEqual(L.wiresCrossed([{ x: 100, y: 50 }, { x: 100, y: 150 }], [straight]), [], 'a cut wire is not cut twice');
const wires = L.makeWires(5, 3, 1234);
assert.strictEqual(wires.length, 5, 'five wires');
assert.strictEqual(wires.filter((w) => w.marked).length, 3, 'three are marked to cut');
assert.deepStrictEqual(L.makeWires(5, 3, 1234).map((w) => w.marked), wires.map((w) => w.marked), 'the same car marks the same wires');
const bars = L.makePattern(5), tg = L.targetsOf(bars);
assert.ok(tg.length === 3 && tg.every((v) => v >= 0 && v <= 100), 'three slider targets from the pattern');
assert.ok(L.sliderMatch(tg.map((v) => v + 5), tg) && !L.sliderMatch(tg.map((v) => v + 9), tg), 'a match is within 7 points');
assert.ok(L.closeness(50, 50) === 'good' && L.closeness(50, 60) === 'near' && L.closeness(50, 90) === 'far', 'the slider colour says how close');
const ch = L.makeChannel(4, 3);
assert.ok(ch.points.length === 5 && L.distToPolyline(ch.points[2], ch.points) < 0.01 && L.distToPolyline({ x: ch.points[2].x, y: ch.points[2].y + 200 }, ch.points) > ch.half, 'the channel: on the line is inside, far off is a wall hit');

// ---- the screen: nothing until a stage comes
assert.ok(!S.root.classList.contains('slt-on') && !S.active(), 'nothing on the screen at the start');

// ---- the lock: pins
const H = 440, bottom = H - 70, top = 60, track = bottom - top;
const yFor = (level) => (bottom - 4) - level * (track - 4);
S.handle('slTheftGame', fx.lock);
assert.ok(S.root.classList.contains('slt-on') && S.active() && q('.slt-title').textContent === 'Lift the pins' && q('.slt-sub').textContent.includes('Ibishu Covet DX') && q('.slt-sub').textContent.includes('Stage 1 of 2'), 'the lock screen is up');
const pins = S.state().pins;
assert.strictEqual(pins.length, 4, 'four pins');
const handles = [...S.root.querySelectorAll('[data-pin]')];
drag(handles[0], { x: 0, y: bottom }, { x: 0, y: yFor(pins[0].centre > 0.5 ? 0.1 : 0.95) });
assert.ok(S.state().noise > 0.11 && S.state().noise < 0.13 && sent.length === 0, 'a pin released at the wrong height is dropped with noise 0.12, nothing is answered yet');
pins.forEach((p, i) => drag(handles[i], { x: 0, y: bottom }, { x: 0, y: yFor(p.centre) }));
assert.strictEqual(sent.length, 1, 'all pins set: one answer');
assert.ok(/^sl_theft\.gameResult\(1234,"lock",true,0\.12\)$/.test(sent[0]), 'the result: ok with the noise made: ' + sent[0]);
advance(1000);
assert.ok(!S.root.classList.contains('slt-on'), 'the screen closes after the answer; the game sends the next stage');

// too many drops fail the stage
sent.length = 0;
S.handle('slTheftGame', fx.lock);
const h2 = [...S.root.querySelectorAll('[data-pin]')], p2 = S.state().pins;
for (let i = 0; i < 7; i++) drag(h2[0], { x: 0, y: bottom }, { x: 0, y: yFor(p2[0].centre > 0.5 ? 0.1 : 0.95) });
assert.strictEqual(sent.length, 1, 'seven drops on four pins: failed, one answer');
assert.ok(/gameResult\(1234,"lock",false,0\.84\)/.test(sent[0]) || /gameResult\(1234,"lock",false,/.test(sent[0]), 'a failure is reported: ' + sent[0]);
advance(1000);

// ---- Escape, the Give up button and the time running out
sent.length = 0;
S.handle('slTheftGame', fx.lock);
doc.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
assert.deepStrictEqual(sent, ['sl_theft.cancel()'], 'Escape gives up: sl_theft.cancel()');
assert.ok(!S.root.classList.contains('slt-on'), 'and the screen closes');
sent.length = 0;
S.handle('slTheftGame', fx.lock);
q('.slt-giveup').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
assert.deepStrictEqual(sent, ['sl_theft.cancel()'], 'the Give up button too');
sent.length = 0;
S.handle('slTheftGame', fx.lock);
advance(40000);
assert.deepStrictEqual(sent, ['sl_theft.cancel()'], 'the time running out cancels once');
assert.ok(!S.root.classList.contains('slt-on'), 'and closes');

// ---- the slim jim
sent.length = 0;
S.handle('slTheftGame', Object.assign({}, fx.lock, { tool: 'slimjim', stages: ['lock'] }));
assert.ok(q('.slt-title').textContent === 'Slim jim' && q('[data-hook]'), 'the slim jim screen');
const channel = S.state().ch;
fire(q('[data-hook]'), 'mousedown', channel.points[0].x, channel.points[0].y);
channel.points.slice(1).forEach((p) => fire(doc.body, 'mousemove', p.x, p.y));
assert.ok(sent.length === 1 && /gameResult\(1234,"lock",true,0\.00\)/.test(sent[0]), 'sliding the hook through every ring in order opens it: ' + sent[0]);
advance(1000);
sent.length = 0;
S.handle('slTheftGame', Object.assign({}, fx.lock, { tool: 'slimjim', stages: ['lock'] }));
fire(q('[data-hook]'), 'mousedown', S.state().ch.points[0].x, S.state().ch.points[0].y);
fire(doc.body, 'mousemove', 400, 5);
assert.ok(S.state().noise > 0.11 && sent.length === 0 && S.state().next === 1, 'touching the wall makes noise and starts over');
S.cancel(); sent.length = 0;

// ---- the bypass box
S.handle('slTheftGame', fx.box);
assert.ok(q('.slt-title').textContent === 'Fit the bypass box' && q('[data-box]'), 'the box screen');
drag(q('[data-box]'), { x: 100, y: 330 }, { x: 300, y: 100 });
assert.strictEqual(sent.length, 0, 'dropped away from the plug: nothing');
drag(q('[data-box]'), { x: 300, y: 100 }, { x: S.state().box.plug.x, y: S.state().box.plug.y });
assert.ok(sent.length === 1 && /gameResult\(1235,"box",true,0\.12\)/.test(sent[0]), 'on the plug: ok (the noise so far carries over): ' + sent[0]);
advance(1000);

// ---- the wires: cut, join, crank
sent.length = 0;
S.handle('slTheftGame', fx.wires);
const ws = S.state().wires, layer = q('[data-cutlayer]');
assert.ok(q('.slt-title').textContent === 'Hot-wire' && ws.filter((w) => w.marked).length === 3, 'the wires screen with three wires to cut');
const noiseBefore = S.state().noise;
const unmarked = ws.find((w) => !w.marked);
drag(layer, { x: 400, y: unmarked.points[20].y - 6 }, { x: 400, y: unmarked.points[20].y + 6 });
assert.ok(unmarked.cut && Math.abs(S.state().noise - noiseBefore - 0.2) < 1e-9, 'a wrong wire cut makes noise 0.2');
ws.filter((w) => w.marked).forEach((w) => drag(layer, { x: 400, y: w.points[20].y - 6 }, { x: 400, y: w.points[20].y + 6 }));
assert.ok(ws.filter((w) => w.marked).every((w) => w.cut) && S.state().phase === 'join', 'all marked wires cut: the join step');
drag(q('[data-battery]'), { x: 120, y: 380 }, { x: 300, y: 300 });
assert.strictEqual(S.state().phase, 'join', 'a lead let go away from the ignition springs back');
drag(q('[data-battery]'), { x: 120, y: 380 }, { x: 680, y: 380 });
assert.strictEqual(S.state().phase, 'crank', 'battery joined to the ignition: the crank step');
const starter = q('[data-starter]');
fire(starter, 'mousedown', 400, 230);
advance(500);
fire(doc.body, 'mouseup', 400, 230);
assert.strictEqual(sent.length, 0, 'let go early: not cranked yet');
fire(starter, 'mousedown', 400, 230);
advance(1500);
assert.ok(sent.length === 1 && /gameResult\(1235,"wires",true,0\.\d\d\)/.test(sent[0]), 'held long enough: the car starts, one answer: ' + sent[0]);
advance(1000);

// ---- the fob
sent.length = 0;
S.handle('slTheftGame', fx.fob);
assert.ok(q('.slt-title').textContent === 'Capture the fob' && q('[data-capture]'), 'the fob screen');
fire(q('[data-capture]'), 'mousedown', 400, 270);
assert.ok(!S.state().captured, 'pressing Capture while no pattern shows captures nothing');
advance(1750);
assert.ok(S.state().showing, 'the pattern shows');
fire(q('[data-capture]'), 'mousedown', 400, 270);
assert.ok(S.state().captured && q('[data-slider="0"]') && q('[data-confirm]'), 'captured while it showed: the three sliders and Confirm');
const wrong = S.state().targets.map((t) => (t > 50 ? 5 : 95));
S.state().values = wrong;
fire(q('[data-confirm]'), 'mousedown', 400, 360);
assert.ok(sent.length === 0 && S.state().noise > 0, 'a mismatch makes noise and stays');
S.state().values = S.state().targets.slice();
fire(q('[data-confirm]'), 'mousedown', 400, 360);
assert.ok(sent.length === 1 && /gameResult\(1236,"fob",true,/.test(sent[0]), 'matched: ok: ' + sent[0]);
advance(1000);
// the pattern shows only `windows` times: missing them all fails
sent.length = 0;
S.handle('slTheftGame', fx.fob);
advance(20000);
assert.ok(sent.length === 1 && /gameResult\(1236,"fob",false,0\.50\)/.test(sent[0]), 'every window missed: failed with noise 0.5: ' + sent[0]);
advance(1000);
// the cloner skips the match
sent.length = 0;
S.handle('slTheftGame', Object.assign({}, fx.fob, { tool: 'cloner' }));
advance(1750);
fire(q('[data-capture]'), 'mousedown', 400, 270);
assert.ok(sent.length === 1 && /gameResult\(1236,"fob",true,0\.00\)/.test(sent[0]), 'with the cloner the capture is the whole stage: ' + sent[0]);
advance(1000);

// ---- a new stage while one is open replaces it; unknown or empty data is ignored
S.handle('slTheftGame', fx.lock);
S.handle('slTheftGame', fx.fob);
assert.strictEqual(q('.slt-title').textContent, 'Capture the fob', 'the newest stage is shown');
S.handle('slTheftGame', null); S.handle('slTheftGame', {});
assert.ok(S.active(), 'odd data changes nothing');
S.handle('slTheftEnd', {});
assert.ok(!S.active(), 'the game can close it');
// the HUD mark: shown while the police follow the car, hidden when the tracker is out
S.handle('slTheftTracked', { on: true, name: 'Covet' });
assert.strictEqual(S.badge.style.display, 'block');
assert.strictEqual(S.badge.textContent, 'TRACKED');
S.handle('slTheftTracked', { on: false });
assert.strictEqual(S.badge.style.display, 'none');
console.log('theft test passed');
