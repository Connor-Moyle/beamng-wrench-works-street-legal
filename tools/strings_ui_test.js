// Every T('key', 'fallback') of the phone and the laptop has its key in sl/core/strings.lua, with the same text as the fallback (so the table and the code
// agree), and strings.lua has no key twice. Needs fengari:  node tools/strings_ui_test.js
const fs = require('fs'), path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const root = path.join(__dirname, '..');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const file = path.join(root, 'mod/lua/ge/extensions/sl/core/strings.lua').split(path.sep).join('/');
const probe = `
local S = dofile(${JSON.stringify(file)})
local out = {}
for k, v in pairs(S.TEXT) do out[#out + 1] = k .. string.char(1) .. v end
return table.concat(out, string.char(2))
`;
if (lauxlib.luaL_dostring(L, to_luastring(probe)) !== lua.LUA_OK) { console.error(to_jsstring(lua.lua_tostring(L, -1))); process.exit(1); }
const table = new Map(to_jsstring(lua.lua_tostring(L, -1)).split('\x02').map((p) => p.split('\x01')));
// no key twice in the file
const src = fs.readFileSync(path.join(root, 'mod/lua/ge/extensions/sl/core/strings.lua'), 'utf8');
const seen = new Set(), dup = [];
for (const m of src.matchAll(/^\s*\[(?:'([^']+)'|"([^"]+)")\]\s*=/gm)) { const k = m[1] || m[2]; if (seen.has(k)) dup.push(k); seen.add(k); }
if (dup.length) { console.error('keys twice in strings.lua: ' + dup.join(', ')); process.exit(1); }
const acorn = require('acorn');
let asked = 0;
const problems = [];
for (const f of ['slPhone/slPhone.js', 'slLaptop/slLaptop.js']) {
  const code = fs.readFileSync(path.join(root, 'mod/ui/modModules', f), 'utf8');
  (function walk(n) {
    if (!n || typeof n.type !== 'string') return;
    if (n.type === 'CallExpression' && n.callee.type === 'Identifier' && n.callee.name === 'T' && n.arguments[0] && n.arguments[0].type === 'Literal' && typeof n.arguments[0].value === 'string') {
      asked++;
      const key = n.arguments[0].value, fb = n.arguments[1] && n.arguments[1].type === 'Literal' ? n.arguments[1].value : null;
      if (!table.has(key)) problems.push(f + ': ' + key + ' is not in the table');
      else if (fb !== null && table.get(key) !== fb) problems.push(f + ': ' + key + ' says "' + fb + '" in the code and "' + table.get(key) + '" in the table');
    }
    for (const k of Object.keys(n)) { const v = n[k]; if (Array.isArray(v)) v.forEach(walk); else if (v && typeof v === 'object') walk(v); }
  })(acorn.parse(code, { ecmaVersion: 2018, sourceType: 'script' }));
}
if (problems.length) { console.error(problems.slice(0, 20).join('\n')); process.exit(1); }
console.log('strings ui test passed: ' + asked + ' texts of the phone and the laptop, all in the table, none twice');
