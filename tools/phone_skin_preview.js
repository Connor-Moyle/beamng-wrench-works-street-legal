// Draws the phone's home screen with each phone skin of the mod (and the classic look) side by side as a page, to look at in a browser:
//   node tools/phone_skin_preview.js out.html [skin.json ...]      (needs jsdom and fengari; with no skin files it uses the skins the mod ships)
// The skin goes through the real checks (sl/core/phoneskin) and the real phone (slPhone.js), so what shows is what the game would show.
const fs = require('fs'), path = require('path');
const { JSDOM } = require('jsdom');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

const root = path.join(__dirname, '..');
const code = fs.readFileSync(path.join(root, 'mod/ui/modModules/slPhone/slPhone.js'), 'utf8');
const out = process.argv[2] || 'phone_skins.html';
let files = process.argv.slice(3);
if (!files.length) {
  const dir = path.join(root, 'mod/street_legal/phone_skins');
  files = fs.readdirSync(dir).filter((d) => !d.startsWith('_') && fs.existsSync(path.join(dir, d, 'skin.json'))).map((d) => path.join(dir, d, 'skin.json'));
}

// the Lua checks, run on a skin.json: the payload as JSON
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const lit = (v) => Array.isArray(v) ? '{' + v.map(lit).join(',') + '}' : (v && typeof v === 'object') ? '{' + Object.keys(v).map((k) => '[' + JSON.stringify(k) + ']=' + lit(v[k])).join(',') + '}' : (typeof v === 'string' ? JSON.stringify(v) : String(v));
lauxlib.luaL_dostring(L, to_luastring(`package.path = ${JSON.stringify(path.join(root, 'mod/lua/ge/extensions/?.lua').replace(/\\/g, '/'))} .. ';' .. package.path`));
function payload(file) {
  const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
  const src = `local PS = require('sl/core/phoneskin')
    local s, why = PS.validate(${lit(raw)}, ${JSON.stringify(path.basename(path.dirname(file)))}, function() return nil end)
    if not s then error(tostring(why)) end
    local function q(x) return '"' .. x:gsub('\\\\', '\\\\\\\\'):gsub('"', '\\\\"'):gsub('\\n', '\\\\n') .. '"' end
    local function map(t) local o = {} for k, v in pairs(t) do o[#o + 1] = q(k) .. ':' .. q(v) end return '{' .. table.concat(o, ',') .. '}' end
    return '{"id":' .. q(s.id) .. ',"css":' .. q(s.css) .. ',"appColors":' .. map(s.appColors) .. ',"icons":' .. map(s.icons) .. '}'`;
  if (lauxlib.luaL_dostring(L, to_luastring(src)) !== lua.LUA_OK) throw new Error(file + ': ' + to_jsstring(lua.lua_tostring(L, -1)));
  const json = to_jsstring(lua.lua_tostring(L, -1));
  lua.lua_pop(L, 1);
  return JSON.parse(json);
}

const data = { active: true, hour: 21, minute: 30, day: 4, mapName: 'West Coast', rep: 120, money: 5400, has: {}, unread: {}, threads: {}, challenges: [], places: [], night: true };
// one page per phone (a skin's style is for the whole page, so the phones cannot share one)
[null].concat(files).forEach((file) => {
  const dom = new JSDOM('<!doctype html><html><body></body></html>', { runScripts: 'outside-only' });
  dom.window.__slPhoneTest = true;
  dom.window.eval(code);
  const p = dom.window.__slPhoneCreate(dom.window.document, () => {}, { now: () => 0, set: () => ({}), clear: () => {} });
  p.handle('slPhoneData', data);
  if (file) p.handle('slPhoneSkin', payload(file));
  p.handle('slPhoneToggle');
  p.act('home');
  const device = p.root.querySelector('.slp-device');
  device.style.cssText = 'position:relative;right:auto;bottom:auto;transform:none;display:block;margin:16px auto';
  const styles = Array.from(p.root.querySelectorAll('style')).map((e) => e.textContent).join(String.fromCharCode(10));
  const page = '<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0;background:#4a4a52}' + styles + '.slp-root{position:static}</style></head><body><div class="slp-root" style="position:static;pointer-events:auto">' + device.outerHTML + '</div></body></html>';
  const name = out.replace(/\.html$/, '') + '_' + (file ? path.basename(path.dirname(file)) : 'classic') + '.html';
  fs.writeFileSync(name, page);
  console.log('wrote ' + name);
});
process.exit(0);
