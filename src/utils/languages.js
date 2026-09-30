import en from '@/assets/locales/en.json';
import { applyLanguageToShell, languageCookie } from '@/utils/Theming';
import { applyPreferences, OUTCOME } from '@/broker/preferences';

/**
 * The locale registry.
 *
 * Each entry carries the language's endonym (what the user sees in their own
 * language), its English name, a flag glyph, and the identifier each embedded
 * application uses for the same language. A language with no mapping for an
 * application is still offered — the shell simply cannot forward it there, and
 * says so (design.md D-I6, D-I10).
 *
 * Identifier sources, verified against the pinned upstreams:
 * - `filebrowser`: `frontend/src/i18n/index.ts` in FileBrowser Quantum
 *   `v2.0.9-beta` — its own keys, not BCP-47 (`cz`, `ua`, `ptBR`, `zhCN`, …).
 * - `zulip`: the codes Zulip accepts for `default_language`, computed from its
 *   `locale/` translations (Django `to_language` form, e.g. `zh-hans`, `pt-pt`).
 */
export const languages = [
  {
    name: 'English', englishName: 'English', code: 'en', flag: '🇬🇧', flagCode: 'gb', filebrowser: 'en', zulip: 'en',
  },
  {
    name: 'English (British)', englishName: 'English (British)', code: 'en-GB', flag: '🇬🇧', flagCode: 'gb', filebrowser: 'en', zulip: 'en-gb',
  },
  {
    name: 'العربية', englishName: 'Arabic', code: 'ar', flag: '🇦🇪', flagCode: 'ae', filebrowser: 'ar', zulip: 'ar',
  },
  {
    name: 'Azərbaycan dili', englishName: 'Azerbaijani', code: 'az', flag: '🇦🇿', flagCode: 'az', filebrowser: null, zulip: null,
  },
  {
    name: 'Български', englishName: 'Bulgarian', code: 'bg', flag: '🇧🇬', flagCode: 'bg', filebrowser: 'bg', zulip: 'bg',
  },
  {
    name: 'বাংলা', englishName: 'Bengali', code: 'bn', flag: '🇧🇩', flagCode: 'bd', filebrowser: null, zulip: null,
  },
  {
    name: 'Čeština', englishName: 'Czech', code: 'cs', flag: '🇨🇿', flagCode: 'cz', filebrowser: 'cz', zulip: 'cs',
  },
  {
    name: 'Dansk', englishName: 'Danish', code: 'da', flag: '🇩🇰', flagCode: 'dk', filebrowser: null, zulip: 'da',
  },
  {
    name: 'Deutsch', englishName: 'German', code: 'de', flag: '🇩🇪', flagCode: 'de', filebrowser: 'de', zulip: 'de',
  },
  {
    name: 'Ελληνικά', englishName: 'Greek', code: 'el', flag: '🇬🇷', flagCode: 'gr', filebrowser: 'el', zulip: 'el',
  },
  {
    name: 'Español', englishName: 'Spanish', code: 'es', flag: '🇪🇸', flagCode: 'es', filebrowser: 'es', zulip: 'es',
  },
  {
    name: 'Français', englishName: 'French', code: 'fr', flag: '🇫🇷', flagCode: 'fr', filebrowser: 'fr', zulip: 'fr',
  },
  {
    name: 'हिन्दी', englishName: 'Hindi', code: 'hi', flag: '🇮🇳', flagCode: 'in', filebrowser: null, zulip: 'hi',
  },
  {
    name: 'Magyar', englishName: 'Hungarian', code: 'hu', flag: '🇭🇺', flagCode: 'hu', filebrowser: 'hu', zulip: 'hu',
  },
  {
    name: 'Italiano', englishName: 'Italian', code: 'it', flag: '🇮🇹', flagCode: 'it', filebrowser: 'it', zulip: 'it',
  },
  {
    name: '日本語', englishName: 'Japanese', code: 'ja', flag: '🇯🇵', flagCode: 'jp', filebrowser: 'ja', zulip: 'ja',
  },
  {
    name: '한국어', englishName: 'Korean', code: 'ko', flag: '🇰🇷', flagCode: 'kr', filebrowser: 'ko', zulip: 'ko',
  },
  {
    name: 'Кыргызча', englishName: 'Kyrgyz', code: 'ky', flag: '🇰🇬', flagCode: 'kg', filebrowser: null, zulip: null,
  },
  {
    name: 'Norsk', englishName: 'Norwegian', code: 'nb', flag: '🇳🇴', flagCode: 'no', filebrowser: null, zulip: null,
  },
  {
    name: 'Nederlands', englishName: 'Dutch', code: 'nl', flag: '🇳🇱', flagCode: 'nl', filebrowser: 'nl', zulip: 'nl',
  },
  {
    name: 'polski', englishName: 'Polish', code: 'pl', flag: '🇵🇱', flagCode: 'pl', filebrowser: 'pl', zulip: 'pl',
  },
  {
    name: 'Português', englishName: 'Portuguese', code: 'pt', flag: '🇵🇹', flagCode: 'pt', filebrowser: 'pt', zulip: 'pt',
  },
  /* No single unambiguous flag: the registry decides, not the component. */
  {
    name: 'Galego', englishName: 'Galician', code: 'gl', flag: '🌐', flagCode: null, filebrowser: null, zulip: null,
  },
  {
    name: 'Русский', englishName: 'Russian', code: 'ru', flag: '🇷🇺', flagCode: 'ru', filebrowser: 'ru', zulip: 'ru',
  },
  {
    name: 'Romana', englishName: 'Romanian', code: 'ro', flag: '🇷🇴', flagCode: 'ro', filebrowser: 'ro', zulip: 'ro',
  },
  {
    name: 'Slovenčina', englishName: 'Slovak', code: 'sk', flag: '🇸🇰', flagCode: 'sk', filebrowser: 'sk', zulip: null,
  },
  {
    name: 'Slovenščina', englishName: 'Slovenian', code: 'sl', flag: '🇸🇮', flagCode: 'si', filebrowser: null, zulip: 'sl',
  },
  {
    name: 'Svenska', englishName: 'Swedish', code: 'sv', flag: '🇸🇪', flagCode: 'se', filebrowser: 'svSE', zulip: 'sv',
  },
  {
    name: 'Türkçe', englishName: 'Turkish', code: 'tr', flag: '🇹🇷', flagCode: 'tr', filebrowser: 'tr', zulip: 'tr',
  },
  {
    name: 'Ukrainian', englishName: 'Ukrainian', code: 'uk', flag: '🇺🇦', flagCode: 'ua', filebrowser: 'ua', zulip: 'uk',
  },
  {
    name: '简体中文', englishName: 'Chinese (Simplified)', code: 'zh-CN', flag: '🇨🇳', flagCode: 'cn', filebrowser: 'zhCN', zulip: 'zh-hans',
  },
  {
    name: 'Pirate', englishName: 'Pirate', code: 'zz-pirate', flag: '🏴‍☠️', flagCode: null, filebrowser: null, zulip: null,
  },
];

/** The registry entry for a locale code, or null. */
export const getLanguage = (code) => languages.find((lang) => lang.code === code) || null;

/**
 * The ISO 639-1 two-letter code for a locale — what the language button shows
 * beside its flag (design.md D-6.2). A regional locale shows its primary
 * subtag: `en-GB` is `en`, `zh-CN` is `zh`.
 */
export const iso639 = (code) => (code || '').split('-')[0].toLowerCase();

/**
 * The ISO 3166-1 alpha-2 code of the flag that stands for a locale, or null for
 * a language with no country of its own. The committed flag set is named from
 * these codes (`icons/flags/<code>.svg`); null means the shell shows the
 * registry's own glyph instead, because a wrong flag is worse than none.
 */
export const flagCode = (code) => getLanguage(code)?.flagCode || null;

/** The identifier FileBrowser Quantum uses for a locale, or null. */
export const filebrowserLocale = (code) => getLanguage(code)?.filebrowser || null;

/** The Django language code Zulip uses for a locale, or null. */
export const zulipLanguage = (code) => getLanguage(code)?.zulip || null;

/** True when the shell can forward this locale to at least one application. */
export const isForwardable = (code) => Boolean(filebrowserLocale(code) || zulipLanguage(code));

export const messages = { en };

const loaders = import.meta.glob([
  '../assets/locales/*.json',
  '!../assets/locales/en.json', // Exclude English, needed as default + fallback
]);

export const loadLocale = async (code) => {
  if (code === 'en') return en;
  const loader = loaders[`../assets/locales/${code}.json`];
  if (!loader) throw new Error(`Unsupported locale: ${code}`);
  const mod = await loader();
  return mod.default;
};

/**
 * Language bridge outcomes, mirroring the preferences client.
 *
 * SOGo and the Mailcow UI are deliberately absent: neither exposes a language
 * setting the shell can write, so the menu says so instead of failing quietly
 * (design.md D-I10).
 */
export const LANGUAGE_OUTCOME = OUTCOME;

/**
 * Switch the shell's language and forward it to the applications that can take
 * it, in one broker call (rule D-I8).
 *
 * Returns `{ locale, apps }` so the menu can name any application that could
 * not be changed.
 */
export const setLanguage = async (code, appConfig = {}) => {
  applyLanguageToShell(code);
  languageCookie(code, appConfig);
  /* SOGo has no language API; the Mailcow UI is not a pane. Both follow the
     browser, which the shell cannot change for them. */
  const adapters = {};
  const fb = filebrowserLocale(code);
  const zu = zulipLanguage(code);
  if (fb) adapters.filebrowser = fb;
  if (zu) adapters.zulip = zu;
  const result = await applyPreferences({ locale: code, adapters }, {});
  return { locale: code, apps: result.apps };
};

export default languages;
