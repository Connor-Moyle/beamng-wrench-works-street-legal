// Moves the player-facing texts of the Lua modules into the strings table (#51), by the syntax tree (luaparse), so nothing but the text changes.
//   NODE_PATH=<qa>/node_modules node tools/strings_lua.js [--dry] [--audit] [files...]      (default: every .lua under mod/lua/ge/extensions/sl)
// A text is a string literal with a space and some letters that is not a key, not compared, not an argument of find/match/require/log...
// A literal becomes strings.t('module.some_words'); a chain  'a ' .. x .. ' b'  becomes strings.t('module.a_b', (x)) with the template 'a {1} b'.
// The texts go into sl/core/strings.lua between its BEGIN/END extracted markers. Run it again and again: it finds the inner texts of what it just
// wrapped, and stops when nothing is left. --audit only counts what is left (texts in code) and what is already in the table.
const fs = require('fs'), path = require('path');
const luaparse = require('luaparse');

const ROOT = path.join(__dirname, '..', 'mod', 'lua', 'ge', 'extensions', 'sl');
const STRINGS = path.join(ROOT, 'core', 'strings.lua');
const BEGIN = '  -- BEGIN extracted (tools/strings_extract.py)', END = '  -- END extracted';
const args = process.argv.slice(2);
const dry = args.includes('--dry'), audit = args.includes('--audit');
const only = args.filter((a) => !a.startsWith('--'));

// calls whose string arguments are never player-facing: names, patterns, paths, hooks, log lines
const SKIP_CALLS = new Set(['require', 'log', 'error', 'print', 'dump', 'dumps', 'find', 'match', 'gmatch', 'gsub', 'rep', 'hook', 'load', 'loadfile', 'dofile',
  'jsonReadFile', 'jsonWriteFile', 'readFile', 'writeFile', 'fileExists', 'directoryExists', 'directoryCreate', 'findFiles', 'removeFile', 'copyFile', 'findObject',
  'findClassObjects', 'getObject', 'setField', 'getField', 'queueLuaCommand', 'queueGameEngineLua', 'assert', 'rawget', 'rawset', 'setExtensionUnloadMode',
  'getCurrentLevelIdentifier', 'getModel', 'getConfigList', 'spawnNewVehicle', 'setGameState', 'setByName', 'createObject', 'registerObject', 'sendCmd', 'executeJS']);
const SKIP_FIRST = new Set(['trigger']);       // guihooks.trigger('event', { text = '...' }): the event name is skipped, the table is not

function textLike(v) {
  if (v.length < 6 || !/[A-Za-z]{3}/.test(v) || !v.includes(' ')) return false;
  if (/^[a-z0-9_\/.:-]+$/.test(v) || /\.(lua|json|png|jpg|dae|jbeam)\b/.test(v) || v.includes('{')) return false;
  if (/^Street Legal - /.test(v)) return false;            // (a file name, not a text)
  return /^[A-Z0-9('"$%]/.test(v) || /[.!?:,]/.test(v) || /%[dsf]/.test(v);
}

function unescape(raw) {
  // raw includes the quotes; the escapes the code uses
  const q = raw[0], body = raw.slice(1, -1);
  return body.replace(/\\(\d{1,3}|.)/g, (m, c) => (/^\d+$/.test(c) ? String.fromCharCode(Number(c)) : ({ n: '\n', t: '\t', r: '\r', '\\': '\\', "'": "'", '"': '"', a: '\x07' }[c] ?? c)));
}

function luaQuote(t) { return '"' + t.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n') + '"'; }
function slug(text, module, taken) {
  const words = (text.toLowerCase().match(/[a-z0-9]+/g) || ['text']).slice(0, 5).join('_');
  let key = module + '.' + words, n = 2;
  while (taken.has(key)) key = module + '.' + words + '_' + n++;
  return key;
}

function load() {
  const s = fs.readFileSync(STRINGS, 'utf8');
  const bi = s.indexOf(BEGIN), ei = s.indexOf(END);
  const byText = new Map(), taken = new Set();
  for (const m of s.matchAll(/\['([^']+)'\]|\["([^"]+)"\]\s*=\s*"((?:[^"\\]|\\.)*)"/g)) { if (m[1]) taken.add(m[1]); if (m[2]) taken.add(m[2]); }
  for (const m of s.slice(bi, ei).matchAll(/\["([^"]+)"\]\s*=\s*"((?:[^"\\]|\\.)*)",/g)) byText.set(m[2].replace(/\\(.)/g, (x, c) => (c === 'n' ? '\n' : c)), m[1]);
  return { s, byText, taken };
}

function files() {
  if (only.length) return only.map((f) => path.resolve(f));
  const out = [];
  (function walk(d) { for (const n of fs.readdirSync(d)) { const p = path.join(d, n); if (fs.statSync(p).isDirectory()) walk(p); else if (n.endsWith('.lua') && p !== STRINGS) out.push(p); } })(ROOT);
  return out.sort();
}

function visit(node, parent, key, f) {
  if (!node || typeof node !== 'object') return;
  if (Array.isArray(node)) { node.forEach((n, i) => visit(n, parent, key, f)); return; }
  if (node.type) { f(node, parent, key); }
  for (const k of Object.keys(node)) {
    if (k === 'range' || k === 'loc' || k === 'type') continue;
    const v = node[k];
    if (v && typeof v === 'object') visit(v, node, k, f);
  }
}

function calleeName(call) {
  const b = call.base;
  if (!b) return null;
  if (b.type === 'Identifier') return b.name;
  if (b.type === 'MemberExpression') return b.identifier.name;
  return null;
}

// one file: returns { src, changes: [{start,end,text}], texts: [{key,text}] }
function processFile(file, st) {
  const src = fs.readFileSync(file, 'utf8');
  let ast;
  try { ast = luaparse.parse(src, { luaVersion: '5.1', ranges: true, comments: false }); } catch (e) { console.log('skipped (does not parse for luaparse): ' + path.basename(file) + ': ' + e.message); return null; }
  const module = path.basename(file, '.lua');
  const rep = [];
  const skipNode = new Set();               // string literal nodes that are not texts here
  const chainsDone = new Set();
  // pass 1: mark literals that must stay (keys, compared, call arguments of the skipped calls)
  visit(ast, null, null, (n, p, k) => {
    if (n.type === 'TableKey' && n.key) skipNode.add(n.key);
    if (n.type === 'IndexExpression' && n.index) skipNode.add(n.index);
    if (n.type === 'BinaryExpression' && ['==', '~=', '<', '>', '<=', '>='].includes(n.operator)) { skipNode.add(n.left); skipNode.add(n.right); }
    if (n.type === 'CallExpression' || n.type === 'StringCallExpression' || n.type === 'TableCallExpression') {
      const name = calleeName(n);
      if (n.type === 'StringCallExpression' && n.argument) skipNode.add(n.argument);
      if (name && SKIP_CALLS.has(name)) (n.arguments || []).forEach((a) => skipNode.add(a));
      if (name && SKIP_FIRST.has(name) && n.arguments && n.arguments[0]) skipNode.add(n.arguments[0]);
    }
  });
  function flatten(n, out) { if (n.type === 'BinaryExpression' && n.operator === '..') { flatten(n.left, out); flatten(n.right, out); } else out.push(n); return out; }
  let count = 0;
  visit(ast, null, null, (n, p, k) => {
    if (n.type === 'BinaryExpression' && n.operator === '..' && !(p && p.type === 'BinaryExpression' && p.operator === '..')) {
      // a maximal concatenation chain
      const parts = flatten(n, []);
      const lits = parts.filter((x) => x.type === 'StringLiteral');
      if (parts.some((x) => skipNode.has(x)) || skipNode.has(n)) return;
      const vars = parts.filter((x) => x.type !== 'StringLiteral');
      const template = parts.map((x, i) => (x.type === 'StringLiteral' ? unescape(x.raw) : '{' + (parts.slice(0, i).filter((y) => y.type !== 'StringLiteral').length + 1) + '}')).join('');
      if (vars.length && vars.length <= 8 && lits.length && textLike(template.replace(/\{\d\}/g, 'x')) && !template.includes('\n')) {
        rep.push({ start: n.range[0], end: n.range[1], template, vars: vars.map((v) => src.slice(v.range[0], v.range[1])) });
        chainsDone.add(n);
        parts.forEach((x) => chainsDone.add(x));
        count++;
      }
      return;
    }
    if (n.type === 'StringLiteral' && !skipNode.has(n) && !chainsDone.has(n) && !(p && p.type === 'BinaryExpression' && p.operator === '..')) {
      const v = unescape(n.raw);
      if (textLike(v)) { rep.push({ start: n.range[0], end: n.range[1], template: v, vars: [] }); count++; }
    }
  });
  // literals inside a chain that is not a template (no variables or not enough text) but are texts on their own
  visit(ast, null, null, (n, p) => {
    if (n.type === 'StringLiteral' && !skipNode.has(n) && !chainsDone.has(n) && p && p.type === 'BinaryExpression' && p.operator === '..') {
      const v = unescape(n.raw);
      if (textLike(v)) { rep.push({ start: n.range[0], end: n.range[1], template: v, vars: [] }); count++; }
    }
  });
  return { src, rep, module };
}

const st = load();
let total = 0, filesChanged = 0;
const newEntries = new Map();
for (const file of files()) {
  if (/lua[\\/](vehicle|common)[\\/]/.test(file)) continue;
  if (/core[\\/]help\.lua$/.test(file)) continue;       // (the help pages are their own table, and docs/PLAYER_GUIDE.md is made from them)
  const r = processFile(file, st);
  if (!r) continue;
  // drop replacements inside another one
  const reps = r.rep.sort((a, b) => a.start - b.start || b.end - a.end).filter((x, i, arr) => !arr.slice(0, i).some((y) => y.start <= x.start && y.end >= x.end && y !== x));
  if (!reps.length) continue;
  total += reps.length;
  if (audit || dry) { console.log(path.basename(file).padEnd(22), String(reps.length).padStart(4), 'texts left in code'); continue; }
  let out = r.src;
  for (const x of reps.sort((a, b) => b.start - a.start)) {
    let key = st.byText.get(x.template);
    if (!key) { key = slug(x.template, r.module, new Set([...st.taken, ...newEntries.keys()])); st.byText.set(x.template, key); newEntries.set(key, x.template); }
    out = out.slice(0, x.start) + "strings.t('" + key + "'" + x.vars.map((v) => ', (' + v + ')').join('') + ')' + out.slice(x.end);
  }
  if (!/local strings = require\('sl\/core\/strings'\)/.test(out)) {
    const m = out.match(/^local M = \{\}[^\n]*\n/m);
    if (!m) { console.log('no "local M = {}" in ' + path.basename(file) + ': skipped'); continue; }
    out = out.slice(0, m.index + m[0].length) + "\nlocal strings = require('sl/core/strings')\n" + out.slice(m.index + m[0].length);
  }
  fs.writeFileSync(file, out);
  filesChanged++;
  console.log(path.basename(file).padEnd(22), String(reps.length).padStart(4), 'texts moved');
}
if (audit || dry) { console.log('TOTAL', total, 'texts still in code'); process.exit(0); }
if (newEntries.size) {
  let s = fs.readFileSync(STRINGS, 'utf8');
  const nl = s.includes('\r\n') ? '\r\n' : '\n';
  const ei = s.indexOf(END);
  const block = [...newEntries].sort().map(([k, v]) => '  [' + luaQuote(k) + '] = ' + luaQuote(v) + ',' + nl).join('');
  s = s.slice(0, ei) + block + s.slice(ei);
  fs.writeFileSync(STRINGS, s);
}
console.log(total + ' texts moved in ' + filesChanged + ' files, ' + newEntries.size + ' new keys');
