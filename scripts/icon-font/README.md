# Icon font

`assets/fonts/ConfigIcons.ttf` is built from Font Awesome Pro SVGs (solid style). The SVGs are not in
this repository (Pro license); `assets/icons/map.json` lists, for each icon, its name, codepoint
(U+F600 onwards) and the Font Awesome icon name. `lua/core/icons.lua` mirrors the map.

```sh
cd scripts/icon-font && npm install
FONTAWESOME_SOLID=/path/to/fontawesome/solid npm run build
```

Every glyph is drawn in a 600x1000 box (JetBrains Mono's advance width), 540 units tall and seated on
the baseline, so it fills one terminal cell.
