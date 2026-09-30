/**
 * Appearance and language preferences.
 *
 * One switch in the shell has to reach three embedded applications that expose
 * three different mechanisms. The shell cannot hold their credentials, so the
 * fan-out happens in the broker, which acts only on the calling user
 * (architecture.md AR-47, design.md section 4.4).
 *
 * The bridge is advisory (rule D-T1): the broker adapters skip a user who has
 * set the value themselves, and this client never retries a refusal.
 */

import { postJson } from '@/broker/client';

export const PREFERENCES_PATH = '/api/broker/preferences';

/** The per-application outcomes the broker may report. */
export const OUTCOME = Object.freeze({
  OK: 'ok',
  UNSUPPORTED: 'unsupported',
  UNAVAILABLE: 'unavailable',
  FAILED: 'failed',
});

/** Every application, so a missing broker answer still has a stated outcome. */
const noAnswer = (reason) => ({
  files: reason,
  chat: reason,
  mail: reason,
});

/**
 * Ask the broker to forward the preference to the embedded applications.
 *
 * The request carries `mode` and/or `locale`, plus the per-application
 * identifier the shell's locale registry resolved (`adapters`), because the
 * mapping belongs to the shell and never to a caller (design.md D-I6). The
 * broker ignores an adapter it has no identifier for and reports it as
 * `unsupported`.
 *
 * Returns `{ ok, apps }`, where each entry is one of OUTCOME. When the broker
 * is absent — a shell-only deployment, or the broker not yet deployed — every
 * application is `unavailable`, which the user menu reports as "could not
 * switch" instead of pretending the switch worked.
 */
export const applyPreferences = async (preferences, { timeoutMs } = {}) => {
  const { mode, locale, adapters } = preferences || {};
  const body = {};
  if (mode) body.mode = mode;
  if (locale) body.locale = locale;
  if (adapters && Object.keys(adapters).length) body.adapters = adapters;
  if (!Object.keys(body).length) return { ok: true, apps: {} };

  const res = await postJson(PREFERENCES_PATH, body, { timeoutMs });
  if (res.status === 0) return { ok: false, apps: noAnswer(OUTCOME.UNAVAILABLE) };
  if (res.status === 401 || res.status === 403) {
    return { ok: false, apps: noAnswer(OUTCOME.UNAVAILABLE) };
  }
  if (res.status === 404) {
    // No broker in this deployment: a stated outcome, not a broken shell.
    return { ok: false, apps: noAnswer(OUTCOME.UNAVAILABLE) };
  }
  if (!res.ok) return { ok: false, apps: noAnswer(OUTCOME.FAILED) };

  const apps = res.data?.apps || {};
  return {
    ok: Boolean(res.data?.ok),
    apps: {
      files: apps.files?.outcome || apps.files || OUTCOME.UNSUPPORTED,
      chat: apps.chat?.outcome || apps.chat || OUTCOME.UNSUPPORTED,
      mail: apps.mail?.outcome || apps.mail || OUTCOME.UNSUPPORTED,
    },
  };
};

export default applyPreferences;
