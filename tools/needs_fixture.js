// The Health page's data contract as a fixture: what sl_needs.summary() hands the phone. tools/phone_audit.js uses it (_app is the page it shows); showMeters puts all three meters in the home pill.
// { meters = { { id food|water|rest, value 0..100, stage ok|handicap|problem, word } }, wellFed, effects = { blur, lag, tremor, sleepy }, items = { { id, name, price } }, canEat, canNap, showMeters }
module.exports = {
  _app: 'health',
  meters: [{ id: 'food', value: 72, stage: 'ok', word: 'fed' }, { id: 'water', value: 28, stage: 'handicap', word: 'parched' }, { id: 'rest', value: 9, stage: 'problem', word: 'exhausted' }],
  wellFed: false,
  effects: { blur: 0.3, lag: 0.05, tremor: 0.2, sleepy: true },
  items: [{ id: 'drink', name: 'Drink', price: 2 }, { id: 'meal', name: 'Meal with a very long name from the fuel station', price: 12 }],
  canEat: true, canNap: true, showMeters: true,
};
