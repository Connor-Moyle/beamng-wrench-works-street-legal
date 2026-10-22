// The Rivals cards' data contract as a fixture: the 'slRivals' guihook (sl_rivals.list()). tools/phone_audit.js feeds it through _hook and shows the Street cred page that carries the cards.
// { rank, rivals = { { id, name, tier, boss, crew, car, meter, word, beaten, youLost, locked, offer = { stake, myCar, theirCar, hunt = 'car they want back', sweetener = money on top } } } }
module.exports = {
  _hook: 'slRivals',
  _app: 'me',
  rank: 2,
  rivals: [
    { id: 'r05', name: 'Viktor "Nitro" Halasz of the Ring Road Ghosts', tier: 4, boss: true, crew: 'Ring Road Ghosts', car: 'Covet "Dodger" with a very long name', meter: -80, word: 'blood', beaten: 3, youLost: 1,
      offer: { stake: 'pink', myCar: 'Covet 1.5 Sport', theirCar: 'Scintilla Prestige Coupe', hunt: 'Covet 1.5 Sport', sweetener: 1500 } },
    { id: 'r02', name: 'Mina Ortiz', tier: 1, boss: false, crew: 'Pier Street', car: 'Pessima', meter: 10, word: 'neutral', beaten: 0, youLost: 0,
      offer: { stake: 'pink', myCar: 'Pessima', theirCar: 'Bolide' } },
  ],
};
