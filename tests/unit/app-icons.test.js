import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';

/**
 * Every icon the application asks a browser for has to be there.
 *
 * This is not hypothetical. The Web App Manifest, `index.html` and the build's
 * own PWA configuration each name icon files by **path**, and nothing between
 * them and a 404 checks that the path resolves: a missing favicon is a blank tab
 * icon, and a missing manifest icon is a browser that silently refuses to install
 * the app. The files were in fact deleted from `public/` while every reference to
 * them stayed behind, and nothing failed — no test, no build error, and no
 * console message a person would see.
 *
 * The source of truth is the repository, not `dist/`: `dist/` is gitignored and
 * rebuilt, so a reference that only resolves after a build is still a broken
 * checkout.
 */
const root = path.resolve(__dirname, '../..');
const publicDir = path.join(root, 'public');

const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');

/** A manifest entry's `src` is relative to the manifest, or absolute from the root. */
const resolvePublic = (src) => (src.startsWith('/')
  ? path.join(publicDir, src)
  : path.join(publicDir, src.replace(/^\.\//, '')));

describe('the icons the application asks for', () => {
  const manifest = JSON.parse(read('public/manifest.json'));

  it('are all present in public/, as the Web App Manifest names them', () => {
    expect(manifest.icons.length).toBeGreaterThan(0);
    for (const icon of manifest.icons) {
      const file = resolvePublic(icon.src);
      expect(fs.existsSync(file), `manifest.json names ${icon.src}, which does not exist`).toBe(true);
      expect(fs.statSync(file).size, `${icon.src} is empty`).toBeGreaterThan(0);
    }
  });

  it('are all present in public/, as index.html names them', () => {
    const html = read('index.html');
    const hrefs = [...html.matchAll(/href="(\/[^"]+\.(?:png|ico|svg))"/g)].map((m) => m[1]);
    expect(hrefs.length).toBeGreaterThan(0);
    for (const href of hrefs) {
      expect(fs.existsSync(resolvePublic(href)), `index.html names ${href}, which does not exist`).toBe(true);
    }
  });

  it('are all present in public/, as the build configuration names them', () => {
    /* `vite.config.mjs` writes its own manifest at build time, so an icon it
       names is baked into the built app even though no source file mentions it. */
    const config = read('vite.config.mjs');
    const block = config.slice(config.indexOf('icons: ['), config.indexOf(']', config.indexOf('icons: [')));
    const srcs = [...block.matchAll(/src:\s*'([^']+)'/g)].map((m) => m[1]);
    expect(srcs.length).toBeGreaterThan(0);
    for (const src of srcs) {
      expect(fs.existsSync(resolvePublic(src)), `vite.config.mjs names ${src}, which does not exist`).toBe(true);
    }
  });

  it('declare the size they actually are', () => {
    /* A manifest that overstates an icon's size makes a browser scale it up and
       install a blurry app icon — a quiet wrong answer rather than a failure. */
    for (const icon of manifest.icons) {
      const declared = Number.parseInt(icon.sizes.split('x')[0], 10);
      const file = resolvePublic(icon.src);
      const { width, height } = pngInfo(file);
      expect(width, `${icon.src} is ${width}x${height}, declared ${icon.sizes}`).toBe(declared);
      expect(height).toBe(declared);
    }
  });

  it('carry an alpha channel, so their corners are not white', () => {
    /* The icon is a rounded square authored on white, and its four corners held a
       white-to-dark gradient. Left opaque, the application wears white corners on
       every dark surface it is placed on — the tab strip, the dock, the launcher.
       The corners are transparent now, and every size is derived from the icon
       itself, so an RGBA channel is the property that says so.
       `pngInfo` reads the header rather than the pixels: the colour type is part
       of the file's own description, and no decoder is needed to trust it. */
    const icons = [
      ...manifest.icons.map((i) => i.src),
      ...[...read('index.html').matchAll(/href="(\/[^"]+\.png)"/g)].map((m) => m[1]),
    ];
    for (const src of new Set(icons)) {
      const { colorType } = pngInfo(resolvePublic(src));
      expect(colorType, `${src} has no alpha channel (colour type ${colorType})`).toBe(6);
    }
  });
});

/**
 * The facts a PNG states about itself in its IHDR, without decoding pixels.
 *
 * Colour type 6 is truecolour with alpha; 2 is truecolour without, which is what
 * an icon still carrying its white corners looks like from here.
 */
function pngInfo(file) {
  const buf = fs.readFileSync(file);
  expect(buf.subarray(1, 4).toString('ascii'), `${file} is not a PNG`).toBe('PNG');
  return {
    width: buf.readUInt32BE(16),
    height: buf.readUInt32BE(20),
    bitDepth: buf[24],
    colorType: buf[25],
  };
}
