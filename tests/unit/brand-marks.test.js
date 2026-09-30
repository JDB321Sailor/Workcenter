import {
  describe, it, expect,
} from 'vitest';
import fs from 'node:fs';
import path from 'node:path';

/**
 * The committed brand marks.
 *
 * Workcenter commits one SVG per integrated application at the repository root
 * and reaches them through the `@icons` alias, so a missing file fails the build
 * and nothing is fetched from a third-party CDN at runtime (design.md D-2I,
 * architecture.md AR-46).
 *
 * Every mark must be inert: no script, no event handler and no remote
 * reference, because these files are rendered inside the shell (design.md
 * D-2I.8).
 */

const iconsDir = path.resolve(__dirname, '../../icons');

/* The complete set the shell references, by registry key. */
const REQUIRED = [
  'filebrowser-quantum.svg',
  'zulip.svg',
  'mailcow.svg',
  'sogo.svg',
  'onlyoffice.svg',
  'traefik.svg',
  'authentik.svg',
];

describe('the committed brand marks', () => {
  it('exists one per integrated application and surface', () => {
    REQUIRED.forEach((name) => {
      expect(fs.existsSync(path.join(iconsDir, name)), `${name} is missing`).toBe(true);
    });
  });

  it('holds no file that is not required, so the set stays the source of truth', () => {
    const present = fs.readdirSync(iconsDir).filter((name) => name.endsWith('.svg')).sort();
    expect(present).toEqual([...REQUIRED].sort());
  });

  it('contains no script, event handler or remote reference', () => {
    const offenders = [];
    fs.readdirSync(iconsDir).filter((name) => name.endsWith('.svg')).forEach((name) => {
      const svg = fs.readFileSync(path.join(iconsDir, name), 'utf8');
      if (/<script/i.test(svg)) offenders.push(`${name}: script`);
      if (/\son[a-z]+\s*=/i.test(svg)) offenders.push(`${name}: event handler`);
      if (/(?:href|src)\s*=\s*["']https?:/i.test(svg)) offenders.push(`${name}: remote reference`);
    });
    expect(offenders).toEqual([]);
  });

  it('is referenced through the alias rather than a relative path', () => {
    const component = fs.readFileSync(
      path.resolve(__dirname, '../../src/components/AppMark.vue'),
      'utf8',
    );
    expect(component).toMatch(/from '@icons\//);
    expect(component).not.toMatch(/from '\.\.\/\.\.\/icons/);
  });
});
