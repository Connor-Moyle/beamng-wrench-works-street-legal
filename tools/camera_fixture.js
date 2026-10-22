// The phone camera's data contract as a fixture: the phone snapshot's `camera` (the settings of the Camera app as a camera: first-person view on, hand sway 0..1, grid on, the bezel, the highest zoom).
// `_app` makes phone_audit open the Camera app with it.
module.exports = { firstPerson: true, sway: 0.5, grid: true, bezel: true, zoomMax: 4, _app: 'camera' };
