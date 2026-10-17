// Street Legal Racing - the laptop.
// A global UI module (like the phone, the game imports /ui/modModules/<name>/<name>.js once): a full-screen Windows-style desktop opened at
// a map's computer ("Use the laptop", sl/computer.lua). The tiles come from the Lua side, from the computer's own function list
// (sl/core/laptop.lua) and are desktop icons; each function opens in a window (title bar with icon and minimise / maximise / close,
// a drop shadow, a resize grip), the taskbar has a Start button, a button for every open window and a tray with rank, clock, day and
// money; the Start menu lists the apps and shuts the laptop down. The cars, bank and street cred windows show the phone's data
// (slPhoneData), the parts window the Wrench Works shelf, the dealers window the stock dealers (sl/dealers).
// The wallpaper is the player's own Windows one when tools/wallpaper.ps1 has copied it, else a built-in one. Colours are the phone's.
//
// createLaptop() is plain DOM, so tools/laptoptest.js can run it outside the game.

(function () {
  'use strict';

  var CSS = [
    '.sll-root{position:fixed;left:0;top:0;right:0;bottom:0;pointer-events:none;z-index:60;font-family:"Segoe UI","Roboto","Noto Sans",Arial,sans-serif;color:#e6e1e5;-webkit-user-select:none;user-select:none}',
    '.sll-root *{box-sizing:border-box}',
    '.sll-screen{position:absolute;left:0;top:0;right:0;bottom:0;overflow:hidden;pointer-events:auto;transition:opacity .2s;',
    '  background-color:#0d0b12;background-size:cover;background-position:center}',
    '.sll-screen.sll-gone{opacity:0;pointer-events:none;visibility:hidden}',
    '.sll-wall{position:absolute;left:0;top:0;right:0;bottom:0;',
    '  background:radial-gradient(120% 70% at 20% 0%,#3b2f6b 0%,rgba(59,47,107,0) 60%),radial-gradient(90% 60% at 100% 100%,#7a2e3d 0%,rgba(122,46,61,0) 65%),linear-gradient(#17121f,#0d0b12);',
    '  background-size:cover;background-position:center}',
    /* desktop icons, a column from the top left like Windows */
    '.sll-icons{position:absolute;left:6px;top:6px;bottom:52px;display:flex;flex-direction:column;flex-wrap:wrap;align-content:flex-start;gap:2px}',
    '.sll-icon{width:84px;height:92px;padding:6px 3px;border-radius:3px;display:flex;flex-direction:column;align-items:center;gap:5px;cursor:default;border:1px solid transparent}',
    '.sll-icon svg{width:48px;height:48px;flex:none;filter:drop-shadow(0 2px 3px rgba(0,0,0,.55))}',
    '.sll-icon span{font-size:12px;line-height:14px;color:#fff;text-align:center;text-shadow:0 1px 3px #000,0 0 2px #000;max-height:28px;overflow:hidden}',
    '.sll-icon:hover{background:rgba(255,255,255,.12);border-color:rgba(255,255,255,.22)}',
    '.sll-icon.sll-sel,.sll-icon:focus{background:rgba(120,170,255,.28);border-color:rgba(160,200,255,.7);outline:none}',
    '.sll-icon.sll-off svg{opacity:.5}.sll-icon.sll-off span{opacity:.7}',
    /* the garage widget: a small window of its own */
    '.sll-widget{position:absolute;right:18px;top:18px;width:300px;border-radius:8px;overflow:hidden;background:rgba(27,25,32,.94);box-shadow:0 0 0 1px #3a3a42,0 10px 30px rgba(0,0,0,.55)}',
    '.sll-widget .sll-title{cursor:default}',
    '.sll-widget .sll-wb{padding:10px 12px}',
    '.sll-wb b{font-size:15px;font-weight:500}',
    '.sll-wb span{display:block;color:#cac4d0;font-size:12px;margin-top:3px}',
    '.sll-wrow{display:flex;gap:8px;align-items:center}.sll-wrow .sll-car{flex:1;min-width:0}',
    /* windows */
    '.sll-win{position:absolute;display:flex;flex-direction:column;border-radius:8px 8px 4px 4px;overflow:hidden;background:#141218;',
    '  box-shadow:0 0 0 1px #3a3a42,0 14px 40px rgba(0,0,0,.6)}',
    '.sll-win.sll-top{box-shadow:0 0 0 1px #6b88b8,0 18px 50px rgba(0,0,0,.7)}',
    '.sll-win.sll-max{left:0 !important;top:0 !important;width:100% !important;height:calc(100% - 44px) !important;border-radius:0}',
    '.sll-title{flex:none;display:flex;align-items:center;gap:8px;height:32px;padding:0 0 0 10px;background:#2b3a52;color:#d3e3fd;font-size:13px}',
    '.sll-win.sll-top .sll-title{background:#34507a}',
    '.sll-title svg{width:16px;height:16px;flex:none}',
    '.sll-title b{font-weight:400;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.sll-title .sll-sp{flex:1}',
    '.sll-tb{width:42px;height:32px;display:flex;align-items:center;justify-content:center;cursor:default;font-size:13px;border:1px solid transparent}',
    '.sll-tb:hover,.sll-tb:focus{background:rgba(255,255,255,.16);outline:none;border-color:rgba(255,255,255,.3)}',
    '.sll-tb.sll-xb:hover,.sll-tb.sll-xb:focus{background:#c2412d;border-color:#f2b8b5}',
    '.sll-grip{position:absolute;right:2px;bottom:2px;width:14px;height:14px;opacity:.5;background:linear-gradient(135deg,transparent 0 55%,#cac4d0 55% 62%,transparent 62% 76%,#cac4d0 76% 83%,transparent 83%)}',
    '.sll-body{flex:1;overflow-y:auto;padding:14px 18px 6px 18px}',
    '.sll-note{flex:none;min-height:22px;padding:0 18px 8px 18px;font-size:13px;color:#f2b8b5}',
    /* the taskbar, the tray and the Start menu */
    '.sll-task{position:absolute;left:0;right:0;bottom:0;height:44px;display:flex;align-items:center;gap:4px;padding:0 6px;background:rgba(18,16,23,.97);border-top:1px solid #3a3a42;font-size:12px}',
    '.sll-task .sll-sp{flex:1}',
    '.sll-startbtn{height:36px;padding:0 14px;display:flex;align-items:center;gap:8px;border-radius:4px;cursor:default;font-size:13px;border:1px solid transparent}',
    '.sll-startbtn svg{width:18px;height:18px}',
    '.sll-startbtn:hover,.sll-startbtn.sll-on,.sll-startbtn:focus{background:rgba(255,255,255,.14);outline:none;border-color:rgba(255,255,255,.28)}',
    '.sll-taskwin{height:36px;min-width:150px;max-width:210px;padding:0 12px;display:flex;align-items:center;gap:8px;border-radius:4px;cursor:default;background:rgba(255,255,255,.07);border-bottom:2px solid #5b6b86;border:1px solid transparent;border-bottom:2px solid #5b6b86}',
    '.sll-taskwin svg{width:16px;height:16px;flex:none}',
    '.sll-taskwin span{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.sll-taskwin.sll-on{background:rgba(120,170,255,.2);border-bottom-color:#a8c7fa}',
    '.sll-taskwin:hover,.sll-taskwin:focus{background:rgba(255,255,255,.16);outline:none}',
    '.sll-tray{display:flex;align-items:center;gap:12px;padding:0 10px;color:#e6e1e5}',
    '.sll-tray .sll-clock{text-align:right;line-height:15px;font-size:12px}',
    '.sll-menu{position:absolute;left:6px;bottom:48px;width:320px;max-height:78%;display:flex;flex-direction:column;border-radius:8px;background:rgba(27,25,32,.98);box-shadow:0 0 0 1px #3a3a42,0 18px 50px rgba(0,0,0,.6);overflow:hidden}',
    '.sll-menu .sll-mlist{overflow-y:auto;padding:8px}',
    '.sll-menu .sll-user{padding:12px 16px;background:rgba(255,255,255,.05);font-size:13px;color:#cac4d0}',
    '.sll-menu .sll-band{margin:8px 8px 4px 8px}',
    '.sll-mi{display:flex;align-items:center;gap:12px;padding:7px 10px;border-radius:4px;font-size:13px;cursor:default;border:1px solid transparent}',
    '.sll-mi svg{width:24px;height:24px;flex:none}',
    '.sll-mi:hover,.sll-mi:focus{background:rgba(120,170,255,.2);outline:none;border-color:rgba(160,200,255,.5)}.sll-mi.sll-off{opacity:.5}',
    '.sll-mfoot{display:flex;justify-content:flex-end;padding:8px;background:rgba(255,255,255,.05)}',
    /* a balloon over the tray for the reason a greyed icon gives */
    '.sll-balloon{position:absolute;right:12px;bottom:52px;max-width:360px;padding:10px 14px;border-radius:8px;background:#34364a;color:#f2b8b5;font-size:13px;box-shadow:0 0 0 1px #5b5f7a,0 10px 30px rgba(0,0,0,.5)}',
    /* what the windows hold: the phone's cards and buttons */
    '.sll-btn{display:inline-flex;align-items:center;justify-content:center;min-height:34px;padding:0 16px;border-radius:17px;background:#a8c7fa;color:#062e6f;font-size:13px;font-weight:500;cursor:pointer;border:2px solid transparent}',
    '.sll-btn.sll-tonal{background:#2b3a52;color:#d3e3fd}',
    '.sll-btn.sll-text{background:transparent;color:#a8c7fa}',
    '.sll-btn.sll-off{opacity:.4}',
    '.sll-btn:focus,.sll-listing:focus{outline:none;border-color:#a8c7fa}',
    '.sll-band{font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:#cac4d0}',
    '.sll-car{background:rgba(255,255,255,.06);border-radius:8px;padding:8px 12px}',
    '.sll-card{background:#211f26;border-radius:12px;padding:12px 16px;margin:0 0 10px 0}',
    '.sll-card h4{margin:0 0 6px 0;font-size:15px;font-weight:500}',
    '.sll-card p{margin:0;color:#cac4d0;font-size:13px}',
    '.sll-report{margin:6px 0}.sll-rsec{margin:8px 0;padding:8px 10px;border-radius:10px;background:rgba(0,0,0,.25)}.sll-rsec h5{margin:0 0 4px;font-size:13px;color:#a8c7fa}.sll-rok{color:#7bd88f}.sll-rmid{color:#e6c35c}.sll-rbad{color:#f2b8b5}',
    '.sll-kv{display:flex;justify-content:space-between;gap:12px;padding:5px 0;border-bottom:1px solid rgba(255,255,255,.07);font-size:13px}',
    '.sll-kv span{color:#cac4d0}',
    '.sll-acts{display:flex;gap:10px;margin-top:10px;flex-wrap:wrap}',
    '.sll-empty{color:#cac4d0;padding:16px 4px;font-size:13px}',
    '.sll-plus{color:#c3e7c6}.sll-minus{color:#f2b8b5}',
    '.sll-meter{height:6px;border-radius:3px;background:rgba(255,255,255,.12);margin-top:10px}.sll-meter i{display:block;height:100%;border-radius:3px;background:#a8c7fa}',
    /* a listing as the stock shop shows one */
    '.sll-listing{display:flex;gap:14px;align-items:stretch;cursor:pointer;border:2px solid transparent}',
    '.sll-pic{flex:none;width:200px;aspect-ratio:16/9;border-radius:8px;overflow:hidden;background:#0d0b12;display:flex;align-items:center;justify-content:center;color:#6f6a78;font-size:12px}',
    '.sll-pic img{width:100%;height:100%;object-fit:cover}',
    '.sll-li{flex:1;min-width:0}',
    '.sll-brand{color:#cac4d0;font-size:12px;margin-bottom:4px}',
    '.sll-props{color:#cac4d0;font-size:12px;margin-top:3px}',
    '.sll-lbuy{flex:none;display:flex;flex-direction:column;align-items:flex-end;justify-content:space-between}',
    '.sll-lbuy b{font-size:18px;font-weight:500}',
    '.sll-detail{display:flex;gap:18px;flex-wrap:wrap}',
    '.sll-tabs{flex:none;display:flex;gap:6px;padding:10px 18px 0 18px}',
    '.sll-tab{padding:6px 16px;border-radius:15px;background:#2b2930;color:#cac4d0;font-size:12px;cursor:pointer;border:2px solid transparent}',
    '.sll-tab.sll-tabon{background:#a8c7fa;color:#062e6f;font-weight:500}.sll-tab:focus{outline:none;border-color:#e6e1e5}',
    '.sll-detail .sll-pic{width:min(480px,100%)}',
  ].join('');

  function esc(t) {
    return String(t == null ? '' : t).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; });
  }
  function money(v) { v = Math.round(v || 0); return (v < 0 ? '-$' : '$') + String(Math.abs(v)).replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
  function arr(x) { return Array.isArray(x) ? x : []; }
  function obj(x) { return x && typeof x === 'object' && !Array.isArray(x) ? x : {}; }
  function two(n) { return ('0' + n).slice(-2); }

  // the icons: a coloured rounded square with a white outline glyph, one per laptop function
  var GLYPHS = {
    vehicleInventory: ['#2f6fd0', '<path d="M8 30l3-9c.6-1.7 2-3 4-3h18c2 0 3.400 1.300 4 3l3 9v6h-4v-3H12v3H8z"/><circle cx="15" cy="29" r="2.500"/><circle cx="33" cy="29" r="2.500"/>'],
    partInventory: ['#7a5bd0', '<path d="M24 8l14 7v18l-14 7-14-7V15z"/><path d="M10 15l14 7 14-7M24 22v18"/>'],
    vehicleShop: ['#d0662f', '<path d="M8 18l3-8h26l3 8v3H8z"/><path d="M10 21v17h28V21"/><path d="M20 38V29h8v9"/>'],
    insurances: ['#1f8a70', '<path d="M24 8l16 7H8z"/><path d="M12 19v15M20 19v15M28 19v15M36 19v15M8 39h32"/>'],
    playerAbstract: ['#c2a02f', '<path d="M24 8l5 10 11 1.500-8 7.500 2 11-10-5.500L14 38l2-11-8-7.500L19 18z"/>'],
    partShop: ['#c2412d', '<path d="M7 11h6l4 19h19l4-14H14"/><circle cx="19" cy="37" r="2.500"/><circle cx="33" cy="37" r="2.500"/>'],
    tuning: ['#4a8a2f', '<path d="M10 14h28M10 24h28M10 34h28"/><circle cx="18" cy="14" r="3.500" fill="#4a8a2f"/><circle cx="31" cy="24" r="3.500" fill="#4a8a2f"/><circle cx="22" cy="34" r="3.500" fill="#4a8a2f"/>'],
    painting: ['#b04a8f', '<rect x="9" y="9" width="26" height="10" rx="2"/><path d="M35 14h4v11H22v6"/><rect x="19" y="31" width="6" height="9" rx="1"/>'],
    phaseSwitch: ['#3b4a78', '<path d="M30 8a16 16 0 1 0 10 28A13 13 0 0 1 30 8z"/>'],
    partsMarket: ['#a3322c', '<path d="M8 21h32l-3 17H11z"/><path d="M16 21l6-11M32 21l-6-11"/><path d="M19 28v6M24 28v6M29 28v6"/>'],
    repair: ['#5a6a7a', '<path d="M34 10a8 8 0 0 0-8 10L10 36a3.500 3.500 0 0 0 5 5l16-16a8 8 0 0 0 10-8l-5 5-4-1-1-4z"/>'],
  };
  function icon(id, size) {
    var g = GLYPHS[id] || ['#5a6a7a', '<rect x="12" y="12" width="24" height="24" rx="3"/>'];
    return '<svg viewBox="0 0 48 48"' + (size ? ' width="' + size + '" height="' + size + '"' : '') + '><rect width="48" height="48" rx="10" fill="' + g[0] + '"/>' +
      '<g fill="none" stroke="#fff" stroke-width="2.600" stroke-linecap="round" stroke-linejoin="round">' + g[1] + '</g></svg>';
  }
  var WINDOWS = { cars: ['vehicleInventory', 'My cars'], parts: ['partInventory', 'My parts'], bank: ['insurances', 'Bank / insurance'], cred: ['playerAbstract', 'Street cred'], dealers: ['vehicleShop', 'Car market'], partmarket: ['partsMarket', 'Part market'] };

  function createLaptop(doc, lua) {
    var root = doc.createElement('div');
    root.className = 'sll-root';
    var style = doc.createElement('style');
    style.textContent = CSS;
    root.appendChild(style);
    var layer = doc.createElement('div');
    root.appendChild(layer);
    doc.body.appendChild(root);

    // wins: the open windows, the last one on top; each { id, min, max }. dview: what the dealers window shows (dealers | offers | offer)
    var st = { rep: {}, open: false, view: null, data: { active: false }, parts: [], wins: [], menu: false, sel: null, car: 0, note: '', padAt: 0,
      dealers: null, offers: null, dview: 'dealers', offerId: null, wallpaper: null, tab: { dealers: 'dealers', partmarket: 'revline' } };

    // ---------------------------------------------------------------- what the windows hold
    function dist(m) { m = Number(m) || 0; return m >= 1000 ? (m / 1000).toFixed(1) + ' km' : Math.round(m) + ' m'; }
    function pic(c) {
      return '<div class="sll-pic">' + (c.preview ? '<img src="' + esc(c.preview) + '" alt="" onerror="this.style.display=\'none\'">' : 'no picture') + '</div>';
    }
    // the stock card's one-line facts: mileage, transmission, drivetrain, power, weight
    function facts(c) {
      var sp = obj(c.specs), out = [];
      if (c.mileage != null) out.push(Number(c.mileage).toLocaleString() + ' km');
      if (sp.transmission) out.push(esc(sp.transmission));
      if (sp.drivetrain) out.push(esc(sp.drivetrain));
      if (sp.power) out.push(Math.round(sp.power) + ' PS');
      if (sp.weight) out.push(Math.round(sp.weight).toLocaleString() + ' kg');
      return out.join(' &middot; ');
    }
    function body(inner) { return '<div class="sll-body">' + inner + '</div><div class="sll-note"></div>'; }

    function carsBody() {
      var cards = arr(st.data.fleet).map(function (c) {
        var acts = [];
        if (c.impounded) acts.push('<div class="sll-btn" data-a="release" data-v="' + c.id + '">Get it out of the impound &middot; ' + money(c.impounded) + '</div>');
        else if (!c.active) acts.push('<div class="sll-btn" data-a="usecar" data-v="' + c.id + '">Drive this one</div>');
        if (c.out && c.towFee && c.where === 'Out on the street') acts.push('<div class="sll-btn sll-tonal" data-a="tow" data-v="' + c.id + '">Tow it home &middot; ' + money(c.towFee) + '</div>');
        if (c.out && !c.impounded) acts.push('<div class="sll-btn sll-text" data-a="despawn" data-v="' + c.id + '">Put it away</div>');
        var faults = arr(c.faults);
        return '<div class="sll-card"><h4>' + esc(c.name) + (c.active ? ' &#9733;' : '') + '</h4><p>' + esc(c.where) + ' &middot; condition ' + Math.round((c.condition || 0) * 100) + '% &middot; value ' + money(c.value) +
          (faults.length ? '<br>Needs: ' + esc(faults.join(', ')) : '') + '</p>' + reportBlock('car:' + c.id, c.report) + (acts.length ? '<div class="sll-acts">' + acts.join('') + '</div>' : '') + '</div>';
      });
      return body(cards.join('') || '<div class="sll-empty">You have no car.</div>');
    }

    function dealersBody() {
      var d = st.dealers || { dealers: [], coming: [] };
      var rows = arr(d.dealers).map(function (x) {
        return '<div class="sll-card" data-a="dealer" data-v="' + esc(x.id) + '"><h4>' + esc(x.name) + '</h4><p>' + dist(x.metres) +
          ' away &middot; ' + x.count + ' car' + (x.count === 1 ? '' : 's') + ' today</p></div>';
      }).join('');
      var coming = arr(d.coming).map(function (c) {
        return '<div class="sll-kv"><span>' + esc(c.name) + '</span><b>' + (c.hours > 0 ? 'in about ' + c.hours + ' h' : 'arriving') + '</b></div>';
      }).join('');
      return body((coming ? '<div class="sll-card"><h4>On the way to your garage</h4>' + coming + '</div>' : '') + (rows || '<div class="sll-empty">No dealers on this map.</div>'));
    }

    function offersBody() {
      var o = st.offers || { name: 'Dealer', offers: [] };
      var cards = arr(o.offers).map(function (c) {
        var faults = arr(c.faults);
        return '<div class="sll-card sll-listing" data-a="offer" data-v="' + esc(c.id) + '">' + pic(c) + '<div class="sll-li"><h4>' + (c.year ? c.year + ' ' : '') + esc(c.name) + '</h4>' +
          '<div class="sll-brand">' + esc(c.brand || '') + (c.title ? ' &middot; ' + esc(c.title) : '') + '</div><div class="sll-props">' + facts(c) + '</div>' +
          '<div class="sll-props">' + esc(c.seller || o.name) + ' &middot; ' + dist(c.metres) + ' away &middot; arrives in about ' + (c.hours || 0) + ' h</div>' +
          '<div class="sll-props">condition ' + Math.round((c.condition || 0) * 100) + '%' + (faults.length ? '<br>Needs: ' + esc(faults.join(', ')) : '') + '</div></div>' +
          '<div class="sll-lbuy"><b>' + money(c.price) + '</b><div class="sll-btn' + ((o.money || 0) < c.price ? ' sll-off' : '') + '" data-a="buy" data-v="' + esc(o.dealer) + '|' + esc(c.id) + '">Buy</div></div></div>';
      }).join('');
      return body(cards || '<div class="sll-empty">Nothing left on the lot today.</div>');
    }

    function currentOffer() {
      var o = st.offers || { offers: [] }, c = null;
      arr(o.offers).forEach(function (x) { if (x.id === st.offerId) c = x; });
      return c;
    }
    // the detail view: the picture, every spec, the seller, the delivery and the price
    function offerBody() {
      var o = st.offers || { offers: [] }, c = currentOffer();
      if (!c) return body('<div class="sll-empty">This car has gone.</div>');
      var sp = obj(c.specs), faults = arr(c.faults);
      var row = function (k, v) { return v == null || v === '' ? '' : '<div class="sll-kv"><span>' + k + '</span><b>' + v + '</b></div>'; };
      return body('<div class="sll-detail">' + pic(c) +
        '<div class="sll-li"><div class="sll-card">' + row('Brand', esc(c.brand)) + row('Year', c.year) + row('Mileage', c.mileage != null ? Number(c.mileage).toLocaleString() + ' km' : null) +
        row('Condition', Math.round((c.condition || 0) * 100) + '%' + (c.title ? ' (' + esc(c.title) + ')' : '')) + row('Power', sp.power ? Math.round(sp.power) + ' PS' : null) +
        row('Weight', sp.weight ? Math.round(sp.weight).toLocaleString() + ' kg' : null) + row('Transmission', esc(sp.transmission)) + row('Drivetrain', esc(sp.drivetrain)) +
        row('Fuel', esc(sp.fuel)) + row('Body', esc(sp.body)) + row('Top speed', sp.topSpeed ? Math.round(sp.topSpeed * 3.6) + ' km/h' : null) +
        (faults.length ? row('Needs', esc(faults.join(', '))) : '') + reportBlock('offer:' + c.id, c.report) + '</div>' +
        '<div class="sll-card">' + row('Seller', esc(c.seller || o.name)) + row('Distance', dist(c.metres)) + row('Delivery', 'to your garage in about ' + (c.hours || 0) + ' h') +
        '<div class="sll-kv"><span>Price</span><b style="font-size:18px">' + money(c.price) + '</b></div>' +
        '<div class="sll-acts"><div class="sll-btn' + ((o.money || 0) < c.price ? ' sll-off' : '') + '" data-a="buy" data-v="' + esc(o.dealer) + '|' + esc(c.id) + '">Buy &middot; ' + money(c.price) + '</div></div></div></div></div>');
    }

    // ---- the marketplaces: the car market (dealers + private ads) and the part market (Revline, Swap & Bid, the paper, the catalog): the phone's data
    function tabsHtml(kind, list) {
      var cur = st.tab[kind];
      return '<div class="sll-tabs">' + list.map(function (t) {
        return '<div class="sll-tab' + (t[0] === cur ? ' sll-tabon' : '') + '" data-a="mtab" data-v="' + kind + '|' + t[0] + '">' + t[1] + '</div>';
      }).join('') + '</div>';
    }
    function mkButtons(l) {
      var offers = l.agreed ? '' : [0.9, 0.8, 0.7].map(function (f) {
        var amt = Math.round(l.ask * f / 10) * 10;
        return '<div class="sll-btn sll-text" data-a="mkoffer" data-v="' + esc(l.id) + '|' + amt + '">Offer ' + money(amt) + '</div>';
      }).join('');
      return '<div class="sll-acts">' + offers + '<div class="sll-btn" data-a="mkbuy" data-v="' + esc(l.id) + '|pickup">Pick up</div>' +
        (l.delivery != null ? '<div class="sll-btn sll-tonal" data-a="mkbuy" data-v="' + esc(l.id) + '|delivery">Deliver &middot; +' + money(l.delivery) + '</div>' : '') + '</div>';
    }
    // the full car report (#58): every part by section with its condition, the dents, the faults and a repair estimate per section
    function reportBlock(key, rp) {
      if (!rp || !rp.sections) return '';
      var on = !!st.rep[key];
      var head = '<div class="sll-btn sll-tonal" data-a="report" data-v="' + esc(key) + '">' + (on ? 'Hide car report' : 'Show full car report') + '</div>';
      if (!on) return '<div class="sll-acts">' + head + '</div>';
      var secs = arr(rp.sections).map(function (sc) {
        var parts = arr(sc.parts).map(function (p) {
          return '<div class="sll-kv"><span>' + esc(p.name) + (p.fault ? ' <b class="sll-rbad">&#9888; ' + esc(p.fault) + '</b>' : '') + '</span><b class="sll-r' + (p.condition < 30 ? 'bad' : p.condition < 50 ? 'mid' : 'ok') + '">' + p.condition + '% ' + esc(p.label) + '</b></div>';
        }).join('');
        return '<div class="sll-rsec"><h5>' + esc(sc.title) + ' &middot; ' + sc.condition + '% ' + esc(sc.label) + '</h5>' + parts +
          '<div class="sll-kv"><span>Repair estimate</span><b>' + (sc.estimate > 0 ? money(sc.estimate) : 'none') + '</b></div></div>';
      }).join('');
      var dm = obj(rp.damage);
      return '<div class="sll-acts">' + head + '</div><div class="sll-report"><div class="sll-kv"><span>Overall</span><b>' + rp.condition + '% ' + esc(rp.label) + '</b></div>' +
        '<div class="sll-kv"><span>Mileage</span><b>' + Number(rp.mileage || 0).toLocaleString() + ' km</b></div><div class="sll-kv"><span>Dents and damage</span><b>' + esc(dm.label) + ' (' + (dm.amount || 0) + '%)</b></div>' +
        '<div class="sll-kv"><span>Known faults</span><b>' + (arr(rp.faults).length ? esc(arr(rp.faults).join(', ')) : 'none') + '</b></div>' + secs +
        '<div class="sll-kv"><span><b>Repair estimate, to 95 %</b></span><b>' + money(rp.total) + '</b></div></div>';
    }
    function adCardL(l) {
      var tells = arr(l.tells).length ? '<div class="sll-props" style="color:#f2b8b5">&#9888; ' + arr(l.tells).map(esc).join(' &middot; ') + '</div>' : '';
      if (l.car) {
        return '<div class="sll-card sll-listing">' + pic(l) + '<div class="sll-li"><h4>' + (l.year ? l.year + ' ' : '') + esc(l.name) + '</h4><div class="sll-brand">' + esc(l.brand || '') + '</div>' +
          '<div class="sll-props">' + facts(l) + '</div><div class="sll-props">' + esc(l.seller) + ' ' + '&#9733;'.repeat(l.rating || 0) + (l.metres != null ? ' &middot; ' + dist(l.metres) + ' away' : '') +
          (l.hours ? ' &middot; delivered in about ' + l.hours + ' h' : '') + ' &middot; condition ' + l.condition + '%' + (l.faults ? ' &middot; ' + l.faults + ' fault' + (l.faults > 1 ? 's' : '') : '') + '</div>' + tells +
          '<div class="sll-props"><b>' + money(l.ask) + '</b>' + (l.agreed ? ' (agreed)' : '') + ' &middot; deposit ' + money(l.deposit) + '</div>' + reportBlock('ad:' + l.id, l.report) + mkButtons(l) + '</div></div>';
      }
      return '<div class="sll-card"><h4>' + (l.rare ? '&#9733; ' : '') + esc(l.name) + '</h4><p>For the ' + esc(l.model) + ' &middot; ' + l.condition + '% condition &middot; ' + esc(l.seller) + ' ' + '&#9733;'.repeat(l.rating || 0) +
        ' &middot; ' + Math.max(0, l.hoursLeft | 0) + ' h left</p>' + tells + '<p><b>' + money(l.ask) + '</b>' + (l.agreed ? ' (agreed)' : '') + ' &middot; deposit ' + money(l.deposit) + '</p>' + mkButtons(l) + '</div>';
    }
    function sellL(m, kind) {
      var mine = arr(m.mine).filter(function (y) { return (kind === 'cars') === (y.carId != null); }).map(function (y) {
        var inner = y.channel === 'auction' ? '<p>At auction &middot; ' + (y.bid ? 'top bid ' + money(y.bid) : 'no bids yet') + ' &middot; ' + Math.max(0, y.hoursLeft | 0) + ' h left</p>'
          : (arr(y.offers).length ? arr(y.offers).map(function (o) {
              return '<div class="sll-acts"><div class="sll-btn" data-a="mkaccept" data-v="' + esc(y.id) + '|' + o.index + '">Accept ' + money(o.amount) + ' from ' + esc(o.buyer || 'a buyer') + '</div></div>';
            }).join('') : '<p>No offers yet.</p>');
        return '<div class="sll-card"><h4>Your ' + esc(y.name) + '</h4>' + inner + '<div class="sll-acts"><div class="sll-btn sll-text" data-a="mkwithdraw" data-v="' + esc(y.id) + '">Withdraw</div></div></div>';
      }).join('');
      var lists = kind === 'cars' ? arr(m.cars).map(function (c) {
        return '<div class="sll-card"><h4>' + esc(c.name) + '</h4><p>Your car &middot; buyers pay up to about ' + money(c.estimate || 0) + '</p><div class="sll-acts"><div class="sll-btn" data-a="mkcar" data-v="' + esc(c.id) + '">List car</div></div></div>';
      }).join('') : arr(m.shelf).map(function (it) {
        return '<div class="sll-card"><h4>' + esc(it.name) + '</h4><p>On your shelf &middot; buyers pay up to about ' + money(it.estimate) + '</p><div class="sll-acts">' +
          '<div class="sll-btn" data-a="mklist" data-v="' + esc(it.model) + '|' + it.id + '|app">List it</div><div class="sll-btn sll-tonal" data-a="mklist" data-v="' + esc(it.model) + '|' + it.id + '|auction">Auction it</div></div></div>';
      }).join('');
      return (mine ? '<div class="sll-band" style="margin:8px 0">Your listings</div>' + mine : '') + (lists ? '<div class="sll-band" style="margin:8px 0">' + (kind === 'cars' ? 'Sell a car' : 'Sell from your shelf') + '</div>' + lists : '');
    }
    function carAdsBody() {
      var m = obj(st.data.market);
      var cards = arr(m.listings).filter(function (l) { return l.car; }).map(adCardL).join('');
      return body((cards || '<div class="sll-empty">No private cars for sale right now. New ads come in through the day.</div>') + sellL(m, 'cars'));
    }
    function partMarketBody() {
      var m = obj(st.data.market), tab = st.tab.partmarket;
      if (tab === 'auctions') {
        var lots = arr(m.auctions).map(function (l) {
          var mine = l.high === 'you';
          return '<div class="sll-card"><h4>' + (l.rare ? '&#9733; ' : '') + esc(l.name) + '</h4><p>For the ' + esc(l.model) + ' &middot; ' + l.condition + '% condition &middot; ' + Math.max(0, l.hoursLeft | 0) + ' h left</p>' +
            '<p><b>' + money(l.bid) + '</b> ' + (mine ? '(your bid)' : (l.high === 'ai' ? '(outbid)' : '(opening bid)')) + ' &middot; delivery +' + money(l.delivery || 0) + '</p>' +
            (mine ? '' : '<div class="sll-acts"><div class="sll-btn" data-a="mkbid" data-v="' + esc(l.id) + '">Bid ' + money(l.next) + '</div></div>') + '</div>';
        }).join('');
        var meet = obj(m.meet), stalls = '';
        if (meet.open) {
          stalls = '<div class="sll-empty">Swap meet today at the ' + esc(meet.place || 'Tuning shop lot') + (meet.here ? '. You are here.' : ': go and buy in person.') + '</div>' + arr(meet.listings).map(function (l) {
            return '<div class="sll-card"><h4>' + esc(l.name) + '</h4><p>' + esc(l.seller) + '\'s stall &middot; ' + l.condition + '% condition</p><p><b>' + money(l.ask) + '</b></p>' +
              (meet.here ? '<div class="sll-acts"><div class="sll-btn" data-a="mkmeet" data-v="' + esc(l.id) + '">Buy it</div></div>' : '') + '</div>';
          }).join('');
        }
        return body(stalls + (lots || '<div class="sll-empty">No lots right now.</div>'));
      }
      if (tab === 'paper') {
        var p = obj(m.paper);
        var ads = arr(p.listings).map(function (l) { return adCardL(l).replace('<h4>', '<h4>' + (l.printOnly ? '[print only] ' : '')); }).join('');
        return body('<div class="sll-empty">Edition ' + (p.edition || 1) + '. Small ads go fast.' + (p.bought ? ' You have the printed copy.' : (p.hidden ? ' ' + p.hidden + ' more in the printed copy.' : '')) + '</div>' +
          (p.bought ? '' : '<div class="sll-acts"><div class="sll-btn" data-a="buypaper" data-v="1">Buy the paper (' + money(p.price || 2) + ', at a gas station)</div></div>') +
          (ads || '<div class="sll-empty">No ads right now. New ones come out through the week.</div>'));
      }
      if (tab === 'catalog') {
        return body('<div class="sll-card"><h4>The Wrench Works catalog</h4><p>Every part that fits your car, new, with its price. The car goes into the garage it stands at and the catalog opens; what you order is delivered to your shelf.</p>' +
          '<div class="sll-acts"><div class="sll-btn" data-a="pcatalog" data-v="1">Open the catalog</div></div></div>');
      }
      var cards = arr(m.listings).filter(function (l) { return !l.car; }).map(adCardL).join('');
      return body((m.deliveries ? '<div class="sll-empty">' + m.deliveries + ' on the way to your garage.</div>' : '') + (cards || '<div class="sll-empty">Nothing listed right now. New ads come in through the day.</div>') + sellL(m, 'parts'));
    }

    function partsBody() {
      var by = {}, order = [];
      st.parts.forEach(function (p) { if (!by[p.car]) { by[p.car] = []; order.push(p.car); } by[p.car].push(p); });
      var cards = order.map(function (car) {
        return '<div class="sll-card"><h4>' + esc(car) + '</h4>' + by[car].map(function (p) {
          return '<div class="sll-kv"><span>' + esc(p.name) + (p.count > 1 ? ' &times;' + p.count : '') + '</span><b>' + money(p.value) + '</b></div>';
        }).join('') + '</div>';
      });
      return body(cards.join('') || '<div class="sll-empty">The shelf in your garage is empty. Parts you take off a car, and parts delivered to you, wait there.</div>');
    }

    function bankBody() {
      var d = st.data, bk = d.bank, cards = '';
      if (bk) {
        if (bk.loan) {
          cards += '<div class="sll-card"><h4>Loan: ' + money(bk.loan.owed) + ' owed</h4><p>Next payment ' + money(bk.loan.due) + ' in ' + bk.loan.dueIn + ' day' + (bk.loan.dueIn === 1 ? '' : 's') + '</p>' +
            '<div class="sll-acts"><div class="sll-btn" data-a="repay" data-v="' + Math.min(bk.loan.owed, d.money || 0) + '">Pay ' + money(Math.min(bk.loan.owed, d.money || 0)) + '</div></div></div>';
        } else {
          var half = Math.floor(bk.limit / 200) * 100, quarter = Math.floor(bk.limit / 400) * 100;
          cards += '<div class="sll-card"><h4>Borrow</h4><p>Up to ' + money(bk.limit) + ' &middot; ' + Math.round(bk.rate * 100) + '% a day &middot; a quarter due each week</p>' +
            '<div class="sll-acts">' + (quarter >= 100 && quarter < half ? '<div class="sll-btn sll-tonal" data-a="borrow" data-v="' + quarter + '">' + money(quarter) + '</div>' : '') + '<div class="sll-btn sll-tonal" data-a="borrow" data-v="' + half + '">' + money(half) + '</div><div class="sll-btn sll-tonal" data-a="borrow" data-v="' + bk.limit + '">' + money(bk.limit) + '</div></div></div>';
        }
        cards += bk.policy ? '<div class="sll-card"><h4>Insured</h4><p>' + (bk.policy.startsIn ? 'Cover starts tomorrow' : 'Covering half of repairs and impound bills over ' + money(bk.deductible)) + '</p>' +
            '<div class="sll-acts"><div class="sll-btn sll-text" data-a="insure" data-v="false">Cancel</div></div></div>'
          : '<div class="sll-card"><h4>Insurance</h4><p>' + money(bk.premium) + ' a week: half of repairs and impound bills over ' + money(bk.deductible) + ', from the next day</p>' +
            '<div class="sll-acts"><div class="sll-btn sll-tonal" data-a="insure" data-v="true">Insure</div></div></div>';
      }
      var rows = arr(d.ledger).map(function (e) {
        return '<div class="sll-kv"><span>' + esc(e.label || '') + '</span><b class="' + (e.amount >= 0 ? 'sll-plus' : 'sll-minus') + '">' + (e.amount >= 0 ? '+' : '') + money(e.amount) + '</b></div>';
      }).join('');
      return body('<div class="sll-card"><h4>Balance</h4><p style="font-size:24px;color:#e6e1e5">' + money(d.money) + '</p></div>' + cards + '<div class="sll-card">' + (rows || '<p>No transactions yet.</p>') + '</div>');
    }

    function credBody() {
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
      return body('<div class="sll-card"><h4>' + esc(d.title) + '</h4><p>' + (d.rep || 0) + ' reputation' + (to ? ' &middot; next title at ' + to : '') + '</p>' +
        '<div class="sll-meter"><i style="width:' + pct.toFixed(1) + '%"></i></div></div>' +
        '<div class="sll-card"><div class="sll-kv"><span>Garage</span><b>' + esc(d.garage || '') + '</b></div>' + next +
        '<div class="sll-kv"><span>Cars</span><b>' + (d.cars || 0) + '</b></div>' +
        '<div class="sll-kv"><span>Races</span><b>' + (s.races || 0) + ' (' + (s.wins || 0) + ' won)</b></div>' +
        '<div class="sll-kv"><span>Pink slips</span><b>' + (s.pinksWon || 0) + ' won, ' + (s.pinksLost || 0) + ' lost</b></div>' + acts + '</div>' + ach);
    }

    function winTitle(w) {
      if (w.id === 'dealers' && st.tab.dealers === 'dealers') {
        if (st.dview === 'offers') return (st.offers && st.offers.name) || WINDOWS.dealers[1];
        if (st.dview === 'offer') { var c = currentOffer(); return c ? (c.year ? c.year + ' ' : '') + c.name : 'Sold'; }
      }
      return WINDOWS[w.id][1];
    }
    function winBody(w) {
      switch (w.id) {
        case 'cars': return carsBody();
        case 'parts': return partsBody();
        case 'bank': return bankBody();
        case 'cred': return credBody();
        case 'partmarket': return tabsHtml('partmarket', [['revline', 'Revline'], ['auctions', 'Swap & Bid'], ['paper', 'Classifieds'], ['catalog', 'Catalog']]) + partMarketBody();
        default:
          return tabsHtml('dealers', [['dealers', 'Dealers'], ['ads', 'Private ads']]) +
            (st.tab.dealers === 'ads' ? carAdsBody() : st.dview === 'offers' ? offersBody() : (st.dview === 'offer' ? offerBody() : dealersBody()));
      }
    }
    // the dealers window goes back from a car to the list, from the list to the dealers
    function canGoBack(w) { return w.id === 'dealers' && st.tab.dealers === 'dealers' && st.dview !== 'dealers'; }

    // ---------------------------------------------------------------- the desktop, the windows, the taskbar
    // the tiles for the chosen car (whether it stands at this garage differs per car); without cars, the general ones
    function groupsFor(car) {
      var v = st.view || { groups: [] };
      return car && v.byCar && v.byCar[car.id] ? v.byCar[car.id] : v.groups;
    }
    function allTiles() {
      var out = [];
      groupsFor(arr(st.data.fleet)[st.car]).forEach(function (g) { g.tiles.forEach(function (t) { out.push(t); }); });
      return out;
    }

    function tileLabel(t) { return t.id === 'phaseSwitch' && st.data.phaseSwitch ? st.data.phaseSwitch : t.label; }
    function iconsHtml() {
      return '<div class="sll-icons">' + allTiles().map(function (t) {
        return '<div class="sll-icon' + (t.enabled ? '' : ' sll-off') + (st.sel === t.id ? ' sll-sel' : '') + '" data-a="tile" data-v="' + esc(t.id) + '">' + icon(t.id) + '<span>' + esc(tileLabel(t)) + '</span></div>';
      }).join('') + '</div>';
    }

    // the car the garage tiles act on, as a small window of its own
    function widgetHtml() {
      var fleet = arr(st.data.fleet);
      st.car = Math.max(0, Math.min(st.car, fleet.length - 1));
      if (!(st.view && st.view.lists)) return '';
      var c = fleet[st.car];
      return '<div class="sll-widget"><div class="sll-title">' + icon('vehicleInventory', 16) + '<b>My garage</b><div class="sll-sp"></div></div><div class="sll-wb"><div class="sll-wrow">' +
        '<div class="sll-btn sll-tonal" data-a="car" data-v="-1">&#9664;</div><div class="sll-car">' + (c ? '<b>' + esc(c.name) + '</b><span>' + esc(c.where) + ' &middot; condition ' + Math.round((c.condition || 0) * 100) + '% &middot; value ' + money(c.value) + '</span>'
          : '<b>No car yet</b><span>The junkyard and the dealers sell them.</span>') + '</div><div class="sll-btn sll-tonal" data-a="car" data-v="1">&#9654;</div></div></div></div>';
    }

    function winHtml(w, i, top) {
      if (w.min) return '';
      var n = st.wins.indexOf(w);
      var style = 'z-index:' + (10 + n) + ';left:' + (11 + 3 * n) + '%;top:' + (5 + 4 * n) + '%;width:56%;height:64%';
      return '<div class="sll-win' + (w.max ? ' sll-max' : '') + (w === top ? ' sll-top' : '') + '" data-win="' + w.id + '" style="' + style + '">' +
        '<div class="sll-title" data-a="focus" data-v="' + w.id + '">' + icon(WINDOWS[w.id][0], 16) + '<b>' + esc(winTitle(w)) + '</b><div class="sll-sp"></div>' +
        (canGoBack(w) ? '<div class="sll-tb" data-a="back" data-v="' + w.id + '" title="Back">&#9664;</div>' : '') +
        '<div class="sll-tb" data-a="winmin" data-v="' + w.id + '" title="Minimise">&#8212;</div>' +
        '<div class="sll-tb" data-a="winmax" data-v="' + w.id + '" title="' + (w.max ? 'Restore' : 'Maximise') + '">' + (w.max ? '&#10064;' : '&#9744;') + '</div>' +
        '<div class="sll-tb sll-xb" data-a="winclose" data-v="' + w.id + '" title="Close">&#10005;</div></div>' +
        winBody(w).replace('<div class="sll-note"></div>', '<div class="sll-note">' + (w === top ? esc(st.note) : '') + '</div>') + '<div class="sll-grip"></div></div>';
    }
    function topWin() {
      for (var i = st.wins.length - 1; i >= 0; i--) if (!st.wins[i].min) return st.wins[i];
      return null;
    }

    function menuHtml() {
      if (!st.menu) return '';
      var d = st.data;
      var groups = groupsFor(arr(d.fleet)[st.car]);
      return '<div class="sll-menu"><div class="sll-user">' + (d.active ? esc(d.title || '') + ' &middot; ' + (d.rep || 0) + ' reputation' : 'Street Legal') + '</div><div class="sll-mlist">' + groups.map(function (g) {
        return '<div class="sll-band">' + esc(g.title) + '</div>' + g.tiles.map(function (t) {
          return '<div class="sll-mi' + (t.enabled ? '' : ' sll-off') + '" data-a="tile" data-v="' + esc(t.id) + '">' + icon(t.id, 24) + '<span>' + esc(tileLabel(t)) + '</span></div>';
        }).join('');
      }).join('') + '</div><div class="sll-mfoot"><div class="sll-btn sll-tonal" data-a="close">Shut down</div></div></div>';
    }

    function taskbarHtml() {
      var d = st.data, h = d.hour || 0, m = d.minute || 0, top = topWin();
      return '<div class="sll-task"><div class="sll-startbtn' + (st.menu ? ' sll-on' : '') + '" data-a="start"><svg viewBox="0 0 18 18"><path fill="#a8c7fa" d="M1 2l7-1v7H1zm8-1.200L17 0v8H9zM1 9h7v7l-7-1zm8 0h8v9l-8-1.200z"/></svg>Start</div>' +
        st.wins.map(function (w) {
          return '<div class="sll-taskwin' + (w === top ? ' sll-on' : '') + '" data-a="task" data-v="' + w.id + '">' + icon(WINDOWS[w.id][0], 16) + '<span>' + esc(winTitle(w)) + '</span></div>';
        }).join('') + '<div class="sll-sp"></div>' +
        (d.active ? '<div class="sll-tray"><span>' + esc(d.title || '') + ' &middot; ' + (d.rep || 0) + ' rep</span><span>' + money(d.money) + '</span><div class="sll-clock">' + two(h) + ':' + two(m) + '<br>Day ' + (d.day || 1) + '</div></div>' : '') + '</div>';
    }

    // ---------------------------------------------------------------- drawing and gamepad focus
    var focusKey = null;
    function keyOf(el) { return el && el.getAttribute ? (el.getAttribute('data-a') || '') + '|' + (el.getAttribute('data-v') || '') : null; }
    function render() {
      var inner = '';
      if (st.open) {
        var top = topWin();
        inner = '<div class="sll-wall"' + (st.wallpaper ? ' style="background-image:url(\'' + esc(st.wallpaper) + '\'),linear-gradient(#17121f,#0d0b12)"' : '') + '></div>' +
          '<div class="sll-desk">' + iconsHtml() + widgetHtml() + '</div>' + st.wins.map(function (w) { return winHtml(w, 0, top); }).join('') + menuHtml() +
          (st.note && !top ? '<div class="sll-balloon">' + esc(st.note) + '</div>' : '') + taskbarHtml();
      }
      layer.innerHTML = '<div class="sll-screen' + (st.open ? '' : ' sll-gone') + '">' + inner + '</div>';
      navify();
    }
    // the game moves the focus between [bng-nav-item] elements with the d-pad/stick and clicks the focused one on A
    function navify() {
      var items = layer.querySelectorAll('[data-a]');
      var first = null, again = null;
      // the d-pad moves inside what is on top: the Start menu, else the top window, else the desktop (the taskbar is always reachable)
      var top = topWin();
      var scope = !st.open ? null : st.menu ? layer.querySelector('.sll-menu') : top ? layer.querySelector('.sll-win.sll-top') : layer.querySelector('.sll-desk');
      for (var i = 0; i < items.length; i++) {
        var el = items[i];
        var live = st.open && ((scope && scope.contains(el)) || (el.closest && el.closest('.sll-task')));
        if (!live) { el.setAttribute('bng-no-nav', 'true'); el.removeAttribute('bng-nav-item'); el.removeAttribute('tabindex'); continue; }
        el.removeAttribute('bng-no-nav');
        el.setAttribute('bng-nav-item', '');
        el.setAttribute('tabindex', '0');
        var a = el.getAttribute('data-a');
        if (!first && !el.closest('.sll-task') && a !== 'focus' && !el.classList.contains('sll-tb')) first = el;
        if (focusKey && !again && keyOf(el) === focusKey) again = el;
      }
      var bodies = layer.querySelectorAll('.sll-body, .sll-icons, .sll-mlist');
      for (var j = 0; j < bodies.length; j++) bodies[j].setAttribute('bng-nav-scroll', '');
      if (!st.open) return;
      var active = doc.activeElement;
      var inside = active && layer.contains(active) && active.hasAttribute && active.hasAttribute('bng-nav-item');
      var target = again || (!inside ? first : null);
      if (target && target !== active && target.focus) target.focus();
    }
    doc.addEventListener('focusin', function (ev) { if (layer.contains(ev.target)) focusKey = keyOf(ev.target); }, true);

    // ---------------------------------------------------------------- what the buttons do
    function tileById(id) {
      var tiles = allTiles();
      for (var i = 0; i < tiles.length; i++) if (tiles[i].id === id) return tiles[i];
      return null;
    }
    function winById(id) {
      for (var i = 0; i < st.wins.length; i++) if (st.wins[i].id === id) return st.wins[i];
      return null;
    }
    // bring a window to the front (a minimised one comes back)
    function focusWin(w) {
      st.wins.splice(st.wins.indexOf(w), 1);
      st.wins.push(w);
      w.min = false;
    }
    function openWin(id) {
      var w = winById(id);
      if (!w) { w = { id: id, min: false, max: false }; st.wins.push(w); }
      focusWin(w);
      if (id === 'dealers') st.dview = 'dealers';
      st.note = ''; focusKey = null;
    }
    function closeWin(w) {
      st.wins.splice(st.wins.indexOf(w), 1);
      st.note = ''; focusKey = null;
    }
    // B: the Start menu first, then one step back inside the top window, then the window, then (a bare desktop) the laptop
    function back() {
      if (st.menu) { st.menu = false; render(); return; }
      var w = topWin();
      if (w) {
        if (canGoBack(w)) {
          if (st.dview === 'offer') st.dview = 'offers'; else { st.dview = 'dealers'; lua('@sl_dealers.list()'); }
          st.note = ''; focusKey = null;
        } else closeWin(w);
        render();
        return;
      }
      close();
    }
    function close() { lua('@sl_computer.close()'); setOpen(false); }
    function setOpen(open) { st.open = open; if (!open) { st.wins = []; st.note = ''; st.menu = false; st.sel = null; focusKey = null; } render(); }
    function act(a, v) {
      switch (a) {
        case 'start': st.menu = !st.menu; focusKey = null; render(); break;
        case 'tile':
          st.menu = false;
          var t = tileById(v);
          if (!t) break;
          st.sel = v;
          if (!t.enabled) { st.note = t.label + ': ' + (t.reason || 'Not available.'); render(); break; }
          if (t.page) {
            openWin(t.page);
            if (t.page === 'parts') lua('@sl_computer.parts()');
            if (t.page === 'dealers') lua('@sl_dealers.list()');
            lua('@sl_phone.request()');
            render();
          } else if (t.run === 'phase') {
            lua('@sl_phone.wait("switch")');
          } else if (t.mode) {
            // the garage tiles: the Wrench Works garage opens on the chosen car (the game closes this screen when it has)
            var car = arr(st.data.fleet)[st.car];
            if (car) lua('@sl_computer.enterGarage(' + JSON.stringify(t.mode) + ',' + Number(car.id) + ')');
            else render();
          }
          break;
        case 'select': st.sel = v; st.menu = false; render(); break;
        case 'focus': var fw = winById(v); if (fw && topWin() !== fw) { focusWin(fw); render(); } break;
        case 'task':
          var tw = winById(v);
          if (!tw) break;
          st.menu = false;
          if (tw === topWin()) tw.min = true; else focusWin(tw);      // the focused window's button minimises it, any other brings it up
          focusKey = null; render();
          break;
        case 'winmin': var mw = winById(v); if (mw) { mw.min = true; focusKey = null; render(); } break;
        case 'winmax': var xw = winById(v); if (xw) { xw.max = !xw.max; focusWin(xw); render(); } break;
        case 'winclose': var cw = winById(v); if (cw) { closeWin(cw); render(); } break;
        case 'mtab': var tp = String(v).split('|'); st.tab[tp[0]] = tp[1]; st.note = ''; focusKey = null; if (tp[0] === 'dealers' && tp[1] === 'dealers') { st.dview = 'dealers'; lua('@sl_dealers.list()'); } render(); break;
        case 'mkoffer': var op = String(v).split('|'); lua('@sl_phone.marketOffer(' + JSON.stringify(op[0]) + ',' + Number(op[1]) + ')'); break;
        case 'mkbuy': var bp = String(v).split('|'); lua('@sl_phone.marketBuy(' + JSON.stringify(bp[0]) + ',' + JSON.stringify(bp[1]) + ')'); break;
        case 'mkbid': lua('@sl_phone.marketBid(' + JSON.stringify(String(v)) + ')'); break;
        case 'mkmeet': lua('@sl_phone.buyAtMeet(' + JSON.stringify(String(v)) + ')'); break;
        case 'buypaper': lua('@sl_phone.buyPaper()'); break;
        case 'mkcar': lua('@sl_phone.listCar(' + JSON.stringify(String(v)) + ')'); break;
        case 'mklist': var lp = String(v).split('|'); lua('@sl_phone.listPart(' + JSON.stringify(lp[0]) + ',' + Number(lp[1]) + ',' + JSON.stringify(lp[2]) + ')'); break;
        case 'mkaccept': var ap = String(v).split('|'); lua('@sl_phone.acceptOffer(' + JSON.stringify(ap[0]) + ',' + Number(ap[1]) + ')'); break;
        case 'mkwithdraw': lua('@sl_phone.withdrawListing(' + JSON.stringify(String(v)) + ')'); break;
        case 'pcatalog': lua('@sl_phone.catalog()'); break;
        case 'dealer': st.dview = 'offers'; st.offers = { name: 'Dealer', offers: [], dealer: v }; st.note = ''; focusKey = null; lua('@sl_dealers.offers(' + JSON.stringify(v) + ')'); render(); break;
        case 'report': st.rep[v] = !st.rep[v]; render(); break;
        case 'offer': st.dview = 'offer'; st.offerId = v; st.note = ''; focusKey = null; render(); break;
        case 'buy':
          var pair = String(v).split('|');
          lua('@sl_dealers.buy(' + JSON.stringify(pair[0]) + ',' + JSON.stringify(pair[1]) + ')');
          break;
        case 'back': back(); break;
        case 'close': close(); break;
        case 'car': st.car += Number(v) || 0; render(); break;
        case 'usecar': lua('@sl_phone.useCar(' + Number(v) + ')'); break;
        case 'tow': lua('@sl_phone.tow(' + Number(v) + ')'); break;
        case 'despawn': lua('@sl_phone.despawn(' + Number(v) + ')'); break;
        case 'release': lua('@sl_phone.release(' + Number(v) + ')'); break;
        case 'borrow': lua('@sl_phone.borrow(' + Number(v) + ')'); break;
        case 'repay': lua('@sl_phone.repay(' + Number(v) + ')'); break;
        case 'insure': lua('@sl_phone.insure(' + (v === 'true' ? 'true' : 'false') + ')'); break;
        case 'move': lua('@sl_phone.moveGarage()'); break;
      }
    }
    // a desktop icon works as in Windows: one click with the mouse selects it, a double click opens it; the pad's A (a click with no
    // click count) and the keyboard's Enter open it at once. Everything else acts on the first click.
    root.addEventListener('click', function (ev) {
      var el = ev.target;
      while (el && el !== root && !(el.getAttribute && el.getAttribute('data-a'))) el = el.parentNode;
      if (el && el !== root) {
        var a = el.getAttribute('data-a'), v = el.getAttribute('data-v');
        if (a === 'tile' && ev.detail === 1 && el.classList.contains('sll-icon')) act('select', v);
        else act(a, v);
        return;
      }
      // a click anywhere in a window brings it forward; one on the bare desktop shuts the Start menu
      var win = ev.target;
      while (win && win !== root && !(win.getAttribute && win.getAttribute('data-win'))) win = win.parentNode;
      if (win && win !== root) { var w = winById(win.getAttribute('data-win')); if (w && topWin() !== w) { focusWin(w); render(); } }
      else if (st.menu) { st.menu = false; render(); }
    });
    // B on the pad (and Escape) goes back; tab_l / tab_r change the car. Window capture: before the game's own handler, so B does not
    // open the pause menu.
    (doc.defaultView || doc).addEventListener('ui_nav', function (ev) {
      var d = ev.detail || {};
      st.padAt = Date.now();
      if (!st.open || d.value !== 1) return;
      if (d.name === 'back') back();
      else if ((d.name === 'tab_l' || d.name === 'tab_r') && arr(st.data.fleet).length > 1) { st.car += d.name === 'tab_l' ? -1 : 1; render(); }
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
          st.parts = arr(data.parts); st.wins = []; st.note = ''; st.car = 0; st.sel = null; st.menu = false; focusKey = null;
          st.wallpaper = typeof data.wallpaper === 'string' && data.wallpaper ? data.wallpaper : null;
          setOpen(true);
          break;
        case 'slLaptopClose': if (st.open) setOpen(false); break;
        case 'slLaptopParts': st.parts = arr(data.parts); if (st.open) render(); break;
        case 'slLaptopDealers': st.dealers = data; if (st.open) render(); break;
        case 'slLaptopOffers': st.offers = data; if (st.open) render(); break;
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
