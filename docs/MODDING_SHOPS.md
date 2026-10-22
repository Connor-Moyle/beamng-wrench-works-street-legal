# Shops for map and mod makers

Street Legal draws every shop with one screen (`ui/modModules/slShop`) that changes its theme for each kind of shop: an accent colour, a header pattern, an icon and the wording. A map maker places a shop with a small JSON file; another mod opens one from Lua. Both need a Street Legal career running, and the Shops switch (ESC > Mods > Street Legal > Parts of the game > Shops) on.

## Kinds

| Kind | Screen | Goods |
|---|---|---|
| `tyre` | catalogue | the tyre ranges of Street Legal (`range`: `torres`, `race`, or all); buying fits the set on your car through Car Surface FX (it needs that mod) |
| `exhaust`, `parts`, `performance`, `dealerparts` | catalogue | parts that fit the player's car, read from Wrench Works (`slrr_garage.lookupParts`; Wrench Works 1.8.7 or later). Bought parts go on the shelf of the car's model. Give `stock` instead and the shop sells your own list |
| `accessories` | catalogue | the stock you give; without any, plates for $60 (eight texts) that are set on the car |
| `paint` | services | what the state of the player's car calls for (Car Surface FX): Wash ($15, when the car is dirty), Scratch polish ($80 light, $190 heavy), and a Respray in one of eight colours ($450: the car comes out clean and unscratched; the paint goes on through the game's vehicle colours). Give `services` instead and the shop sells your list |
| `tuner` | services | a Dyno run ($90): the car runs on the rollers through Wrench Works' vehicle side and the screen shows the peak power and torque and the curve. Needs Wrench Works |
| `diner` | catalogue | drinks, coffee, meals and a meal plan: the stock is the Needs part's (drink, coffee, meal, big meal; what each gives is shown), a sale is eaten and you sit down for twenty minutes of the clock (the clock may refuse in a race, on a job or with the police on you: you eat standing). Open day and night. Needs the Needs part, which is off by default |
| `motel` | services | a room for the night ($40): a full sleep, the clock runs on up to six hours (or to the end of the phase); refused when the clock may not move. Open day and night. Needs the Needs part |
| `mechanic` | services | the independent mechanic: your car's basic service and overhaul at 85% of the phone's price (an hour of the clock; refused in a race, on a job or with the police on you) and an Inspection ($40) that shows the car report. Give `services` instead and the shop sells your list |
| `carwash` | services | a wash ($15) for a dirty car, a wash and polish ($45; $25 with no scratches) for a dirty or scratched one (Car Surface FX). No wax: the mod has no call to slow the dirt |
| `junkyard` | catalogue | a second-hand pick (24 parts, a different pick each day) of the parts that fit the car, 35 to 65% off and worn (condition 0.3 to 0.7), one of each; they go on the shelf with their wear. The junkyard's lot gets a "Parts yard" button beside Look at the cars |

A mod can add its own kind with `sl_shops.define` (below).

## 1. Place a shop on a map

Put a file `street_legal_shops.json` in your level's folder (`/levels/<level>/`), or a `*.json` in `/street_legal/shops/` (a mod's own) or `/settings/street_legal/shops/` (the player's). A file can name its level (`"level": "west_coast_usa"`) and is then read on that level only:

```json
{ "shops": [
  { "kind": "exhaust", "name": "Pipe Dreams", "pos": [-310.2, 112.9, 24.1], "hours": "9-17",
    "keeper": "Rosa",
    "stock": [
      { "id": "cat_ss", "name": "Cat-back, stainless", "group": "Cat-back", "price": 420 },
      { "id": "hdr", "name": "Long-tube headers", "group": "Headers", "price": 560, "desc": "Hand-welded." },
      { "id": "cat_used", "name": "Cat-back, used", "group": "Cat-back", "price": 180, "cond": 0.55 }
    ] },
  { "kind": "paint", "name": "Spray Kings", "pos": [20, 40, 3.5], "accent": "#9b8cf0",
    "services": [ { "id": "buff", "name": "Buff out scratches", "price": 80, "minutes": 30 } ] }
] }
```

Fields (names are matched without case):

| Field | Meaning |
|---|---|
| `kind` | needed; one of the kinds above |
| `pos` | needed; `[x, y, z]` of the marker (it shows as a ring with a "Go in" button, like the laptops) |
| `name` | shop name on the screen (default: the kind's title) |
| `brand` | shown after the name, for a brand's counter |
| `hours` | `"9-17"` (24 h); without it the kind's usual hours apply (shops 08:00 to 18:00, dealers 09:00 to 17:00), shut at night |
| `keeper` | a name, or `{ "name": "Rosa", "line": "It should sound like a promise." }` |
| `accent` | `#rrggbb`; replaces the kind's accent colour (anything else is ignored) |
| `stock` | items: `id` (letters, digits, `_` `.` `-`), `name`, `price` (dollars), optional `group` (the category on the left), `desc`, `cond` (0..1; a used item is priced by its condition), `count` (how many there are) |
| `services` | rows with `id`, `name`, `price`, optional `minutes`, `desc` |
| `range` | tyre shops: `torres` or `race` |
| `sections` | catalogue shops: the Wrench Works chapters it sells, `"engine/exhaust"`, a whole section `"body"` or a chapter `"exhaust"` (the kind's own default when left out: an exhaust shop sells `exhaust`, a parts shop everything) |
| `brands` | catalogue shops: only parts of these brands (a dealer's counter) |
| `replaces` | the id of a Wrench Works parts counter (`torresTires`, `exhaustShop` ...) at this place: Wrench Works then leaves its own screen to this shop |
| `id` | a name for the shop (default: file and position in it) |

The shop's goods change a little each day (about a quarter of the lines are missing, the first four always stay), the price is the player's: reputation gives up to 8% off.
A shop that cannot be read is skipped and a line goes in the game's log (`sl_shops`).
A scene object cannot name a shop type yet; the file is the convention.

What a kind adds to the detail pane (all optional, per item or per service): `specs` = `[ { "label": "Sound", "text": "Loud", "bar": 0.7 } ]` (up to six rows; `bar` 0..1), `swatch` = `"#c0392b"` (a colour chip, for paint), `curve` = `[20, 55, 90, 125]` with `curveLabel` (a small line chart, for a dyno). Each kind also has its own words (the tagline under the name when there is no keeper, and the add and pay buttons: Choose these / Fit them for tyres, Book / Pay and book for services). The tyre shop fills its specs from Car Surface FX's compound rules (dry and wet grip, tread, working temperature, loose ground). The Reduce motion option (`slReduceMotion`) switches every transition off.

Stock and baskets: an item with no `count` can be bought in any quantity (the player's money is the limit); with a `count` the basket may not hold more than that, however many times the item is listed. A tyre shop sells one set at a time, and the card shows the price at the counter (the trade-in of the old set counted) when Car Surface FX is on, the set price ("before the trade-in") when it is not.

## 2. Open a shop from Lua

```lua
-- true, or false and the reason
local ok, why = sl_shops.open('exhaust', {
  name = 'Pipe Dreams', brand = 'Ibishu', keeper = { name = 'Rosa', line = 'Sounds like a promise.' },
  stock = { { id = 'cat_ss', name = 'Cat-back, stainless', group = 'Cat-back', price = 420 } },
  onBuy = function(lines, total)           -- optional; called after the money is taken; return false (or raise an error) and the money is given back
    -- lines = { { id, name, qty, each, sum } ... }
    return true
  end,
})
sl_shops.close()
```

`sl_shops.open(kind, opts)` takes the fields of section 1 (as a Lua table) plus `onBuy`; `pos` is optional and may be a vec3, `{ x, y, z }` or `{ x, y, z }` as a list (the shop closes when the player is 25 m away from it; without `pos` it stays open until closed). The player pays through the career (`sl_career.addMoney`); every sale also fires the extension hook, so a mod that does not own the shop can react:

```lua
function M.onStreetLegalShopBought(shopId, kind, lines, total) end
```

Map makers: stand where the shop should be and call `sl_shops.placeHere('tyre', 'Torres on 5th')` in the console; it writes a file under `settings/street_legal/shops/` at your position and the marker appears (delete the file to remove it). It is a tool: it works without a career and is not behind the Shops switch.

Other calls: `sl_shops.kinds()` (the kinds known), `sl_shops.isOpen()`, `sl_shops.placed()` (the shops from files), `sl_shops.define(kind, def)`.

### Price modifiers

`sl_shops.setPriceFactor(id, fn)` registers a function `fn(item, shop)` that returns a factor (1 = the price as it is, 0.8 = twenty per cent off); `fn = nil` removes it. `item` is the line as the shop shows it (`id`, `name`, `brand`, `price`, `group`...) and `shop` is `{ kind, name, brand }`. Several mods may register, each under its own `id`; the factors multiply. It is nil-safe: an error, or a result that is not a number, counts as 1, and the total factor is held between 0.05 and 3. It applies to the price shown (the list price is struck out) and to what is charged. Tyre shops charge their own counter price and ignore it.

## Giving a kind its stock and its sale (`sl_shops.provide`)

A shop placed from a file has no code of its own. A mod gives its kind what it sells and what a sale does with `sl_shops.provide(kind, { stock = function(shop) return lines, note end, services = function(shop) return lines, note end, buy = function(lines, total, shop) return ok end })`. `stock` fills a `given` shop whose file names no stock, `services` a `services` shop, and `buy` runs after the money is taken (return `false` and it is given back). The Needs part does this for the diner and the motel.

## Special orders (the performance shop)

The `performance` kind sells big hardware by special order: the player pays a deposit of 30% now, and the parts are put on the shelf of the car's model after 6 hours plus one hour for each $300 of the price (48 at most), when the balance is paid; if the money is not there yet the order waits and a text says so once. The orders are kept in the career save (`shopOrders`, additive; a save without it starts empty) and the shop screen lists them with the hours to go. Other catalogue kinds can be special-order shops too: pass `order = true` to `sl_shops.open`. An order is delivered whatever the Shops switch says (it is the player's money). If the shelf fails, the balance is given back and it is tried again after a wait that grows (1, 2, 4 minutes, at most 10), with one text. Without the garage mod nothing can be delivered, and a week after its time the deposit is given back with a text. A dyno run that gets no answer from the garage mod's vehicle side within 20 seconds is refunded. Not done: the car does not go away for the build.

For services, a mod that opens a `services` shop with its own `services` and an `onBuy` gets the usual flow (pay, then `onBuy`); a shop with neither gets the built-in jobs of its kind.

## Dealers: the parts counter

A dealer whose sign shows car brands gets a second button next to "Look at the cars": **Parts counter (Bruckell, Gavril, Ibishu)**. The brands are in `/street_legal/shops/dealer_brands.json`: `{ "<level>": { "<place id, stock id or place name>": [ "Brand", ... ] } }`. The counter lists the parts of those brands that fit the car you drive (the maker's parts from Wrench Works' catalogue, branded by `slrr_brands`); when none fits it says so, with your car and the brands. Bought parts go on the shelf of the car's model at your garage. On West Coast USA, Jefferson Motors has Bruckell, Gavril and Ibishu and Belasco Auto Ibishu and Gavril (read from the brand flags standing at their lots in the level's files).

## 3. Add your own kind

```lua
sl_shops.define('exhaustplus', {
  title = 'Exhaust Plus', goods = 'given', screen = 'catalogue', hours = 'shop',
  theme = { accent = '#ff7a00', pattern = 'pipes', icon = 'exhaust' },
})
```

`goods`: `given` (the opener's `stock`), `services`, `catalog` or `tyres`. `screen`: `catalogue` or `services`. `pattern`: `tread`, `pipes`, `grid`, `chevrons`, `spray`, `dyno`, `bolts`, `stripes`, `badge`. `icon`: `tyre`, `exhaust`, `wrench`, `engine`, `paint`, `gauge`, `spanner`, `star`, `badge`. A built-in kind cannot be replaced. The layout, colours of text and surfaces, focus ring and pad controls are the same for every kind on purpose; a theme changes only the accent, the pattern, the icon and the wording.

## What is not here yet

- Parts for the player's car (the exhaust shop, the parts shop, the dealer's brand counter) need a catalogue of the car's slots from Wrench Works; until then a `catalog` shop shows a note unless `stock` is given.
- Shopkeepers as people on the map (needs Drivers & Pedestrians), a shop's day-to-day favour, delivery to the shelf and the phone's Map pins.
