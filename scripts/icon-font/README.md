# Icon font

`assets/fonts/ConfigIcons.ttf` is built from `assets/icons/*.svg` (Font Awesome Pro, solid style).
`assets/icons/map.json` assigns each SVG a codepoint from U+F600; `lua/core/icons.lua` mirrors it.

```sh
cd scripts/icon-font && npm install && npm run build
```

Every glyph is drawn in a 600x1000 box (JetBrains Mono's advance width), 540 units tall and seated on
the baseline, so it fills one terminal cell.
