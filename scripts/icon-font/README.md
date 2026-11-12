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

Because the SVGs are Pro, a machine without that package cannot run the build at all -- not even to
add one icon, since every glyph is redrawn from its SVG into a new font. There, the committed
`assets/fonts/ConfigIcons.ttf` is the only copy of the glyphs that exists, and a name added to
`assets/icons/map.json` and `lua/core/icons.lua` without a rebuild renders as a missing-glyph box
wherever it is used. So adding an icon has to happen on a machine that has the Pro package, and the
rebuilt TTF is committed together with the two source edits.

On this machine the package is unpacked at `P:\Sandbox\Notes\fontawesome`, so the build runs as:

```sh
cd scripts/icon-font && node build.mjs ../../assets/icons/map.json ../../assets/fonts/ConfigIcons.ttf \
  P:/Sandbox/Notes/fontawesome/solid
```

The two files are each other's mirror and the font is the third copy: `tests/grip/unit_explorer.lua`
checks that every icon the database explorer draws is in the map under the codepoint `lua/core/icons.lua`
claims, which is the half of the mistake a test can catch. The other half -- a codepoint in the map with
no glyph behind it in the committed TTF -- only shows as a box in the terminal, so rebuild and commit the
TTF in the same change as the names.
