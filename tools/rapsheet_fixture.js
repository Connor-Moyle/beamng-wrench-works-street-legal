// The Rivals card with the file on the boss (hook slRivals, sl_rivals.list() with the Rap sheet switch on), for tools/phone_audit.js. _hook / _app: how the audit feeds and opens it.
module.exports = {
  _hook: 'slRivals', _app: 'me',
  rank: 2,
  sheet: { boss: 'r7', title: 'The file on Dante Ruiz', all: false, lines: [
    { text: 'Win 3 races at tier 2 or above', have: 3, need: 3, done: true },
    { text: 'Earn $900 in racing and jobs', have: 410, need: 900, done: false },
    { text: 'Beat 2 of the other named rivals', have: 1, need: 2, done: false },
  ] },
  rivals: [
    { id: 'r7', name: 'Dante Ruiz', tier: 2, boss: true, crew: 'Southside Kings', car: 'Covet GTS', meter: 20, word: 'neutral', beaten: 2, youLost: 1, stage: 1 },
    { id: 'r3', name: 'Mara Quinn', tier: 3, nemesis: true, crew: 'Riverbed Runners', car: 'Pickup V8', meter: -40, word: 'rivals', beaten: 0, youLost: 2, stage: 0, locked: 'Dante Ruiz' },
  ],
};
