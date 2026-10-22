// The free-roam Freight runs page's data contract as a fixture: what sl_frjobs.summary() hands the free-roam phone. tools/phone_audit.js uses it (_app is the page it shows).
// { offers = { { id, title, item, from, to, pay, seconds, metres } }, active = nil | { title, item, next, to, pay, leg (1 = to the pickup, 2 = to the drop) }, pay = 'who pays' }
module.exports = {
  _app: 'frjobs',
  pay: 'Wrench Works',
  offers: [
    { id: 'fr1', title: 'Tyre run', item: 'Four boxed tyres', from: 'Torres Tires', to: 'Belasco Auto', pay: 480, seconds: 420, metres: 5200 },
    { id: 'fr2', title: 'Rush parcel to the Extremely Long Name Industrial Garage Annex', item: 'A sealed crate of mixed engine parts for a customer', from: 'Fast Automotive', to: 'Industrial Garage', pay: 1260, seconds: 900, metres: 14800 },
  ],
  active: { title: 'Brake pad run', item: 'Two boxes of brake pads', next: 'Jerry Riggs', to: 'Smash Auto Repairs', pay: 640, leg: 1 },
};
