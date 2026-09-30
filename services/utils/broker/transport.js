/**
 * The broker's outbound HTTP transport.
 *
 * One implementation for every adapter, so timeouts, the user agent and TLS
 * verification live in exactly one place (standards.md S-ND-7). TLS verification
 * is never disabled here.
 */

const DEFAULT_TIMEOUT_MS = 10000;
const USER_AGENT = 'Workcenter-Broker/0.1';

const timeoutError = () => {
  const error = new Error('request timed out');
  error.code = 'timeout';
  return error;
};

/** One request, with an explicit timeout. Returns `{ status, headers, body }`. */
const request = async ({
  method = 'GET',
  url,
  query,
  headers = {},
  body,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  fetchImpl = globalThis.fetch,
}) => {
  const target = new URL(url);
  Object.entries(query || {}).forEach(([key, value]) => {
    if (value !== undefined && value !== null) target.searchParams.set(key, String(value));
  });

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetchImpl(target.toString(), {
      method,
      headers: {
        'User-Agent': USER_AGENT,
        Accept: 'application/json',
        ...(body ? { 'Content-Type': 'application/json' } : {}),
        ...headers,
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: controller.signal,
      redirect: 'manual',
    });
    let parsed = null;
    const text = await res.text().catch(() => '');
    if (text) {
      try {
        parsed = JSON.parse(text);
      } catch {
        parsed = null; // A non-JSON body is a valid answer; the status is the signal.
      }
    }
    return { status: res.status, headers: res.headers, body: parsed };
  } catch (e) {
    if (e?.name === 'AbortError') throw timeoutError();
    throw e;
  } finally {
    clearTimeout(timer);
  }
};

/** A HEAD probe, used by the health checks. Returns the response headers. */
const head = async (url, { timeoutMs = DEFAULT_TIMEOUT_MS, fetchImpl = globalThis.fetch } = {}) => {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetchImpl(url, {
      method: 'HEAD',
      headers: { 'User-Agent': USER_AGENT },
      signal: controller.signal,
      redirect: 'manual',
    });
    return res.headers;
  } catch (e) {
    if (e?.name === 'AbortError') throw timeoutError();
    throw e;
  } finally {
    clearTimeout(timer);
  }
};

module.exports = {
  request, head, DEFAULT_TIMEOUT_MS, USER_AGENT,
};
