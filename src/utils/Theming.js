/**
 * Utils for applying user's theme to the document
 */

import { reactive } from 'vue';
import {
  localStorageKeys, cookieKeys, mainCssVars, builtInThemes,
} from '@/utils/config/defaults';
import { applyPreferences, OUTCOME } from '@/broker/preferences';
import ErrorHandler from '@/utils/logging/ErrorHandler';

const EXTERNAL_STYLE_ID = 'user-defined-stylesheet';
const html = () => document.documentElement;

/* Appearance modes. Dark is the Workcenter default (design.md D-6.1). */
export const MODE = Object.freeze({ DARK: 'dark', LIGHT: 'light' });
export const DEFAULT_MODE = MODE.DARK;

/* The mode cookie's lifetime: one year, refreshed on every change (D-4.4.2). */
const COOKIE_MAX_AGE_SECONDS = 60 * 60 * 24 * 365;

/**
 * The shell's appearance state.
 *
 * Reactive, because the user menu's appearance control and the panes' states
 * both read it. `panes` carries the per-application outcome of the last switch
 * so a partial failure can be named in the UI instead of hidden.
 */
export const modeState = reactive({
  mode: DEFAULT_MODE,
  applied: null,
  panes: {},
});

/**
 * Pane adapters, registered by the panes themselves.
 *
 * An adapter is `{ origin, getWindow, refresh }`, where `refresh` returns false
 * when the pane deferred its reload (an open editor, design.md D-T7). The shell
 * owns the bridge, so panes never talk to an application directly.
 */
const paneAdapters = new Map();

export const registerPane = (appId, adapter) => {
  paneAdapters.set(appId, adapter);
  return () => paneAdapters.delete(appId);
};

/** The pane adapter for one application, for tests and for the refresh policy. */
export const getPaneAdapter = (appId) => paneAdapters.get(appId) || null;

/** Forget every registered pane, for tests and for a full teardown. */
export const unregisterAllPanes = () => {
  paneAdapters.clear();
};

/**
 * The cookie domain shared by the shell and every application host.
 *
 * The deployment derives its hostnames by prefix substitution on one base
 * domain (production.md), so stripping the first label of a configured
 * application host yields it exactly. With nothing derivable the cookie stays
 * host-only, which is correct but does not reach the panes.
 */
export const cookieDomain = (appConfig) => {
  const applications = appConfig?.applications || {};
  for (const key of ['files', 'chat', 'mail']) {
    const configured = applications[key];
    const raw = typeof configured === 'string' ? configured : configured?.url;
    if (!raw) continue;
    try {
      const labels = new URL(raw).hostname.split('.');
      if (labels.length >= 3) return `.${labels.slice(1).join('.')}`;
    } catch {
      // Not a usable URL: try the next application.
    }
  }
  return '';
};

/** Write one of the shell's own first-paint cookies. */
const writeCookie = (name, value, appConfig) => {
  const parts = [
    `${name}=${encodeURIComponent(value)}`,
    'Path=/',
    'SameSite=Lax',
    `Max-Age=${COOKIE_MAX_AGE_SECONDS}`,
  ];
  const domain = cookieDomain(appConfig);
  if (domain) parts.push(`Domain=${domain}`);
  // Secure cookies are dropped over plain http, so the attribute follows the
  // scheme the shell is actually served from.
  if (window.location.protocol === 'https:') parts.push('Secure');
  document.cookie = parts.join('; ');
};

/** The shell's own first-paint cookies, for tests. */
export const modeCookie = (appConfig) => writeCookie(cookieKeys.MODE, modeState.mode, appConfig);
export const languageCookie = (locale, appConfig) => writeCookie(cookieKeys.LANGUAGE, locale, appConfig);

/** Post a message to every mounted pane, each at its own exact origin. */
export const postToPanes = (message) => {
  let delivered = 0;
  paneAdapters.forEach((adapter, appId) => {
    const frameWindow = adapter?.getWindow?.();
    if (!adapter?.origin || !frameWindow) return;
    try {
      frameWindow.postMessage(message, adapter.origin);
      delivered += 1;
    } catch (e) {
      ErrorHandler(`[theme] could not message the ${appId} pane`, e);
    }
  });
  return delivered;
};

/**
 * Apply a mode to the shell alone: the document attribute, the localStorage
 * mirror and the mode cookie. Nothing is fetched and nothing is remounted
 * (rule D-T5).
 */
export const applyModeToShell = (mode, appConfig = {}) => {
  const next = mode === MODE.LIGHT ? MODE.LIGHT : MODE.DARK;
  modeState.mode = next;
  html().setAttribute('data-wc-mode', next);
  try {
    localStorage.setItem(localStorageKeys.MODE, next);
  } catch (e) {
    ErrorHandler('Could not mirror the appearance mode locally', e);
  }
  writeCookie(cookieKeys.MODE, next, appConfig);
  postToPanes({ type: 'workcenter:mode', mode: next });
  return next;
};

/** The mode to start in: the user's stored choice, else dark. */
export const readStoredMode = () => {
  try {
    return localStorage.getItem(localStorageKeys.MODE) === MODE.LIGHT ? MODE.LIGHT : DEFAULT_MODE;
  } catch {
    return DEFAULT_MODE;
  }
};

/**
 * Apply the stored mode before the shell renders, so the first paint is already
 * in the right mode and nothing flashes (rule D-6.1).
 */
export const initModeFromStorage = () => {
  const mode = readStoredMode();
  modeState.mode = mode;
  html().setAttribute('data-wc-mode', mode);
  return mode;
};

/**
 * Switch the mode everywhere.
 *
 * The shell repaints immediately; the broker then forwards the choice to the
 * applications that can accept it, and the Files pane is reloaded only after
 * the broker confirms the write, at the path it last reported (rule D-T6).
 */
export const setMode = async (mode, appConfig = {}) => {
  const next = applyModeToShell(mode, appConfig);
  const result = await applyPreferences({ mode: next }, {});
  modeState.applied = result;
  modeState.panes = { ...result.apps };

  // FileBrowser Quantum has no inbound channel: its pane is refreshed once the
  // preference is persisted, unless a document editor is open.
  if (result.apps.files === OUTCOME.OK) {
    const adapter = paneAdapters.get('files');
    if (adapter?.refresh && adapter.refresh() === false) modeState.panes.files = 'deferred';
  }
  return modeState;
};

/**
 * Apply a language to the shell alone and announce it to the panes.
 *
 * The vue-i18n locale is set by the caller, which owns loading the message
 * bundle; this function owns the document language, the local mirror and the
 * pane message, exactly as the mode path does.
 */
export const applyLanguageToShell = (locale) => {
  if (!locale) return '';
  html().setAttribute('lang', locale);
  try {
    localStorage.setItem(localStorageKeys.WC_LANGUAGE, locale);
  } catch (e) {
    ErrorHandler('Could not mirror the language locally', e);
  }
  postToPanes({ type: 'workcenter:lang', locale });
  return locale;
};

/* Map of { label: href } for stylesheets declared in appConfig.externalStyleSheet */
export const getExternalThemes = (appConfig) => {
  const ext = appConfig?.externalStyleSheet;
  if (!ext) return {};
  if (Array.isArray(ext)) {
    return Object.fromEntries(ext.map((href, i) => [`External Stylesheet ${i + 1}`, href]));
  }
  if (typeof ext === 'string') return { 'External Stylesheet': ext };
  ErrorHandler('External stylesheets must be of type string or string[]');
  return {};
};

/* Names of user-defined themes (appConfig.cssThemes). Always returns an array. */
export const getExtraThemeNames = (appConfig) => {
  const t = appConfig?.cssThemes;
  if (!t) return [];
  return typeof t === 'string' ? [t] : t;
};

const resetDom = () => {
  document.getElementById(EXTERNAL_STYLE_ID)?.remove();
  html().removeAttribute('data-theme');
};

const applyRemote = (href) => {
  resetDom();
  const link = document.createElement('link');
  link.rel = 'stylesheet';
  link.type = 'text/css';
  link.id = EXTERNAL_STYLE_ID;
  link.href = href;
  document.head.appendChild(link);
};

/* Collect every CSS var name that appears in any theme's custom colors */
const allKnownVarNames = (colorMap) => {
  const names = new Set();
  Object.values(colorMap || {}).forEach((themeVars) => {
    Object.keys(themeVars || {}).forEach((v) => names.add(v));
  });
  return names;
};

const applyCustomVars = (theme, appConfig) => {
  let localColors = {};
  try {
    localColors = JSON.parse(localStorage[localStorageKeys.CUSTOM_COLORS] || '{}');
  } catch (e) {
    ErrorHandler('Corrupted theme data in localstorage', e);
  }
  const configColors = appConfig?.customColors || {};

  // Clear any and all vars set by a previous theme
  const toClear = new Set([
    ...mainCssVars,
    ...allKnownVarNames(configColors),
    ...allKnownVarNames(localColors),
  ]);
  toClear.forEach((v) => html().style.removeProperty(`--${v}`));

  // Apply the current theme's custom colors (localStorage overrides appConfig)
  const vars = { ...configColors, ...localColors }[theme];
  if (!vars) return;
  Object.entries(vars).forEach(([k, v]) => html().style.setProperty(`--${k}`, v));
};

/**
 * Apply a theme name to the document
 * Handles built-in, user-defined, external stylesheets,
 * the special "default" reset, and per-theme custom CSS vars
 */
export const applyTheme = (theme, appConfig = {}) => {
  if (!theme) return;
  const externals = getExternalThemes(appConfig);
  const locals = [...builtInThemes, ...getExtraThemeNames(appConfig)];

  if (theme.toLowerCase() === 'default') {
    resetDom();
  } else if (locals.includes(theme)) {
    resetDom();
    html().setAttribute('data-theme', theme);
  } else if (externals[theme]) {
    applyRemote(externals[theme]);
  }
  applyCustomVars(theme, appConfig);
};
