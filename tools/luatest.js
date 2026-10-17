// Runs tools/luatest.lua - the tests of the game rules in mod/lua/ge/extensions/sl/core - outside the game.
//   npm i fengari   (once, anywhere above this folder or globally)
//   node tools/luatest.js
// fengari is Lua 5.3; the rules are written to run the same there and in the game's LuaJIT.
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

const root = path.join(__dirname, '..');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const lp = (p) => JSON.stringify(path.join(root, p).replace(/\\/g, '/'));
const setup = `package.path = ${lp('mod/lua/ge/extensions/?.lua')} .. ';' .. ${lp('mod/lua/common/?.lua')} .. ';' .. package.path`;
if (lauxlib.luaL_dostring(L, to_luastring(setup)) !== lua.LUA_OK) throw new Error('setup failed');
const status = lauxlib.luaL_dofile(L, to_luastring(path.join(__dirname, 'luatest.lua')));
if (status !== lua.LUA_OK) {
  console.error(to_jsstring(lua.lua_tostring(L, -1)));
  process.exit(1);
}
// undefined globals (a local helper used before it is defined, a typo): tools/globalcheck.js, which needs luaparse (npm i luaparse)
try { require.resolve('luaparse'); } catch (e) { console.log('globalcheck skipped: luaparse is not installed'); process.exit(0); }
const gc = require('child_process').spawnSync(process.execPath, [path.join(__dirname, 'globalcheck.js')], { encoding: 'utf8' });
process.stdout.write(gc.stdout || '');
if (gc.status !== 0) { console.error(gc.stderr || 'globalcheck failed'); process.exit(1); }
