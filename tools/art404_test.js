// SLRR's own art is not in the released pack: the UI must not ask for it unless the game side says it is there (otherwise every launch logs 404s).  node tools/art404_test.js
const fs = require('fs'), path = require('path'), assert = require('assert');
const root = path.join(__dirname, '..', 'mod');
const hud = fs.readFileSync(path.join(root, 'ui', 'modModules', 'slHud', 'slHud.js'), 'utf8');
const phone = fs.readFileSync(path.join(root, 'ui', 'modModules', 'slPhone', 'slPhone.js'), 'utf8');
const hudLua = fs.readFileSync(path.join(root, 'lua', 'ge', 'extensions', 'sl', 'hud.lua'), 'utf8');
const phoneLua = fs.readFileSync(path.join(root, 'lua', 'ge', 'extensions', 'sl', 'phone.lua'), 'utf8');
assert.ok(/hud\.settings\.art === true/.test(hud) && !/gauge: img\(/.test(hud), 'the HUD asks for SLRR pictures only when settings.art is true');
assert.ok(/new Image\(\)[^;]*;\s*made\[name\]\.src/.test(hud.replace(/\n\s*/g, ' ')) , 'the HUD makes an image once, on demand');
const startup = phone.slice(phone.indexOf("window.__slPhone = phone;"));
assert.ok(/data\.art !== true\) return;[\s\S]*probe\.src = '\/ui\/modModules\/slHud\/slrr\/icons\/cup\.png'/.test(startup) && !/var probe = new Image\(\);\s*probe\.onload = function \(\) \{ phone\.handle\('slArt'\); \};\s*probe\.src[^\n]*\n\s*\['slPhoneData'/.test(startup), 'the phone probes for the SLRR icons only when the data says the art is there');
assert.ok(/FS:fileExists\('\/ui\/modModules\/slHud\/slrr\/osd\.png'\)/.test(hudLua) && /settings\.art = slrrArt\(\)/.test(hudLua), 'the game side checks for the art once and sends it with the HUD settings');
assert.ok(/art = sl_hud ~= nil and sl_hud\.slrrArt/.test(phoneLua), 'and with the phone data');
console.log('art 404 test passed');
