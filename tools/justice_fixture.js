// The police pages' data contract as a fixture: what sl_justice.summary() hands the phone (nil with no career or the part off), police batch 2 (ab).
// tickets: { { id, day, amount, due (a day), paid, contested, overdue } }, suspended (the licence), lawyerFee, wanted = { car, model, bounty, since (a day), days, informant (a crew perk), informantPrice } or nil,
// impound = { car, carId, owed, place, standing } or nil. Actions, each answering ok, text: sl_justice.payTicket(id), contestTicket(id), informant().
module.exports = {
  tickets: [
    { id: 't1', day: 38, amount: 120, due: 45, paid: false, contested: false, overdue: false },
    { id: 't2', day: 33, amount: 300, due: 40, paid: false, contested: false, overdue: true },
    { id: 't3', day: 36, amount: 80, due: 43, paid: false, contested: true, overdue: false },
    { id: 't4', day: 30, amount: 60, due: 37, paid: true, contested: false, overdue: false },
  ],
  suspended: true,
  lawyerFee: 150,
  wanted: { car: 'c9', model: 'Covet 1.5', bounty: 2400, since: 39, days: 2, informant: true, informantPrice: 900 },
  impound: { car: 'Pessima', carId: 8, owed: 450, place: 'Belasco police impound', standing: true },
};
