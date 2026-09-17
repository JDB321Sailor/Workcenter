import { describe, it, expect } from 'vitest';
import {
  makePageName,
  viewFromPath,
  resolveRouteIntent,
  PAGE_STATUS,
  RESERVED_ROOT,
  formatConfigPath,
  componentVisibility,
  getCustomKeyShortcuts,
} from '@/utils/config/ConfigHelpers';

describe('ConfigHelpers - makePageName', () => {
  it('converts page name to lowercase', () => {
    expect(makePageName('My Page')).toBe('my-page');
  });

  it('replaces spaces with hyphens', () => {
    expect(makePageName('Multiple Word Page')).toBe('multiple-word-page');
  });

  it('removes .yml extension', () => {
    expect(makePageName('config.yml')).toBe('config');
  });

  it('removes special characters', () => {
    expect(makePageName('Page!@#$Name')).toBe('pagename');
  });

  it('handles undefined input', () => {
    expect(makePageName(undefined)).toBe('unnamed-page');
  });

  it('handles null input', () => {
    expect(makePageName(null)).toBe('unnamed-page');
  });

  it('handles empty string', () => {
    expect(makePageName('')).toBe('unnamed-page');
  });

  it('trims leading dash left by stripped emoji', () => {
    expect(makePageName('🌐 Command Center')).toBe('command-center');
  });

  it('trims trailing dashes', () => {
    expect(makePageName('My Page-')).toBe('my-page');
  });

  it('falls back to unnamed-page when all chars are stripped', () => {
    expect(makePageName('🌐🚀')).toBe('unnamed-page');
  });

  it(`reserves "${RESERVED_ROOT}" so user pages cannot shadow the root sentinel`, () => {
    expect(makePageName('Main')).toBe(`${RESERVED_ROOT}-page`);
    expect(makePageName('main')).toBe(`${RESERVED_ROOT}-page`);
    expect(makePageName(' MAIN ')).toBe(`${RESERVED_ROOT}-page`);
  });

  it('is idempotent — slugging an already-slug string returns the same slug', () => {
    const slug = makePageName('🌐 Command Center');
    expect(makePageName(slug)).toBe(slug);
  });

  it('preserves accented Latin so names round-trip (Vue Router percent-encodes the URL)', () => {
    expect(makePageName('Sección Configuración')).toBe('sección-configuración');
    expect(makePageName('Größe')).toBe('größe');
  });

  it('preserves CJK, Cyrillic, and Arabic names', () => {
    expect(makePageName('中文')).toBe('中文');
    expect(makePageName('日本語 工具')).toBe('日本語-工具');
    expect(makePageName('Привет')).toBe('привет');
    expect(makePageName('مرحبا')).toBe('مرحبا');
  });

  it('still strips emoji, punctuation and symbols in mixed-script names', () => {
    expect(makePageName('🌐 Command Center!')).toBe('command-center');
    expect(makePageName('⚙️ 设置')).toBe('设置');
    expect(makePageName('$100 Club')).toBe('100-club');
  });

  it('NFC-normalizes so composed and decomposed forms produce the same slug', () => {
    // 'é' as one codepoint (U+00E9) vs 'e' + combining acute (U+0065 U+0301)
    expect(makePageName('café')).toBe(makePageName('cafe\u0301'));
  });

  it('collapses whitespace-only names to unnamed-page', () => {
    expect(makePageName('   ')).toBe('unnamed-page');
    expect(makePageName('\t\n')).toBe('unnamed-page');
  });
});


describe('ConfigHelpers - viewFromPath', () => {
  it('extracts the pane segment from a path', () => {
    expect(viewFromPath('/files')).toBe('files');
    expect(viewFromPath('/chat')).toBe('chat');
    expect(viewFromPath('/mail')).toBe('mail');
    expect(viewFromPath('/')).toBe('workspace');
  });

  it('defaults to the workspace for unknown paths', () => {
    expect(viewFromPath('/about')).toBe('workspace');
    expect(viewFromPath('')).toBe('workspace');
  });
});

describe('ConfigHelpers - resolveRouteIntent', () => {
  const fakeStore = ({ pages = [], rootSections = [] } = {}) => ({
    getters: { pages },
    state: { rootConfig: { sections: rootSections } },
  });
  const route = (path, params = {}) => ({ path, params });

  it('classifies a pane route as ROOT', () => {
    const out = resolveRouteIntent(route('/files', {}), fakeStore());
    expect(out).toEqual({
      view: 'files', pageId: null, sectionSlug: null, status: PAGE_STATUS.ROOT,
    });
  });

  it('classifies the empty path as the workspace root', () => {
    const out = resolveRouteIntent(route('/', {}), fakeStore());
    expect(out.status).toBe(PAGE_STATUS.ROOT);
    expect(out.pageId).toBeNull();
    expect(out.view).toBe('workspace');
  });

  it('classifies /<view>/main/:section as ROOT with sectionSlug', () => {
    const out = resolveRouteIntent(
      route('/home/main/tools', { page: 'main', section: 'Tools' }),
      fakeStore(),
    );
    expect(out.status).toBe(PAGE_STATUS.ROOT);
    expect(out.pageId).toBeNull();
    expect(out.sectionSlug).toBe('tools');
  });

  it('classifies a known sub-page as KNOWN', () => {
    const store = fakeStore({ pages: [{ name: '🏠 Homelab' }] });
    const out = resolveRouteIntent(
      route('/home/homelab/media', { page: 'homelab', section: 'Media' }),
      store,
    );
    expect(out.status).toBe(PAGE_STATUS.KNOWN);
    expect(out.pageId).toBe('homelab');
    expect(out.sectionSlug).toBe('media');
  });

  it('forgives a legacy /<view>/<root-section> URL as LEGACY_SECTION', () => {
    const store = fakeStore({ rootSections: [{ name: 'Getting Started' }] });
    const out = resolveRouteIntent(
      route('/home/getting-started', { page: 'getting-started' }),
      store,
    );
    expect(out.status).toBe(PAGE_STATUS.LEGACY_SECTION);
    expect(out.pageId).toBeNull();
    expect(out.sectionSlug).toBe('getting-started');
  });

  it('does NOT fall through to legacy when the URL has an explicit :section', () => {
    const store = fakeStore({ rootSections: [{ name: 'Getting Started' }] });
    const out = resolveRouteIntent(
      route('/home/getting-started/whatever', {
        page: 'getting-started', section: 'whatever',
      }),
      store,
    );
    expect(out.status).toBe(PAGE_STATUS.UNKNOWN);
  });

  it('returns UNKNOWN for a page that matches neither a sub-page nor a root section', () => {
    const store = fakeStore({ pages: [{ name: 'Homelab' }], rootSections: [{ name: 'Tools' }] });
    const out = resolveRouteIntent(
      route('/home/bogus', { page: 'bogus' }),
      store,
    );
    expect(out.status).toBe(PAGE_STATUS.UNKNOWN);
    expect(out.pageId).toBe('bogus');
  });

  it('normalizes raw params — /home/-Homelab resolves to KNOWN homelab', () => {
    const store = fakeStore({ pages: [{ name: 'Homelab' }] });
    const out = resolveRouteIntent(
      route('/home/-Homelab', { page: '-Homelab' }),
      store,
    );
    expect(out.status).toBe(PAGE_STATUS.KNOWN);
    expect(out.pageId).toBe('homelab');
  });

  it('resolves a CJK page name (Vue Router hands us the decoded param)', () => {
    const store = fakeStore({ pages: [{ name: '中文' }] });
    const out = resolveRouteIntent(
      route('/home/中文/工具', { page: '中文', section: '工具' }),
      store,
    );
    expect(out.status).toBe(PAGE_STATUS.KNOWN);
    expect(out.pageId).toBe('中文');
    expect(out.sectionSlug).toBe('工具');
  });

  it('safely accepts undefined route or store', () => {
    const out = resolveRouteIntent(undefined, undefined);
    expect(out.view).toBe('workspace');
    expect(out.status).toBe(PAGE_STATUS.ROOT);
  });
});


describe('ConfigHelpers - formatConfigPath', () => {
  it('leaves http URLs unchanged', () => {
    const url = 'https://example.com/config.yml';
    expect(formatConfigPath(url)).toBe(url);
  });

  it('adds leading slash to relative paths', () => {
    expect(formatConfigPath('config.yml')).toBe('/config.yml');
  });

  it('keeps absolute paths unchanged', () => {
    expect(formatConfigPath('/config.yml')).toBe('/config.yml');
  });

  it('strips a leading ./ so relative YAML paths resolve correctly', () => {
    expect(formatConfigPath('./config.yml')).toBe('/config.yml');
    expect(formatConfigPath('./sub/config.yml')).toBe('/sub/config.yml');
  });
});

describe('ConfigHelpers - componentVisibility', () => {
  it('returns all visible by default when no config', () => {
    const result = componentVisibility({});
    expect(result.pageTitle).toBe(true);
    expect(result.navigation).toBe(true);
    expect(result.searchBar).toBe(true);
    expect(result.settings).toBe(true);
  });

  it('hides components based on config', () => {
    const appConfig = {
      hideComponents: {
        hideHeading: true,
        hideNav: true,
      },
    };
    const result = componentVisibility(appConfig);
    expect(result.pageTitle).toBe(false);
    expect(result.navigation).toBe(false);
    expect(result.searchBar).toBe(true);
  });

  it('handles partial config correctly', () => {
    const appConfig = {
      hideComponents: {
        hideSettings: true,
      },
    };
    const result = componentVisibility(appConfig);
    expect(result.settings).toBe(false);
    expect(result.pageTitle).toBe(true);
  });
});

describe('ConfigHelpers - getCustomKeyShortcuts', () => {
  it('extracts hotkeys from sections', () => {
    const sections = [
      {
        items: [
          { hotkey: 1, url: 'https://example.com' },
          { url: 'https://example.org' },
        ],
      },
    ];
    const result = getCustomKeyShortcuts(sections);
    expect(result).toHaveLength(1);
    expect(result[0]).toEqual({ hotkey: 1, url: 'https://example.com' });
  });

  it('returns empty array when no hotkeys', () => {
    const sections = [{ items: [{ url: 'https://example.com' }] }];
    expect(getCustomKeyShortcuts(sections)).toEqual([]);
  });

  it('flattens hotkeys from multiple sections', () => {
    const sections = [
      { items: [{ hotkey: 1, url: 'https://a.com' }] },
      { items: [{ hotkey: 2, url: 'https://b.com' }] },
    ];
    const result = getCustomKeyShortcuts(sections);
    expect(result).toHaveLength(2);
  });

  it('skips sections that have no items array (widgets-only)', () => {
    const sections = [
      { name: 'Widgets Only', widgets: [{ type: 'embed' }] },
      { items: [{ hotkey: 1, url: 'https://a.com' }] },
    ];
    expect(getCustomKeyShortcuts(sections)).toEqual([
      { hotkey: 1, url: 'https://a.com' },
    ]);
  });

  it('returns an empty array for null or undefined input', () => {
    expect(getCustomKeyShortcuts(null)).toEqual([]);
    expect(getCustomKeyShortcuts(undefined)).toEqual([]);
  });
});
