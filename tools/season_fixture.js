// The home championship's data contract as a fixture: what sl_season.summary() hands the phone (nil with no career or the part off; ab's season branch). The Series tab of the Calendar app shows it.
// { titles, trophies = { { title, season, day } }, purse, season = nil | { id, n, from, to (days), entered, canEnter, round (the next round number or nil), position,
//   next = { kind 'race'|'duel', title, day, eventId, done, missed, place, points } | nil, rounds = { six of that shape }, table = { { pos, name, points, you } } (top 8 and you) } }
// Action: sl_season.enter() -> ok, text.
const round = (kind, title, day, extra) => Object.assign({ kind, title, day, eventId: kind === 'race' ? 'race:dock-' + day : 'duel:' + day, done: false, missed: false, place: null, points: null }, extra || {});
const rounds = [
  round('race', 'Dockyards sprint', 41, { done: true, place: 2, points: 8 }),
  round('duel', 'Hill duel night, Saturday 21:00', 44, { done: true, place: 1, points: 10 }),
  round('race', 'Pier 6-lap race', 47, { missed: true }),
  round('race', 'Industrial circuit', 51),
  round('duel', 'Hill duel night, Saturday 21:00', 55),
  round('race', 'Belasco night finale', 58),
];
module.exports = {
  titles: 1, purse: 2000,
  trophies: [{ title: 'Home championship, season 1', season: 1, day: 40 }],
  season: {
    id: 'home:2', n: 2, from: 40, to: 58, entered: true, canEnter: false, round: 4, position: 2, next: rounds[3], rounds,
    table: [{ pos: 1, name: 'K. Ward', points: 26, you: false }, { pos: 2, name: 'You', points: 18, you: true }, { pos: 3, name: 'R. Santos', points: 15, you: false }, { pos: 4, name: 'Mia the Mechanic of the Pier Street Garage Crew', points: 9, you: false }],
  },
};
