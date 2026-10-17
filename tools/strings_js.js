// Moves the player-facing texts of the phone and the laptop (HTML builders and labels) into the strings table (#51), by the syntax tree (acorn).
//   NODE_PATH=<qa>/node_modules node tools/strings_js.js [--dry] [--audit] [files...]     (default: slPhone.js and slLaptop.js)
// In the code a text becomes  T('ui.some_words', 'the text')  (the second argument shows until the table has arrived, so nothing changes without it);
// a chain  'Season ' + n + ', day ' + d  becomes  T('ui.season_1_day_2', 'Season {1}, day {2}', n, d); a literal with HTML is split into markup and texts:
// '<h4>Last race</h4>'  becomes  ('<h4>' + T('ui.last_race', 'Last race') + '</h4>'). The texts go into sl/core/strings.lua between the BEGIN/END extracted markers
// (the UI gets the keys that start with ui., app., laptop., status., phase., wait., hud. and settings. through sl_phone.requestStrings).
// Run it again and again: it stops when nothing is left.
const fs = require('fs'), path = require('path');
const acorn = require('acorn');

const ROOT = path.join(__dirname, '..');
const WW = process.argv.includes('--ww');          // Wrench Works: the garage screen says $scope.t('key', 'text'); the table is slrr/garageStrings.lua
const CALL = WW ? '$scope.t' : 'T', PREFIX = WW ? 'p' : 'ui';
const STRINGS = WW ? 'C:/Dev/Beam NG SLRR MOD/mod/lua/ge/extensions/slrr/garageStrings.lua' : path.join(ROOT, 'mod', 'lua', 'ge', 'extensions', 'sl', 'core', 'strings.lua');
const BEGIN = '  -- BEGIN extracted (tools/strings_extract.py)', END = '  -- END extracted';
const args = process.argv.slice(2);
const dry = args.includes('--dry'), audit = args.includes('--audit');
const only = args.filter((a) => !a.startsWith('--'));
const FILES = WW ? ['C:/Dev/Beam NG SLRR MOD/mod/ui/modules/apps/slrrGarage/app.js'] : only.length ? only.map((f) => path.resolve(f)) : ['slPhone/slPhone.js', 'slLaptop/slLaptop.js'].map((f) => path.join(ROOT, 'mod', 'ui', 'modModules', f));

const SKIP_METHODS = new Set(['querySelector', 'querySelectorAll', 'getAttribute', 'setAttribute', 'removeAttribute', 'addEventListener', 'removeEventListener', 'createElement',
  'contains', 'add', 'remove', 'toggle', 'hasOwnProperty', 'setProperty', 'getPropertyValue', 'engineLua',
  'serializeToLua', 'matches', 'closest', 'dispatchEvent', 'getElementById', 'getElementsByClassName', 'createTextNode', 'join'].concat(WW ? ['t'] : []));
const FIRST_ONLY = new Set(['indexOf', 'lastIndexOf', 'split', 'replace', 'test', 'match', 'search', 'startsWith', 'endsWith', 'includes']);      // (only the pattern is code: replace('<h4>', '<h4>text'))
const SKIP_FUNCS = new Set(['lua', 'require', 'T', 'icon', 'svg', 'RegExp', 'parseInt', 'Number', 'setTimeout', 'avatar', 'kv']);
const SKIP_ASSIGN = new Set(['className', 'id', 'type', 'href', 'src', 'display', 'cssText', 'name', 'value', 'placeholder']);

function q(v) { return "'" + v.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, '\\n') + "'"; }
function luaQuote(t) { return '"' + t.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n') + '"'; }

function textLike(v) {
  const t = v.replace(/&[#a-zA-Z0-9]+;/g, ' ').trim();                 // (entities like &middot; are markup, not text)
  if (!/[A-Za-z]{3}/.test(t)) return false;
  if (/^&[#a-z0-9]+;$/i.test(t) || /^[a-z0-9_.#:\/-]+$/.test(t)) return false;
  if (/=["']|["'] *[a-z-]+=/.test(v)) return false;                              // (attributes of a tag split across literals)
  if (/[{};]/.test(t) || /\b(px|rgba?|data-|slp-|sll-|slh-)/.test(t) || /^#[0-9a-f]{3,8}$/i.test(t) || /^[MmLlHhVvCcZz][\d .,-]*\d/.test(t)) return false;
  const words = t.split(/\s+/);
  if (words.every((w) => /^[a-z][a-z0-9_-]*$/.test(w)) && words.some((w) => /[-_]/.test(w))) return false;      // a class list
  if (t.includes(' ')) return true;
  if (/^[A-Z][A-Za-z']{2,}[.!?:]?$/.test(t)) return true;                                                         // a one-word label
  const w = t.replace(/^[(\[]+/, '').replace(/[)\].,:;!?]+$/, '');
  return /^[A-Za-z']{3,}$/.test(w) && (/^\s|\s$/.test(v.replace(/&[#a-zA-Z0-9]+;/g, '')) || w !== t);                          // a word of a sentence, with its space
}

function loadTable() {
  const s = fs.readFileSync(STRINGS, 'utf8');
  const byText = new Map(), taken = new Set();
  for (const m of s.matchAll(/\['([^']+)'\]|\["([^"]+)"\]/g)) taken.add(m[1] || m[2]);
  const bi = s.indexOf(BEGIN), ei = s.indexOf(END);
  for (const m of s.slice(bi, ei).matchAll(/\["([^"]+)"\]\s*=\s*"((?:[^"\\]|\\.)*)",/g)) byText.set(m[2].replace(/\\(.)/g, (x, c) => (c === 'n' ? '\n' : c)), m[1]);
  return { byText, taken };
}
const table = loadTable();
const newEntries = new Map();
function keyFor(text) {
  let key = table.byText.get(text);
  if (key) return key;
  const words = (text.toLowerCase().match(/[a-z0-9]+/g) || ['text']).slice(0, 5).join('_');
  key = PREFIX + '.' + words;
  for (let n = 2; table.taken.has(key) || newEntries.has(key); n++) key = PREFIX + '.' + words + '_' + n;
  table.byText.set(text, key);
  newEntries.set(key, text);
  return key;
}

// the HTML of a literal split into [{ markup: '..' } | { text: '..' }]
function split(v) {
  const out = [];
  let i = 0, inTag = false;
  const firstLt = v.indexOf('<'), firstGt = v.indexOf('>');
  if (firstGt !== -1 && (firstLt === -1 || firstGt < firstLt)) inTag = true;           // it begins inside a tag that the literal before opened
  let buf = '';
  const flush = (markup) => { if (buf) out.push(markup ? { markup: buf } : { text: buf }); buf = ''; };
  while (i < v.length) {
    const c = v[i];
    if (inTag) { buf += c; if (c === '>') { flush(true); inTag = false; } i++; continue; }
    if (c === '<') { flush(false); inTag = true; buf += c; i++; continue; }
    if (c === '&') { const m = /^&[#a-zA-Z0-9]+;/.exec(v.slice(i)); if (m) { flush(false); out.push({ markup: m[0] }); i += m[0].length; continue; } }
    buf += c; i++;
  }
  flush(inTag);
  // merge neighbouring markup
  const merged = [];
  for (const p of out) { const l = merged[merged.length - 1]; if (l && l.markup !== undefined && p.markup !== undefined) l.markup += p.markup; else merged.push(p); }
  return merged;
}

function run(file) {
  const src = fs.readFileSync(file, 'utf8');
  const ast = acorn.parse(src, { ecmaVersion: 2018, ranges: true, sourceType: 'script', preserveParens: true })      // (a parenthesised sum is one operand, never part of the string chain);
  const rep = [];
  const skip = new Set(), done = new Set();
  const nodes = [];
  (function walk(n, parent) {
    if (!n || typeof n.type !== 'string') return;
    nodes.push([n, parent]);
    for (const k of Object.keys(n)) {
      const v = n[k];
      if (Array.isArray(v)) v.forEach((x) => walk(x, n)); else if (v && typeof v === 'object' && typeof v.type === 'string') walk(v, n);
    }
  })(ast, null);
  for (const [n, p] of nodes) {
    if (n.type === 'ExpressionStatement' && n.expression && n.expression.type === 'Literal') skip.add(n.expression);      // ('use strict')
    if (n.type === 'Property' && !n.computed) skip.add(n.key);
    if (n.type === 'MemberExpression' && n.computed) skip.add(n.property);
    if (n.type === 'SwitchCase' && n.test) skip.add(n.test);
    if (n.type === 'BinaryExpression' && ['===', '!==', '==', '!=', '<', '>', '<=', '>=', 'in'].includes(n.operator)) { skip.add(n.left); skip.add(n.right); }
    if (n.type === 'NewExpression') n.arguments.forEach((a) => skip.add(a));
    if (n.type === 'AssignmentExpression' && n.left.type === 'MemberExpression' && !n.left.computed && SKIP_ASSIGN.has(n.left.property.name)) skip.add(n.right);
    if (n.type === 'CallExpression') {
      const c = n.callee;
      const name = c.type === 'Identifier' ? c.name : (c.type === 'MemberExpression' && !c.computed ? c.property.name : null);
      if (name && (c.type === 'Identifier' ? SKIP_FUNCS.has(name) : SKIP_METHODS.has(name))) n.arguments.forEach((a) => skip.add(a));
      if (name === 'join') n.arguments.forEach((a) => skip.add(a));
      if (name && FIRST_ONLY.has(name) && c.type === 'MemberExpression' && n.arguments[0]) skip.add(n.arguments[0]);
    }
    if (n.type === 'VariableDeclarator' && n.init && n.id && /^(CSS|STYLE|NAV|APP_COLORS|AV_COLORS|CREW_COLOURS|CREW_INITIALS|ICONS|WINDOWS|WIN_KEYS|CAB_KINDS|YOURS_COLOUR)$/.test(n.id.name)) skip.add(n.init);
  }
  // the whole CSS array and similar blocks: every literal in a skipped container
  const insideSkipped = (node) => { for (const [m] of nodes) { if (skip.has(m) && m.range[0] <= node.range[0] && m.range[1] >= node.range[1] && m !== node && m.type !== 'Literal') return true; } return false; };
  const isStr = (n) => n.type === 'Literal' && typeof n.value === 'string';
  function chainParts(n, out) { if (n.type === 'BinaryExpression' && n.operator === '+') { chainParts(n.left, out); chainParts(n.right, out); } else out.push(n); return out; }
  const parentOf = new Map(nodes.map(([n, p]) => [n, p]));
  let count = 0;
  const add = (start, end, code) => { rep.push({ start, end, code }); count++; };
  // 1. template chains: 'text ' + x + ' more' (the first operand is a string, no markup in any literal)
  for (const [n, p] of nodes) {
    if (n.type !== 'BinaryExpression' || n.operator !== '+' || (p && p.type === 'BinaryExpression' && p.operator === '+')) continue;
    if (skip.has(n) || insideSkipped(n)) continue;
    const parts = chainParts(n, []);
    if (!isStr(parts[0]) || parts.some((x) => skip.has(x))) continue;
    const lits = parts.filter(isStr), vars = parts.filter((x) => !isStr(x));
    if (!vars.length || vars.length > 6 || lits.some((l) => /[<>]/.test(l.value) || l.value.includes('{'))) continue;
    let k = 0;
    const template = parts.map((x) => (isStr(x) ? x.value : '{' + (++k) + '}')).join('');
    if (!textLike(template.replace(/\{\d\}/g, 'x'))) continue;
    const call = CALL + '(' + q(keyFor(template)) + ', ' + q(template) + vars.map((v) => ', ' + src.slice(v.range[0], v.range[1])).join('') + ')';
    add(n.range[0], n.range[1], call);
    parts.forEach((x) => done.add(x));
  }
  // 2. the literals
  for (const [n, p] of nodes) {
    if (!isStr(n) || skip.has(n) || done.has(n) || insideSkipped(n)) continue;
    const v = n.value;
    if (/[<>]/.test(v)) {
      const pieces = split(v);
      if (!pieces.some((x) => x.text !== undefined && textLike(x.text))) continue;
      const code = '(' + pieces.map((x) => (x.markup !== undefined ? q(x.markup) : (textLike(x.text) ? CALL + '(' + q(keyFor(x.text)) + ', ' + q(x.text) + ')' : q(x.text)))).join(' + ') + ')';
      add(n.range[0], n.range[1], code);
    } else if (textLike(v)) {
      add(n.range[0], n.range[1], CALL + '(' + q(keyFor(v)) + ', ' + q(v) + ')');
    }
  }
  return { src, rep, count };
}

// --sync: the table gets every T('key', 'text') of the files that it does not have yet (after the Lua side was redone, say)
if (args.includes('--sync')) {
  let added = 0;
  for (const file of FILES) {
    const code = fs.readFileSync(file, 'utf8');
    (function walk(n) {
      if (!n || typeof n.type !== 'string') return;
      if (n.type === 'CallExpression' && n.callee.type === 'Identifier' && n.callee.name === 'T' && n.arguments[1] && n.arguments[0].type === 'Literal' && n.arguments[1].type === 'Literal' &&
          !table.taken.has(n.arguments[0].value) && !newEntries.has(n.arguments[0].value)) { newEntries.set(n.arguments[0].value, n.arguments[1].value); table.taken.add(n.arguments[0].value); added++; }
      for (const k of Object.keys(n)) { const v = n[k]; if (Array.isArray(v)) v.forEach(walk); else if (v && typeof v === 'object') walk(v); }
    })(acorn.parse(code, { ecmaVersion: 2018, sourceType: 'script' }));
  }
  let s = fs.readFileSync(STRINGS, 'utf8');
  const nl = s.includes('\r\n') ? '\r\n' : '\n';
  const ei = s.indexOf(END);
  s = s.slice(0, ei) + [...newEntries].sort().map(([k, v]) => '  [' + luaQuote(k) + '] = ' + luaQuote(v) + ',' + nl).join('') + s.slice(ei);
  fs.writeFileSync(STRINGS, s);
  console.log(added + ' keys added to the table');
  process.exit(0);
}
let total = 0;
for (const file of FILES) {
  const r = run(file);
  const reps = r.rep.sort((a, b) => a.start - b.start || b.end - a.end).filter((x, i, arr) => !arr.slice(0, i).some((y) => y.start <= x.start && y.end >= x.end));
  total += reps.length;
  console.log(path.basename(file).padEnd(18), String(reps.length).padStart(5), audit || dry ? 'texts left in code' : 'texts moved');
  if (audit || dry || !reps.length) continue;
  let out = r.src;
  for (const x of reps.sort((a, b) => b.start - a.start)) out = out.slice(0, x.start) + x.code + out.slice(x.end);
  fs.writeFileSync(file, out);
}
if (!audit && !dry && newEntries.size) {
  let s = fs.readFileSync(STRINGS, 'utf8');
  const nl = s.includes('\r\n') ? '\r\n' : '\n';
  const ei = WW ? s.indexOf('}' + nl + nl + 'function M.t') : s.indexOf(END);
  s = s.slice(0, ei) + [...newEntries].sort().map(([k, v]) => '  [' + (WW ? q(k) + '] = ' + q(v) : luaQuote(k) + '] = ' + luaQuote(v)) + ',' + nl).join('') + s.slice(ei);
  fs.writeFileSync(STRINGS, s);
}
console.log('TOTAL', total, audit || dry ? 'texts still in code' : 'texts moved, ' + newEntries.size + ' new keys');
