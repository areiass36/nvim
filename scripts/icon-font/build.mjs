// Build an icon-only TTF from Font Awesome SVGs. Usage: node build.mjs <map.json> <out.ttf> <font-awesome-solid-dir>
// (JetBrains Mono advance), scaled to 540 units and seated on the baseline.
import fs from "node:fs"; import path from "node:path"; import { Readable } from "node:stream";
import { SVGIcons2SVGFontStream } from "svgicons2svgfont"; import svg2ttf from "svg2ttf";
const [,, mapFile, outFile, svgDir] = process.argv;
if (!svgDir) { console.error("usage: node build.mjs <map.json> <out.ttf> <font-awesome-solid-dir>"); process.exit(1); }
const map = JSON.parse(fs.readFileSync(mapFile, "utf8")); // [{name, codepoint, icon}]
const font = new SVGIcons2SVGFontStream({ fontName: "ConfigIcons", fontHeight: 1000, descent: 250, normalize: false, log: () => {} });
let out = ""; font.on("data", d => out += d);
const done = new Promise((res, rej) => { font.on("end", res); font.on("error", rej); });
for (const { name, codepoint, icon } of map) {
  const raw = fs.readFileSync(path.join(svgDir, `${icon}.svg`), "utf8");
  const vb = raw.match(/viewBox="([^"]+)"/)[1].split(/\s+/).map(Number); const [vx, vy, vw, vh] = vb;
  const inner = raw.replace(/^[\s\S]*?<svg[^>]*>/, "").replace(/<\/svg>\s*$/, "").replace(/<!--[\s\S]*?-->/g, "");
  const size = 540, scale = size / Math.max(vw, vh);
  const tx = 30 + (size - vw * scale) / 2 - vx * scale, ty = 210 + (size - vh * scale) / 2 - vy * scale;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 1000" width="600" height="1000"><g transform="translate(${tx} ${ty}) scale(${scale})">${inner}</g></svg>`;
  const s = Readable.from([svg]); s.metadata = { unicode: [String.fromCodePoint(codepoint)], name }; font.write(s);
}
font.end(); await done;
fs.writeFileSync(outFile, Buffer.from(svg2ttf(out, { familyname: "ConfigIcons", subfamilyname: "Regular", version: "1.0" }).buffer));
console.log(`wrote ${outFile} with ${map.length} glyphs`);
