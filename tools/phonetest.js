// Runs the phone (ui/modModules/slPhone/slPhone.js) in a simulated page and checks what it shows and
// what it asks the game for. Needs jsdom:  npm i jsdom   then   node tools/phonetest.js
// With --html <file> it also writes a page showing the phone in a few states, to look at in a browser.
const fs = require('fs'), path = require('path'), assert = require('assert');
const { JSDOM } = require('jsdom');

const code = fs.readFileSync(path.join(__dirname, '..', 'mod/ui/modModules/slPhone/slPhone.js'), 'utf8');
const dom = new JSDOM('<!doctype html><html><body></body></html>', { runScripts: 'outside-only', pretendToBeVisual: true });
const win = dom.window;
win.__slPhoneTest = true;
win.eval(code);

// a clock the test moves by hand
let now = 0, timers = [];
const clock = {
  now: () => now,
  set: (f, ms) => { const t = { at: now + ms, f }; timers.push(t); return t; },
  clear: (t) => { timers = timers.filter((x) => x !== t); },
};
function advance(ms) {
  now += ms;
  const due = timers.filter((t) => t.at <= now);
  timers = timers.filter((t) => t.at > now);
  due.forEach((t) => t.f());
}

const calls = [];
const phone = win.__slPhoneCreate(win.document, (c) => calls.push(c), clock);
const $ = (sel) => phone.root.querySelector(sel);
const text = () => phone.root.textContent;
const click = (a, v) => {
  const el = [...phone.root.querySelectorAll('[data-a="' + a + '"]')].find((e) => v === undefined || e.getAttribute('data-v') === v);
  assert.ok(el, 'nothing to click: ' + a + ' ' + (v || ''));
  el.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
};

const data = {
  active: true, money: 3500, rep: 120, title: 'Street kid', nextRep: 300, titleRep: 100, day: 2, hour: 21, minute: 5, night: true,
  garage: 'Club Garage 1', nextGarage: { name: 'Club Garage 2', canMove: false, why: 'needs 1500 reputation' }, roc: false,
  contacts: [
    { id: 'benny', name: 'Benny (garage)', phone: '555-0100', system: true },
    { id: 'r01', name: 'Mick "Clutch" Santana', short: 'Mick Santana', phone: '555-1137', tier: 1, class: 'beater', nightOnly: true, wins: 1, losses: 2 },
    { id: 'r02', name: 'Dora Kovacs', short: 'Dora Kovacs', phone: '555-1274', tier: 2, class: 'compact', wins: 0, losses: 0 },
  ],
  threads: { benny: [{ from: 'them', text: 'Welcome to Valo City, kid.', at: 1 }], r01: [{ from: 'me', text: 'Up for a race?', at: 2 }, { from: 'them', text: 'You\'re on <b>$300</b>', at: 3 }] },
  unread: { r01: 1 },
  challenges: [{ id: 'r01:1', racer: 'r01', name: 'Mick "Clutch" Santana', stake: 'money', bet: 300, raceName: 'Night race 4', nightOnly: true }],
  ledger: [{ at: 3, amount: -45, label: 'Cab to Junkyard' }, { at: 2, amount: 300, label: 'Won a race against Mick Santana' }],
  places: [{ id: 'junkyard', name: 'Junkyard', kind: 'junkyard' }],
  cars: 0, stats: { races: 3, wins: 2, pinksWon: 0, pinksLost: 0 },
};

// nothing shows before a career runs
assert.ok(!$('.slp-device'), 'no phone without a career');
phone.handle('slPhoneData', data);
assert.ok($('.slp-device.slp-away'), 'the phone starts in the pocket');
assert.ok($('.slp-pill') && text().includes('$3,500'), 'money shows in the corner');

// K takes it out: home screen with the time, the day and badges
phone.handle('slPhoneToggle');
assert.ok(!$('.slp-device.slp-away'), 'K takes it out');
assert.ok(calls.includes('request()'), 'opening asks for fresh data');
assert.ok(text().includes('21:05') && text().includes('Day 2'), 'clock and day on the home screen');
assert.strictEqual($('.slp-dock .slp-badge').textContent, '1', 'unread messages badge on Messages');

// contacts -> a contact -> call; it rings, then they answer and the stakes are offered
click('open', 'contacts');
assert.ok(text().includes('Mick "Clutch" Santana') && text().includes('Dora Kovacs'), 'contacts listed');
assert.strictEqual(phone.root.querySelector('[data-v="benny"] .slp-av').textContent, 'B', 'initials leave out what is in brackets');
click('contact', 'r01');
assert.ok(text().includes('555-1137') && text().includes('nights'), 'contact card');
click('call', 'r01');
assert.ok(calls.includes('call("r01")') && text().includes('Calling'), 'calling');
phone.handle('slPhoneCall', { id: 'r01', answered: true, greeting: 'Yeah? Who is this?', options: ['race', 'high', 'pink'] });
assert.ok(text().includes('Calling'), 'it rings a moment first');
advance(2000);
assert.ok(text().includes('Who is this') && text().includes('Pink slips'), 'they answer, stakes offered');
click('stake', 'pink');
assert.ok(calls.includes('challenge("r01","pink")'), 'pink slips asked for');
assert.ok(!$('[data-a="stake"]'), 'one question per call');
phone.handle('slPhoneCallReply', { id: 'r01', accept: true, text: 'Pink slips it is.', challenge: { id: 'r01:9', raceName: 'Night race 7' } });
assert.ok(text().includes('Pink slips it is') && text().includes('Night race 7'), 'their answer and the way to the race');
click('gps', 'r01:9');
assert.ok(calls.includes('waypoint("r01:9")'), 'route asked for');
click('hang');
assert.ok(!$('.slp-call'), 'hung up');

// an unanswered call ends by itself
click('call', 'r01');
phone.handle('slPhoneCall', { id: 'r01', answered: false, text: 'No answer.' });
advance(2000);
assert.ok(text().includes('No answer') && text().includes('Call ended'), 'no answer');
click('hang');

// messages: unread thread, opening it marks it read, quick replies
click('home');
click('open', 'messages');
assert.ok($('.slp-rt span.slp-unread'), 'unread thread stands out');
click('thread', 'r01');
assert.ok(calls.includes('markRead("r01")'), 'opening a thread marks it read');
assert.ok(text().includes('<b>$300</b>') && !$('.slp-bub b'), 'message text is shown as text, never as markup');
click('text', 'high');
assert.ok(calls.includes('text("r01","high")'), 'quick reply sent');
click('back');
click('thread', 'benny');
assert.ok(!$('[data-a="text"]'), 'no race offers to Benny');

// a text arriving while the phone is away pops up; clicking it opens the thread
click('away');
phone.handle('slPhoneNotify', { thread: 'r02', name: 'Dora Kovacs', text: 'Tonight?' });
assert.ok(!$('.slp-hu.slp-gone') && text().includes('Tonight?'), 'heads-up notification');
click('openthread', 'r02');
assert.ok(!$('.slp-device.slp-away') && $('.slp-msgs'), 'the notification opens the thread');
advance(7000);
assert.ok($('.slp-hu.slp-gone'), 'notifications go away');

// dialling a number that belongs to a contact calls them
click('home');
click('open', 'phone');
'5551274'.split('').forEach((d) => click('key', d));
assert.ok(text().includes('Dora Kovacs'), 'the dialler recognises the number');
click('dial');
assert.ok(calls.includes('call("r02")'), 'dialled');
click('hang');
click('del');

// races, bank, cab, profile
click('home');
click('open', 'races');
assert.ok(text().includes('Night race 4') && text().includes('$300'), 'arranged races');
click('cancel', 'r01:1');
assert.ok(calls.includes('cancel("r01:1")'), 'calling one off');
click('home');
click('open', 'bank');
assert.ok(text().includes('-$45') && text().includes('+$300'), 'bank statement');
click('home');
click('open', 'cab');
click('taxi', 'junkyard');
assert.ok(calls.includes('taxi("junkyard")'), 'cab ordered');
click('home');
click('open', 'me');
assert.ok(text().includes('Street kid') && text().includes('needs 1500 reputation'), 'street cred page');

// back walks back through the pages, and out of the phone at the end
click('back');
assert.ok($('.slp-clock'), 'back to the home screen');
click('back');
assert.ok($('.slp-device.slp-away'), 'and into the pocket');

// leaving the career puts it away for good
phone.handle('slPhoneData', { active: false });
assert.ok(!$('.slp-device'), 'gone when the career stops');

console.log('phone test passed');

// a page to look at: the phone in several states side by side
const out = process.argv.indexOf('--html');
if (out > 0) {
  const shots = [];
  const views = [['home'], ['contacts'], ['contact', 'r01'], ['call'], ['thread', 'r01'], ['races'], ['me']];
  views.forEach((view) => {
    const d2 = new JSDOM('<!doctype html><html><body></body></html>', { runScripts: 'outside-only' });
    d2.window.__slPhoneTest = true;
    d2.window.eval(code);
    const p = d2.window.__slPhoneCreate(d2.window.document, () => {}, clock);
    p.handle('slPhoneData', data);
    p.handle('slPhoneToggle');
    if (view[0] === 'call') {
      p.act('call', 'r01');
      p.handle('slPhoneCall', { id: 'r01', answered: true, greeting: 'Yeah? Who is this?', options: ['race', 'high', 'pink'] });
      now += 3000; p.act('noop');
      p.state.call.phase = 'talking'; p.state.call.greeting = 'Yeah? Who is this?'; p.state.call.options = ['race', 'high', 'pink'];
      p.act('noop');
    } else if (view[0] === 'contact' || view[0] === 'thread') {
      p.act('open', view[0] === 'contact' ? 'contacts' : 'messages');
      p.act(view[0], view[1]);
    } else if (view[0] !== 'home') {
      p.act('open', view[0]);
    }
    const device = p.root.querySelector('.slp-device');
    device.style.cssText = 'position:relative;right:auto;bottom:auto;transform:none;display:inline-block;margin:16px;vertical-align:top';
    shots.push(device.outerHTML);
    if (!shots.css) shots.css = p.root.querySelector('style').textContent;
  });
  const page = '<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0;background:#3a3a40;width:2700px}' + shots.css +
    '.slp-root{position:static}</style></head><body><div class="slp-root" style="position:static;pointer-events:auto">' + shots.join('') + '</div></body></html>';
  fs.writeFileSync(process.argv[out + 1], page);
  console.log('wrote ' + process.argv[out + 1]);
}
