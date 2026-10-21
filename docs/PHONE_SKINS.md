# Phone skins

The phone can wear a skin: other colours and shapes, a colour and an icon for each app. Pick it in ESC > Mods > Street Legal > Screens and texts > Phone skin. **Classic** is the phone as it has always been and is the default; with it nothing from this page is loaded.

## What ships
- **Classic** (no folder: the phone itself).
- **Slate**: our own modern look. Squircle app tiles with a soft shine, outline icons drawn for every app, a pill-shaped camera island, a darker frame. It has no relation to any phone maker's design or icons.

## Your own skin
1. Copy `street_legal/phone_skins/_template/` from the mod (or the folder below) to the user folder: `<user folder>/settings/street_legal/phone_skins/<your id>/` (`<user folder>` is the one with your `settings` folder, e.g. `Documents/BeamNG/BeamNG.drive/current` or `%LOCALAPPDATA%/BeamNG/BeamNG.drive/current`). The folder name is the skin's id: lower-case letters, digits, `-` and `_`, up to 32 characters, and not `classic`.
2. Edit `skin.json` (all of it is optional, see below). Pictures go next to it.
3. Restart the game. The skin is in the Phone skin list. (A mod zip can ship a skin too: a folder `street_legal/phone_skins/<id>/skin.json` in the zip. If the user folder has the same id, the user folder wins.)

## skin.json
```json
{
  "id": "my_skin", "name": "My skin", "author": "You",
  "vars": { "frame": "#202020", "rim": "#444444", "screen": "#101010", "text": "#ffffff", "accent": "#ffcc00", "iconColor": "#ffffff",
            "frameRadius": 40, "screenRadius": 30, "iconRadius": 12, "iconSize": 26, "gloss": false, "tileShadow": false, "notch": "none" },
  "appColors": { "map": "#2a7f62" },
  "icons": { "map": { "path": "M12 21s-6.5-6-6.5-11a6.5 6.5 0 0 1 13 0c0 5-6.5 11-6.5 11z", "viewBox": "0 0 24 24", "stroke": 1.8 },
             "camera": { "file": "camera.svg" } }
}
```
- **vars**: colours are `#rgb` or `#rrggbb`. `frame` is the body of the phone, `rim` its edge, `screen` the screen background, `text` the text of the home screen, `accent` the small icons inside apps, `iconColor` the colour of outline icons on the tiles. `frameRadius` 0-70, `screenRadius` 0-60, `iconRadius` 0-40, `iconSize` 16-44 (px). `gloss: true` puts a soft shine on the app tiles, `tileShadow: true` a shadow under them. `notch: "pill"` draws a pill-shaped camera island (anything else: none).
- **appColors**: the tile colour of an app. App ids: `races garage garagekit bank me jobs wait help map camera gallery club turf carmarket partmarket phone messages contacts cab`. At most 40.
- **icons**: the same ids. An icon is a `path` (SVG path data in a 24x24 box, or another `viewBox`; filled, or an outline when `stroke` is set to a line width) or a `file` (an `.svg` or a `.png` in the skin folder, read through the game's own file system, so it also works from a mod zip). A png may be at most 256x256 pixels, any picture at most 64 KB, all pictures of a skin together at most 512 KB, and all icons together at most 300 KB. Icons that share a name with an inner icon of the phone (`map`, `camera`, `phone`, `bank`, ...) are used there too. At most 80.
- **There is no CSS field.** A skin cannot bring its own style: the look is made from the variables above by the mod, so a skin file cannot restyle or cover the rest of the game's screen, or load anything.

What is not valid is left out, with a line in the game's log (`phone skin ... ignored`). A skin that fails entirely is not in the list; the phone stays Classic. A skin.json over 64 KB is not read.

## Limits
- The list is read once at start: a new skin needs a restart. A change to a skin you already picked needs a restart too.
- Skins change the look only: no text, no layout, no behaviour.
- The bottom navigation icons (back, home, recent) keep their shapes in every skin.
