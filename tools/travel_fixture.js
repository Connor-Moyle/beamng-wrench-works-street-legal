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
// sl_series.hub() as a5 wrote it (sl/series.lua): the event, the standings (top 8 plus you), the schedule, the cars brought, whether Start works and why not; the trip's end day is on the phone's `visit`
const hub = {
  event: { id: 'utah-rally:3:r2', title: 'NGRC Utah Rally', mapName: 'Utah', series: 'utah-rally', round: 2, rounds: 4, rules: ['Stage times: fastest wins, 25-18-15 points.'], startHour: 10, status: 'ready' },
  standings: [
    { pos: 1, name: 'K. Ward', points: 25, you: false, time: '4:12.3' },
    { pos: 2, name: 'You', points: 18, you: true, time: '4:15.9' },
    { pos: 3, name: 'R. Santos', points: 15, you: false, time: '4:16.4' },
  ],
  schedule: [
    { day: 42, hour: 10, title: 'SS1 River', status: 'done' },
    { day: 43, hour: 10, title: 'SS2 Canyon', status: 'next' },
    { day: 44, hour: 10, title: 'SS3 River reverse', status: 'later' },
    { day: 45, hour: 10, title: 'SS4 Canyon reverse', status: 'later' },
  ],
  cars: [{ id: 1, name: 'Subaru Impreza GC8' }, { id: 2, name: 'Ibishu Pessima' }],
  canStart: true, startWhy: null, leaveNote: 'Go home now? The rounds you have not run count as missed.',
};
module.exports = { options, hub, visit: { level: 'utah', round: 2, rounds: 4, untilDay: 45 } };
