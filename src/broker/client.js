/**
 * The shell's client for the broker API.
 *
 * The broker is same-origin with the shell, so no CORS arrangement is needed
 * and the session's bearer token applies directly (architecture.md AR-14).
 * Every call has an explicit timeout, and a failure is returned to the caller
 * as a typed result rather than thrown into a component (A-6.6, S4).
 */

import getApiAuthHeader from '@/utils/auth/getApiAuthHeader';
import ErrorHandler from '@/utils/logging/ErrorHandler';

/* Long enough for a fan-out across three applications, short enough that the
   user is never left waiting on a wedged request. */
export const DEFAULT_TIMEOUT_MS = 15000;

/**
 * Call a broker route.
 *
 * Returns `{ ok, status, data }` on a response the broker produced and
 * `{ ok: false, status: 0, reason }` when the call itself failed, so a caller
 * can tell "the broker said unsupported" from "the broker is not there".
 */
export const request = async (path, { method = 'GET', body, timeoutMs = DEFAULT_TIMEOUT_MS } = {}) => {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const authHeader = getApiAuthHeader();
    const res = await fetch(path, {
      method,
      credentials: 'same-origin',
      headers: {
        Accept: 'application/json',
        ...(body ? { 'Content-Type': 'application/json' } : {}),
        ...(authHeader || {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: controller.signal,
    });
    let data = null;
    try {
      data = await res.json();
    } catch {
      // A route with no body (204) or a non-JSON error page: the status is the
      // answer, and there is nothing to parse.
      data = null;
    }
    return {
      ok: res.ok, status: res.status, data,
    };
  } catch (e) {
    const reason = e?.name === 'AbortError' ? 'timeout' : 'unreachable';
    ErrorHandler(`[broker] ${method} ${path} failed: ${reason}`, e);
    return {
      ok: false, status: 0, reason, data: null,
    };
  } finally {
    clearTimeout(timer);
  }
};

export const postJson = (path, body, options = {}) => request(path, { ...options, method: 'POST', body });

export default request;
