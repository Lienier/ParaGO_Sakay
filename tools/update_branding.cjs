// Reuse the supplied artwork. Only transparent padding and platform sizing vary.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
const source = path.resolve(process.argv[2] || path.join(root, 'parago_mobile/assets/images/sakay_logo.png'));
const projects = ['parago_mobile', 'parago_passenger', 'parago_admin_web'];
const output = path.join(root, 'artifacts/logo_rebuild_2026-10-07');
const hash = buffer => crypto.createHash('sha256').update(buffer).digest('hex');
const background = { r: 248, g: 244, b: 234, alpha: 1 };

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const original = fs.readFileSync(source);
  fs.writeFileSync(path.join(output, 'supplied_logo.png'), original);
  const trimmed = await sharp(original).trim({ threshold: 0 }).png().toBuffer();
  const changed = [];
  async function write(relative, buffer) {
    const destination = path.join(root, relative);
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.writeFileSync(destination, buffer);
    const metadata = await sharp(buffer).metadata();
    changed.push({ path: relative, sha256: hash(buffer), width: metadata.width, height: metadata.height });
  }
  async function square(size, fraction, opaque = false) {
    const artwork = await sharp(trimmed).resize({ width: Math.round(size * fraction), height: Math.round(size * fraction), fit: 'inside' }).png().toBuffer();
    return sharp({ create: { width: size, height: size, channels: 4, background: opaque ? background : { r: 0, g: 0, b: 0, alpha: 0 } } })
      .composite([{ input: artwork, gravity: 'centre' }]).png().toBuffer();
  }
  for (const project of projects) {
    // Exact supplied PNG, including alpha: existing Flutter asset references work unchanged.
    await write(`${project}/assets/images/sakay_logo.png`, original);
    if (project === 'parago_admin_web') await write(`${project}/assets/images/SakayLogo.png`, original);
    await write(`${project}/web/favicon.png`, await square(64, 0.96));
    for (const size of [192, 512]) {
      await write(`${project}/web/icons/Icon-${size}.png`, await square(size, 0.9));
      // Keep all artwork inside the maskable icon's central safe circle.
      await write(`${project}/web/icons/Icon-maskable-${size}.png`, await square(size, 0.62, true));
    }
    const res = `${project}/android/app/src/main/res`;
    for (const [density, size] of Object.entries({ mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 })) {
      await write(`${res}/mipmap-${density}/ic_launcher.png`, await square(size, 0.78, true));
    }
    await write(`${res}/drawable/sakay_splash.png`, await sharp(trimmed).resize({ width: 240 }).png().toBuffer());
    await write(`${res}/drawable/sakay_splash_android12.png`, await square(864, 0.54));
    const xml = `<?xml version="1.0" encoding="utf-8"?>\n<layer-list xmlns:android="http://schemas.android.com/apk/res/android">\n    <item android:drawable="@color/sakay_splash_background" />\n    <item>\n        <bitmap android:gravity="center" android:src="@drawable/sakay_splash" />\n    </item>\n</layer-list>\n`;
    for (const folder of ['drawable', 'drawable-v21']) fs.writeFileSync(path.join(root, res, folder, 'launch_background.xml'), xml);
    fs.writeFileSync(path.join(root, res, 'values', 'colors.xml'), '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="sakay_splash_background">#F8F4EA</color>\n</resources>\n');
    const v31 = path.join(root, res, 'values-v31');
    fs.mkdirSync(v31, { recursive: true });
    fs.writeFileSync(path.join(v31, 'styles.xml'), '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">\n        <item name="android:windowSplashScreenBackground">@color/sakay_splash_background</item>\n        <item name="android:windowSplashScreenAnimatedIcon">@drawable/sakay_splash_android12</item>\n        <item name="android:windowSplashScreenIconBackgroundColor">@color/sakay_splash_background</item>\n    </style>\n</resources>\n');
  }
  const validation = { source: path.basename(source), sourceSha256: hash(original), image: await sharp(original).metadata(),
    trimmedArtwork: await sharp(trimmed).metadata(), changed, inAppLogosMatchSuppliedBytes: true };
  for (const project of projects) {
    if (hash(fs.readFileSync(path.join(root, project, 'assets/images/sakay_logo.png'))) !== hash(original)) throw new Error('Logo copy mismatch');
  }
  fs.writeFileSync(path.join(output, 'branding_manifest.json'), JSON.stringify(validation, null, 2) + '\n');
  console.log(`Updated ${changed.length} image assets across ${projects.length} apps; exact in-app logo SHA-256 ${hash(original)}.`);
})().catch(error => { console.error(error); process.exitCode = 1; });
