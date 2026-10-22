// The trophy list's data contract as a fixture: what the phone and the garage computer get as `trophies` (a5's s.trophies, written at the win, newest last, capped at 40):
// { { name, kind = 'sprint' | 'invite' | 'series', day, place } }. The Street cred page of the phone and of the laptop show them, newest first. Nothing without the list.
module.exports = [
  { name: 'Dockyards 3-lap sprint', kind: 'sprint', day: 41, place: 1 },
  { name: 'Hirochi invitational', kind: 'invite', day: 49, place: 2 },
  { name: 'NGRC Utah Rally', kind: 'series', day: 58, place: 1 },
];
