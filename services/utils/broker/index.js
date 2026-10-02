/**
 * The broker API.
 *
 * Same origin as the shell, so no CORS arrangement is needed and the session's
 * bearer token applies directly (architecture.md AR-14, AR-15). The only
 * unauthenticated route is the health probe, and it answers with liveness and
 * per-application reachability only — never with anything about a user.
 *
 * Phase 2 ships the two routes the shell needs: the status indicators' health
 * feed, and the appearance/language fan-out. The transfer routes arrive with the
 * file-movement phase and are deliberately absent rather than stubbed.
 */

const express = require('express');
const { loadOidcSettings, createOidcMiddleware } = require('../../utils/auth-oidc');
const { composeHealth } = require('./health/integrations');
const { fanOut } = require('./engine/preferences');
const {
  OUTCOME, createFilesAdapter, createChatAdapter, createMailAdapter,
} = require('./adapters/preferences');
const transport = require('./transport');

const PREFERENCES_DEADLINE_MS = 10000;

/* The per-application identifiers the shell resolved from its locale registry.
   The shell owns that mapping (design.md D-I6), so the broker only checks that
   what it was handed is a short string. */
const isValidIdentifier = (value) => typeof value === 'string' && value.length > 0 && value.length <= 32;

const isValidMode = (value) => value === 'dark' || value === 'light';

/** Validate the preference body. Returns an error message, or null. */
const validatePreferences = (body) => {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return 'body must be an object';
  const { mode, locale, adapters } = body;
  if (mode === undefined && locale === undefined) return 'mode or locale is required';
  if (mode !== undefined && !isValidMode(mode)) return 'mode must be "dark" or "light"';
  if (locale !== undefined && (typeof locale !== 'string' || locale.length > 35)) {
    return 'locale must be a language tag';
  }
  if (adapters !== undefined) {
    if (typeof adapters !== 'object' || adapters === null || Array.isArray(adapters)) {
      return 'adapters must be an object';
    }
    const unknown = Object.keys(adapters).filter((key) => !['filebrowser', 'zulip'].includes(key));
    if (unknown.length) return `unknown adapter: ${unknown[0]}`;
    const bad = Object.entries(adapters).find(([, value]) => !isValidIdentifier(value));
    if (bad) return `adapter ${bad[0]} must be an identifier`;
  }
  return null;
};

/**
 * Build the broker router.
 *
 * Everything it needs is injected, so the routes are testable without a live
 * deployment and without real credentials.
 */
const createBrokerRouter = ({
  applications = {},
  authConfig = {},
  /* The shell's own origin, used to judge an application's framing allow-list
     (WORKCENTER_BASE_URL). Empty means "cannot judge", and the check then accepts
     only `frame-ancestors *`. */
  shellOrigin = '',
  adapters = [],
  credentialsFor = async () => null,
  transportImpl = transport,
  fetchImpl = globalThis.fetch,
  now = () => new Date(),
  /* Injected so the routes can be tested without a live identity provider. The
     default verifies the session's bearer token against Authentik's JWKS. */
  authMiddleware = null,
} = {}) => {
  const router = express.Router();
  const oidcSettings = loadOidcSettings(authConfig);
  /* The adapter set is resolved once, before the routes close over it. */
  const activeAdapters = adapters.length
    ? adapters
    : [
      createFilesAdapter({ transport: transportImpl, credentialsFor }),
      createChatAdapter({ transport: transportImpl, credentialsFor }),
      createMailAdapter(),
    ];

  /* Health: liveness plus per-application reachability. No user data. */
  router.get('/health', async (req, res) => {
    try {
      const payload = await composeHealth({
        applications,
        transport: transportImpl,
        fetchImpl,
        now,
        shellOrigin,
      });
      res.set('Cache-Control', 'no-store');
      return res.json({ status: 'ok', apps: payload.apps });
    } catch (e) {
      // The shell treats a failed poll as "unknown", so liveness is still ok.
      console.warn('[broker] health composition failed:', e?.message || e); // eslint-disable-line no-console
      return res.status(500).json({ status: 'error', apps: {} });
    }
  });

  /* Everything below acts on a user and therefore requires a verified token.
     With no identity provider configured the broker has no way to attribute a
     request, so it refuses rather than guessing. */
  const requireAuth = authMiddleware || ((req, res, next) => {
    if (!oidcSettings) {
      return res.status(401).json({ ok: false, error: 'no identity provider configured' });
    }
    return createOidcMiddleware(oidcSettings)(req, res, () => {
      if (!req.auth) return res.status(401).json({ ok: false, error: 'unauthenticated' });
      return next();
    });
  });

  router.post('/preferences', requireAuth, async (req, res) => {
    const problem = validatePreferences(req.body);
    if (problem) return res.status(400).json({ ok: false, error: problem });

    const { mode, locale, adapters: adapterLocales } = req.body;
    /* The user comes from the verified token, never from the body. */
    const userId = req.auth.user;
    try {
      const result = await fanOut(activeAdapters, {
        userId,
        mode,
        locale,
        adapterLocales: adapterLocales || {},
        deadlineMs: PREFERENCES_DEADLINE_MS,
      });
      return res.json(result);
    } catch (e) {
      console.error('[broker] preference fan-out failed:', e?.message || e); // eslint-disable-line no-console
      return res.status(500).json({ ok: false, apps: {} });
    }
  });

  return { router, adapters: activeAdapters };
};

module.exports = {
  createBrokerRouter, validatePreferences, OUTCOME,
};
