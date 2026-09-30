import {
  describe, it, expect, beforeEach, vi,
} from 'vitest';
import {
  MODE, DEFAULT_MODE, modeState, cookieDomain, readStoredMode, initModeFromStorage,
  applyModeToShell, applyLanguageToShell, registerPane, postToPanes, setMode,
} from '@/utils/Theming';
import { localStorageKeys } from '@/utils/config/defaults';

vi.mock('@/utils/request', () => ({ default: { get: vi.fn() } }));
vi.mock('@/broker/preferences', () => ({
  applyPreferences: vi.fn(async () => ({ ok: true, apps: { files: 'ok', chat: 'ok', mail: 'unsupported' } })),
  OUTCOME: { OK: 'ok', UNSUPPORTED: 'unsupported', UNAVAILABLE: 'unavailable', FAILED: 'failed' },
}));

// eslint-disable-next-line import/first
import { applyPreferences } from '@/broker/preferences';

/**
 * The appearance engine.
 *
 * Dark is the default, the shell repaints from a document attribute, the mode
 * cookie carries no identity, and a pane message always goes to that pane's
 * exact origin (design.md D-6.1, D-4.4.2, D-T8).
 */
describe('the appearance mode', () => {
  const appConfig = {
    applications: {
      files: { url: 'https://filebrowser.example.com' },
      chat: { url: 'https://chat.example.com' },
      mail: { url: 'https://mail.example.com/SOGo' },
    },
  };

  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.getItem.mockReturnValue(undefined);
    document.documentElement.removeAttribute('data-wc-mode');
    modeState.mode = DEFAULT_MODE;
    modeState.panes = {};
    modeState.applied = null;
  });

  it('defaults to dark when the user has never chosen', () => {
    expect(DEFAULT_MODE).toBe(MODE.DARK);
    expect(readStoredMode()).toBe(MODE.DARK);
  });

  it('remembers an explicit choice', () => {
    localStorage.getItem.mockReturnValue('light');
    expect(readStoredMode()).toBe(MODE.LIGHT);
  });

  it('sets the document attribute before the shell renders', () => {
    expect(initModeFromStorage()).toBe(MODE.DARK);
    expect(document.documentElement.getAttribute('data-wc-mode')).toBe(MODE.DARK);
  });

  it('repaints the shell without fetching anything', () => {
    applyModeToShell(MODE.LIGHT, appConfig);
    expect(document.documentElement.getAttribute('data-wc-mode')).toBe(MODE.LIGHT);
    expect(modeState.mode).toBe(MODE.LIGHT);
    expect(localStorage.setItem).toHaveBeenCalledWith(localStorageKeys.MODE, MODE.LIGHT);
    expect(applyPreferences).not.toHaveBeenCalled();
  });

  it('writes the mode cookie for the shared domain, with no identity in it', () => {
    const cookie = vi.spyOn(document, 'cookie', 'set');
    applyModeToShell(MODE.DARK, appConfig);
    const written = cookie.mock.calls.map(([value]) => value).join(';');
    expect(written).toContain('wc_mode=dark');
    expect(written).toContain('Domain=.example.com');
    expect(written).toContain('Path=/');
    expect(written).toContain('SameSite=Lax');
    expect(written).toContain('Max-Age=');
    expect(written).not.toMatch(/token|user|email/i);
    cookie.mockRestore();
  });

  it('derives the cookie domain by stripping the application host prefix', () => {
    expect(cookieDomain(appConfig)).toBe('.example.com');
    expect(cookieDomain({ applications: { files: 'https://files.example.co.uk' } })).toBe('.example.co.uk');
  });

  it('falls back to a host-only cookie when no application address is usable', () => {
    expect(cookieDomain({})).toBe('');
    expect(cookieDomain({ applications: { files: 'not a url' } })).toBe('');
  });

  it('posts the mode to each pane at its own exact origin, never a wildcard', () => {
    const filesWindow = { postMessage: vi.fn() };
    const chatWindow = { postMessage: vi.fn() };
    const unregisterFiles = registerPane('files', {
      origin: 'https://filebrowser.example.com',
      getWindow: () => filesWindow,
      refresh: () => true,
    });
    const unregisterChat = registerPane('chat', {
      origin: 'https://chat.example.com',
      getWindow: () => chatWindow,
      refresh: () => true,
    });

    postToPanes({ type: 'workcenter:mode', mode: 'light' });

    expect(filesWindow.postMessage).toHaveBeenCalledWith(
      { type: 'workcenter:mode', mode: 'light' },
      'https://filebrowser.example.com',
    );
    expect(chatWindow.postMessage).toHaveBeenCalledWith(
      { type: 'workcenter:mode', mode: 'light' },
      'https://chat.example.com',
    );
    const origins = [...filesWindow.postMessage.mock.calls, ...chatWindow.postMessage.mock.calls]
      .map(([, origin]) => origin);
    expect(origins).not.toContain('*');

    unregisterFiles();
    unregisterChat();
  });

  it('announces a language change to the panes and the document', () => {
    const pane = { postMessage: vi.fn() };
    const unregister = registerPane('chat', {
      origin: 'https://chat.example.com',
      getWindow: () => pane,
    });
    applyLanguageToShell('de');
    expect(document.documentElement.getAttribute('lang')).toBe('de');
    expect(pane.postMessage).toHaveBeenCalledWith({ type: 'workcenter:lang', locale: 'de' }, 'https://chat.example.com');
    expect(localStorage.setItem).toHaveBeenCalledWith(localStorageKeys.WC_LANGUAGE, 'de');
    unregister();
  });

  it('refreshes the Files pane only after the broker confirms, at its reported path', async () => {
    const refresh = vi.fn(() => true);
    const unregister = registerPane('files', {
      origin: 'https://filebrowser.example.com',
      getWindow: () => ({ postMessage: vi.fn() }),
      refresh,
    });

    const state = await setMode(MODE.LIGHT, appConfig);

    expect(applyPreferences).toHaveBeenCalledWith({ mode: 'light' }, {});
    expect(refresh).toHaveBeenCalledTimes(1);
    expect(state.panes.files).toBe('ok');
    expect(state.panes.mail).toBe('unsupported');
    unregister();
  });

  it('reports a deferred Files refresh while a document editor is open', async () => {
    const unregister = registerPane('files', {
      origin: 'https://filebrowser.example.com',
      getWindow: () => ({ postMessage: vi.fn() }),
      refresh: () => false,
    });

    const state = await setMode(MODE.LIGHT, appConfig);

    expect(state.panes.files).toBe('deferred');
    unregister();
  });
});
