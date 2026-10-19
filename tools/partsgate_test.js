// Every extension of a part of the game that can be switched off carries its gate (sl/core/features): node tools/partsgate_test.js
const fs = require('fs'), path = require('path'), assert = require('assert');
const dir = path.join(__dirname, '..', 'mod', 'lua', 'ge', 'extensions', 'sl');
const parts = { spectators: 'spectators', billboards: 'billboards', ambience: 'ambience', puddlefx: 'puddles', achievements: 'achievements', tutorial: 'tutorial', classifieds: 'market', carauctions: 'market',
  rally: 'rally', races: 'races', drag: 'races', clubs: 'clubs', crews: 'crews', tow: 'tow', cab: 'cab', jobs: 'jobs', wwjobs: 'jobs' };
const feats = fs.readFileSync(path.join(dir, 'core', 'features.lua'), 'utf8');
for (const [file, id] of Object.entries(parts)) {
  const src = fs.readFileSync(path.join(dir, file + '.lua'), 'utf8');
  assert.ok(src.includes("require('sl/core/features').gate('" + id + "', M"), file + ' is gated as ' + id);
  assert.ok(/\nreturn M\s*$/.test(src), file + ' still ends with return M');
  assert.ok(feats.includes("id = '" + id + "'"), id + ' is in the list of parts');
}
// the career's map features and the phone's apps follow the switches
assert.ok(/PART_OF = \{[^}]*classifieds = 'market'/.test(fs.readFileSync(path.join(dir, 'career.lua'), 'utf8')), 'career.has follows the market, clubs and crews switches');
const phone = fs.readFileSync(path.join(dir, 'phone.lua'), 'utf8'), js = fs.readFileSync(path.join(__dirname, '..', 'mod', 'ui', 'modModules', 'slPhone', 'slPhone.js'), 'utf8');
for (const k of ['races', 'jobs', 'market']) assert.ok(phone.includes(k + " = require('sl/core/features').on('" + k + "')"), 'the phone data says whether ' + k + ' is on');
for (const a of ["has.races === false", "has.jobs === false", "has.market === false"]) assert.ok(js.includes(a), 'the phone hides an app: ' + a);
console.log('parts gate test passed (' + Object.keys(parts).length + ' extensions)');
