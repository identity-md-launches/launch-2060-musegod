/** Optional asset authoring. Normal site export only copies the committed SVGs and PNGs. */
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { pathToFileURL } from "node:url";
const sharp = (
  await import(
    process.env.MUSEGOD_SHARP
      ? pathToFileURL(process.env.MUSEGOD_SHARP).href
      : "sharp"
  )
).default;
const mascot = (await readFile("site/assets/musegod.svg", "utf8"))
  .replace(/^<svg[^>]*>/, "")
  .replace(/<\/svg>\s*$/, "");
const plush = (x, y, w = 310, rotate = 0) =>
  `<g transform="translate(${x} ${y}) rotate(${rotate} ${w / 2} ${w / 2}) scale(${w / 400})">${mascot}</g>`;
const caption = (lines, y = 70, color = "#fff", size = 38) =>
  lines
    .map(
      (line, i) =>
        `<text x="300" y="${y + i * (size + 8)}" fill="${color}" font-family="sans-serif" font-weight="700" font-size="${size}" text-anchor="middle">${line}</text>`,
    )
    .join("");
const star = (x, y, r = 12) =>
  `<path d="M${x} ${y - r}l${r * 0.28} ${r * 0.72} ${r * 0.72} ${r * 0.28}-${r * 0.72} ${r * 0.28}-${r * 0.28} ${r * 0.72}-${r * 0.28}-${r * 0.72}-${r * 0.72}-${r * 0.28} ${r * 0.72}-${r * 0.28}Z" fill="#FFD700"/>`;
const robot = (x, y) =>
  `<g transform="translate(${x} ${y})"><path d="M25 0v12" stroke="#fff" stroke-width="4"/><circle cx="25" cy="0" r="4" fill="#FFD700"/><rect x="0" y="12" width="50" height="45" rx="7" fill="#303030" stroke="#fff" stroke-width="2"/><circle cx="15" cy="31" r="4" fill="#FFD700"/><circle cx="35" cy="31" r="4" fill="#FFD700"/><path d="M12 46h26M6 70l38-38" stroke="#fff" stroke-width="3"/></g>`;
const designs = [
  [
    "worthy",
    `<circle cx="300" cy="300" r="200" fill="#202020" stroke="#666"/><path d="M380 164l30 30 62-67" stroke="#FFD700" stroke-width="15" fill="none" stroke-linecap="round" stroke-linejoin="round"/>${plush(120, 120, 330)}${caption(["Judged plush", "and found worthy."], 510, "#FFD700", 34)}`,
  ],
  [
    "cape",
    `${caption(["When the buy fee is 2%", "and the plush is 100%."], 65, "#fff", 32)}<path d="M155 370q-120-90-80-150 30 50 130 30Z" fill="#fff" stroke="#FFD700" stroke-width="3"/>${plush(145, 150, 340, -12)}${[0, 1, 2, 3, 4, 5].map((i) => `<ellipse cx="${75 + i * 87}" cy="${330 + Math.sin(i) * 150}" rx="15" ry="20" fill="#FFD700" transform="rotate(${i * 24} ${75 + i * 87} ${330 + Math.sin(i) * 150})"/>`).join("")}`,
  ],
  [
    "swarm",
    `${Array.from({ length: 16 }, (_, i) => plush(12 + (i % 4) * 145, 8 + Math.floor(i / 4) * 125, 125, i % 2 ? 6 : -6)).join("")}${caption(["Swarm, but make it holy."], 565, "#fff", 32)}`,
  ],
  [
    "blessed",
    `<ellipse cx="300" cy="280" rx="235" ry="185" fill="none" stroke="#666" stroke-dasharray="3 12"/>${plush(120, 100, 350)}${Array.from({ length: 14 }, (_, i) => star(60 + ((i * 47) % 500), 90 + ((i * 79) % 365), 7 + (i % 3) * 4)).join("")}${caption(["Every meme blessed", "by the plush."], 505, "#FFD700", 35)}`,
  ],
  [
    "bots",
    `${caption(["Launchbots freeze"], 65)}${plush(20, 100, 300, 7)}${robot(340, 270)}${robot(420, 270)}${robot(500, 270)}<path d="M333 370h225" stroke="#666" stroke-width="2"/>${caption(["when Musegod logs on."], 550, "#fff", 35)}`,
  ],
  [
    "throne",
    `${caption(["No roadmap. No plan.", "Eternal plush."], 60, "#fff", 35)}<path d="M145 510V195h310v315M130 500h340M175 215v260h250V215" stroke="#fff" stroke-width="9" fill="#202020"/><path d="M145 510L50 600h500l-95-90" fill="#000"/>${plush(130, 145, 330)}${star(300, 174, 22)}`,
  ],
  [
    "halo",
    `<ellipse cx="300" cy="310" rx="245" ry="200" stroke="#FFD700" stroke-width="2" fill="none"/><ellipse cx="300" cy="310" rx="205" ry="155" stroke="#666" stroke-width="2" fill="none"/>${plush(205, 195, 185)}${star(75, 180, 18)}${star(510, 420, 18)}${caption(["Small plush."], 65, "#fff", 42)}${caption(["Immense meme energy."], 550, "#FFD700", 34)}`,
  ],
  [
    "verdict",
    `<path d="M0 0h600v600H0Z" fill="#fff"/>${caption(["THE SWARM HAS SPOKEN"], 65, "#181818", 28)}<rect x="45" y="100" width="510" height="390" rx="195" fill="#181818"/>${plush(140, 106, 320)}<g transform="translate(380 370) rotate(-12)"><rect width="140" height="85" rx="8" fill="#FFD700" stroke="#181818" stroke-width="5"/><text x="70" y="54" text-anchor="middle" font-family="sans-serif" font-weight="700" font-size="30" fill="#181818">WORTHY</text></g>${caption(["Plush wins."], 555, "#181818", 46)}`,
  ],
];
await mkdir("site/assets/memes", { recursive: true });
for (const [slug, body] of designs) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600" viewBox="0 0 600 600"><rect width="600" height="600" fill="#181818"/>${body}</svg>`;
  await writeFile(`site/assets/memes/${slug}.svg`, svg);
  await sharp(Buffer.from(svg))
    .png({ compressionLevel: 9, palette: true, quality: 90 })
    .toFile(`site/assets/memes/${slug}.png`);
}
console.log(
  "Rendered eight original SVG compositions and their PNG downloads.",
);
