// The Turf app's data contract as a fixture: what sl_crews.summary() hands the phone, with the turf income lines (docs/TURF_INCOME_PLAN.md). tools/phone_audit.js uses it (the key is the data's name).
// { held, turfWar, income (next payout, nil with the Turf income part off), districts = { { id, name, owner, yours, crew, control, home, here, cut (a week, yours only), base, x, y } }, crews = { { name, leader } }, you = { x, y } }
module.exports = {
  held: 3,
  turfWar: false,
  income: 350,
  districts: [
    { id: 'd1', name: 'Belasco City', owner: 'You', yours: true, control: 100, cut: 150, base: true, here: true, x: 0, y: 0 },
    { id: 'd2', name: 'Alder Dragway of the Extremely Long Name Garage Crew', owner: 'You', yours: true, control: 80, cut: 80, x: 900, y: 200 },
    { id: 'd3', name: 'Industrial', owner: 'You', yours: true, control: 100, cut: 0, x: -700, y: 500 },
    { id: 'd4', name: 'Quarryside', owner: 'the Ring Road Ghosts', crew: 'ringroad', control: 60, home: 'the Ring Road Ghosts', x: 300, y: -900 },
    { id: 'd5', name: 'Riverbed', owner: 'the Riverbed Runners', crew: 'riverbed', control: 75, x: -400, y: -600 },
  ],
  crews: [{ name: 'the Ring Road Ghosts', leader: 'Nina' }, { name: 'the Riverbed Runners', leader: 'Tomas' }],
  you: { x: 10, y: 10 },
};
