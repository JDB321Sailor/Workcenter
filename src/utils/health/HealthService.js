/**
 * Integration health.
 *
 * The application switcher shows one status indicator per application (design.md
 * D-2S). The states come from the broker's health endpoint, which composes the
 * container healthchecks described in integration.md section 10.
 *
 * Until the broker exists the endpoint is absent, so every application reports
 * `unknown`. That is a real state, not an error: the indicator is grey and its
 * tooltip says the check has not run.
 */

import request from '@/utils/request';
import { APP_LIST } from '@/utils/apps/registry';
import { serviceEndpoints } from '@/utils/config/defaults';
import ErrorHandler from '@/utils/logging/ErrorHandler';

/** The four states an indicator can be in. */
export const HEALTH = Object.freeze({
  HEALTHY: 'healthy',
  DEGRADED: 'degraded',
  UNHEALTHY: 'unhealthy',
  UNKNOWN: 'unknown',
});

/** The poll interval while everything is healthy. */
const BASE_INTERVAL_MS = 30 * 1000;
/** The ceiling the backoff climbs to while nothing changes. */
const MAX_INTERVAL_MS = 5 * 60 * 1000;
/** Never poll faster than this, whatever a caller asks for. */
const MIN_INTERVAL_MS = 15 * 1000;

/** Every application starts unknown, and its own entry carries the detail. */
const unknownState = () => APP_LIST.reduce((acc, app) => {
  acc[app.id] = { state: HEALTH.UNKNOWN, check: '', since: null };
  return acc;
}, {});

const HealthService = {
  /** Reactive-by-reference state, read by the switcher's indicators. */
  state: {
    apps: unknownState(),
    lastChecked: null,
    polling: false,
  },

  _timer: null,
  _interval: BASE_INTERVAL_MS,

  /** The health entry for one application. */
  forApp(appId) {
    return this.state.apps[appId] || { state: HEALTH.UNKNOWN, check: '', since: null };
  },

  /** True when every application is healthy. */
  allHealthy() {
    return APP_LIST.every((app) => this.forApp(app.id).state === HEALTH.HEALTHY);
  },

  /** Replace the state from a health payload keyed by application id. */
  apply(payload) {
    const next = unknownState();
    Object.entries(payload || {}).forEach(([appId, entry]) => {
      if (!next[appId]) return; // An application this build does not have.
      next[appId] = {
        state: entry?.state || HEALTH.UNKNOWN,
        check: entry?.check || '',
        since: entry?.since || null,
      };
    });
    this.state.apps = next;
    this.state.lastChecked = new Date().toISOString();
  },

  /** Mark one application's state directly, for tests and for local changes. */
  set(appId, state, check = '') {
    if (!this.state.apps[appId]) return;
    this.state.apps[appId] = { state, check, since: new Date().toISOString() };
  },

  /**
   * Poll once.
   *
   * A failed poll is not an application failure: it means the check itself did
   * not run, so every application goes to `unknown` rather than `unhealthy`.
   */
  async check() {
    try {
      const res = await request.get(serviceEndpoints.brokerHealth);
      this.apply(res?.apps || res || {});
      return this.state.apps;
    } catch {
      this.apply({});
      return this.state.apps;
    }
  },

  /** Back off while the state does not change, and reset when it does. */
  _nextInterval(previous) {
    const changed = APP_LIST.some((app) => this.forApp(app.id).state !== previous[app.id]);
    if (changed) return BASE_INTERVAL_MS;
    return Math.min(this._interval * 2, MAX_INTERVAL_MS);
  },

  /** Start polling. Safe to call twice. */
  start(intervalMs = BASE_INTERVAL_MS) {
    this.stop();
    this._interval = Math.max(intervalMs, MIN_INTERVAL_MS);
    this.state.polling = true;
    const tick = async () => {
      const before = Object.fromEntries(
        APP_LIST.map((app) => [app.id, this.forApp(app.id).state]),
      );
      await this.check();
      this._interval = this._nextInterval(before);
      if (this.state.polling) this._timer = setTimeout(tick, this._interval);
    };
    this._timer = setTimeout(tick, 0);
  },

  /** Stop polling. */
  stop() {
    this.state.polling = false;
    if (this._timer) clearTimeout(this._timer);
    this._timer = null;
  },

  /** Log a configuration problem without breaking the shell. */
  warn(message) {
    ErrorHandler(`[health] ${message}`);
  },
};

export default HealthService;
