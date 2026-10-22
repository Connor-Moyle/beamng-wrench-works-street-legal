// The data of the Camera app's photo challenge list (hook slPhotoChallenges, sl_photos.challenges()), for tools/phone_audit.js. _hook / _app: how the audit feeds and opens it.
module.exports = {
  _hook: 'slPhotoChallenges', _app: 'camera',
  on: true, title: 'Photo challenges',
  list: [
    { id: 'w3_1', text: 'Photograph your red car under 120 hp at the Pier at sunset.', pays: 'pays $310, 3 rep', done: false },
    { id: 'w3_2', text: 'Photograph your car at night.', pays: 'pays $130, 1 rep', done: true },
    { id: 'w3_3', text: 'Photograph your blue car over 200 hp at Harbour Marina Cruise Meet in daylight.', pays: 'pays $400, 3 rep', done: false },
  ],
};
