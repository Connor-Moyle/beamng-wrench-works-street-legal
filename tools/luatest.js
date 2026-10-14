// Runs tools/luatest.lua - the tests of the game rules in mod/lua/ge/extensions/sl/core - outside the game.
//   npm i fengari   (once, anywhere above this folder or globally)
//   node tools/luatest.js
// fengari is Lua 5.3; the rules are written to run the same there and in the game's LuaJIT.
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

const root = path.join(__dirname, '..');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const setup = `package.path = ${JSON.stringify(path.join(root, 'mod/lua/ge/extensions/?.lua').replace(/\\/g, '/'))} .. ';' .. package.path`;
if (lauxlib.luaL_dostring(L, to_luastring(setup)) !== lua.LUA_OK) throw new Error('setup failed');
const status = lauxlib.luaL_dofile(L, to_luastring(path.join(__dirname, 'luatest.lua')));
if (status !== lua.LUA_OK) {
  console.error(to_jsstring(lua.lua_tostring(L, -1)));
  process.exit(1);
}
