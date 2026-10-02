/**
 * Integration health.
 *
 * The shell's status indicators are fed from here (design.md D-2S). Workcenter
 * never mounts the Docker socket (architecture.md AR-37), so this composes the
 * signals it can obtain over the network:
 *
 * - reachability of each configured application address, and
 * - whether that application refuses to be framed, which the shell cannot see
 *   from inside an iframe but a server-side fetch can (the header is visible in
 *   the response).
 *
 * A check that cannot run reports `unknown`, never `unhealthy`: not knowing is
 * not the same as being broken, and the shell must not cry wolf.
 */

const HEALTH = Object.freeze({
  HEALTHY: 'healthy',
  DEGRADED: 'degraded',
  UNHEALTHY: 'unhealthy',
  UNKNOWN: 'unknown',
});

/* Short: the indicator row must not wait on a slow application. */
const PROBE_TIMEOUT_MS = 4000;

/* Whether the application refuses to be framed by the shell.
 *
 * `frame-ancestors` is read first, and it decides on its own: a browser that sees
 * that directive **ignores `X-Frame-Options`** (CSP Level 2 and later), which is
 * how a Zulip that still sends `X-Frame-Options: DENY` — as the pinned upstream
 * image does — is framed by the ingress (integration.md §5.4, IN-5.8). Checking
 * XFO first would report the specified configuration as blocked.
 *
 * `shellOrigin` is the shell's own origin, which the health route takes from
 * WORKCENTER_BASE_URL: IN-8.5 requires every application to name that origin and
 * *never* `*`, so a check that only accepted `*` would do the same. `'self'` is
 * the *application's* origin, a different host from the shell's here, so it does
 * not cover the shell on its own. */
const parseFraming = (headers, shellOrigin = '') => {
  const csp = String(headers.get('content-security-policy') || '').toLowerCase();
  if (csp.includes('frame-ancestors')) {
    /* A directive that allows nobody, or that lists no source covering the shell,
       blocks it. */
    const value = (csp.split('frame-ancestors')[1] || '').split(';')[0].trim();
    if (!value) return true;
    const sources = value.split(/\s+/).filter(Boolean);
    if (sources.includes('*')) return false;
    if (shellOrigin && sources.includes(shellOrigin.toLowerCase())) return false;
    return true;
  }
  /* No `frame-ancestors`: X-Frame-Options is the only policy there is. */
  const xfo = String(headers.get('x-frame-options') || '').toLowerCase();
  return xfo.includes('deny') || xfo.includes('sameorigin');
};

/** Probe one application. */
const probe = async ({ id, url, transport, fetchImpl, shellOrigin = '' }) => {
  if (!url) {
    return { id, state: HEALTH.UNKNOWN, check: 'no address configured', endpoint: url || '' };
  }
  try {
    const headers = await transport.head(url, { timeoutMs: PROBE_TIMEOUT_MS, fetchImpl });
    const frameBlocked = parseFraming(headers, shellOrigin);
    return {
      id,
      state: frameBlocked ? HEALTH.DEGRADED : HEALTH.HEALTHY,
      check: frameBlocked ? 'refuses to be framed' : 'reachable',
      endpoint: url,
      frameBlocked,
    };
  } catch (e) {
    return {
      id,
      state: HEALTH.UNHEALTHY,
      check: e?.code === 'timeout' ? 'timed out' : 'unreachable',
      endpoint: url,
    };
  }
};

/** A configured application address is either a string or `{url}`. */
const addressOf = (configured) => {
  if (!configured) return '';
  if (typeof configured === 'string') return configured;
  return typeof configured.url === 'string' ? configured.url : '';
};

/**
 * Compose the per-application health payload.
 *
 * The application id is the shell's identifier (`files`, `chat`, `mail`), which
 * is what `HealthService` keys on.
 */
const composeHealth = async ({
  applications = {}, transport, fetchImpl, now = () => new Date(), shellOrigin = '',
}) => {
  const targets = [
    { id: 'files', url: addressOf(applications.files) },
    { id: 'chat', url: addressOf(applications.chat) },
    { id: 'mail', url: addressOf(applications.mail) },
  ];
  const probed = await Promise.all(
    targets.map((target) => probe({ ...target, transport, fetchImpl, shellOrigin })),
  );
  const since = now().toISOString();
  const apps = {};
  probed.forEach((entry) => {
    apps[entry.id] = {
      state: entry.state,
      check: entry.check,
      endpoint: entry.endpoint,
      frameBlocked: Boolean(entry.frameBlocked),
      since,
    };
  });
  return { apps };
};

module.exports = {
  HEALTH, composeHealth, parseFraming, PROBE_TIMEOUT_MS,
};
