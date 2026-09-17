import { describe, it, expect } from 'vitest';
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
});
