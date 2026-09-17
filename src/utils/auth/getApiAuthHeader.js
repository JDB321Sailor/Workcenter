/**
 * Auth for internal API requests when OIDC/Keycloak is configured.
 * Uses the id_token stashed in localStorage after a successful login.
 *
 * `getApiAuthHeader()` returns the Bearer header, or null when the token is unusable.
 * `getApiAuthState()` returns { ok, reason, header? }, to say if/why token failed
 */

import { localStorageKeys } from '@/utils/config/defaults';

// Grace period on token expiry, 30 seconds
const CLOCK_TOLERANCE_MS = 30 * 1000;

/* Base64URL → utf-8 string decode */
function decodeBase64Url(input) {
  const padded = input.replace(/-/g, '+').replace(/_/g, '/');
  const pad = padded.length % 4;
  return atob(pad ? padded + '='.repeat(4 - pad) : padded);
}

const tokenParts = (token) => (typeof token === 'string' ? token.split('.') : []);

function decodeClaims(token) {
  const [, payload] = tokenParts(token);
  if (!payload) throw new Error('Missing token payload');
  return JSON.parse(decodeBase64Url(payload));
}

export function getApiAuthState() {
  let token;
  try {
    token = localStorage.getItem(localStorageKeys.ID_TOKEN);
  } catch {
    return { ok: false, reason: 'storage' };
  }
  if (!token) return { ok: false, reason: 'missing' };
  if (tokenParts(token).length === 5) return { ok: false, reason: 'encrypted-jwe' };
  if (tokenParts(token).length !== 3) return { ok: false, reason: 'malformed' };
  let claims;
  try {
    claims = decodeClaims(token);
    if (typeof claims.exp === 'number' && claims.exp * 1000 + CLOCK_TOLERANCE_MS <= Date.now()) {
      return { ok: false, reason: 'expired' };
    }
  } catch {
    return { ok: false, reason: 'malformed' };
  }
  return { ok: true, reason: 'valid', header: { Authorization: `Bearer ${token}` } };
}

/* Returns { Authorization: 'Bearer...' } or null if no usable token */
export default function getApiAuthHeader() {
  const auth = getApiAuthState();
  return auth.ok ? auth.header : null;
}
