#!/usr/bin/env node
// Workcenter — a headless OIDC login, for the end-to-end harness.
//
// `scripts/e2e.sh` has to prove the thing Phase 4 exists for: that a member of
// `workspaceusers` can sign in to every surface with one Authentik identity, that
// a member of `workspaceadmin` additionally reaches the Traefik dashboard, and
// that somebody in neither group is refused. Playwright does not arrive until
// Phase 6, so until then the sign-in has to be driven over the protocol.
//
// This does exactly what a browser does, with no browser:
//
//   1. runs Authentik's authentication flow through the flow executor API —
//      identification, then password — and keeps the session cookie;
//   2. calls the provider's authorization endpoint with PKCE and reads the
//      authorization code out of the redirect it answers with;
//   3. exchanges the code at the token endpoint, as a public client (PKCE, no
//      secret) or a confidential one (secret supplied);
//   4. verifies the id_token's signature against the provider's JWKS and prints
//      its claims, so a caller can assert on `groups`.
//
// Step 4 matters as much as step 3: it is the check IN-7.4, IN-7.5 and IN-7.6
// describe — the issuer the token claims must match the one the client expects, a
// signing key must exist or there is no JWKS to verify against, and `groups` must
// actually arrive in the token for `adminGroup` to mean anything.
//
// Usage:
//   node scripts/lib/oidc-login.mjs --client-id workcenter \
//     --redirect-uri https://workcenter.local/ --username admin@wc.test \
//     --password '...' --base-url https://auth.workcenter.local \
//     [--client-secret S] [--ca Traefik/certs/local-ca.crt] \
//     [--resolve auth.workcenter.local:127.0.0.1] [--scope "..."] [--json]
//
// It exits 0 when the whole exchange succeeded and prints a JSON object on
// stdout; any failure exits non-zero with the reason on stderr.
//
// The transport is Node's own `https`, not a package: the harness must not depend
// on anything the repository does not already install.

import { readFileSync } from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import { createHash, createPublicKey, verify as cryptoVerify } from 'node:crypto';
import { pathToFileURL } from 'node:url';

// ---------------------------------------------------------------------------
// Arguments
// ---------------------------------------------------------------------------
function parseArgs(argv) {
  const out = {
    scope: 'openid profile email groups',
    ca: '',
    resolve: '',
    clientSecret: '',
    json: false,
    timeoutMs: 20000,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    const value = argv[i + 1];
    switch (key) {
      case '--base-url': out.baseUrl = value; i += 1; break;
      case '--client-id': out.clientId = value; i += 1; break;
      case '--client-secret': out.clientSecret = value; i += 1; break;
      case '--redirect-uri': out.redirectUri = value; i += 1; break;
      case '--username': out.username = value; i += 1; break;
      case '--password': out.password = value; i += 1; break;
      case '--scope': out.scope = value; i += 1; break;
      case '--ca': out.ca = value; i += 1; break;
      case '--resolve': out.resolve = value; i += 1; break;
      case '--timeout': out.timeoutMs = Number(value) * 1000; i += 1; break;
      case '--json': out.json = true; break;
      // A negative test: the account is expected to be refused, and being refused
      // is the pass condition. Without it a refusal and a configuration error look
      // the same to the caller.
      case '--expect-denied': out.expectDenied = true; break;
      // Prove single logout (roadmap A-7): after the token is verified, call the
      // provider's end-session endpoint and then check that the session is really
      // gone by re-entering the authorization endpoint with the same cookies.
      case '--then-logout': out.thenLogout = true; break;
      // Prove the account reaches Authentik's **admin console**. The console's
      // HTML shell answers 200 to anyone — it is a single-page app and the
      // redirect happens in JavaScript — so "the page loaded" proves nothing.
      // This authenticates and then asks an admin-only API endpoint who it is,
      // which is the part a browser cannot fake.
      case '--admin-console': out.adminConsole = true; break;
      // Walk the forward-auth chain for a protected URL (the Traefik dashboard).
      // The whole point is that the browser is the one that authenticates: the
      // outpost challenges, the browser signs in, and the retry succeeds.
      case '--forward-auth': out.forwardAuth = value; i += 1; break;
      // Sign in the way an **application** starts it, rather than the way the
      // provider does.
      //
      // This is the half the forward-auth mode cannot cover. An application that is
      // an OIDC client owns both ends: it sends the browser to the provider with a
      // `state` it remembers in its own session, and it expects the browser back
      // with a `code` and that same session. A verifier that starts at the provider
      // exercises neither, so it can report success for a sign-in a browser cannot
      // finish — which is what happened here. Every provider-side check passed while
      // Mailcow answered every real sign-in with a blank page.
      case '--sso-entry': out.ssoEntry = value; i += 1; break;
      // Print the bytes of the page the application finally serves. Whether a login
      // worked is decided by the page it lands on, and that page is the one thing a
      // status code cannot describe.
      case '--print-body': out.printBody = true; break;
      // A substring the final page must contain. Without one, "we got a 200" is
      // satisfied by the application's own login page: the failure and the success
      // wear the same status code.
      case '--expect': out.expect = value; i += 1; break;
      // Emit the raw tokens alongside the claims. Opt-in, because they are
      // credentials and everything else this tool prints is not.
      //
      // It exists because the checks here prove the *provider* issues a good token
      // and cannot prove that an application *accepts* one — those are different
      // failures with the same symptom on screen, and telling them apart needed the
      // token in hand. First use: a userinfo endpoint that answers `401` with no
      // `Access-Control-Allow-Origin`, which a browser rejects as a CORS failure
      // while every Node-side check sails past it.
      case '--print-tokens': out.printTokens = true; break;
      default:
        if (key.startsWith('--')) throw new Error(`unknown argument ${key}`);
    }
  }
  // A direct authorization-code run needs a client and a registered redirect URI.
  // The two provider-side checks do not: the admin console is the provider's own
  // UI, and forward auth is Traefik asking the outpost.
  const required = out.adminConsole || out.forwardAuth || out.ssoEntry
    ? ['baseUrl', 'username', 'password']
    : ['baseUrl', 'clientId', 'redirectUri', 'username', 'password'];
  for (const name of required) {
    if (!out[name]) {
      throw new Error(`missing --${name.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}`);
    }
  }
  out.baseUrl = out.baseUrl.replace(/\/$/, '');
  return out;
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------
// One agent carries the deployment's own CA and, when asked, sends every request
// for that hostname to the loopback Traefik the harness binds — the same trick
// `curl --resolve` does for the shell checks, which is what lets the harness test
// a real hostname on a machine with no DNS.
function buildAgent(args) {
  const options = { keepAlive: true };
  if (args.ca) {
    try {
      options.ca = readFileSync(args.ca, 'utf8');
    } catch (err) {
      throw new Error(`could not read --ca ${args.ca}: ${err.message}`);
    }
  }
  if (args.resolve) {
    // `host:ip` pairs, comma-separated, because a forward-auth run crosses between
    // the protected host and the identity host and both have to resolve here.
    const map = new Map();
    for (const pair of args.resolve.split(',')) {
      const [name, ip] = pair.trim().split(':');
      if (name) map.set(name, ip || '127.0.0.1');
    }
    options.servername = [...map.keys()][0];
    // Node calls this with `{all: true}` when `autoSelectFamily` is on (the
    // default since Node 20), and in that form it must be handed an **array**.
    // Returning the three-argument form there fails with
    // `Invalid IP address: undefined`, which is what an ignore-the-shape
    // implementation produces.
    options.lookup = (name, opts, callback) => {
      const ip = map.get(name);
      if (!ip) {
        callback(new Error(`oidc-login: refusing to resolve ${name}; mapped: ${[...map.keys()].join(', ')}`));
        return;
      }
      if (opts && opts.all) callback(null, [{ address: ip, family: 4 }]);
      else callback(null, ip, 4);
    };
  }
  return new https.Agent(options);
}

// A deliberately small cookie jar: Authentik's flow is one origin and a handful of
// cookies, and keeping it explicit means the redirect handling stays readable.
// Node's `res.headers['set-cookie']` is already an array, so no comma-splitting.
class Jar {
  constructor() {
    this.cookies = new Map();
  }

  store(headers) {
    const raw = headers['set-cookie'];
    if (!raw) return;
    for (const header of Array.isArray(raw) ? raw : [raw]) {
      const [pair] = header.split(';');
      const index = pair.indexOf('=');
      if (index > 0) this.cookies.set(pair.slice(0, index).trim(), pair.slice(index + 1).trim());
    }
  }

  header() {
    return [...this.cookies.entries()].map(([k, v]) => `${k}=${v}`).join('; ');
  }
}

function makeTransport(args) {
  const agent = buildAgent(args);

  return async function request(url, options = {}) {
    const jar = options.jar;
    const headers = { Accept: 'application/json', ...(options.headers || {}) };
    if (jar) {
      const cookie = jar.header();
      if (cookie) headers.Cookie = cookie;
    }
    const body = options.body || '';
    if (body) headers['Content-Length'] = Buffer.byteLength(body);

    return new Promise((resolve, reject) => {
      const target = new URL(url);
      const lib = target.protocol === 'https:' ? https : http;
      const req = lib.request({
        protocol: target.protocol,
        hostname: target.hostname,
        port: target.port || (target.protocol === 'https:' ? 443 : 80),
        path: `${target.pathname}${target.search}`,
        method: options.method || 'GET',
        headers,
        agent: target.protocol === 'https:' ? agent : undefined,
      }, (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => {
          if (jar) jar.store(res.headers);
          resolve({
            status: res.statusCode,
            headers: res.headers,
            text: Buffer.concat(chunks).toString('utf8'),
          });
        });
      });
      req.setTimeout(args.timeoutMs, () => req.destroy(new Error(`request to ${url} timed out`)));
      req.on('error', reject);
      if (body) req.write(body);
      req.end();
    });
  };
}

// ---------------------------------------------------------------------------
// Authentik's flow executor
// ---------------------------------------------------------------------------
// A flow is a sequence of challenges. The executor is asked for the current one,
// the answer is posted back, and the flow advances — precisely the loop the
// browser's flow UI runs. `query` is the querystring the flow was entered with;
// Authentik requires it on every call, and an empty string is valid.
async function runFlow(request, jar, baseUrl, slug, query, credentials, log) {
  let url = `${baseUrl}/api/v3/flows/executor/${slug}/?query=${encodeURIComponent(query)}`;
  for (let step = 0; step < 12; step += 1) {
    const response = await request(url, { jar });

    // After every stage that succeeds, Authentik answers with a redirect back to
    // the executor — that is how the flow UI is told to fetch the next challenge.
    // Following it is part of running the flow, not an error: stopping here leaves
    // the run one stage short, which is exactly what a login that "succeeds" in
    // the logs but leaves no session looks like.
    if (response.status >= 300 && response.status < 400) {
      const target = response.headers.location || '';
      if (!target) throw new Error(`flow ${slug}: redirect with no Location`);
      const absolute = target.startsWith('http') ? target : `${baseUrl}${target}`;
      if (new URL(absolute).pathname.startsWith('/api/v3/flows/executor/')) {
        url = absolute;
        continue;
      }
      log(`  ${slug}: complete`);
      return absolute;
    }

    let challenge;
    try {
      challenge = JSON.parse(response.text);
    } catch {
      throw new Error(`flow ${slug}: expected JSON, got HTTP ${response.status}: ${response.text.slice(0, 200)}`);
    }
    const component = challenge.component;

    if (component === 'ak-stage-identification') {
      log(`  identification: ${credentials.username}`);
      await request(url, {
        method: 'POST',
        jar,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ component, uid_field: credentials.username }),
      });
      continue;
    }
    if (component === 'ak-stage-password') {
      log('  password: ••••••••');
      await request(url, {
        method: 'POST',
        jar,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ component, password: credentials.password }),
      });
      continue;
    }
    if (component === 'xak-flow-redirect') {
      // The flow finished and wants the browser sent somewhere — for the
      // authorization flow that is the authorization endpoint again, which now
      // has a session and can issue a code.
      return challenge.to;
    }
    if (component === 'ak-stage-session-end') {
      // The invalidation flow's last screen. It asks for nothing, but the flow
      // only completes when it is answered — returning here would leave the
      // session alive while looking exactly like a successful sign-out.
      log(`  ${slug}: session end`);
      await request(url, {
        method: 'POST',
        jar,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ component }),
      });
      continue;
    }
    if (challenge.response_errors) {
      throw new Error(`flow ${slug} rejected the answer: ${JSON.stringify(challenge.response_errors)}`);
    }
    // Any other component (consent, MFA, …) is a stage this harness does not
    // drive. Say so rather than looping until the step limit.
    throw new Error(`flow ${slug}: unsupported stage ${component}`);
  }
  throw new Error(`flow ${slug}: did not finish within the step limit`);
}

// ---------------------------------------------------------------------------
// PKCE
// ---------------------------------------------------------------------------
function pkce() {
  const verifier = createHash('sha256')
    .update(String(Date.now()) + String(Math.random()))
    .digest('base64url');
  const challenge = createHash('sha256').update(verifier).digest('base64url');
  return { verifier, challenge };
}

// ---------------------------------------------------------------------------
// id_token verification
// ---------------------------------------------------------------------------
function decodeSegment(segment) {
  return JSON.parse(Buffer.from(segment, 'base64url').toString('utf8'));
}

// The claim checks IN-7.4/IN-7.5/IN-7.6 imply: the token must verify against the
// provider's published JWKS. A token that "works" because nobody checked is
// exactly the silent failure those requirements exist to prevent.
async function verifyIdToken(request, jar, idToken) {
  const [headerPart, payloadPart, signaturePart] = idToken.split('.');
  if (!headerPart || !payloadPart || !signaturePart) throw new Error('id_token is not a JWS');
  const header = decodeSegment(headerPart);
  const payload = decodeSegment(payloadPart);

  const jwksResponse = await request(`${payload.iss.replace(/\/$/, '')}/jwks/`, { jar });
  let jwks;
  try {
    jwks = JSON.parse(jwksResponse.text);
  } catch {
    throw new Error(`the provider published no JWKS at ${payload.iss}jwks/ (HTTP ${jwksResponse.status})`);
  }
  const jwk = (jwks.keys || []).find((k) => !header.kid || k.kid === header.kid);
  if (!jwk) {
    throw new Error('the provider published no matching JWKS key — the token cannot be verified ' +
      '(OIDC.md §4.5 Trap 2: a provider with no signing key publishes no JWKS)');
  }

  const key = createPublicKey({ key: jwk, format: 'jwk' });
  const algorithm = header.alg === 'RS256' ? 'RSA-SHA256' : header.alg;
  const ok = cryptoVerify(
    algorithm,
    Buffer.from(`${headerPart}.${payloadPart}`),
    key,
    Buffer.from(signaturePart, 'base64url'),
  );
  if (!ok) throw new Error('id_token signature does not verify against the published JWKS');
  return payload;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
  const args = parseArgs(process.argv.slice(2));
  const log = (line) => { if (!args.json) process.stderr.write(`${line}\n`); };
  const request = makeTransport(args);
  const jar = new Jar();
  const { verifier, challenge } = pkce();

  const authorizeQuery = new URLSearchParams({
    client_id: args.clientId || '',
    response_type: 'code',
    scope: args.scope,
    redirect_uri: args.redirectUri || `${args.baseUrl}/`,
    state: `wc-${Date.now()}`,
    code_challenge: challenge,
    code_challenge_method: 'S256',
  }).toString();

  // --- an application's own SSO entry --------------------------------------
  // Start where a user starts: the application's sign-in link. The application
  // sends us to the provider with a `state` stored in its session cookie, the
  // provider authenticates us, and the application is handed back a `code` — which
  // it must exchange and accept. Only the application can decide whether that
  // worked, so the evidence is the page it finally serves.
  if (args.ssoEntry) {
    const appOrigin = new URL(args.ssoEntry).origin;
    log(`sso entry: ${args.ssoEntry}`);
    let location = args.ssoEntry;
    let status = 0;
    let body = '';
    let landed = '';
    for (let hop = 0; hop < 15; hop += 1) {
      // `Accept: text/html`, because these are pages rather than API responses:
      // Mailcow decides what to render from it, and the point here is to see what
      // a browser would see.
      const response = await request(location, { jar, headers: { Accept: 'text/html,application/xhtml+xml' } });
      const finalUrl = location;
      status = response.status;
      // Landing on the application again means the round trip completed: it has
      // its `code` and has made its own decision about it.
      if (status === 200 && new URL(finalUrl).origin === appOrigin
          && new URL(finalUrl).pathname !== new URL(args.ssoEntry).pathname) {
        body = response.text;
        landed = finalUrl;
        break;
      }
      if (status === 200) {
        // A 200 on the entry path itself is the application re-rendering its own
        // login page — which is what a refused sign-in looks like.
        body = response.text;
        landed = finalUrl;
        break;
      }
      const target = response.headers.location || '';
      if (!target) {
        body = response.text;
        landed = finalUrl;
        break;
      }
      let absolute = target.startsWith('http') ? target : new URL(target, finalUrl).toString();
      const parsed = new URL(absolute);
      if (parsed.pathname.startsWith('/if/flow/')) {
        const slug = parsed.pathname.split('/')[3];
        log(`  authentication flow: ${slug}`);
        const next = await runFlow(request, jar, args.baseUrl, slug, parsed.search.slice(1), {
          username: args.username,
          password: args.password,
        }, log);
        absolute = next.startsWith('http') ? next : next ? `${args.baseUrl}${next}` : args.ssoEntry;
      }
      location = absolute;
    }
    const refused = /login_failed|iam_sso|"type":"danger"/.test(body);
    const missing = args.expect && !body.includes(args.expect);
    if (args.printBody) process.stdout.write(`${body}\n`);
    const result = {
      ok: status === 200 && !refused && !missing,
      username: args.username,
      sso_entry: args.ssoEntry,
      landed,
      status,
      bytes: body.length,
      refused,
      ...(args.expect ? { expected: args.expect, found: !missing } : {}),
    };
    process.stdout.write(`${JSON.stringify(result)}\n`);
    if (!result.ok) {
      throw new Error(`SSO into ${args.ssoEntry} did not complete: HTTP ${status} at ${landed}` +
        `${refused ? ' (the application refused the sign-in)' : ''}` +
        `${missing ? ` (the page did not contain ${JSON.stringify(args.expect)})` : ''}`);
    }
    log(`${args.username} signed in at ${landed} (HTTP ${status}, ${body.length} bytes)`);
    return;
  }

  // --- forward auth (the Traefik dashboard) --------------------------------
  // A protected URL is not an OIDC client: nothing exchanges a code. Traefik asks
  // the outpost about every request, the outpost challenges an unauthenticated
  // browser, and once the browser holds an Authentik session the retry succeeds
  // and the outpost's cookie keeps it that way. So this walks the chain the browser
  // walks, and the proof is the final status code.
  if (args.forwardAuth) {
    log(`forward auth: ${args.forwardAuth}`);
    let location = args.forwardAuth;
    let status = 0;
    for (let hop = 0; hop < 15; hop += 1) {
      const response = await request(location, { jar });
      // A 200 only counts when it is the **protected** URL that answered. The
      // outpost serves its own pages on the same host — the callback that sets its
      // cookie, and a refusal page — and those answer 200 too. Accepting any 200
      // would report a denied request as a successful one, which is precisely the
      // mistake this check exists to prevent.
      const reachedProtected = new URL(location).pathname === new URL(args.forwardAuth).pathname;
      if (response.status === 200 && reachedProtected) { status = 200; break; }
      if (response.status === 401 || response.status === 403) {
        throw new Error(`forward auth refused ${args.forwardAuth} with HTTP ${response.status} ` +
          `for ${args.username}`);
      }
      if (response.status === 200) {
        throw new Error(`forward auth ended at ${location} with HTTP 200, which is not the ` +
          `protected URL — the request was not granted access to ${args.forwardAuth}`);
      }
      const target = response.headers.location || '';
      if (!target) throw new Error(`HTTP ${response.status} from ${location} with no Location`);
      let absolute = target.startsWith('http') ? target : new URL(target, location).toString();
      const parsed = new URL(absolute);

      if (parsed.pathname.startsWith('/if/flow/')) {
        const slug = parsed.pathname.split('/')[3];
        log(`  authentication flow: ${slug}`);
        const next = await runFlow(request, jar, args.baseUrl, slug, parsed.search.slice(1), {
          username: args.username,
          password: args.password,
        }, log);
        absolute = next.startsWith('http') ? next : next ? `${args.baseUrl}${next}` : args.forwardAuth;
      }
      location = absolute;
    }
    if (status !== 200) throw new Error(`forward auth never granted access to ${args.forwardAuth}`);
    const result = { ok: true, username: args.username, forward_auth: true, url: args.forwardAuth, status };
    process.stdout.write(`${JSON.stringify(result)}\n`);
    log(`${args.username} reached ${args.forwardAuth} (HTTP 200)`);
    return;
  }

  // --- Authentik's admin console -------------------------------------------
  // Authentication is all this needs: it is not an OIDC client flow, it is the
  // provider's own console. What makes it evidence is the second request — an
  // admin-only endpoint that answers with the account it authenticated.
  if (args.adminConsole) {
    log('authenticating…');
    await runFlow(request, jar, args.baseUrl, 'default-authentication-flow',
      `next=${encodeURIComponent('/if/admin/')}`, {
        username: args.username,
        password: args.password,
      }, log);

    const me = await request(`${args.baseUrl}/api/v3/core/users/me/`, { jar });
    let payload;
    try {
      payload = JSON.parse(me.text);
    } catch {
      throw new Error(`the admin API answered HTTP ${me.status} with a non-JSON body`);
    }
    if (me.status !== 200) {
      throw new Error(`the admin API refused the session (HTTP ${me.status}) — ` +
        'the account authenticated but the console is not reachable');
    }
    const result = {
      ok: true,
      username: args.username,
      console: true,
      api_username: payload.user?.username || null,
      is_superuser: Boolean(payload.user?.is_superuser),
    };
    process.stdout.write(`${JSON.stringify(result)}\n`);
    log(`admin console reachable as ${result.api_username}` +
      `${result.is_superuser ? ' (superuser)' : ' (NOT a superuser)'}`);
    return;
  }

  // 1. Authenticate. The authentication flow is entered exactly as the
  //    authorization endpoint enters it: `/flows/-/default/authentication/?next=`,
  //    where `next` is the authorization request to return to. Authentik stores
  //    that in the flow plan, and without it the run finishes without the session
  //    being established for the authorization request that follows.
  const authorizePath = `/application/o/authorize/?${authorizeQuery}`;
  log('authenticating…');
  await runFlow(request, jar, args.baseUrl, 'default-authentication-flow',
    `next=${encodeURIComponent(authorizePath)}`, {
      username: args.username,
      password: args.password,
    }, log);

  // 2. Authorize. Follow redirects by hand: the first hop may be the provider's
  //    authorization flow (implicit consent), which is driven the same way; the
  //    last hop is the registered redirect URI carrying the code.
  log('authorizing…');
  const baseOrigin = new URL(args.baseUrl).origin;
  let location = `${args.baseUrl}/application/o/authorize/?${authorizeQuery}`;
  let code = '';
  for (let hop = 0; hop < 6 && !code; hop += 1) {
    const response = await request(location, { jar });
    const target = response.headers.location || '';
    if (!target) {
      // No redirect at all. Authentik answers the authorization request with a
      // rendered page when the application's bindings refuse this user — which is
      // the behaviour the exit criteria test for an account in no group, so it is
      // reported as a refusal rather than as a broken redirect.
      if (response.status === 200) {
        if (args.expectDenied) {
          process.stdout.write(`${JSON.stringify({ ok: true, denied: true, username: args.username, client_id: args.clientId })}\n`);
          log(`${args.username} was refused, as expected (application binding)`);
          return;
        }
        throw new Error(`authorization denied for ${args.username}: the application is not bound to a group ` +
          'this account belongs to (OIDC.md §3, O-3.3)');
      }
      throw new Error(`expected a redirect from ${location}, got HTTP ${response.status}`);
    }
    const absolute = target.startsWith('http') ? target : `${args.baseUrl}${target}`;

    if (absolute.startsWith(args.redirectUri)) {
      const parsed = new URL(absolute);
      code = parsed.searchParams.get('code') || '';
      if (!code) {
        throw new Error(`authorization failed: ${parsed.searchParams.get('error') || 'no code in the redirect'} ` +
          `${parsed.searchParams.get('error_description') || ''}`);
      }
      break;
    }

    const parsed = new URL(absolute);
    if (parsed.origin !== baseOrigin) throw new Error(`unexpected redirect to ${absolute}`);

    if (parsed.pathname.startsWith('/if/flow/')) {
      const slug = parsed.pathname.split('/')[3];
      const next = await runFlow(request, jar, args.baseUrl, slug, parsed.search.slice(1), {
        username: args.username,
        password: args.password,
      }, log);
      location = next.startsWith('http') ? next : `${args.baseUrl}${next}`;
      // `xak-flow-redirect` answers with the *original* authorization request, so
      // the loop re-enters the authorization endpoint with a session this time.
      continue;
    }
    throw new Error(`unexpected redirect to ${absolute}`);
  }
  if (!code) throw new Error('the authorization endpoint never returned a code');

  // 3. Exchange.
  log('exchanging the code…');
  const form = new URLSearchParams({
    grant_type: 'authorization_code',
    code,
    redirect_uri: args.redirectUri,
    client_id: args.clientId,
    code_verifier: verifier,
  });
  if (args.clientSecret) form.set('client_secret', args.clientSecret);
  const tokenResponse = await request(`${args.baseUrl}/application/o/token/`, {
    method: 'POST',
    jar,
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form.toString(),
  });
  let tokens;
  try {
    tokens = JSON.parse(tokenResponse.text);
  } catch {
    throw new Error(`token endpoint returned HTTP ${tokenResponse.status}: ${tokenResponse.text.slice(0, 200)}`);
  }
  if (tokenResponse.status !== 200) {
    throw new Error(`token endpoint refused the exchange: ${tokens.error} — ${tokens.error_description || ''}`);
  }
  if (!tokens.id_token) throw new Error('the token response carried no id_token');

  // 3b. Call the userinfo endpoint the way a **browser** does.
  //
  // This is not decoration. A browser client sets `loadUserInfo`, so the first
  // thing it does after the exchange is a cross-origin GET to `/userinfo/` — and
  // that request is subject to two rules nothing else here exercises:
  //
  //   * it must be **authorised**, which needs the `openid` scope to have survived
  //     the authorize request. Authentik intersects what a client asks for with
  //     what the provider is configured for and *silently drops* the rest, so a
  //     provider built without the built-in `openid` mapping issues a perfectly
  //     good id_token that `/userinfo/` then refuses with `403 Scope mismatch`;
  //   * it must be **readable cross-origin**, which needs
  //     `Access-Control-Allow-Origin` on the response. A refusal does not carry it,
  //     so the browser reports a CORS failure rather than the 403 underneath.
  //
  // A Node client enforces neither, which is exactly how every check here passed
  // while the shell showed "Authentication failed (OIDC)".
  log('calling userinfo as a browser would…');
  const userinfo = await request(`${args.baseUrl}/application/o/userinfo/`, {
    jar,
    headers: {
      Authorization: `Bearer ${tokens.access_token}`,
      Origin: new URL(args.redirectUri).origin,
    },
  });
  const corsAllow = userinfo.headers['access-control-allow-origin'] || null;
  const userinfoOk = userinfo.status === 200 && Boolean(corsAllow);
  if (!userinfoOk) {
    const scopeWarning = userinfo.status === 403
      ? ' — the token is missing the `openid` scope, so the provider has no openid scope mapping attached'
      : '';
    throw new Error(
      `userinfo is not usable from a browser: HTTP ${userinfo.status}, `
      + `Access-Control-Allow-Origin ${corsAllow || '(absent)'}${scopeWarning}`,
    );
  }

  // 4. Verify and report.
  log('verifying the id_token…');
  const claims = await verifyIdToken(request, jar, tokens.id_token);
  const result = {
    ok: true,
    username: args.username,
    client_id: args.clientId,
    issuer: claims.iss,
    subject: claims.sub,
    preferred_username: claims.preferred_username || null,
    email: claims.email || null,
    email_verified: claims.email_verified === undefined ? null : claims.email_verified,
    groups: Array.isArray(claims.groups) ? claims.groups : [],
    scopes: (tokens.scope || '').split(' ').filter(Boolean),
    has_access_token: Boolean(tokens.access_token),
    has_refresh_token: Boolean(tokens.refresh_token),
    id_token_verified: true,
    userinfo_ok: userinfoOk,
    userinfo_cors_origin: corsAllow,
  };
  if (args.printTokens) {
    result.access_token = tokens.access_token || null;
    result.id_token = tokens.id_token || null;
  }
  process.stdout.write(`${JSON.stringify(result)}\n`);
  log(`signed in as ${result.username} — groups: ${result.groups.join(', ') || '(none)'}`);

  // 5. Optionally prove that signing out is single-action (roadmap A-7).
  //
  // Calling the end-session endpoint and taking its word for it proves nothing:
  // what matters is whether the **session** is gone afterwards, because that is
  // the thing every application follows. So the authorization request is replayed
  // with the same cookies. If the provider still knows the user it answers with a
  // code; if the session ended — as it must — it sends the browser back to the
  // authentication flow instead.
  if (args.thenLogout) {
    const endSession = `${claims.iss.replace(/\/$/, '')}/end-session/`;
    log('signing out…');
    const endUrl = `${endSession}?id_token_hint=${encodeURIComponent(tokens.id_token)}` +
      `&post_logout_redirect_uri=${encodeURIComponent(args.redirectUri)}`;
    const endResponse = await request(endUrl, { jar });
    if (endResponse.status >= 400) {
      throw new Error(`the end-session endpoint answered HTTP ${endResponse.status}`);
    }

    // The end-session endpoint does not end the session itself: it starts the
    // provider's **invalidation flow**, which is a flow like any other and has to
    // be driven to completion. Skipping it leaves the session alive, which looks
    // exactly like a provider that ignored the request — and, from a browser, is
    // indistinguishable from logout having worked.
    let location = endResponse.headers.location || '';
    for (let hop = 0; hop < 5 && location; hop += 1) {
      const absolute = location.startsWith('http') ? location : `${args.baseUrl}${location}`;
      const parsed = new URL(absolute);
      if (!parsed.pathname.startsWith('/if/flow/')) break;
      const slug = parsed.pathname.split('/')[3];
      log(`  invalidation flow: ${slug}`);
      const next = await runFlow(request, jar, args.baseUrl, slug, parsed.search.slice(1), {
        username: args.username,
        password: args.password,
      }, log);
      location = next.startsWith('http') ? next : next ? `${args.baseUrl}${next}` : '';
    }

    const replay = await request(`${args.baseUrl}/application/o/authorize/?${authorizeQuery}`, { jar });
    const target = replay.headers.location || '';
    const ended = target.includes('/flows/-/') || target.includes('/if/flow/');
    if (!ended) {
      throw new Error('the session survived the end-session call: the authorization endpoint ' +
        `still issued a redirect to ${target.slice(0, 80)} — single logout does not work (A-7)`);
    }
    const loggedOut = { ...result, logged_out: true, session_ended: true };
    process.stdout.write(`${JSON.stringify(loggedOut)}\n`);
    log('the provider session ended: a new authorization request asks for a fresh sign-in');
  }
}

// Run only when executed, not when imported: the helpers are unit-tested, and an
// import that authenticated against a live provider as a side effect would be a
// surprise no test should have to work around.
const invokedDirectly = process.argv[1]
  && import.meta.url === pathToFileURL(process.argv[1]).href;

if (invokedDirectly) {
  main().catch((err) => {
    process.stderr.write(`oidc-login: ${err.message}\n`);
    process.exit(1);
  });
}

export { parseArgs, pkce, Jar, buildAgent, makeTransport };
