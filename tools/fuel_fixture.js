// The Map app's gas stations with their price and the low-fuel line (hook slMap, sl/phone.lua mapPlaces with the Fuel range switch on), and the HUD record, for tools/phone_audit.js.
// _hook / _app: how the audit feeds and opens it. hud: what sl_fuelrange.hud(vid) answers in each level (sl/hud.lua puts it in the slHud payload; slHud.js draws it).
module.exports = {
  _hook: 'slMap', _app: 'map',
  groups: [
    { kind: 'gas', places: [
      { id: 'gas_1', name: 'Shell Station Highway 17', dist: 2100, info: 'from $1.45/L' },
      { id: 'gas_2', name: 'Valo Harbour Fuel and Service Depot', dist: 9300, info: 'from $1.45/L' },
    ] },
    { kind: 'dealer', places: [{ id: 'd1', name: 'Southside Motors', dist: 1500 }] },
  ],
  route: null,
  fuelNote: 'Low on fuel (about 35 km left). Nearest station: Shell Station Highway 17, 2.1 km.',
  hud: { ok: { range: 310, level: 'ok' }, low: { range: 35, level: 'low' }, critical: { range: 5, level: 'critical' }, empty: { range: 0, level: 'empty' } },
};
