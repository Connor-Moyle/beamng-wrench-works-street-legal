# Factory order at dealers (C3)

**What:** besides the cars standing on its lot, a dealer takes orders for new cars from the game's own catalogue: pick a model the dealer sells, pick a trim, see only what the factory offers, pay the config's price, and the car is delivered.

**Catalogue.** The dealer's pool (`lot.poolOf(place)`: the stock dealer's filter over `carBuilder.configs()`, police/service/race cars and excluded models already out) grouped by `model`; each model's entries are its trims (the factory `.pc` configs), sorted by value. Only high-end dealers get it first (`lot.tier(place) == 'high'`); any dealer can be switched on by one tier test. Pure grouping and sorting live in `sl/core/factory.lua` (luatest).

**Spec screen (factory options only).** Read from the trim's `.pc` file (`jsonReadFile(c.config)`): `parts` (slot -> stock part), shown by section with `partinfo.displayName`; the colours are the model's own paints (`core_vehicles.getModel(model).model.paints`). Nothing else can be changed: no part swaps, no tuning. The chosen colour only sets `paints` of the spawn config. Price = the config's `value`, no markup, no haggling; always a new car (condition 1, no faults, 0 km).

**Buying.** `sl_lot.orderFactory(modelKey, configIndex, paintName)` checks the money, charges it (`sl_career.addMoney`), and queues `{ model, config, paint, name, price, dueHour }` in `s.factoryOrders` (saved). Delivery time `DELIVERY_HOURS = 6` game hours (so the order rides on the career clock like the classifieds' deliveries). The dealer texts when it is placed and when the car is ready.

**Delivery.** When due, a job spawns the `.pc` at the garage forecourt (`sl_fleet.forecourt`) with `carBuilder.spawn`, registers it with `sl_fleet.registerVehicle(vid, {name, brand, value, condition = 1, price})` (that records the full parts tree, so the later `sl_fleet.deliver`/`spawnOwned` paths work as for any bought car), and toasts. If the garage forecourt is not available (no garage yet) the order waits. This does not touch `carBuilder` internals; it only calls `spawn` and `configs`.

**UI.** The lot card gets a second button, "Order from the factory" (high-end dealers); it opens a catalogue list, then the spec screen with a Buy button. Gamepad: same focus rules as the lot card; B goes back a step. Strings in `strings.lua`.

**Not in this step:** orders at mid/low dealers, delivery to the lot instead of the garage, cancelling an order, custom colours.
