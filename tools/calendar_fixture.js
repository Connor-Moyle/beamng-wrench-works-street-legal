// The Calendar's data contract as a fixture: what sl_calendar.summary() hands the phone (docs/DESIGN_CAREER_TRAVEL.md section 4). The phone's tests and the screenshot tool use it,
// and sl_calendar's own test can check its summary has these fields with these types. Event ids are kind:series-or-slot:cycle-number.
module.exports = {
  today: { day: 40, hour: 17.5, week: 6, dayOfWeek: 5 },
  events: [
    { id: 'weekend:dock-3:5', title: 'Dockyards 3-lap sprint', kind: 'weekend', day: 41, hour: 15, place: 'Belasco Dockyards', map: null, travel: { needed: false, fee: 0, hours: 0 }, series: null, status: 'open', reward: 800, requires: null, reminder: false, expiresIn: null },
    { id: 'utah-rally:3:r1', title: 'NGRC Utah Rally: SS1 River', kind: 'series', day: 42, hour: 8, place: 'Utah paddock', map: 'Utah', travel: { needed: true, fee: 800, hours: 6 }, series: { id: 'utah-rally:3', name: 'NGRC Utah Rally', round: 1, rounds: 4 }, status: 'open', reward: 'Purse by place, up to $3,000', requires: { label: 'A gravel or rally car', met: false }, reminder: true, expiresIn: 2 },
    { id: 'swap:meet:6', title: 'Swap meet', kind: 'weekend', day: 41, hour: 20, place: 'Pier lot', map: null, travel: { needed: false, fee: 0, hours: 0 }, series: null, status: 'entered', reward: null, requires: null, reminder: true, expiresIn: null },
    { id: 'race:dock-1:4', title: 'Dockyards night heat', kind: 'race', day: 38, hour: 21, place: 'Belasco Dockyards', map: null, travel: { needed: false, fee: 0, hours: 0 }, series: null, status: 'done', reward: 450, requires: { label: 'Any road car', met: true }, reminder: false, expiresIn: null },
    { id: 'jv-offroad:2:r2', title: 'Johnson Valley off-road, round 2', kind: 'series', day: 36, hour: 10, place: 'Johnson Valley', map: 'Johnson Valley', travel: { needed: true, fee: 600, hours: 5 }, series: { id: 'jv-offroad:2', name: 'Johnson Valley off-road', round: 2, rounds: 5 }, status: 'missed', reward: 1200, requires: null, reminder: false, expiresIn: null },
  ],
  series: [{ id: 'jv-offroad:2', name: 'Johnson Valley off-road', map: 'Johnson Valley', round: 2, rounds: 5, points: 17, rank: 3, nextDay: 44 }],
  invites: [{ id: 'inv:utah-rally:3', from: 'Benny', text: 'The NGRC Utah Rally starts on day 42. Entry $800. Bring a car for gravel.', eventId: 'utah-rally:3:r1', expiresIn: 2 }],
};
