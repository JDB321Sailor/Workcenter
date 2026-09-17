import { describe, it, expect } from 'vitest';
import { appUrl, appUrls, isAppConfigured, deepLink } from '@/utils/apps/urls';

/**
 * Addresses come from `appConfig.applications`, never from a component, so an
 * operator can move a pane without touching the code. See architecture.md AR-9.
 */
const config = (over = {}) => ({
  applications: {
    files: { url: 'https://filebrowser.example.com' },
    chat: { url: 'https://chat.example.com' },
    mail: { url: 'https://mail.example.com/SOGo' },
    ...over,
  },
});

describe('pane addresses', () => {
  it('reads an application address from the config', () => {
    expect(appUrl(config(), 'files')).toBe('https://filebrowser.example.com');
    expect(appUrl(config(), 'chat')).toBe('https://chat.example.com');
  });

  it('accepts a bare string as well as an object', () => {
    expect(appUrl({ applications: { files: 'https://files.example.com' } }, 'files'))
      .toBe('https://files.example.com');
  });

  it('returns an empty string when the application is not configured', () => {
    expect(appUrl({}, 'files')).toBe('');
    expect(appUrl({ applications: {} }, 'chat')).toBe('');
    expect(appUrl(config({ files: {} }), 'files')).toBe('');
  });

  it('returns an empty string for an unknown application', () => {
    expect(appUrl(config(), 'nope')).toBe('');
  });

  it('rejects a non-http address', () => {
    // sanitizeUrl permits only http and https.
    expect(appUrl({ applications: { files: { url: 'javascript:alert(1)' } } }, 'files')).toBe('');
    expect(appUrl({ applications: { files: { url: 'ftp://example.com' } } }, 'files')).toBe('');
  });

  it('tolerates an absent or malformed appConfig', () => {
    expect(appUrl(undefined, 'files')).toBe('');
    expect(appUrl(null, 'files')).toBe('');
    expect(appUrl({ applications: null }, 'files')).toBe('');
  });

  it('reports configuration for every application at once', () => {
    expect(appUrls(config())).toEqual({
      files: 'https://filebrowser.example.com',
      chat: 'https://chat.example.com',
      mail: 'https://mail.example.com/SOGo',
    });
  });

  it('answers whether an application can be shown', () => {
    expect(isAppConfigured(config(), 'files')).toBe(true);
    expect(isAppConfigured({}, 'files')).toBe(false);
  });
});

describe('deep links', () => {
  it('returns the base address when no path is given', () => {
    expect(deepLink(config(), 'files', '')).toBe('https://filebrowser.example.com');
  });

  it('appends a path to the application address', () => {
    expect(deepLink(config(), 'files', 'files/Documents'))
      .toBe('https://filebrowser.example.com/files/Documents');
  });

  it('does not double the separator when the base ends in a slash', () => {
    expect(deepLink({ applications: { files: { url: 'https://files.example.com/' } } }, 'files', '/a'))
      .toBe('https://files.example.com/a');
  });

  it('keeps a sub-path that is part of the configured address', () => {
    expect(deepLink(config(), 'mail', 'SOGo/'))
      .toBe('https://mail.example.com/SOGo/SOGo/');
  });

  it('returns an empty string when the application has no address', () => {
    expect(deepLink({}, 'files', 'anything')).toBe('');
  });
});
