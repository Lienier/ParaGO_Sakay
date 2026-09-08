// Raster previews for visual inspection; authoritative exports remain SVG/draw.io.
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
const source = path.join(root, 'artifacts/diagrams');
const target = path.join(root, 'artifacts/diagram-audit/corrected-previews');
fs.mkdirSync(target, { recursive: true });
(async () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(source, 'validation-all.json'), 'utf8'));
  for (const item of manifest) {
    await sharp(path.join(source, item.svg)).resize({ width: 1200 }).png().toFile(path.join(target, item.svg + '.png'));
  }
  console.log(`Rendered ${manifest.length} SVG previews.`);
  process.exit(0);
})().catch(error => { console.error(error.message); process.exit(1); });
