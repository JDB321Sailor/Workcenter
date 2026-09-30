import {
  describe, it, expect,
} from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { languages, flagCode, iso639 } from '@/utils/languages';

/**
 * The committed language flags and theme glyphs. Design.md D-6.2, D-2I.3.
 *
 * Flags are square SVGs at `icons/flags/<ISO 3166-1 alpha-2>.svg`, reached
 * through the `@icons` alias so a missing file is a build failure rather than a
 * broken image at runtime. A language with no country of its own has no file and
 * falls back to the registry's glyph.
 */

const repoRoot = path.resolve(__dirname, '../..');
const flagsDir = path.join(repoRoot, 'icons/flags');
const uiDir = path.join(repoRoot, 'icons/ui');

const committedFlags = () => fs.readdirSync(flagsDir)
  .filter((name) => name.endsWith('.svg'))
  .map((name) => name.replace(/\.svg$/, ''));

const read = (file) => fs.readFileSync(file, 'utf8');

describe('the language flags', () => {
  it('exists one per language that has a country', () => {
    const present = committedFlags();
    const wanted = languages
      .map((language) => flagCode(language.code))
      .filter(Boolean);
    wanted.forEach((code) => {
      expect(present, `icons/flags/${code}.svg is missing`).toContain(code);
    });
  });

  it('holds no flag that no language uses', () => {
    const wanted = languages.map((language) => flagCode(language.code)).filter(Boolean);
    committedFlags().forEach((code) => expect(wanted).toContain(code));
  });

  it('names a country only for the languages that have one', () => {
    /* Galician and the joke locale must not wear someone else's flag. */
    expect(flagCode('gl')).toBeNull();
    expect(flagCode('zz-pirate')).toBeNull();
    expect(flagCode('en')).toBe('gb');
    expect(flagCode('zh-CN')).toBe('cn');
    expect(flagCode('sv')).toBe('se');
  });

  it('is a square SVG, so the circle is a crop and not a distortion', () => {
    committedFlags().forEach((code) => {
      const svg = read(path.join(flagsDir, `${code}.svg`));
      expect(svg, `${code} has no viewBox`).toMatch(/viewBox="0 0 512 512"/);
    });
  });

  it('is inert: no script, no event handler and no remote load', () => {
    const offenders = [];
    const files = [
      ...committedFlags().map((code) => path.join(flagsDir, `${code}.svg`)),
      path.join(uiDir, 'sun.svg'),
      path.join(uiDir, 'moon.svg'),
    ];
    files.forEach((file) => {
      const svg = read(file);
      const name = path.relative(repoRoot, file);
      if (/<script/i.test(svg)) offenders.push(`${name}: script`);
      if (/\son[a-z]+\s*=/i.test(svg)) offenders.push(`${name}: event handler`);
      /* A remote *load*, not a namespace identifier or an attribution comment. */
      if (/(?:href|src)\s*=\s*["']https?:/i.test(svg)) offenders.push(`${name}: remote reference`);
      if (/<image/i.test(svg)) offenders.push(`${name}: embedded image`);
      /* Any xlink target must be inside the file. */
      const xlink = svg.match(/xlink:href="([^"]+)"/g) || [];
      xlink.forEach((match) => {
        if (!match.includes('"#')) offenders.push(`${name}: external xlink`);
      });
    });
    expect(offenders).toEqual([]);
  });
});

describe('the theme glyphs', () => {
  it('commits a sun and a moon for the mode toggle', () => {
    ['sun.svg', 'moon.svg'].forEach((name) => {
      const file = path.join(uiDir, name);
      expect(fs.existsSync(file), `${name} is missing`).toBe(true);
      expect(read(file)).toMatch(/viewBox="0 0 512 512"|viewBox="0 0 384 512"/);
    });
  });

  it('is reached through the alias, so the button cannot fall back to the icon font', () => {
    const component = read(path.resolve(__dirname, '../../src/components/User/ModeToggleButton.vue'));
    expect(component).toMatch(/from '@icons\/ui\/sun\.svg'/);
    expect(component).toMatch(/from '@icons\/ui\/moon\.svg'/);
  });
});

describe('the ISO 639-1 code on the language button', () => {
  it('takes the primary subtag of a regional locale', () => {
    expect(iso639('en')).toBe('en');
    expect(iso639('en-GB')).toBe('en');
    expect(iso639('zh-CN')).toBe('zh');
    expect(iso639('pt')).toBe('pt');
  });

  it('is two letters for every language the shell offers', () => {
    languages.forEach((language) => {
      expect(iso639(language.code), language.code).toMatch(/^[a-z]{2}$/);
    });
  });
});
