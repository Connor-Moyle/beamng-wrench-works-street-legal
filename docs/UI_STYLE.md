# Street Legal and Wrench Works: UI style kit

Author: connor-9e (UI owner). One family for the phone, the laptop, the HUD, the shops and the Mods menu: dark, Material-3 flavoured, rounded, calm, readable at a glance on a pad. The values below are the ones the phone (`slPhone.js`) and the laptop (`slLaptop.js`) already use, measured from their CSS; new screens use these tokens, they do not invent colours. If a screen needs something this page does not have, add it here first.

## 1. Colour tokens

Define them as CSS custom properties on the module's root element, so a skin or a theme can replace them. The phone's literal values are the defaults.

| Token | Value | Use |
|---|---|---|
| `--sl-text` | `#e6e1e5` | text, prices, numbers |
| `--sl-text2` | `#cac4d0` | secondary text, captions |
| `--sl-muted` | `#938f99` | hints, disabled labels |
| `--sl-accent` | `#a8c7fa` | primary buttons, selected outline, links |
| `--sl-accent-l` | `#d3e3fd` | text on the tonal fills, light accent |
| `--sl-on-accent` | `#062e6f` on the default accent; for any other accent whichever of `--sl-deep` or `#ffffff` has the higher contrast (always at least 4.5:1) | text on an accent fill |
| `--sl-bad` | `#f2b8b5` | errors, losses, warnings (never alone: add ▼ or ⚠) |
| `--sl-good` | `#6dd58c` | gains, success (never alone: add ▲ or ✔) |
| `--sl-surface1` | `#141218` | app bar, page |
| `--sl-surface2` | `#211f26` | cards |
| `--sl-surface3` | `#2b2930` | raised cards, inputs |
| `--sl-outline` | `#49454f` | borders, dividers |
| `--sl-deep` | `#0d0b12` | the darkest background; text on light accents |
| `--sl-focus` | `#ffd54f` | the focus ring |

**Colour-blind mode** (option `slColorBlind`, sent in the data as `colorBlind`; the root toggles `*-cb`): good `#56b4e9`, bad `#ffb454`, and the marks are always drawn (`▲` gain, `▼` loss, `✔` ok), also without the mode. Colour is never the only carrier of meaning.

Contrast: body text at least 4.5:1 on its surface, large text and icons 3:1. A shop theme's accent is checked with the WCAG formula in its test (`tools/shoptest.js` does it for the built-in accents).

## 2. Type

Font stack: `"Segoe UI", "Roboto", "Noto Sans", sans-serif` (the HUD dials use "Overpass" for digits). Sizes in px as the phone uses them (the phone zooms the whole page with `--sl-zoom` for the text-size option, so never fix sizes in vw/vh): 12 caption, 13 body small, 14 body and button, 15 row title, 20 app bar title, 22 / 26 section numbers, 34 big figure (the balance). Weights 400 normal, 500 buttons and row titles, 300 only for cinematic titles. Line height 1.35.

Every player-facing string goes through `T('ui.some_words', 'the text', a, b)` (phone/laptop) or the strings table of the module (shops): no literal text in the code, so it can be translated and tested (`tools/strings_ui_test.js`).

## 3. Space, shape, elevation

Spacing 4 / 8 / 12 / 16 / 24 px (page gutter 16, card padding 14 x 16, list row min height 64, button height 40). Radii: 4 small chips, 10 fields, 16 / 18 cards and panels, 20 buttons (fully rounded), 24 big sheets, 46 the phone body. Elevation is a background step (`surface1` to `surface3`), a 1 px `--sl-outline` where two surfaces meet, and one soft shadow only on things that float over the game (`0 8px 30px rgba(0,0,0,.5)`).

## 4. Components

- **Button** (`.slp-btn`): 40 px high, radius 20, 14 px / 500. Filled (accent, `--sl-on-accent`) for the one primary action of a view; tonal (`#3a3f4b` fill, `#d7e3ff` text) for secondary; text (no fill, accent text) for tertiary; red (`#f2b8b5` fill, `#601410` text) for the destructive one. Disabled: 38 % opacity and no pointer events, and say why in a caption when the reason is not obvious. Every button is a real focusable element with `data-a` (the action) and `bng-nav-item` for the pad.
- **Card** (`.slp-card`): `surface2`, radius 18, padding 14 x 16, an `h4` title, then facts as `kv` rows (label left in `--sl-text2`, value right in `--sl-text`), then at most three buttons in a row (`.slp-acts`).
- **Row** (list item): 64 px, title 15 px and a 13 px caption, an amount at the right (`.slp-amt` with plus/minus classes: `▲` and `▼`), hover `rgba(255,255,255,.05)`.
- **Chip**: 12 px, radius 16, `rgba(255,255,255,.1)`.
- **Warning line**: `.slp-warn` with `⚠`, in `--sl-bad`.
- **Toast** (`slPhoneToast`): one line, 4 s, never blocks input; the game's own toastr for Wrench Works messages.
- **Page**: app bar (60 px, back arrow, title 20 px) then a scrolling body with `padding-bottom 12`, hidden scroll bar on the phone and a 6 px thin one on the laptop and the shops.
- **Focus**: every interactive element shows a **3 px `--sl-focus` ring at 2 px offset** on `:focus`, and where the control sits on a yellow or amber fill a 2 px `--sl-deep` band between the control and the ring so it still shows. Pad navigation follows `bng-nav-item` and the game's `ui_nav`; no element may be reachable only by mouse.

Shop and screen themes (`slShop`): a theme changes only the accent, the header pattern, the icon and the wording; layout, spacing, components and focus are the family's.

## 5. Motion

Motion tells the player what happened; it is never the only carrier of meaning and never slows an action down.

| Use | Duration | Easing |
|---|---|---|
| a control reacting (hover, press) | 120 ms | `ease-out` |
| a panel or sheet opening or closing, a list item appearing | 200 to 320 ms | `cubic-bezier(.2,.9,.25,1)` (the phone's) |
| the phone's turn out of the Maps app (K) | 420 ms in, 360 ms back | `cubic-bezier(.2,.9,.25,1)` in, `cubic-bezier(.4,0,.6,1)` out |
| a full-screen cinematic moment (night, day, ...) | 2.4 to 3.4 s, skippable after 0.4 s | opacity and transform only |

Rules: animate **only `opacity` and `transform`** (compositor properties: nothing that lays the page out again); no JavaScript timer per frame (CSS keyframes or the Web Animations API); a transition never blocks the next action (a press during it is applied when it ends, as the phone's K slide does); every animation has a **reduce-motion path**: the CSS media query `prefers-reduced-motion: reduce` **and** the career option `slReduceMotion` ("Reduce motion") both turn motion into an instant change or a short fade, and cinematic scenes into a still title card; and every cinematic scene can be skipped by any key or click. Proofs of motion are made frame by frame in headless Chrome (`tools/slide_proof.js`, `tools/scenes_proof.js`), not by eye.

## 6. Writing

Short, concrete, in the player's words; numbers with units (`$1,200`, `14 km`, `3 days`); no jargon; a refusal says why and what to do ("Clear your weekly debt first."). Titles in sentence case. No emoji except the marks above (`▲ ▼ ✔ ⚠`) and `★` for the active car.

## 7. Where each part lives

Phone `ui/modModules/slPhone/slPhone.js` (CSS at the top of the file), laptop `slLaptop.js`, HUD `slHud.js`, cinematic moments `slScenes.js`, shops `slShop.js` (connor-19). The Mods menu pages are the game's Vue components (`ui/ui-vue/mods/slrr_settings`, Wrench Works) and follow the game's own look; our pages put their groups, tooltips and notes in the registry (`slrr/settings.lua`). The Wrench Works garage screen is Angular (`ui/modules/apps/slrrGarage/app.js`) and keeps the same colours.

Tests that guard the family: `tools/phonetest.js`, `laptoptest.js`, `hudtest.js`, `strings_ui_test.js`, `shoptest.js`, `scenes_test.js`, and the contrast check in each theme's test.
