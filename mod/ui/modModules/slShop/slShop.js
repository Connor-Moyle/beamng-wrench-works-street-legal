// Street Legal Racing - the shop screens.
// A global UI module (like the phone and the laptop, imported once by the game from /ui/modModules/<name>/<name>.js). One screen for every kind of shop: the Lua side (sl/shops,
// event slShopOpen) sends the shop record (kind, name, theme, stock, services, money) and this draws it. A kind only changes the THEME: accent colour, header pattern, icon and
// wording; the layout, the components, the spacing and the pad and focus behaviour are the same everywhere, so every shop feels like one family (docs/UI_STYLE.md).
// The components are small pure functions (header, rail, card, detail, cart bar, service row, toast) with no state of their own, so the phone or the laptop can lift them later.
// createShop() is plain DOM, so tools/shoptest.js can run it outside the game. Classes are .slsh-*; colours are the custom properties --sl-*.

(function () {
  'use strict';

  // the player-facing text: sl/core/strings (event slStrings). T('key', 'the text', a, b): the second argument shows until the table has arrived and for a key it lacks.
  var TABLE = null;
  function T(key, fallback) {
    var text = TABLE && TABLE[key] !== undefined ? TABLE[key] : fallback, a = arguments;
    return String(text).replace(/\{(\d+)\}/g, function (m, i) { var v = a[Number(i) + 1]; return v === undefined ? '' : v; });
  }
  function esc(s) { return String(s === undefined || s === null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function arr(a) { return Array.isArray(a) ? a : []; }
  function money(n) { return '$' + Math.round(Number(n) || 0).toLocaleString('en-US'); }

  // ---------------------------------------------------------------- the look
  var CSS = [
    '.slsh-root{--sl-text:#e6e1e5;--sl-text2:#cac4d0;--sl-muted:#938f99;--sl-accent:#a8c7fa;--sl-accent-l:#d3e3fd;--sl-bad:#f2b8b5;--sl-good:#6dd58c;--sl-surface1:#141218;--sl-surface2:#211f26;--sl-surface3:#2b2930;--sl-outline:#49454f;--sl-deep:#0d0b12;--sl-focus:#ffd54f;',
    '  position:fixed;left:0;top:0;right:0;bottom:0;z-index:61;display:none;align-items:center;justify-content:center;background:rgba(0,0,0,.6);pointer-events:auto;',
    '  font-family:"Segoe UI","Roboto","Noto Sans",Arial,sans-serif;color:var(--sl-text);-webkit-user-select:none;user-select:none}',
    '.slsh-root.slsh-open{display:flex}.slsh-root *{box-sizing:border-box}',
    '.slsh-cb{--sl-good:#56b4e9;--sl-bad:#ffb454}',
    '.slsh-rm *,.slsh-rm.slsh-open{transition:none!important;animation:none!important}',
    '.slsh-panel{width:min(1120px,96vw);height:min(700px,92vh);display:flex;flex-direction:column;border-radius:16px;background:var(--sl-surface1);box-shadow:0 20px 60px rgba(0,0,0,.6);overflow:hidden;border:1px solid var(--sl-outline)}',
    '.slsh-head{position:relative;display:flex;align-items:center;gap:16px;padding:14px 20px;background:var(--sl-deep);border-bottom:3px solid var(--sl-accent);overflow:hidden}',
    '.slsh-pattern{position:absolute;left:0;top:0;right:0;bottom:0;opacity:.35;pointer-events:none}',
    '.slsh-icon{position:relative;width:48px;height:48px;flex:none;color:var(--sl-accent)}.slsh-icon svg{width:48px;height:48px}',
    '.slsh-title{position:relative;flex:1;min-width:0}.slsh-title b{display:block;font-size:22px;font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.slsh-title span{font-size:14px;color:var(--sl-text2)}.slsh-money{position:relative;font-size:20px;color:var(--sl-text);font-variant-numeric:tabular-nums}',
    '.slsh-closed{padding:8px 20px;background:var(--sl-surface3);color:var(--sl-bad);font-size:15px}.slsh-closed:before{content:"\\25BC "}',
    '.slsh-body{flex:1;min-height:0;display:flex}',
    '.slsh-rail{width:200px;flex:none;padding:12px 8px;border-right:1px solid var(--sl-outline);overflow-y:auto;background:var(--sl-surface1)}',
    '.slsh-main{flex:1;min-width:0;overflow-y:auto;padding:14px 16px}',
    '.slsh-side{width:300px;flex:none;display:flex;flex-direction:column;border-left:1px solid var(--sl-outline);background:var(--sl-surface2)}',
    '.slsh-btn{display:inline-flex;align-items:center;justify-content:center;gap:6px;min-height:40px;padding:8px 16px;border:1px solid var(--sl-outline);border-radius:20px;background:var(--sl-surface3);color:var(--sl-text);font:inherit;font-size:15px;cursor:pointer}',
    '.slsh-btn:hover{border-color:var(--sl-accent)}.slsh-btn.slsh-pri{background:var(--sl-accent);color:var(--sl-on-accent,#0d0b12);border-color:var(--sl-accent)}.slsh-btn[disabled]{opacity:.45;cursor:default}',
    '.slsh-cat{display:block;width:100%;text-align:left;margin:2px 0;padding:10px 12px;border:0;border-radius:12px;background:transparent;color:var(--sl-text2);font:inherit;font-size:15px;cursor:pointer}',
    '.slsh-cat.slsh-on{background:var(--sl-surface3);color:var(--sl-text);box-shadow:inset 3px 0 0 var(--sl-accent)}',
    '.slsh-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:12px}',
    '.slsh-card{display:flex;flex-direction:column;gap:6px;padding:12px;border:1px solid var(--sl-outline);border-radius:18px;background:var(--sl-surface2);color:inherit;font:inherit;text-align:left;cursor:pointer}',
    '.slsh-card:hover,.slsh-card.slsh-sel{border-color:var(--sl-accent)}.slsh-card b{font-size:16px;font-weight:500}.slsh-card small{color:var(--sl-muted);font-size:13px}',
    '.slsh-price{font-size:17px;color:var(--sl-text);font-variant-numeric:tabular-nums}.slsh-was{margin-left:6px;font-size:13px;color:var(--sl-muted);text-decoration:line-through}',
    '.slsh-good{color:var(--sl-good)}.slsh-good:before{content:"\\2714 "}.slsh-bad{color:var(--sl-bad)}.slsh-bad:before{content:"\\25BC "}.slsh-up:before{content:"\\25B2 "}',
    '.slsh-cond{height:6px;border-radius:3px;background:var(--sl-surface3);overflow:hidden}.slsh-cond i{display:block;height:100%;background:var(--sl-accent)}',
    '.slsh-row{display:flex;align-items:center;gap:12px;min-height:64px;padding:12px 14px;margin-bottom:8px;border:1px solid var(--sl-outline);border-radius:18px;background:var(--sl-surface2)}',
    '.slsh-spec{display:grid;grid-template-columns:96px 1fr auto;gap:8px;align-items:center;margin:4px 0;font-size:13px;color:var(--sl-text2)}.slsh-spec .slsh-bar{height:6px;border-radius:3px;background:var(--sl-surface3);overflow:hidden}.slsh-spec .slsh-bar i{display:block;height:100%;background:var(--sl-accent)}.slsh-spec b{font-weight:400;color:var(--sl-text);font-variant-numeric:tabular-nums}',
    '.slsh-swatch{width:28px;height:28px;border-radius:14px;border:2px solid var(--sl-text2);flex:none}.slsh-curve{width:120px;height:34px;flex:none}.slsh-curve path{stroke:var(--sl-accent);stroke-width:2;fill:none}',
    '.slsh-row .slsh-grow{flex:1;min-width:0}.slsh-row b{font-weight:500;font-size:16px}.slsh-row small{display:block;color:var(--sl-muted);font-size:13px}',
    '.slsh-detail{padding:14px 16px;border-bottom:1px solid var(--sl-outline);min-height:120px}.slsh-detail h3{margin:0 0 6px;font-size:18px;font-weight:500}.slsh-detail p{margin:6px 0;color:var(--sl-text2);font-size:14px;line-height:1.45}',
    '.slsh-cart{flex:1;min-height:0;overflow-y:auto;padding:10px 16px}.slsh-line{display:flex;align-items:center;gap:8px;padding:6px 0;font-size:14px}.slsh-line span{flex:1}',
    '.slsh-foot{padding:12px 16px;border-top:1px solid var(--sl-outline);display:flex;flex-direction:column;gap:8px}.slsh-total{display:flex;justify-content:space-between;font-size:18px}',
    '.slsh-note{padding:16px;border:1px dashed var(--sl-outline);border-radius:14px;color:var(--sl-text2);font-size:15px;line-height:1.5}.slsh-muted{color:var(--sl-muted)}',
    '.slsh-toast{position:absolute;left:50%;bottom:28px;transform:translateX(-50%);padding:10px 18px;border-radius:20px;background:var(--sl-surface3);border:1px solid var(--sl-accent);font-size:15px}',
    '.slsh-root [data-a]:focus,.slsh-root [tabindex]:focus{outline:3px solid var(--sl-focus)!important;outline-offset:2px;box-shadow:0 0 0 2px var(--sl-deep)}',
    '.slsh-main::-webkit-scrollbar,.slsh-rail::-webkit-scrollbar,.slsh-cart::-webkit-scrollbar{width:6px}.slsh-main::-webkit-scrollbar-thumb,.slsh-rail::-webkit-scrollbar-thumb,.slsh-cart::-webkit-scrollbar-thumb{background:var(--sl-outline);border-radius:4px}',
    '.slsh-count{float:right;color:var(--sl-muted);font-size:13px;font-variant-numeric:tabular-nums}',
    '@media (prefers-reduced-motion:no-preference){.slsh-card,.slsh-btn,.slsh-cat{transition:border-color .15s,background .15s}.slsh-root.slsh-open{animation:slsh-in .18s ease-out}@keyframes slsh-in{from{opacity:0}to{opacity:1}}}',
  ].join('\n');

  // ---------------------------------------------------------------- the themes: a header pattern and an icon per kind (the accent colour comes from the shop record)
  var PATTERNS = {
    tread: function (c) { return '<path d="M0 8h120M0 24h120M0 40h120" stroke="' + c + '" stroke-width="6" stroke-dasharray="14 8" fill="none"/>'; },
    pipes: function (c) { return '<path d="M0 12h70a14 14 0 0 1 0 28h-40" stroke="' + c + '" stroke-width="5" fill="none"/><circle cx="26" cy="40" r="6" fill="none" stroke="' + c + '" stroke-width="3"/>'; },
    grid: function (c) { return '<path d="M0 0h60v60H0zM30 0v60M0 30h60" stroke="' + c + '" stroke-width="1.5" fill="none"/>'; },
    chevrons: function (c) { return '<path d="M0 6l16 14L0 34M20 6l16 14-16 14" stroke="' + c + '" stroke-width="4" fill="none"/>'; },
    spray: function (c) { return '<g fill="' + c + '"><circle cx="8" cy="10" r="3"/><circle cx="26" cy="22" r="5"/><circle cx="14" cy="38" r="2"/><circle cx="44" cy="12" r="2.5"/><circle cx="48" cy="40" r="4"/></g>'; },
    dyno: function (c) { return '<path d="M0 40q15-34 30-12t30-22" stroke="' + c + '" stroke-width="3" fill="none"/><path d="M0 52h60" stroke="' + c + '" stroke-width="1.5"/>'; },
    bolts: function (c) { return '<path d="M10 4l10 6v12l-10 6-10-6V10zM38 30l10 6v12l-10 6-10-6V36z" stroke="' + c + '" stroke-width="2.5" fill="none"/>'; },
    stripes: function (c) { return '<path d="M-10 60L30-10M10 60L50-10M30 60L70-10" stroke="' + c + '" stroke-width="5" fill="none"/>'; },
    badge: function (c) { return '<path d="M30 4l22 8v18c0 14-10 22-22 26C18 52 8 44 8 30V12z" stroke="' + c + '" stroke-width="2.5" fill="none"/>'; },
  };
  var ICONS = {
    tyre: '<circle cx="24" cy="24" r="19" fill="none" stroke="currentColor" stroke-width="5"/><circle cx="24" cy="24" r="7" fill="none" stroke="currentColor" stroke-width="3"/><path d="M24 5v6M24 37v6M5 24h6M37 24h6" stroke="currentColor" stroke-width="3"/>',
    exhaust: '<path d="M4 34h20a8 8 0 0 0 0-16H14" fill="none" stroke="currentColor" stroke-width="4"/><circle cx="38" cy="18" r="6" fill="none" stroke="currentColor" stroke-width="3"/><path d="M38 6v-3M44 9l2-2" stroke="currentColor" stroke-width="2.5"/>',
    wrench: '<path d="M30 6a10 10 0 0 0-9 14L6 35l7 7 15-15a10 10 0 0 0 14-9l-7 5-5-5z" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linejoin="round"/>',
    engine: '<path d="M8 18h8v-6h14v6h6l4 5v13H10l-2-4zM2 24h6" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linejoin="round"/>',
    paint: '<path d="M12 6h24v12H12zM24 18v10M20 28h8v14h-8z" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linejoin="round"/>',
    gauge: '<path d="M6 34a18 18 0 1 1 36 0" fill="none" stroke="currentColor" stroke-width="4"/><path d="M24 34l9-12" stroke="currentColor" stroke-width="4"/><circle cx="24" cy="34" r="3" fill="currentColor"/>',
    spanner: '<path d="M10 38L30 18a8 8 0 1 1 6 6L16 44z" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linejoin="round"/>',
    star: '<path d="M24 4l6 13 14 2-10 10 3 14-13-7-13 7 3-14L4 19l14-2z" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linejoin="round"/>',
    badge: '<path d="M24 4l17 6v14c0 10-8 16-17 20C15 40 7 34 7 24V10z" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linejoin="round"/>',
  };
  function iconSvg(name) { return '<svg viewBox="0 0 48 48" aria-hidden="true">' + (ICONS[name] || ICONS.wrench) + '</svg>'; }
  function patternSvg(name, accent) {
    var fn = PATTERNS[name] || PATTERNS.grid;
    return '<svg class="slsh-pattern" width="100%" height="100%" aria-hidden="true"><defs><pattern id="slsh-pat" width="60" height="60" patternUnits="userSpaceOnUse">' + fn(accent) + '</pattern></defs><rect width="100%" height="100%" fill="url(#slsh-pat)"/></svg>';
  }

  // text on an accent fill: --sl-deep or white, whichever has more contrast (docs/UI_STYLE.md says deep above a luminance of 0.4; the cross-over that always reaches 4.5:1 is lower; the test checks every built-in accent)
  function luminance(hex) {
    var c = [1, 3, 5].map(function (i) { var v = parseInt(hex.substr(i, 2), 16) / 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); });
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
  }
  function onAccent(hex) { var l = luminance(hex); return (l + 0.05) / (0.0036 + 0.05) >= 1.05 / (l + 0.05) ? '#0d0b12' : '#ffffff'; }      // (whichever of the two reads better: the cross-over is at about 0.18, never below 4.5:1)

  // ---------------------------------------------------------------- components: pure functions, each returns a string of HTML
  function specRows(specs) {
    return arr(specs).map(function (sp) {
      return '<div class="slsh-spec"><span>' + esc(sp.label) + '</span>' + (sp.bar !== undefined && sp.bar !== null ? '<div class="slsh-bar"><i style="width:' + Math.round(sp.bar * 100) + '%"></i></div>' : '<span></span>') + '<b>' + esc(sp.text === undefined ? '' : sp.text) + '</b></div>';
    }).join('');
  }
  function curveSvg(values, cls) {
    var v = arr(values).map(Number).filter(function (n) { return isFinite(n); });
    if (v.length < 2) return '';
    var lo = Math.min.apply(null, v), hi = Math.max.apply(null, v), span = hi - lo || 1;
    var pts = v.map(function (n, i) { return (i ? 'L' : 'M') + (i * 100 / (v.length - 1)).toFixed(1) + ' ' + (30 - (n - lo) / span * 28).toFixed(1); }).join('');
    return '<svg class="' + cls + '" viewBox="0 0 100 32" preserveAspectRatio="none" aria-hidden="true"><path d="' + pts + '" vector-effect="non-scaling-stroke"/></svg>';
  }
  function header(shop, closed) {
    var sub = shop.keeper && shop.keeper.name ? esc(shop.keeper.name) + (shop.keeper.line ? ': ' + esc(shop.keeper.line) : '') : esc(shop.tagline || shop.title);
    return '<div class="slsh-head">' + patternSvg(shop.theme.pattern, shop.theme.accent) + '<div class="slsh-icon">' + iconSvg(shop.theme.icon) + '</div>' +
      '<div class="slsh-title"><b>' + esc(shop.name) + (shop.brand ? ' <span>(' + esc(shop.brand) + ')</span>' : '') + '</b><span>' + sub + '</span></div>' +
      '<div class="slsh-money" title="' + esc(T('shops.ui_money', 'Your money')) + '">' + money(shop.money) + '</div>' +
      '<button class="slsh-btn" data-a="close" bng-nav-item>' + esc(T('shops.ui_close', 'Close')) + '</button></div>' +
      (closed ? '<div class="slsh-closed">' + esc(closed) + '</div>' : '');
  }
  function rail(groups, cat, counts) {
    counts = counts || {};
    var out = '<div class="slsh-rail">' + '<button class="slsh-cat' + (cat === 'all' ? ' slsh-on' : '') + '" data-a="cat" data-v="all" bng-nav-item>' + esc(T('shops.ui_all', 'Everything')) + '<span class="slsh-count">' + (counts.all || 0) + '</span></button>';
    groups.forEach(function (g) { out += '<button class="slsh-cat' + (cat === g ? ' slsh-on' : '') + '" data-a="cat" data-v="' + esc(g) + '" bng-nav-item>' + esc(g) + '<span class="slsh-count">' + (counts[g] || 0) + '</span></button>'; });
    return out + '</div>';
  }
  function condBar(cond) { return cond === undefined || cond === null ? '' : '<div class="slsh-cond" title="' + Math.round(cond * 100) + '%"><i style="width:' + Math.round(cond * 100) + '%"></i></div>'; }
  function priceTag(it) { return '<span class="slsh-price">' + money(it.price) + '</span>' + (it.was && it.was > it.price ? '<span class="slsh-was">' + money(it.was) + '</span>' : ''); }
  function card(it, selected, inCart) {
    return '<button class="slsh-card' + (selected ? ' slsh-sel' : '') + '" data-a="pick" data-v="' + esc(it.id) + '" bng-nav-item><b>' + esc(it.name) + '</b>' +
      (it.group ? '<small>' + esc(it.group) + '</small>' : '') + condBar(it.cond) +
      '<span>' + priceTag(it) + '</span>' + (inCart ? '<small class="slsh-good">' + esc(T('shops.ui_in_basket', 'In the basket')) + ' x' + inCart + '</small>' : '') + '</button>';
  }
  function detail(it, canAdd, words) {
    if (!it) return '<div class="slsh-detail"><p class="slsh-muted">' + esc(T('shops.ui_pick', 'Pick something to see it here.')) + '</p></div>';
    return '<div class="slsh-detail"><h3>' + esc(it.name) + '</h3>' + (it.desc ? '<p>' + esc(it.desc) + '</p>' : '') +
      (it.cond !== undefined && it.cond !== null ? '<p>' + esc(T('shops.ui_condition', 'Condition')) + ': ' + Math.round(it.cond * 100) + '%</p>' + condBar(it.cond) : '') +
      (it.swatch ? '<p><span class="slsh-swatch" style="background:' + esc(it.swatch) + '"></span></p>' : '') + specRows(it.specs) + (it.curve ? curveSvg(it.curve, 'slsh-curve') + (it.curveLabel ? '<small class="slsh-muted">' + esc(it.curveLabel) + '</small>' : '') : '') +
      '<p>' + priceTag(it) + '</p><button class="slsh-btn slsh-pri" data-a="add" data-v="' + esc(it.id) + '" bng-nav-item' + (canAdd ? '' : ' disabled') + '>' + esc((words && words.add) || T('shops.ui_add', 'Add to basket')) + '</button></div>';
  }
  function cartBar(lines, total, have, closed, words) {
    var rows = lines.map(function (l) {
      return '<div class="slsh-line"><span>' + esc(l.name) + ' x' + l.qty + '</span><b>' + money(l.sum) + '</b><button class="slsh-btn" data-a="remove" data-v="' + esc(l.id) + '" bng-nav-item aria-label="' + esc(T('shops.ui_remove', 'Remove')) + '">&minus;</button></div>';
    }).join('') || '<p class="slsh-muted">' + esc(T('shops.ui_empty', 'Nothing in the basket.')) + '</p>';
    var short = total > have;
    return '<div class="slsh-cart">' + rows + '</div><div class="slsh-foot"><div class="slsh-total"><span>' + esc(T('shops.ui_total', 'Total')) + '</span><b class="' + (short ? 'slsh-bad' : '') + '">' + money(total) + '</b></div>' +
      (short ? '<span class="slsh-bad">' + esc(T('shops.cannot_afford', 'You cannot afford that.')) + '</span>' : '') +
      '<button class="slsh-btn slsh-pri" data-a="buy" bng-nav-item' + (lines.length && !short && !closed ? '' : ' disabled') + '>' + esc((words && words.buy) || T('shops.ui_buy', 'Pay')) + '</button></div>';
  }
  function serviceRow(sv, inCart, words) {
    return '<div class="slsh-row">' + (sv.swatch ? '<span class="slsh-swatch" style="background:' + esc(sv.swatch) + '"></span>' : '') + '<div class="slsh-grow"><b>' + esc(sv.name) + '</b>' + (sv.desc ? '<small>' + esc(sv.desc) + '</small>' : '') +
      (sv.minutes ? '<small>' + esc(T('shops.ui_minutes', '{1} min', sv.minutes)) + '</small>' : '') + specRows(sv.specs) + '</div>' + (sv.curve ? curveSvg(sv.curve, 'slsh-curve') : '') + '<span>' + priceTag(sv) + '</span>' +
      '<button class="slsh-btn' + (inCart ? '' : ' slsh-pri') + '" data-a="' + (inCart ? 'remove' : 'add') + '" data-v="' + esc(sv.id) + '" bng-nav-item>' + esc(inCart ? T('shops.ui_remove', 'Remove') : ((words && words.add) || T('shops.ui_do', 'Book'))) + '</button></div>';
  }
  function toast(text) { return text ? '<div class="slsh-toast" role="status">' + esc(text) + '</div>' : ''; }

  // ---------------------------------------------------------------- the screen
  function createShop(doc, send) {
    var root = doc.createElement('div');
    root.className = 'slsh-root';
    var style = doc.createElement('style');
    style.textContent = CSS;
    root.appendChild(style);
    var layer = doc.createElement('div');
    root.appendChild(layer);
    (doc.body || doc.documentElement).appendChild(root);
    var st = { open: false, shop: null, cat: 'all', cart: {}, sel: null, toast: '', toastTimer: null };
    var focusKey = null;

    function items() { return st.shop ? (st.shop.screen === 'services' ? arr(st.shop.services) : arr(st.shop.stock)) : []; }
    function find(id) { var l = items(); for (var i = 0; i < l.length; i++) if (l[i].id === id) return l[i]; return null; }
    function lines() {
      var out = [];
      Object.keys(st.cart).forEach(function (id) { var it = find(id); if (it) out.push({ id: id, name: it.name, qty: st.cart[id], each: it.price, sum: it.price * st.cart[id] }); });
      return out;
    }
    function total() { return lines().reduce(function (a, l) { return a + l.sum; }, 0); }
    function groups() {
      var seen = [];
      arr(st.shop && st.shop.stock).forEach(function (it) { if (it.group && seen.indexOf(it.group) < 0) seen.push(it.group); });
      return seen;
    }
    function say(text) {
      st.toast = text;
      if (st.toastTimer) clearTimeout(st.toastTimer);
      st.toastTimer = setTimeout(function () { st.toast = ''; if (st.open) render(); }, 3500);
    }

    function render() {
      root.classList.toggle('slsh-open', st.open);
      if (!st.open || !st.shop) { layer.innerHTML = ''; return; }
      var shop = st.shop, closed = shop.closed, l = lines(), t = total();
      var body;
      if (shop.screen === 'services') {
        var rows = arr(shop.services).map(function (sv) { return serviceRow(sv, !!st.cart[sv.id], shop.words); }).join('') || '<div class="slsh-note">' + esc(T('shops.ui_none', 'Nothing is on offer today.')) + '</div>';
        body = '<div class="slsh-main">' + rows + '</div><div class="slsh-side">' + cartBar(l, t, shop.money, closed, shop.words) + '</div>';
      } else {
        var g = groups(), list = arr(shop.stock).filter(function (it) { return st.cat === 'all' || it.group === st.cat; });
        var cards = list.map(function (it) { return card(it, st.sel === it.id, st.cart[it.id]); }).join('');
        if (!cards) cards = '<div class="slsh-note">' + esc(shop.goods === 'catalog' ? T('shops.ui_catalog_note', 'Parts for your car are fitted from the Wrench Works catalogue.') : T('shops.ui_none', 'Nothing is on offer today.')) + '</div>';
        var counts = { all: arr(shop.stock).length };
        arr(shop.stock).forEach(function (it) { if (it.group) counts[it.group] = (counts[it.group] || 0) + 1; });
        body = (g.length ? rail(g, st.cat, counts) : '') + '<div class="slsh-main"><div class="slsh-grid">' + cards + '</div></div><div class="slsh-side">' + detail(find(st.sel), !closed, shop.words) + cartBar(l, t, shop.money, closed, shop.words) + '</div>';
      }
      layer.innerHTML = '<div class="slsh-panel" style="--sl-accent:' + esc(shop.theme.accent) + ';--sl-on-accent:' + onAccent(shop.theme.accent) + '">' + header(shop, closed) + '<div class="slsh-body">' + body + '</div>' + toast(st.toast) + '</div>';
      var el = focusKey ? layer.querySelector('[data-a="' + focusKey.a + '"][data-v="' + focusKey.v + '"]') || layer.querySelector('[data-a="' + focusKey.a + '"]') : null;
      if (el && el.focus) el.focus();
    }

    function act(a, v) {
      focusKey = { a: a, v: v === undefined ? '' : v };
      if (a === 'close') { send('@sl_shops.close()'); st.open = false; }
      else if (a === 'cat') { st.cat = v; }
      else if (a === 'pick') { st.sel = v; }
      else if (a === 'add') { var it = find(v); if (it) { var n = (st.cart[v] || 0) + 1; if (it.count && n > it.count) say(T('shops.not_in_stock', 'That is not in stock.')); else st.cart[v] = n; } }
      else if (a === 'remove') { if (st.cart[v] > 1 && st.shop.screen !== 'services') st.cart[v]--; else delete st.cart[v]; }
      else if (a === 'buy') {
        var l = lines();
        if (!l.length) return render();
        send('@sl_shops.buy("' + l.map(function (x) { return x.id.replace(/[^\w.\-]/g, '') + ':' + x.qty; }).join(',') + '")');
      }
      render();
    }

    layer.addEventListener('click', function (ev) {
      var n = ev.target;
      while (n && n !== layer && !(n.getAttribute && n.getAttribute('data-a'))) n = n.parentNode;
      if (!n || n === layer || n.disabled) return;
      act(n.getAttribute('data-a'), n.getAttribute('data-v') === null ? undefined : n.getAttribute('data-v'));
    });

    // the pad: left / up and right / down move along the buttons in the order they are drawn, A (confirm) presses, B closes
    (doc.defaultView || doc).addEventListener('ui_nav', function (ev) {
      var d = ev.detail || {};
      if (!st.open || d.value !== 1) return;
      var all = Array.prototype.slice.call(layer.querySelectorAll('[data-a]')).filter(function (e) { return !e.disabled; });
      var at = all.indexOf(doc.activeElement);
      if (d.name === 'back') act('close');
      else if (d.name === 'confirm') { if (at >= 0) all[at].click(); }
      else if (d.name === 'left' || d.name === 'up') { if (all.length) all[(at <= 0 ? all.length : at) - 1].focus(); }
      else if (d.name === 'right' || d.name === 'down') { if (all.length) all[(at + 1) % all.length].focus(); }
      else return;
      if (ev.stopImmediatePropagation) ev.stopImmediatePropagation();
      if (ev.preventDefault) ev.preventDefault();
    }, true);
    doc.addEventListener('keydown', function (ev) { if (st.open && ev.key === 'Escape') { act('close'); ev.preventDefault(); } });

    function handle(name, data) {
      switch (name) {
        case 'slShopOpen': {
          var fresh = !st.open || !st.shop || st.shop.name !== data.name || st.shop.kind !== data.kind;
          data.theme = data.theme || {}; data.theme.accent = /^#[0-9a-f]{6}$/i.test(data.theme.accent || '') ? data.theme.accent : '#a8c7fa';
          st.shop = data; st.open = true;
          root.classList.toggle('slsh-cb', !!data.colorBlind);
          root.classList.toggle('slsh-rm', !!data.reduceMotion);
          if (fresh) { st.cat = 'all'; st.cart = {}; st.sel = null; focusKey = null; } else { st.cart = {}; }      // (bought: the basket is empty again)
          break;
        }
        case 'slShopClose': st.open = false; break;
        case 'slPhoneToast': if (st.open && data && data.text) say(data.text); break;
        case 'slStrings': TABLE = data; break;
        default: return;
      }
      render();
    }
    return { handle: handle, state: st, act: act, root: root, css: CSS };
  }

  var api = { luminance: luminance, onAccent: onAccent, create: createShop, header: header, rail: rail, card: card, detail: detail, cartBar: cartBar, serviceRow: serviceRow, toast: toast, patternSvg: patternSvg, iconSvg: iconSvg, themes: Object.keys(PATTERNS), specRows: specRows, curveSvg: curveSvg };
  if (typeof window !== 'undefined') { window.__slShopCreate = createShop; window.__slShopParts = api; }

  // in the game: one shop screen for the whole UI, fed by the Lua side's events
  if (typeof angular !== 'undefined' && typeof window !== 'undefined' && !window.__slShopTest) {
    angular.module('slShop', []).run(['$rootScope', function ($rootScope) {
      if (window.__slShop) return;
      var shop = createShop(document, function (call) {
        if (!window.bngApi || call.charAt(0) !== '@') return;
        var ext = call.slice(1).split('.')[0];
        window.bngApi.engineLua('if ' + ext + ' then ' + call.slice(1) + ' end');
      });
      window.__slShop = shop;
      ['slShopOpen', 'slShopClose', 'slPhoneToast', 'slStrings'].forEach(function (name) {
        $rootScope.$on(name, function (ev, data) { shop.handle(name, data); });
      });
    }]);
  }
})();
