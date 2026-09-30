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

/* Cross-origin framing is refused by these values; `sameorigin` blocks every
   other origin, which is what the shell is. */
const parseFraming = (headers) => {
  const xfo = String(headers.get('x-frame-options') || '').toLowerCase();
  if (xfo.includes('deny') || xfo.includes('sameorigin')) return true;
  const csp = String(headers.get('content-security-policy') || '').toLowerCase();
  if (csp.includes('frame-ancestors')) {
    /* A directive that allows nobody, or does not allow any host, blocks the
       shell. `frame-ancestors *` is the only permissive form we can judge
       without knowing the shell's origin. */
    const directive = csp.split('frame-ancestors')[1] || '';
    const value = directive.split(';')[0].trim();
    if (!value || value === "'none'" || value === "'self'") return true;
    if (!value.includes('*')) return true;
  }
  return false;
};

/** Probe one application. */
const probe = async ({ id, url, transport, fetchImpl }) => {
  if (!url) {
    return { id, state: HEALTH.UNKNOWN, check: 'no address configured', endpoint: url || '' };
  }
  try {
    const headers = await transport.head(url, { timeoutMs: PROBE_TIMEOUT_MS, fetchImpl });
    const frameBlocked = parseFraming(headers);
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
const composeHealth = async ({ applications = {}, transport, fetchImpl, now = () => new Date() }) => {
  const targets = [
    { id: 'files', url: addressOf(applications.files) },
    { id: 'chat', url: addressOf(applications.chat) },
    { id: 'mail', url: addressOf(applications.mail) },
  ];
  const probed = await Promise.all(
    targets.map((target) => probe({ ...target, transport, fetchImpl })),
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
