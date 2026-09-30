/**
 * The broker's per-application preference adapters.
 *
 * Each adapter is a pure module with an injected transport, so it is unit
 * testable without a live application (architecture.md AR-17). An adapter that
 * has no preference surface returns `unsupported`, which is a normal outcome
 * and not an error (AR-48).
 *
 * Every request shape here was read from the pinned upstream source:
 * - FileBrowser Quantum: `frontend/src/api/users.js` and
 *   `backend/internal/web/users.go` — `PATCH /api/users?username=<login>` with
 *   `{which:[…], data:{…}}`, 204 on success. `darkMode` is a plain bool, so the
 *   value must always accompany the key.
 * - Zulip: `PATCH /api/v1/settings` with `color_scheme` (1 automatic, 2 dark,
 *   3 light) and `default_language`.
 */

const OUTCOME = Object.freeze({
  OK: 'ok',
  UNSUPPORTED: 'unsupported',
  UNAVAILABLE: 'unavailable',
  FAILED: 'failed',
});

/* The two colour-scheme values Workcenter uses, from the Zulip model. */
const ZULIP_COLOR_SCHEME = Object.freeze({ dark: 2, light: 3 });

/**
 * FileBrowser Quantum.
 *
 * The user's own session is required: `darkMode` and `locale` are
 * non-admin-editable, which is exactly why the user's credentials are used and
 * never a service token (integration.md IN-3.16).
 */
const createFilesAdapter = ({ transport, credentialsFor }) => ({
  id: 'files',
  supports: ['mode', 'locale'],

  async apply({ userId, mode, locale, filebrowserLocale }) {
    const credentials = await credentialsFor('files', userId);
    if (!credentials) return { outcome: OUTCOME.UNAVAILABLE, reason: 'no-session' };
    if (!filebrowserLocale && !mode) return { outcome: OUTCOME.UNSUPPORTED };

    const which = [];
    const data = {};
    if (mode) {
      which.push('darkMode');
      data.darkMode = mode === 'light' ? false : true;
    }
    if (filebrowserLocale) {
      which.push('locale');
      data.locale = filebrowserLocale;
    }

    try {
      const res = await transport.request({
        method: 'PATCH',
        url: `${credentials.baseUrl}/api/users`,
        query: { username: credentials.username },
        headers: { Cookie: credentials.cookie },
        body: { which, data },
      });
      if (res.status === 204) return { outcome: OUTCOME.OK };
      if (res.status === 401 || res.status === 403) {
        return { outcome: OUTCOME.UNAVAILABLE, reason: 'session-rejected' };
      }
      return { outcome: OUTCOME.FAILED, reason: `status-${res.status}` };
    } catch (e) {
      return { outcome: OUTCOME.FAILED, reason: e?.code || 'request-failed' };
    }
  },
});

/**
 * Zulip.
 *
 * `PATCH /api/v1/settings` is a human-user endpoint, so a bot key cannot call
 * it: the adapter needs the user's own credentials (integration.md IN-5.23).
 */
const createChatAdapter = ({ transport, credentialsFor }) => ({
  id: 'chat',
  supports: ['mode', 'locale'],

  async apply({ userId, mode, locale, zulipLocale }) {
    const credentials = await credentialsFor('chat', userId);
    if (!credentials) return { outcome: OUTCOME.UNAVAILABLE, reason: 'no-session' };
    if (!mode && !zulipLocale) return { outcome: OUTCOME.UNSUPPORTED };

    const body = {};
    if (mode) body.color_scheme = ZULIP_COLOR_SCHEME[mode] || ZULIP_COLOR_SCHEME.dark;
    if (zulipLocale) body.default_language = zulipLocale;

    try {
      const res = await transport.request({
        method: 'PATCH',
        url: `${credentials.baseUrl}/api/v1/settings`,
        headers: { Authorization: credentials.authorization },
        body,
      });
      if (res.status === 200) return { outcome: OUTCOME.OK };
      if (res.status === 401 || res.status === 403) {
        return { outcome: OUTCOME.UNAVAILABLE, reason: 'session-rejected' };
      }
      return { outcome: OUTCOME.FAILED, reason: `status-${res.status}` };
    } catch (e) {
      return { outcome: OUTCOME.FAILED, reason: e?.code || 'request-failed' };
    }
  },
});

/**
 * The Mail pane.
 *
 * SOGo has no appearance or language API, and the Mailcow UI is not a pane:
 * the shell supplies its palette through the stylesheet and JavaScript hook
 * provisioned at setup, and drives the live switch with the `wc_mode` cookie
 * and a pane message (integration.md IN-6.23, IN-6.29). There is nothing for
 * the broker to call, and saying so is the correct answer.
 */
const createMailAdapter = () => ({
  id: 'mail',
  supports: [],
  async apply() {
    return { outcome: OUTCOME.UNSUPPORTED, reason: 'shell-cookie-and-message' };
  },
});

module.exports = {
  OUTCOME,
  ZULIP_COLOR_SCHEME,
  createFilesAdapter,
  createChatAdapter,
  createMailAdapter,
};
