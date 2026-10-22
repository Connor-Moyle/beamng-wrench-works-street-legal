// The Inventory page's data contract as a fixture: what sl_inventory.summary() hands the phone (docs/INVENTORY.md). The phone's tests and tools/phone_audit.js use it.
// { used, cap, groups = { { kind = 'item' | 'can' | 'tool' | 'part', name, count, points, extra } } }; extra: item { id }, can { index, litres, size }, tool { id, uses (nil = unlimited) }, part { id, model, brand, wear }.
module.exports = {
  _app: 'inventory',
  used: 14,
  cap: 28,
  groups: [
    { kind: 'item', name: 'Engine oil', count: 2, points: 2, extra: { id: 'oil' } },
    { kind: 'item', name: 'Car battery', count: 1, points: 2, extra: { id: 'battery' } },
    { kind: 'can', name: '10 L jerry can', count: 1, points: 2, extra: { index: 1, litres: 4, size: 10 } },
    { kind: 'tool', name: 'bypass', count: 2, points: 2, extra: { id: 'bypass', uses: 13 } },
    { kind: 'part', name: 'Sport exhaust of the Extremely Long Name Garage Crew', count: 1, points: 3, extra: { id: 4, model: 'covet', brand: 'Ibishu', wear: 0.35 } },
    { kind: 'part', name: 'Big intake', count: 1, points: 2, extra: { id: 5, model: 'covet', brand: 'Zephyrin', wear: 0 } },
  ],
};
