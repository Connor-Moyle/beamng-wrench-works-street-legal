// The per-save economy offer (a5, SL 0.8.0): the phone snapshot's `economyOffer` is this text ONLY for a save from before the 0.8.0 economy, nil for a new career. One card on Street cred
// with one button, "Turn them on", which calls phone.economyOptIn -> sl_career.optInEconomy() (ok, text; the text is the toast); the card is gone at the next snapshot.
module.exports = { economyOffer: 'New in 0.8.0: weekly costs, service schedules, contracts and tier perks. Turn them on for this career?' };
