// The career travel screens' data contract as a fixture (docs/DESIGN_CAREER_TRAVEL.md sections 4 and 11): what the phone gets while a trip is planned or on.
// options = sl_series.options(eventId) (the pick-cars screen), hub = sl_series.hub() (the paddock, only while sl_career.visit() is set).
// Car ids may be strings or numbers: the phone compares and sends them as text, and phone.travelConfirm hands sl_series the ids exactly as these options listed them.
// The phone's tests and tools/phone_shots.js use it; sl_series' own test can check its results have these fields with these types.
const options = {
  eventId: 'utah-rally:3:r1', name: 'NGRC Utah Rally: SS1 River', place: 'Utah paddock', fee: 800, perCar: 200, hours: 6, max: 3, refuse: null,
  cars: [
    { id: 'c1', name: 'Subaru Impreza GC8', fits: true, why: null, report: 'Gravel tyres, rally springs' },
    { id: 2, name: 'Ibishu Pessima', fits: true, why: null, report: 'Road tyres: slow on gravel' },
    { id: 'c3', name: 'Civetta Bolide', fits: false, why: 'Too low for the stages', report: null },
  ],
  loaner: null,
};
const hub = {
  name: 'NGRC Utah Rally', place: 'Utah paddock', round: 2, rounds: 4, day: 42, untilDay: 44,
  standings: [
    { pos: 1, name: 'K. Ward', points: 25, you: false, time: '4:12.3' },
    { pos: 2, name: 'You', points: 18, you: true, time: '4:15.9' },
    { pos: 3, name: 'R. Santos', points: 15, you: false, time: '4:16.4' },
  ],
  next: { name: 'SS2 Canyon', when: 'Day 43 08:00', startable: true, why: null },
  cars: [{ id: 'c1', name: 'Subaru Impreza GC8' }, { id: 'c2', name: 'Ibishu Pessima' }],
};
module.exports = { options, hub, visit: { name: hub.name, round: hub.round, rounds: hub.rounds, untilDay: hub.untilDay } };
