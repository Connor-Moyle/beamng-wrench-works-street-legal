// The My routes page's data contract as a fixture: what sl_myroute.summary() hands the phone. tools/phone_audit.js uses it (_app is the page it shows).
// { routes = { { id, name, points, length (m), best (s, 0 = never), bestText, runs, last, lastText } }, draft (points dropped), draftMin, draftMax, maxRoutes, run = { id, name, next, points, started, t, clock } or nil }
module.exports = {
  _app: 'myroute',
  routes: [
    { id: 1, name: 'Dock loop', points: 5, length: 4200, best: 61.5, bestText: '1:01.50', runs: 3, last: 65, lastText: '1:05.00' },
    { id: 2, name: 'Hill road of the Extremely Long Name Garage Crew', points: 8, length: 11800, best: 0, bestText: '--', runs: 0, last: 0, lastText: '--' },
  ],
  draft: 4,
  draftMin: 4,
  draftMax: 8,
  maxRoutes: 10,
};
