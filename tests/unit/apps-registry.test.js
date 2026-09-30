import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import {
  APP_LIST, APP_IDS, getApp, getAppByRoute, isAppId, appIds,
} from '@/utils/apps/registry';

/**
 * The registry is the single source of truth for the integrated applications.
 * See design.md D-2 and architecture.md AR-9.
 */
describe('the application registry', () => {
  it('has exactly three applications, in rail order', () => {
    expect(appIds()).toEqual(['files', 'chat', 'mail']);
  });

  it('uses the frozen identifiers', () => {
    expect(APP_IDS).toEqual({ FILES: 'files', CHAT: 'chat', MAIL: 'mail' });
  });

  it('gives every application the fields the shell reads', () => {
    for (const app of APP_LIST) {
      expect(typeof app.id).toBe('string');
      expect(app.name).toBeTruthy();
      expect(app.icon).toBeTruthy();
      expect(app.accentVar).toMatch(/^--wc-accent-/);
      expect(app.configKey).toBeTruthy();
      expect(app.healthKey).toBeTruthy();
      expect(app.routeName).toBeTruthy();
      expect(app.sidebar).toBeTruthy();
    }
  });

  it('keeps identifiers unique', () => {
    const ids = APP_LIST.map((a) => a.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('gives each application a distinct accent token', () => {
    const accents = APP_LIST.map((a) => a.accentVar);
    expect(new Set(accents).size).toBe(accents.length);
  });

  it('looks an application up by id', () => {
    expect(getApp('chat').name).toBe('Chat');
    expect(getApp('nope')).toBeNull();
  });

  it('looks an application up by route name', () => {
    expect(getAppByRoute('mail').id).toBe('mail');
    expect(getAppByRoute('unknown')).toBeNull();
  });

  it('recognises its own identifiers, and nothing else', () => {
    expect(isAppId('files')).toBe(true);
    expect(isAppId('widgets')).toBe(false);
    expect(isAppId('')).toBe(false);
  });

  it('names the health key the broker reports each application under', () => {
    // These are the keys integration.md section 10 uses.
    expect(APP_LIST.map((a) => a.healthKey)).toEqual(['filebrowser', 'zulip', 'mailcow']);
  });

  it('cannot drift from the applications the configuration schema accepts', () => {
    // architecture.md AR-32 and Testing.md §4.2: the registry names the three
    // applications and the schema accepts an address for exactly those three,
    // so adding or renaming one is a two-file change that this test catches.
    const schema = JSON.parse(fs.readFileSync(
      path.resolve(__dirname, '../../src/utils/config/ConfigSchema.json'),
      'utf8',
    ));
    const applications = schema.properties.appConfig.properties.applications;
    expect(Object.keys(applications.properties).sort())
      .toEqual(APP_LIST.map((app) => app.configKey).sort());
    // An application entry carries its address and nothing else: the icon,
    // accent, route and sidebar surface all come from the registry.
    Object.values(applications.properties).forEach((entry) => {
      expect(entry.additionalProperties).toBe(false);
      expect(Object.keys(entry.properties)).toEqual(['url']);
    });
  });

  it('gives every application a committed brand mark', () => {
    // design.md D-2I: a mark is committed under icons/ and reached through the
    // @icons alias, so the switcher never falls back to a font glyph.
    const iconsDir = path.resolve(__dirname, '../../icons');
    APP_LIST.forEach((app) => {
      expect(fs.existsSync(path.join(iconsDir, `${app.mark}.svg`))).toBe(true);
      expect(fs.existsSync(path.join(iconsDir, `${app.paneMark}.svg`))).toBe(true);
    });
  });
});
