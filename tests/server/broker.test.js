// @vitest-environment node
import {
  describe, it, expect, vi,
} from 'vitest';
import express from 'express';
import request from 'supertest';
import { createBrokerRouter, validatePreferences } from '../../services/utils/broker';
import { OUTCOME } from '../../services/utils/broker/adapters/preferences';
import { fanOut } from '../../services/utils/broker/engine/preferences';
import { parseFraming, composeHealth } from '../../services/utils/broker/health/integrations';

/**
 * The broker API.
 *
 * Every route except health is authenticated and acts only on the caller
 * (architecture.md AR-15, AR-47). The health route must never break the shell:
 * an unreachable application is reported, not thrown.
 */

const appFor = ({ adapters = [], authMiddleware, applications = {} } = {}) => {
  const app = express();
  app.use(express.json());
  const { router } = createBrokerRouter({
    applications,
    adapters,
    authMiddleware: authMiddleware || ((req, res, next) => {
      req.auth = { user: 'jane', isAdmin: false };
      next();
    }),
  });
  app.use('/api/broker', router);
  return app;
};

describe('POST /api/broker/preferences', () => {
  it('refuses an unauthenticated request', async () => {
    const app = appFor({
      authMiddleware: (req, res) => res.status(401).json({ ok: false, error: 'unauthenticated' }),
    });
    const res = await request(app).post('/api/broker/preferences').send({ mode: 'light' });
    expect(res.status).toBe(401);
  });

  it('rejects a mode that is not dark or light', async () => {
    const app = appFor();
    const res = await request(app).post('/api/broker/preferences').send({ mode: 'purple' });
    expect(res.status).toBe(400);
  });

  it('rejects a body with neither mode nor locale', async () => {
    const app = appFor();
    const res = await request(app).post('/api/broker/preferences').send({});
    expect(res.status).toBe(400);
  });

  it('rejects an unknown adapter identifier', async () => {
    const app = appFor();
    const res = await request(app)
      .post('/api/broker/preferences')
      .send({ locale: 'de', adapters: { gmail: 'de' } });
    expect(res.status).toBe(400);
  });

  it('acts only on the user from the token, ignoring a user in the body', async () => {
    const seen = [];
    const adapter = {
      id: 'files',
      supports: ['mode'],
      apply: vi.fn(async ({ userId }) => {
        seen.push(userId);
        return { outcome: OUTCOME.OK };
      }),
    };
    const app = appFor({ adapters: [adapter] });
    await request(app)
      .post('/api/broker/preferences')
      .send({ mode: 'light', userId: 'someone-else', user: 'someone-else' });
    expect(seen).toEqual(['jane']);
  });

  it('answers with a per-application result, including partial failure', async () => {
    const app = appFor({
      adapters: [
        { id: 'files', supports: ['mode'], apply: async () => ({ outcome: OUTCOME.OK }) },
        { id: 'chat', supports: ['mode'], apply: async () => ({ outcome: OUTCOME.FAILED, reason: 'status-500' }) },
        { id: 'mail', supports: [], apply: async () => ({ outcome: OUTCOME.OK }) },
      ],
    });
    const res = await request(app).post('/api/broker/preferences').send({ mode: 'dark' });
    expect(res.status).toBe(200);
    expect(res.body.apps.files.outcome).toBe(OUTCOME.OK);
    expect(res.body.apps.chat.outcome).toBe(OUTCOME.FAILED);
    expect(res.body.apps.mail.outcome).toBe(OUTCOME.UNSUPPORTED);
    expect(res.body.ok).toBe(false);
  });

  it('passes the per-application locale identifiers through to the adapters', async () => {
    const adapter = {
      id: 'files',
      supports: ['locale'],
      apply: vi.fn(async () => ({ outcome: OUTCOME.OK })),
    };
    const app = appFor({ adapters: [adapter] });
    await request(app)
      .post('/api/broker/preferences')
      .send({ locale: 'pt-BR', adapters: { filebrowser: 'ptBR', zulip: 'pt' } });
    expect(adapter.apply).toHaveBeenCalledWith(expect.objectContaining({
      filebrowserLocale: 'ptBR',
      zulipLocale: 'pt',
    }));
  });
});

describe('GET /api/broker/health', () => {
  it('reports one state per application without requiring a session', async () => {
    const app = appFor({
      applications: {
        files: { url: 'https://files.example.com' },
        chat: 'https://chat.example.com',
      },
      authMiddleware: (req, res) => res.status(401).json({ ok: false }),
    });
    const res = await request(app).get('/api/broker/health');
    expect(res.status).toBe(200);
    expect(res.headers['cache-control']).toBe('no-store');
    expect(Object.keys(res.body.apps).sort()).toEqual(['chat', 'files', 'mail']);
    // The example hosts do not resolve here, so every application is reported
    // unreachable — a stated state, never an exception.
    expect(res.body.apps.files.state).toBe('unhealthy');
    // The mail address is absent, which is unknown rather than broken.
    expect(res.body.apps.mail.state).toBe('unknown');
  });

  it('never leaks a user or a secret in the payload', async () => {
    const app = appFor({ applications: { files: 'https://files.example.com' } });
    const res = await request(app).get('/api/broker/health');
    const body = JSON.stringify(res.body);
    expect(body).not.toMatch(/jane/);
    expect(body).not.toMatch(/token|password|secret/i);
  });
});

describe('validatePreferences', () => {
  it('accepts a mode alone, a locale alone, and both', () => {
    expect(validatePreferences({ mode: 'dark' })).toBeNull();
    expect(validatePreferences({ locale: 'de' })).toBeNull();
    expect(validatePreferences({ mode: 'light', locale: 'zh-CN', adapters: { filebrowser: 'zhCN' } })).toBeNull();
  });

  it('rejects a non-object body and an over-long locale', () => {
    expect(validatePreferences(null)).toBeTruthy();
    expect(validatePreferences([])).toBeTruthy();
    expect(validatePreferences({ locale: 'x'.repeat(40) })).toBeTruthy();
  });
});

describe('the preference fan-out', () => {
  it('reports unsupported without calling an adapter that has no such surface', async () => {
    const adapter = { id: 'mail', supports: [], apply: vi.fn() };
    const result = await fanOut([adapter], { userId: 'jane', mode: 'dark' });
    expect(adapter.apply).not.toHaveBeenCalled();
    expect(result.apps.mail.outcome).toBe(OUTCOME.UNSUPPORTED);
  });

  it('does not let one failing application stop the others', async () => {
    const adapters = [
      { id: 'files', supports: ['mode'], apply: async () => ({ outcome: OUTCOME.OK }) },
      { id: 'chat', supports: ['mode'], apply: async () => { throw new Error('boom'); } },
    ];
    const result = await fanOut(adapters, { userId: 'jane', mode: 'light' });
    expect(result.apps.files.outcome).toBe(OUTCOME.OK);
    expect(result.apps.chat.outcome).toBe(OUTCOME.FAILED);
  });

  it('answers unavailable when an adapter runs past the deadline', async () => {
    const adapters = [{
      id: 'chat',
      supports: ['mode'],
      apply: () => new Promise(() => {}),
    }];
    const result = await fanOut(adapters, { userId: 'jane', mode: 'dark', deadlineMs: 20 });
    expect(result.apps.chat.outcome).toBe(OUTCOME.UNAVAILABLE);
    expect(result.apps.chat.reason).toBe('deadline');
  });
});

describe('framing detection', () => {
  const headers = (map) => new Map(Object.entries(map));

  it('flags the two blocking X-Frame-Options values', () => {
    expect(parseFraming(headers({ 'x-frame-options': 'DENY' }))).toBe(true);
    expect(parseFraming(headers({ 'x-frame-options': 'SAMEORIGIN' }))).toBe(true);
  });

  it('allows a response that does not restrict framing', () => {
    expect(parseFraming(headers({}))).toBe(false);
  });

  it('flags a restrictive frame-ancestors policy', () => {
    expect(parseFraming(headers({ 'content-security-policy': "frame-ancestors 'none'" }))).toBe(true);
    expect(parseFraming(headers({ 'content-security-policy': "frame-ancestors 'self' https://example.com" }))).toBe(true);
    expect(parseFraming(headers({ 'content-security-policy': 'frame-ancestors *' }))).toBe(false);
  });

  it('accepts an allow-list that names the shell own origin', () => {
    const shell = 'https://workcenter.local';
    const csp = (v) => headers({ 'content-security-policy': v });
    /* What the deployment is required to send (IN-5.8): the shell's origin, never
       `*`. */
    expect(parseFraming(csp(`frame-ancestors ${shell}`), shell)).toBe(false);
    expect(parseFraming(csp(`frame-ancestors 'self' ${shell}`), shell)).toBe(false);
    /* An origin that is not the shell's still blocks it. */
    expect(parseFraming(csp('frame-ancestors https://example.com'), shell)).toBe(true);
    expect(parseFraming(csp("frame-ancestors 'self'"), shell)).toBe(true);
    /* `'self'` is the application's own origin, which is a different host here. */
    expect(parseFraming(csp("frame-ancestors 'none'"), shell)).toBe(true);
    expect(parseFraming(csp('frame-ancestors *'), shell)).toBe(false);
    /* Without the shell's origin the check cannot judge an allow-list, so it keeps
       the conservative answer. */
    expect(parseFraming(csp(`frame-ancestors ${shell}`))).toBe(true);
  });

  it('lets frame-ancestors decide when X-Frame-Options is also present', () => {
    /* Zulip ships `X-Frame-Options: DENY` and the ingress adds the allow-list; a
       browser ignores the first when it sees the second (integration.md §5.4). */
    const shell = 'https://workcenter.local';
    const both = (csp) => headers({
      'x-frame-options': 'DENY',
      'content-security-policy': csp,
    });
    expect(parseFraming(both(`frame-ancestors ${shell}`), shell)).toBe(false);
    /* An allow-list that does not cover the shell still blocks it, XFO or not. */
    expect(parseFraming(both('frame-ancestors https://example.com'), shell)).toBe(true);
    /* With no frame-ancestors, XFO is the only policy there is. */
    expect(parseFraming(headers({ 'x-frame-options': 'DENY' }), shell)).toBe(true);
    expect(parseFraming(headers({ 'x-frame-options': 'SAMEORIGIN' }), shell)).toBe(true);
  });
});

describe('composeHealth', () => {
  const transport = {
    head: async (url) => {
      if (url.includes('blocked')) return new Map([['x-frame-options', 'DENY']]);
      if (url.includes('down')) throw Object.assign(new Error('nope'), { code: 'ECONNREFUSED' });
      if (url.includes('slow')) throw Object.assign(new Error('timeout'), { code: 'timeout' });
      return new Map();
    },
  };

  it('reports healthy, degraded, unhealthy and unknown distinctly', async () => {
    const result = await composeHealth({
      applications: {
        files: 'https://ok.example.com',
        chat: 'https://blocked.example.com',
        mail: 'https://down.example.com',
      },
      transport,
      now: () => new Date('2026-01-01T00:00:00.000Z'),
    });
    expect(result.apps.files.state).toBe('healthy');
    expect(result.apps.files.frameBlocked).toBe(false);
    expect(result.apps.chat.state).toBe('degraded');
    expect(result.apps.chat.frameBlocked).toBe(true);
    expect(result.apps.mail.state).toBe('unhealthy');
    expect(result.apps.files.since).toBe('2026-01-01T00:00:00.000Z');
  });
});
