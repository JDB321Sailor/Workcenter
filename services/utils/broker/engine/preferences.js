/**
 * The preference fan-out.
 *
 * One switch in the shell becomes one request here, and this engine asks every
 * adapter in parallel and answers with a per-application result so the shell can
 * name a partial failure instead of pretending the switch worked
 * (architecture.md AR-47, AR-48; design.md D-6.1).
 *
 * The engine acts on the user resolved from the verified token — never on a
 * user named in the request body, which it does not read.
 */

const { OUTCOME } = require('../adapters/preferences');

/* A fan-out that has not answered by now is reported as unavailable; the shell
   has a 15 s budget and must not be left waiting on a wedged application. */
const DEFAULT_DEADLINE_MS = 10000;

const withDeadline = (promise, ms) => Promise.race([
  promise,
  new Promise((resolve) => {
    const timer = setTimeout(() => resolve({ outcome: OUTCOME.UNAVAILABLE, reason: 'deadline' }), ms);
    if (typeof timer.unref === 'function') timer.unref();
  }),
]);

/**
 * Fan a preference out to every adapter.
 *
 * `preferences` is `{ mode, locale, adapters }`; the validators in the router
 * have already checked its shape.
 */
const fanOut = async (adapters, { userId, mode, locale, adapterLocales = {}, deadlineMs = DEFAULT_DEADLINE_MS }) => {
  const results = await Promise.all(adapters.map(async (adapter) => {
    const wanted = [];
    if (mode) wanted.push('mode');
    if (locale) wanted.push('locale');
    /* An adapter that offers none of the requested surfaces answers
       `unsupported` without being called. */
    if (!wanted.some((surface) => adapter.supports.includes(surface))) {
      return [adapter.id, { outcome: OUTCOME.UNSUPPORTED }];
    }
    const call = adapter.apply({
      userId,
      mode,
      locale,
      filebrowserLocale: adapterLocales.filebrowser,
      zulipLocale: adapterLocales.zulip,
    }).catch((e) => ({ outcome: OUTCOME.FAILED, reason: e?.code || 'adapter-failed' }));
    return [adapter.id, await withDeadline(call, deadlineMs)];
  }));

  const apps = Object.fromEntries(results);
  return {
    ok: Object.values(apps).every((entry) => entry.outcome === OUTCOME.OK || entry.outcome === OUTCOME.UNSUPPORTED),
    apps,
  };
};

module.exports = { fanOut, DEFAULT_DEADLINE_MS };
