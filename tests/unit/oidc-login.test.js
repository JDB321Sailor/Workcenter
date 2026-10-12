import { describe, it, expect } from 'vitest';
import { createHash } from 'node:crypto';
import path from 'node:path';

/**
 * `scripts/lib/oidc-login.mjs` is how `scripts/e2e.sh` proves single sign-on
 * without a browser: it drives Authentik's flow, exchanges the authorization code
 * and verifies the id_token against the provider's JWKS.
 *
 * The provider itself is exercised end to end by the harness's own checks when it
 * runs. What is tested here is the part that has no other guard and that failed
 * during development — the argument contract and the resolver — because a mistake
 * in either looks like "the deployment is broken" rather than "the test is wrong".
 */
const modulePath = path.resolve(__dirname, '../../scripts/lib/oidc-login.mjs');
const load = () => import(modulePath);

describe('oidc-login: arguments', () => {
  const base = [
    '--base-url', 'https://auth.example.com',
    '--client-id', 'workcenter',
    '--redirect-uri', 'https://example.com/',
    '--username', 'user@wc.test',
    '--password', 'secret',
  ];

  it('accepts a complete authorization-code invocation', async () => {
    const { parseArgs } = await load();
    const args = parseArgs(base);
    expect(args.baseUrl).toBe('https://auth.example.com');
    expect(args.clientId).toBe('workcenter');
    expect(args.redirectUri).toBe('https://example.com/');
    /* Defaults matter: the scope list is what carries `groups`, and a run that
       silently dropped it would produce a token with no groups claim and look
       like a broken group mapping. */
    expect(args.scope).toBe('openid profile email groups');
    expect(args.json).toBe(false);
  });

  it('normalises a trailing slash on the base URL', async () => {
    const { parseArgs } = await load();
    const args = parseArgs(['--base-url', 'https://auth.example.com/', ...base.slice(2)]);
    expect(args.baseUrl).toBe('https://auth.example.com');
  });

  it('requires a client and a redirect URI for a code exchange', async () => {
    const { parseArgs } = await load();
    expect(() => parseArgs(['--base-url', 'https://a.example', '--username', 'u', '--password', 'p']))
      .toThrow(/missing --client-id/);
  });

  it('does not require a client for the admin console or forward auth', async () => {
    /* Neither is an OIDC client flow: the console is the provider's own UI and
       forward auth is Traefik asking the outpost. Demanding a client id made both
       unusable, which is the regression this pins. */
    const { parseArgs } = await load();
    const minimal = ['--base-url', 'https://a.example', '--username', 'akadmin', '--password', 'p'];
    expect(parseArgs([...minimal, '--admin-console']).adminConsole).toBe(true);
    expect(parseArgs([...minimal, '--forward-auth', 'https://t.example/dashboard/']).forwardAuth)
      .toBe('https://t.example/dashboard/');
  });

  it('rejects an unknown flag rather than ignoring it', async () => {
    const { parseArgs } = await load();
    expect(() => parseArgs([...base, '--nonsense'])).toThrow(/unknown argument/);
  });
});

describe('oidc-login: PKCE', () => {
  it('derives the challenge as base64url(sha256(verifier))', async () => {
    const { pkce } = await load();
    const { verifier, challenge } = pkce();
    expect(verifier).toMatch(/^[A-Za-z0-9_-]+$/);
    expect(challenge).toMatch(/^[A-Za-z0-9_-]+$/);
    /* No padding: the authorization server compares the derived value, and a
       trailing `=` makes the exchange fail with an unhelpful error. */
    expect(challenge).not.toContain('=');
    expect(createHash('sha256').update(verifier).digest('base64url')).toBe(challenge);
  });

  it('produces a different verifier each time', async () => {
    const { pkce } = await load();
    expect(pkce().verifier).not.toBe(pkce().verifier);
  });
});

describe('oidc-login: the cookie jar', () => {
  it('keeps one value per cookie and sends them together', async () => {
    const { Jar } = await load();
    const jar = new Jar();
    jar.store({ 'set-cookie': ['authentik_session=abc; Path=/; HttpOnly', 'authentik_csrf=def; Path=/'] });
    expect(jar.header()).toBe('authentik_session=abc; authentik_csrf=def');
  });

  it('replaces a cookie the server re-issues', async () => {
    /* Authentik cycles the session key on sign-in. A jar that appended instead of
       replacing would send two values for one name, and the server would read the
       stale one — a session that never becomes authenticated. */
    const { Jar } = await load();
    const jar = new Jar();
    jar.store({ 'set-cookie': ['authentik_session=first; Path=/'] });
    jar.store({ 'set-cookie': ['authentik_session=second; Path=/'] });
    expect(jar.header()).toBe('authentik_session=second');
  });

  it('ignores a header with no value', async () => {
    const { Jar } = await load();
    const jar = new Jar();
    jar.store({ 'set-cookie': ['novalue; Path=/'] });
    jar.store({});
    expect(jar.header()).toBe('');
  });
});

describe('oidc-login: name resolution', () => {
  /* The harness reaches a real hostname on a machine with no DNS, so every
     request is pointed at the loopback ingress — the same trick `curl --resolve`
     performs for the shell checks. */
  it('resolves every mapped host, and only those', async () => {
    const { buildAgent } = await load();
    const agent = buildAgent({
      resolve: 'auth.workcenter.local:127.0.0.1,traefik.workcenter.local:127.0.0.1',
    });
    const lookup = agent.options.lookup;

    const single = await new Promise((resolve, reject) =>
      lookup('auth.workcenter.local', {}, (err, address, family) => (err ? reject(err) : resolve({ address, family }))));
    expect(single).toEqual({ address: '127.0.0.1', family: 4 });

    const many = await new Promise((resolve, reject) =>
      lookup('traefik.workcenter.local', { all: true }, (err, addresses) => (err ? reject(err) : resolve(addresses))));
    /* Node asks for the array form whenever `autoSelectFamily` is on, which is the
       default from Node 20. Returning the scalar form there fails with
       `Invalid IP address: undefined`, which is exactly what happened. */
    expect(many).toEqual([{ address: '127.0.0.1', family: 4 }]);

    await expect(new Promise((resolve, reject) =>
      lookup('elsewhere.example', {}, (err) => (err ? reject(err) : resolve()))))
      .rejects.toThrow(/refusing to resolve/);
  });

  it('leaves resolution alone when no mapping is given', async () => {
    const { buildAgent } = await load();
    expect(buildAgent({}).options.lookup).toBeUndefined();
  });
});
