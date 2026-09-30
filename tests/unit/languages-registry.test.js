import {
  describe, it, expect, vi,
} from 'vitest';
import {
  languages, getLanguage, filebrowserLocale, zulipLanguage, isForwardable, setLanguage,
} from '@/utils/languages';
import { MODE, modeState } from '@/utils/Theming';

vi.mock('@/broker/preferences', () => ({
  applyPreferences: vi.fn(async () => ({ ok: true, apps: {} })),
  OUTCOME: {
    OK: 'ok', UNSUPPORTED: 'unsupported', UNAVAILABLE: 'unavailable', FAILED: 'failed',
  },
}));

// eslint-disable-next-line import/first
import { applyPreferences } from '@/broker/preferences';

/**
 * The locale registry.
 *
 * It carries the endonym, the English name, a flag and the identifier each
 * application uses (design.md D-I6). A language with no mapping is still
 * offered: the shell simply cannot forward it, and says so.
 */
describe('the locale registry', () => {
  it('gives every language the fields the switcher reads', () => {
    expect(languages.length).toBeGreaterThan(0);
    languages.forEach((lang) => {
      expect(lang.name).toBeTruthy();
      expect(lang.englishName).toBeTruthy();
      expect(lang.code).toBeTruthy();
      expect(lang.flag).toBeTruthy();
      expect(lang).toHaveProperty('filebrowser');
      expect(lang).toHaveProperty('zulip');
    });
  });

  it('uses FileBrowser Quantum\'s own locale keys, not BCP-47', () => {
    expect(filebrowserLocale('cs')).toBe('cz');
    expect(filebrowserLocale('uk')).toBe('ua');
    expect(filebrowserLocale('sv')).toBe('svSE');
    expect(filebrowserLocale('zh-CN')).toBe('zhCN');
  });

  it('uses the codes Zulip accepts, in Django form', () => {
    expect(zulipLanguage('zh-CN')).toBe('zh-hans');
    expect(zulipLanguage('en-GB')).toBe('en-gb');
    expect(zulipLanguage('de')).toBe('de');
  });

  it('offers a language with no mapping rather than hiding it', () => {
    const unmapped = languages.find((lang) => lang.filebrowser === null && lang.zulip === null);
    expect(unmapped).toBeTruthy();
    expect(getLanguage(unmapped.code)).toBeTruthy();
    expect(isForwardable(unmapped.code)).toBe(false);
  });

  it('returns null identifiers for an unknown code instead of guessing', () => {
    expect(filebrowserLocale('xx-unknown')).toBeNull();
    expect(zulipLanguage('xx-unknown')).toBeNull();
    expect(getLanguage('xx-unknown')).toBeNull();
  });

  it('hands the resolved identifiers to the broker, which owns no mapping itself', async () => {
    await setLanguage('pt', { applications: { files: { url: 'https://f.example.com' } } });
    expect(applyPreferences).toHaveBeenCalledWith(
      { locale: 'pt', adapters: { filebrowser: 'pt', zulip: 'pt' } },
      {},
    );
  });

  it('changing the language never changes the appearance mode', async () => {
    modeState.mode = MODE.DARK;
    await setLanguage('de', {});
    expect(modeState.mode).toBe(MODE.DARK);
    expect(document.documentElement.getAttribute('data-wc-mode')).not.toBe(MODE.LIGHT);
  });
});
