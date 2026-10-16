// Street Legal Racing - the laptop.
// A global UI module (like the phone, the game imports /ui/modModules/<name>/<name>.js once): a full-screen landscape
// layer opened at a map's computer ("Use the laptop", sl/computer.lua). The tiles come from the Lua side, from the
// computer's own function list (sl/core/laptop.lua); the cars, bank and street cred pages show the phone's data
// (slPhoneData), the parts page the Wrench Works shelf. Tiles that cannot be used are greyed with the reason underneath.
// The look is the phone's (colours and shapes copied, nothing edited into slPhone.js).
//
// createLaptop() is plain DOM, so tools/laptoptest.js can run it outside the game.

(function () {
  'use strict';

  var CSS = [
    '.sll-root{position:fixed;left:0;top:0;right:0;bottom:0;pointer-events:none;z-index:60;font-family:"Roboto","Noto Sans","Segoe UI",Arial,sans-serif;color:#e6e1e5;-webkit-user-select:none;user-select:none}',
    '.sll-root *{box-sizing:border-box}',
    '.sll-screen{position:absolute;left:5vw;right:5vw;top:5vh;bottom:5vh;border-radius:24px;background:#141218;box-shadow:0 0 0 2px #2a2a2e,0 30px 80px rgba(0,0,0,.65);',
    '  display:flex;flex-direction:column;padding:22px 28px;overflow:hidden;pointer-events:auto;transition:opacity .2s}',
    '.sll-screen.sll-gone{opacity:0;pointer-events:none;visibility:hidden}',
    '.sll-head{display:flex;align-items:center;gap:18px;flex:none}',
    '.sll-head h1{font-size:26px;font-weight:400;margin:0}',
    '.sll-head .sll-sp{flex:1}',
    '.sll-chip{padding:6px 14px;border-radius:16px;background:rgba(255,255,255,.1);font-size:13px;color:#cac4d0}',
    '.sll-money{font-size:20px}',
    '.sll-btn{display:inline-flex;align-items:center;justify-content:center;min-height:38px;padding:0 18px;border-radius:19px;background:#a8c7fa;color:#062e6f;font-size:14px;font-weight:500;cursor:pointer}',
    '.sll-btn.sll-tonal{background:#2b3a52;color:#d3e3fd}',
    '.sll-btn.sll-text{background:transparent;color:#a8c7fa}',
    '.sll-btn.sll-off{opacity:.4}',
    '.sll-body{flex:1;overflow-y:auto;padding:14px 4px 4px 0}',
    '.sll-band{font-size:12px;letter-spacing:.12em;text-transform:uppercase;color:#cac4d0;margin:16px 0 10px 0}',
    '.sll-carrow{display:flex;align-items:center;gap:12px}',
    '.sll-car{flex:1;background:#211f26;border-radius:18px;padding:14px 20px}',
    '.sll-car b{font-size:18px;font-weight:500}',
    '.sll-car span{display:block;color:#cac4d0;font-size:13px;margin-top:3px}',
    '.sll-tiles{display:flex;flex-wrap:wrap;gap:14px;margin-top:12px}',
    '.sll-tile{width:170px;min-height:104px;border-radius:18px;background:#211f26;padding:16px;display:flex;flex-direction:column;justify-content:flex-end;font-size:15px;cursor:pointer;border:2px solid transparent}',
    '.sll-tile.sll-off{opacity:.45}',
    '.sll-tile:focus,.sll-btn:focus{outline:none;border-color:#a8c7fa}',
    '.sll-note{flex:none;min-height:24px;margin-top:10px;font-size:14px;color:#f2b8b5}',
    '.sll-card{background:#211f26;border-radius:18px;padding:14px 20px;margin:0 0 12px 0}',
    '.sll-card h4{margin:0 0 6px 0;font-size:16px;font-weight:500}',
    '.sll-card p{margin:0;color:#cac4d0;font-size:13px}',
    '.sll-kv{display:flex;justify-content:space-between;padding:6px 0;border-bottom:1px solid rgba(255,255,255,.07);font-size:14px}',
    '.sll-kv span{color:#cac4d0}',
    '.sll-acts{display:flex;gap:10px;margin-top:10px;flex-wrap:wrap}',
    '.sll-empty{color:#cac4d0;padding:18px 4px;font-size:14px}',
    '.sll-plus{color:#c3e7c6}.sll-minus{color:#f2b8b5}',
    '.sll-meter{height:6px;border-radius:3px;background:rgba(255,255,255,.12);margin-top:10px}.sll-meter i{display:block;height:100%;border-radius:3px;background:#a8c7fa}',
  ].join('');

  function esc(t) {
    return String(t == null ? '' : t).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; });
  }
  function money(v) { v = Math.round(v || 0); return (v < 0 ? '-$' : '$') + String(Math.abs(v)).replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
  function arr(x) { return Array.isArray(x) ? x : []; }
  function obj(x) { return x && typeof x === 'object' && !Array.isArray(x) ? x : {}; }

  var TITLES = { cars: 'My cars', parts: 'My parts', bank: 'Bank / insurance', cred: 'Street cred', dealers: 'Dealers' };

  function createLaptop(doc, lua) {
    var root = doc.createElement('div');
    root.className = 'sll-root';
    var style = doc.createElement('style');
    style.textContent = CSS;
    root.appendChild(style);
    var layer = doc.createElement('div');
    root.appendChild(layer);
    doc.body.appendChild(root);

    var st = { open: false, view: null, data: { active: false }, parts: [], page: 'home', car: 0, note: '', padAt: 0, dealers: null, offers: null };

    // ---------------------------------------------------------------- pages
    function head(title) {
      var d = st.data;
      return '<div class="sll-head">' + (st.page !== 'home' ? '<div class="sll-btn sll-tonal" data-a="back">&#9664; Back</div>' : '') +
        '<h1>' + esc(title) + '</h1><div class="sll-sp"></div>' +
        (d.active ? '<div class="sll-chip">' + esc(d.title || '') + ' &middot; ' + (d.rep || 0) + ' rep</div><div class="sll-chip">Day ' + (d.day || 1) + '</div><div class="sll-money">' + money(d.money) + '</div>' : '') +
        '<div class="sll-btn sll-text" data-a="close">Close</div></div>';
    }

    function tileHtml(t) {
      return '<div class="sll-tile' + (t.enabled ? '' : ' sll-off') + '" data-a="tile" data-v="' + esc(t.id) + '">' + esc(t.label) + '</div>';
    }

    // the tiles for the chosen car (whether it stands at this garage differs per car); without cars, the general ones
    function groupsFor(car) {
      var v = st.view || { groups: [] };
      return car && v.byCar && v.byCar[car.id] ? v.byCar[car.id] : v.groups;
    }
    function homePage() {
      var v = st.view || { groups: [] }, out = '';
      var fleet = arr(st.data.fleet);
      st.car = Math.max(0, Math.min(st.car, fleet.length - 1));
      var groups = groupsFor(fleet[st.car]);
      groups.forEach(function (g) {
        out += '<div class="sll-band">' + esc(g.title) + '</div>';
        if (g.id === 'car') {
          var c = fleet[st.car];
          out += '<div class="sll-carrow"><div class="sll-btn sll-tonal" data-a="car" data-v="-1">&#9664;</div>' +
            '<div class="sll-car">' + (c ? '<b>' + esc(c.name) + '</b><span>' + esc(c.where) + ' &middot; condition ' + Math.round((c.condition || 0) * 100) + '% &middot; value ' + money(c.value) + '</span>'
              : '<b>No car yet</b><span>The junkyard and the dealers sell them.</span>') + '</div>' +
            '<div class="sll-btn sll-tonal" data-a="car" data-v="1">&#9654;</div></div>';
        }
        out += '<div class="sll-tiles">' + g.tiles.map(tileHtml).join('') + '</div>';
      });
      if (!groups.length) out += '<div class="sll-empty">This computer has nothing for you.</div>';
      return head(v.name || 'Laptop') + '<div class="sll-body">' + out + '</div><div class="sll-note">' + esc(st.note) + '</div>';
    }

    function carsPage() {
      var cards = arr(st.data.fleet).map(function (c) {
        var acts = [];
        if (c.impounded) acts.push('<div class="sll-btn" data-a="release" data-v="' + c.id + '">Get it out of the impound &middot; ' + money(c.impounded) + '</div>');
        else if (!c.active) acts.push('<div class="sll-btn" data-a="usecar" data-v="' + c.id + '">Drive this one</div>');
        if (c.out && c.towFee && c.where === 'Out on the street') acts.push('<div class="sll-btn sll-tonal" data-a="tow" data-v="' + c.id + '">Tow it home &middot; ' + money(c.towFee) + '</div>');
        var faults = arr(c.faults);
        return '<div class="sll-card"><h4>' + esc(c.name) + (c.active ? ' &#9733;' : '') + '</h4><p>' + esc(c.where) + ' &middot; condition ' + Math.round((c.condition || 0) * 100) + '% &middot; value ' + money(c.value) +
          (faults.length ? '<br>Needs: ' + esc(faults.join(', ')) : '') + '</p>' + (acts.length ? '<div class="sll-acts">' + acts.join('') + '</div>' : '') + '</div>';
      });
      return head(TITLES.cars) + '<div class="sll-body">' + (cards.join('') || '<div class="sll-empty">You have no car.</div>') + '</div><div class="sll-note">' + esc(st.note) + '</div>';
    }

    // the stock dealers: the same cars as walking onto their lots; a bought car is delivered to the garage a few hours later
    function dealersPage() {
      var d = st.dealers || { dealers: [], coming: [] };
      var rows = arr(d.dealers).map(function (x) {
        return '<div class="sll-card" data-a="dealer" data-v="' + esc(x.id) + '"><h4>' + esc(x.name) + '</h4><p>' + (x.metres >= 1000 ? (x.metres / 1000).toFixed(1) + ' km' : x.metres + ' m') +
          ' away &middot; ' + x.count + ' car' + (x.count === 1 ? '' : 's') + ' today</p></div>';
      }).join('');
      var coming = arr(d.coming).map(function (c) {
        return '<div class="sll-kv"><span>' + esc(c.name) + '</span><b>' + (c.hours > 0 ? 'in about ' + c.hours + ' h' : 'arriving') + '</b></div>';
      }).join('');
      return head(TITLES.dealers) + '<div class="sll-body">' + (coming ? '<div class="sll-card"><h4>On the way to your garage</h4>' + coming + '</div>' : '') +
        (rows || '<div class="sll-empty">No dealers on this map.</div>') + '</div><div class="sll-note">' + esc(st.note) + '</div>';
    }

    function offersPage() {
      var o = st.offers || { name: 'Dealer', offers: [] };
      var cards = arr(o.offers).map(function (c) {
        var faults = arr(c.faults);
        return '<div class="sll-card"><h4>' + esc(c.name) + (c.title ? ' &middot; ' + esc(c.title) : '') + '</h4><p>' + (c.mileage != null ? Number(c.mileage).toLocaleString() + ' km' : '') +
          ' &middot; condition ' + Math.round((c.condition || 0) * 100) + '%' + (faults.length ? '<br>Needs: ' + esc(faults.join(', ')) : '') + '</p>' +
          '<div class="sll-acts"><div class="sll-btn' + ((o.money || 0) < c.price ? ' sll-off' : '') + '" data-a="buy" data-v="' + esc(o.dealer) + '|' + esc(c.id) + '">Buy &middot; ' + money(c.price) + '</div></div></div>';
      }).join('');
      return head(o.name) + '<div class="sll-body">' + (cards || '<div class="sll-empty">Nothing left on the lot today.</div>') + '</div><div class="sll-note">' + esc(st.note) + '</div>';
    }

    function partsPage() {
      var by = {}, order = [];
      st.parts.forEach(function (p) { if (!by[p.car]) { by[p.car] = []; order.push(p.car); } by[p.car].push(p); });
      var cards = order.map(function (car) {
        return '<div class="sll-card"><h4>' + esc(car) + '</h4>' + by[car].map(function (p) {
          return '<div class="sll-kv"><span>' + esc(p.name) + (p.count > 1 ? ' &times;' + p.count : '') + '</span><b>' + money(p.value) + '</b></div>';
        }).join('') + '</div>';
      });
      return head(TITLES.parts) + '<div class="sll-body">' + (cards.join('') || '<div class="sll-empty">The shelf in your garage is empty. Parts you take off a car, and parts delivered to you, wait there.</div>') + '</div><div class="sll-note"></div>';
    }

    function bankPage() {
      var d = st.data, bk = d.bank, cards = '';
      if (bk) {
        if (bk.loan) {
          cards += '<div class="sll-card"><h4>Loan: ' + money(bk.loan.owed) + ' owed</h4><p>Next payment ' + money(bk.loan.due) + ' in ' + bk.loan.dueIn + ' day' + (bk.loan.dueIn === 1 ? '' : 's') + '</p>' +
            '<div class="sll-acts"><div class="sll-btn" data-a="repay" data-v="' + Math.min(bk.loan.owed, d.money || 0) + '">Pay ' + money(Math.min(bk.loan.owed, d.money || 0)) + '</div></div></div>';
        } else {
          var half = Math.floor(bk.limit / 200) * 100;
          cards += '<div class="sll-card"><h4>Borrow</h4><p>Up to ' + money(bk.limit) + ' &middot; ' + Math.round(bk.rate * 100) + '% a day &middot; a quarter due each week</p>' +
            '<div class="sll-acts"><div class="sll-btn sll-tonal" data-a="borrow" data-v="' + half + '">' + money(half) + '</div><div class="sll-btn sll-tonal" data-a="borrow" data-v="' + bk.limit + '">' + money(bk.limit) + '</div></div></div>';
        }
        cards += bk.policy ? '<div class="sll-card"><h4>Insured</h4><p>' + (bk.policy.startsIn ? 'Cover starts tomorrow' : 'Covering half of repairs and impound bills over ' + money(bk.deductible)) + '</p>' +
            '<div class="sll-acts"><div class="sll-btn sll-text" data-a="insure" data-v="false">Cancel</div></div></div>'
          : '<div class="sll-card"><h4>Insurance</h4><p>' + money(bk.premium) + ' a week: half of repairs and impound bills over ' + money(bk.deductible) + ', from the next day</p>' +
            '<div class="sll-acts"><div class="sll-btn sll-tonal" data-a="insure" data-v="true">Insure</div></div></div>';
      }
      var rows = arr(d.ledger).map(function (e) {
        return '<div class="sll-kv"><span>' + esc(e.label || '') + '</span><b class="' + (e.amount >= 0 ? 'sll-plus' : 'sll-minus') + '">' + (e.amount >= 0 ? '+' : '') + money(e.amount) + '</b></div>';
      }).join('');
      return head(TITLES.bank) + '<div class="sll-body"><div class="sll-card"><h4>Balance</h4><p style="font-size:26px;color:#e6e1e5">' + money(d.money) + '</p></div>' + cards +
        '<div class="sll-card">' + (rows || '<p>No transactions yet.</p>') + '</div></div><div class="sll-note">' + esc(st.note) + '</div>';
    }

    function credPage() {
      var d = st.data, s = obj(d.stats);
      var from = d.titleRep || 0, to = d.nextRep, pct = to ? Math.max(0, Math.min(100, ((d.rep || 0) - from) / (to - from) * 100)) : 100;
      var next = d.nextGarage ? '<div class="sll-kv"><span>Next garage</span><b>' + esc(d.nextGarage.name) + (d.nextGarage.canMove ? ' - ready' : ' - ' + esc(d.nextGarage.why)) + '</b></div>' : '';
      var acts = d.nextGarage && d.nextGarage.canMove ? '<div class="sll-acts"><div class="sll-btn" data-a="move">Move to ' + esc(d.nextGarage.name) + '</div></div>' : '';
      var a = d.achievements, ach = '';
      if (a) {
        ach = '<div class="sll-card"><h4>Achievements ' + (a.earned || 0) + ' / ' + (a.total || 0) + '</h4>' + arr(a.list).map(function (x) {
          return '<div class="sll-kv"' + (x.day != null ? '' : ' style="opacity:.45"') + '><span>' + esc(x.title) + ' &middot; ' + esc(x.desc) + '</span><b>' + (x.day != null ? 'Day ' + x.day : '') + '</b></div>';
        }).join('') + '</div>';
      }
      return head(TITLES.cred) + '<div class="sll-body"><div class="sll-card"><h4>' + esc(d.title) + '</h4><p>' + (d.rep || 0) + ' reputation' + (to ? ' &middot; next title at ' + to : '') + '</p>' +
        '<div class="sll-meter"><i style="width:' + pct.toFixed(1) + '%"></i></div></div>' +
        '<div class="sll-card"><div class="sll-kv"><span>Garage</span><b>' + esc(d.garage || '') + '</b></div>' + next +
        '<div class="sll-kv"><span>Cars</span><b>' + (d.cars || 0) + '</b></div>' +
        '<div class="sll-kv"><span>Races</span><b>' + (s.races || 0) + ' (' + (s.wins || 0) + ' won)</b></div>' +
        '<div class="sll-kv"><span>Pink slips</span><b>' + (s.pinksWon || 0) + ' won, ' + (s.pinksLost || 0) + ' lost</b></div>' + acts + '</div>' + ach + '</div><div class="sll-note">' + esc(st.note) + '</div>';
    }

    // ---------------------------------------------------------------- drawing and gamepad focus
    var focusKey = null;
    function keyOf(el) { return el && el.getAttribute ? (el.getAttribute('data-a') || '') + '|' + (el.getAttribute('data-v') || '') : null; }
    function render() {
      var html = '';
      if (st.open) {
        if (st.page === 'cars') html = carsPage();
        else if (st.page === 'parts') html = partsPage();
        else if (st.page === 'bank') html = bankPage();
        else if (st.page === 'cred') html = credPage();
        else if (st.page === 'dealers') html = dealersPage();
        else if (st.page === 'offers') html = offersPage();
        else html = homePage();
      }
      layer.innerHTML = '<div class="sll-screen' + (st.open ? '' : ' sll-gone') + '">' + html + '</div>';
      navify();
    }
    // the game moves the focus between [bng-nav-item] elements with the d-pad/stick and clicks the focused one on A
    function navify() {
      var items = layer.querySelectorAll('[data-a]');
      var first = null, again = null;
      for (var i = 0; i < items.length; i++) {
        var el = items[i];
        if (!st.open) { el.setAttribute('bng-no-nav', 'true'); continue; }
        el.setAttribute('bng-nav-item', '');
        el.setAttribute('tabindex', '0');
        var a = el.getAttribute('data-a');
        if (!first && a !== 'back' && a !== 'close') first = el;
        if (focusKey && !again && keyOf(el) === focusKey) again = el;
      }
      var body = layer.querySelector('.sll-body');
      if (body) body.setAttribute('bng-nav-scroll', '');
      if (!st.open) return;
      var active = doc.activeElement;
      var inside = active && layer.contains(active) && active.hasAttribute && active.hasAttribute('bng-nav-item');
      var target = again || (!inside ? first : null);
      if (target && target !== active && target.focus) target.focus();
    }
    doc.addEventListener('focusin', function (ev) { if (layer.contains(ev.target)) focusKey = keyOf(ev.target); }, true);

    // ---------------------------------------------------------------- what the buttons do
    function tileById(id) {
      var groups = groupsFor(arr(st.data.fleet)[st.car]);
      for (var i = 0; i < groups.length; i++) for (var j = 0; j < groups[i].tiles.length; j++) if (groups[i].tiles[j].id === id) return groups[i].tiles[j];
      return null;
    }
    function back() {
      if (st.page === 'offers') { st.page = 'dealers'; st.note = ''; focusKey = null; lua('@sl_dealers.list()'); render(); return; }
      if (st.page !== 'home') { st.page = 'home'; st.note = ''; render(); return; }
      close();
    }
    function close() { lua('@sl_computer.close()'); setOpen(false); }
    function setOpen(open) { st.open = open; if (!open) { st.page = 'home'; st.note = ''; focusKey = null; } render(); }
    function act(a, v) {
      switch (a) {
        case 'tile':
          var t = tileById(v);
          if (!t) break;
          if (!t.enabled) { st.note = t.label + ': ' + (t.reason || 'Not available.'); render(); break; }
          if (t.page) {
            st.page = t.page; st.note = ''; focusKey = null;
            if (t.page === 'parts') lua('@sl_computer.parts()');
            if (t.page === 'dealers') lua('@sl_dealers.list()');
            lua('@sl_phone.request()');
            render();
          } else if (t.mode) {
            // the garage tiles: the Wrench Works garage opens on the chosen car (the game closes this screen when it has)
            var car = arr(st.data.fleet)[st.car];
            if (car) lua('@sl_computer.enterGarage(' + JSON.stringify(t.mode) + ',' + Number(car.id) + ')');
          }
          break;
        case 'dealer': st.page = 'offers'; st.offers = { name: 'Dealer', offers: [], dealer: v }; st.note = ''; focusKey = null; lua('@sl_dealers.offers(' + JSON.stringify(v) + ')'); render(); break;
        case 'buy':
          var pair = String(v).split('|');
          lua('@sl_dealers.buy(' + JSON.stringify(pair[0]) + ',' + JSON.stringify(pair[1]) + ')');
          break;
        case 'back': back(); break;
        case 'close': close(); break;
        case 'car': st.car += Number(v) || 0; render(); break;
        case 'usecar': lua('@sl_phone.useCar(' + Number(v) + ')'); break;
        case 'tow': lua('@sl_phone.tow(' + Number(v) + ')'); break;
        case 'release': lua('@sl_phone.release(' + Number(v) + ')'); break;
        case 'borrow': lua('@sl_phone.borrow(' + Number(v) + ')'); break;
        case 'repay': lua('@sl_phone.repay(' + Number(v) + ')'); break;
        case 'insure': lua('@sl_phone.insure(' + (v === 'true' ? 'true' : 'false') + ')'); break;
        case 'move': lua('@sl_phone.moveGarage()'); break;
      }
    }
    root.addEventListener('click', function (ev) {
      var el = ev.target;
      while (el && el !== root && !(el.getAttribute && el.getAttribute('data-a'))) el = el.parentNode;
      if (el && el !== root) act(el.getAttribute('data-a'), el.getAttribute('data-v'));
    });
    // B on the pad (and Escape) goes back a page, then out; tab_l / tab_r change the car on the home screen. Window capture:
    // before the game's own handler, so B does not open the pause menu.
    (doc.defaultView || doc).addEventListener('ui_nav', function (ev) {
      var d = ev.detail || {};
      st.padAt = Date.now();
      if (!st.open || d.value !== 1) return;
      if (d.name === 'back') back();
      else if ((d.name === 'tab_l' || d.name === 'tab_r') && st.page === 'home' && arr(st.data.fleet).length > 1) { st.car += d.name === 'tab_l' ? -1 : 1; render(); }
      else return;
      if (ev.stopImmediatePropagation) ev.stopImmediatePropagation();
      if (ev.preventDefault) ev.preventDefault();
    }, true);
    doc.addEventListener('keydown', function (ev) { if (st.open && ev.key === 'Escape') { back(); ev.preventDefault(); } });

    // ---------------------------------------------------------------- events from the Lua side
    function handle(name, data) {
      switch (name) {
        case 'slLaptopOpen':
          st.view = { name: data.name, groups: arr(data.groups), byCar: obj(data.byCar), lists: !!data.lists };
          st.parts = arr(data.parts); st.page = 'home'; st.note = ''; st.car = 0; focusKey = null;
          setOpen(true);
          break;
        case 'slLaptopClose': if (st.open) setOpen(false); break;
        case 'slLaptopParts': st.parts = arr(data.parts); if (st.open) render(); break;
        case 'slLaptopDealers': st.dealers = data; if (st.open) render(); break;
        case 'slLaptopOffers': st.offers = data; if (st.open && st.page === 'offers') render(); break;
        case 'slPhoneData': st.data = data || { active: false }; if (st.open) render(); break;
        case 'slPhoneToast': if (st.open && data && data.text) { st.note = data.text; render(); } break;
      }
    }

    render();
    return { handle: handle, state: st, act: act, root: root };
  }

  if (typeof window !== 'undefined') window.__slLaptopCreate = createLaptop;

  // in the game: one laptop for the whole UI, fed by the Lua side's events
  if (typeof angular !== 'undefined' && typeof window !== 'undefined' && !window.__slLaptopTest) {
    angular.module('slLaptop', []).run(['$rootScope', function ($rootScope) {
      if (window.__slLaptop) return;
      var laptop = createLaptop(document, function (call) {
        if (!window.bngApi || call.charAt(0) !== '@') return;
        var ext = call.slice(1).split('.')[0];
        window.bngApi.engineLua('if ' + ext + ' then ' + call.slice(1) + ' end');
      });
      window.__slLaptop = laptop;
      ['slLaptopOpen', 'slLaptopClose', 'slLaptopParts', 'slLaptopDealers', 'slLaptopOffers', 'slPhoneData', 'slPhoneToast'].forEach(function (name) {
        $rootScope.$on(name, function (ev, data) { laptop.handle(name, data); });
      });
    }]);
  }
})();
