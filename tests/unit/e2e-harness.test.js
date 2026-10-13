import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';

/**
 * The e2e harness's own guardrails.
 *
 * `scripts/e2e.sh` has no unit-testable surface — a person is the runner and
 * ShellCheck is the CI gate (`Testing.md` §6.5, §10) — so these assert the
 * properties that are easy to lose in an edit and expensive to notice: the
 * behaviours that failed in the field, and the Phase 4 wiring that the harness's
 * own run then exercises for real.
 *
 * They are deliberately narrow. Anything about whether the deployment *works* is
 * proved by running the harness, not by reading it.
 */
const script = fs.readFileSync(path.resolve(__dirname, '../../scripts/e2e.sh'), 'utf8');
const library = fs.readFileSync(path.resolve(__dirname, '../../scripts/lib/authentik.sh'), 'utf8');
const verifier = fs.readFileSync(path.resolve(__dirname, '../../scripts/lib/oidc-login.mjs'), 'utf8');

describe('the e2e harness', () => {
  it('reads process arguments with basename without treating them as options', () => {
    /* `our_server_pids` sweeps /proc for this checkout's `node server.js`. A Node
       process launched as `node --import …` made the unguarded call print
       `basename: unrecognized option '--import'`, and fail to match. */
    expect(script).toMatch(/basename -- "\$\{argv0:-\}"/);
    expect(script).toMatch(/basename -- "\$\{argv1:-\}"/);
  });

  it('creates the Zulip admin with Zulip’s own commands, not an environment variable', () => {
    /* Zulip authenticates by email and enforces an 8-character password floor, so
       `admin` is refused with PasswordTooWeakError; the harness uses Zulip's
       management commands inside the container. */
    expect(script).toMatch(/export ZULIP_ADMIN_PASSWORD="\$\{ZULIP_ADMIN_PASSWORD:-admin1234\}"/);
    expect(script).toContain('manage.py create_user');
    expect(script).toContain('manage.py change_user_role');
    expect(script).toContain('/api/v1/fetch_api_key');
  });
});

describe('the harness brings the stack up in order', () => {
  it('force-recreates only the services that read a per-run secret', () => {
    /* `up -d` already recreates a service whose *configuration* changed. The flag
       is for the other case — a mounted file whose **contents** changed under an
       identical configuration — so it is scoped to the services that read one.

       Applied to the whole project it also recreated Traefik and all three Authentik
       services, which read no per-run secret: their values are persistent and were
       written before they first started. Measured cost was ten seconds, and worse,
       recreating Traefik changes its address on `proxy`, which fired the re-point
       and left Zulip started three times in one run. */
    const stackUp = script.slice(
      script.indexOf("step 'Bringing up the application stack'"),
      script.indexOf('bring_up_mailcow'),
    );
    expect(stackUp).toMatch(/compose up -d --force-recreate zulip database memcached rabbitmq redis workcenter/);
    /* No bare project-wide force-recreate anywhere. */
    expect(script).not.toMatch(/compose up -d --force-recreate\s*2>&1/);
    expect(script).not.toMatch(/recreate=\(--force-recreate\)/);
  });

  it('announces the application stack as its own stage', () => {
    /* The containers coming up are a different operational area from the identity
       provider being configured, and the output used to read as though they were
       still part of the provisioning. */
    expect(script).toMatch(/step 'Bringing up the application stack'/);
    expect(script).toMatch(/info 'Traefik and Authentik are up and configured/);
    const stackUp = script.slice(script.indexOf("step 'Bringing up the application stack'"));
    /* The title comes before the containers start, not after. */
    expect(stackUp.indexOf("step 'Bringing up the application stack'"))
      .toBeLessThan(stackUp.indexOf('compose up -d 2>&1'));
  });
});

describe('the harness provisions identity', () => {
  it('uses the same library the installer will, rather than its own copy', () => {
    /* One implementation, two callers. A second provisioning path in the harness
       is the drift this avoids: fixing a provider field would fix it in one place
       and leave the other wrong. */
    expect(script).toContain('source "${SCRIPT_DIR}/lib/authentik.sh"');
    expect(script).toMatch(/ensure_authentik_identity\(\)/);
    /* Called from `stack_up`, and *before* the rest of the stack: on a fresh
       instance the provider does not exist until it has been provisioned, and
       FileBrowser's discovery at startup is fatal (IN-3.6). */
    const up = script.slice(script.indexOf('\nstack_up() {'));
    const provision = up.indexOf('ensure_authentik_identity');
    const everything = up.indexOf("step 'Bringing up the application stack'");
    expect(provision).toBeGreaterThan(-1);
    expect(everything).toBeGreaterThan(-1);
    expect(provision).toBeLessThan(everything);
  });

  it('creates the three fixture accounts Testing.md §7.1 fixes', () => {
    for (const who of ['ADMIN', 'USER', 'OUTSIDER']) {
      expect(script).toContain(`AUTHENTIK_TEST_${who}_EMAIL`);
    }
    /* The outsider is in no group, and that is the point of the account: it is
       what makes the refusal checks real rather than assumed. */
    expect(script).toMatch(/identity \$\{AUTHENTIK_TEST_OUTSIDER_EMAIL\}: no group/);
  });

  it('reads each client secret from the same .env line the application reads', () => {
    /* A confidential client is refused with `invalid_client` without its secret,
       and hard-coding the pairing here would let the harness and the deployment
       disagree. The variable name is derived from the client id, which is the one
       thing both ends already share. */
    expect(script).toMatch(/secret_var=.*tr '\[:lower:\]' '\[:upper:\]'/);
    expect(script).toContain('_OIDC_CLIENT_SECRET');
    expect(script).toContain('--client-secret "${secret}"');
  });

  it('generates the identity configuration before the stack starts', () => {
    /* FileBrowser runs provider discovery at startup and stops the container if it
       fails (IN-3.6), so a copy written after `up` would be read by nothing. */
    const config = script.indexOf('\n  ensure_identity_config\n');
    const up = script.indexOf('\n  stack_up\n');
    expect(config).toBeGreaterThan(-1);
    expect(up).toBeGreaterThan(-1);
    expect(config).toBeLessThan(up);
    expect(script).toMatch(/ensure_identity_secrets\(\)/);
    expect(script).toMatch(/ensure_zulip_identity\(\)/);
  });
});

describe('the harness proves the identity model', () => {
  it('signs in through the provider for every application, per account', () => {
    expect(script).toMatch(/oidc_login\(\)/);
    for (const client of ['workcenter', 'filebrowser', 'zulip']) {
      expect(script).toContain(`${client}|${client}|https://`);
    }
    expect(script).toMatch(/check_oidc_groups\(\)/);
  });

  it('asserts a member is not an administrator', () => {
    /* `!` marks a group that must be absent, which is how "in workspaceusers but
       not workspaceadmin" is expressed (O-3.2 keeps the two apart). */
    expect(script).toContain('"!${WORKCENTER_ADMIN_GROUP}"');
  });

  it('asserts the outsider is refused by the application binding', () => {
    expect(script).toContain('--expect-denied');
  });

  it('asserts sign-out ends the provider session, not just the local one', () => {
    /* A provider that accepts `end-session` and keeps the session anyway looks
       identical from a browser, so the check replays the authorization request
       afterwards instead of trusting the redirect. */
    expect(script).toContain('--then-logout');
    expect(script).toMatch(/session_ended/);
  });

  it('asserts the dashboard boundary in both directions', () => {
    /* Only one of these is a security check; the other is the exit criterion a
       person would otherwise have to test by hand. Both are needed: a dashboard
       that refuses everyone also passes the first. */
    expect(script).toContain('--forward-auth');
    expect(script).toMatch(/reaches the Traefik dashboard/);
    expect(script).toMatch(/is refused the Traefik dashboard/);
  });

  it('asserts an administrator can reach the provider’s own console', () => {
    /* The console's HTML answers 200 to anyone — it is a single-page app — so the
       check authenticates and then asks an admin-only API endpoint who it is. */
    expect(script).toContain('--admin-console');
    expect(script).toMatch(/is_superuser == true/);
  });

  it('asserts password login is refused once identity exists', () => {
    /* This assertion inverted in Phase 4. Before identity, the harness proved the
       Files pane was reachable by signing in with a password; now a password must
       be refused and OIDC is what proves access. Leaving the old assertion would
       have made "Phase 4 is done" and "the harness passes" mutually exclusive. */
    const at = script.indexOf('/api/auth/login?username=admin');
    expect(at).toBeGreaterThan(-1);
    const check = script.slice(at, at + 700);
    expect(check).toMatch(/Files password login still works/);
    expect(check).not.toMatch(/ok 'Files admin login works/);
  });
});

describe('the harness never needs root', () => {
  /* A harness that asks for root teaches people to run it as root, and then every
     file it generates belongs to root and the *next* run needs root again. These
     pin the split: `e2e.sh` refuses privilege, and the three things that genuinely
     need it live in one script that is run once. */
  it('refuses to run as root, and refuses to run under sudo', () => {
    expect(script).toMatch(/if \[\[ "\$\(id -u\)" -eq 0 \]\]/);
    expect(script).toContain('refusing to run as root');
    expect(script).toMatch(/if \[\[ -n "\$\{SUDO_USER:-\}" \]\]/);
    expect(script).toContain('refusing to run under sudo');
  });

  it('does not change ownership or write system files', () => {
    /* The one `chown` left is `chown zulip "${pw}"`, which runs **inside** the
       Zulip container through `docker compose exec` and needs no host privilege.
       What must not come back is a host-side chown — the recursive form, one
       against a host path, or one aiming at a container uid. */
    expect(script).not.toMatch(/chown -R/);
    expect(script).not.toMatch(/chown "\$/);
    expect(script).not.toMatch(/chown 1000/);
    expect(script).not.toMatch(/>>?\s*\/etc\/hosts/);
    expect(script).not.toMatch(/update-ca-certificates|update-ca-trust|trust anchor --store/);
  });

  it('checks the browser prerequisites instead of providing them', () => {
    expect(script).toMatch(/check_browser_prerequisites\(\)/);
    expect(script).toContain('setup-testing.sh');
  });

  it('refuses to deploy until the machine is prepared for a browser', () => {
    /* The harness exists so a person can open the result. Discovering after a
       ten-minute build that the page cannot load is the failure this gate exists to
       prevent, so it fails *before* anything is built and names the one command that
       fixes it. `--no-browser` is the way out for a machine with no browser. */
    expect(script).toMatch(/require_browser_preflight\(\)/);
    const main = script.slice(script.indexOf('\nmain() {'));
    expect(main).toMatch(/\[\[ "\$\{DO_BROWSER\}" -eq 1 \]\] && require_browser_preflight/);
    /* Before the build, not after it. */
    expect(main.indexOf('require_browser_preflight'))
      .toBeLessThan(main.indexOf('build_image'));
  });

  it('generates the certificate from the same library the setup script uses', () => {
    /* A certificate generated by two programs is two certificates: the browser
       trusts the one the setup script installed and the stack serves the other.
       One generator, in `scripts/lib/localca.sh`, is what makes those the same
       file. */
    expect(script).toContain('source "${SCRIPT_DIR}/lib/localca.sh"');
    expect(script).toMatch(/localca_ensure/);
    expect(script).not.toMatch(/openssl req -x509 -newkey/);
  });

  it('removes container-owned state without privilege', () => {
    /* Bind mounts make a container's writes the container's uid on the host, so
       `rm -rf` alone cannot clean up. A throwaway container does it as root in its
       own namespace, which needs nothing from the host. */
    expect(script).toMatch(/remove_generated_tree\(\)/);
    expect(script).toContain('--entrypoint sh');
    expect(script).toMatch(/readonly RUNTIME_STATE_IMAGE=/);
  });
});

describe('setup-testing.sh', () => {
  const setup = fs.readFileSync(path.resolve(__dirname, '../../scripts/setup-testing.sh'), 'utf8');

  it('does not abort when a browser store has no certificate yet', () => {
    /* `certutil -L -n <name>` and `certutil -D -n <name>` both exit non-zero when
       the nickname is absent — the normal first run, and every fresh profile — so
       under `pipefail` the unguarded probes aborted the whole run before the
       certificate could be installed. The trust logic moved out of `e2e.sh` into
       this script and the guard had to move with it; a rebase is what showed it had
       not, which is why the check lives here rather than where it was written. */
    expect(setup).toContain('fingerprint -sha256 2>/dev/null || true)');
    expect(setup).toContain('-D -n "${LOCALCA_STORE_NAME}" >/dev/null 2>&1 || true');
  });

  it('is the only script that requires root, and says so', () => {
    expect(setup).toMatch(/require_root\(\)/);
    expect(setup).toMatch(/if \[\[ "\$\(id -u\)" -ne 0 \]\]/);
    expect(setup).toContain('/etc/hosts');
    expect(setup).toContain('trust anchor --store');
  });

  it('acts on the invoking user, never on root', () => {
    /* `SUDO_USER` is the whole point: files must land on the person who will run
       the harness, or the next run needs root to touch its own files. */
    expect(setup).toMatch(/target_user\(\)/);
    expect(setup).toContain('${SUDO_USER:-$(id -un)}');
    expect(setup).toMatch(/chown -R "\$\{target\}:\$\{target\}"/);
  });

  it('gives Authentik’s own directories to the uid its image runs as', () => {
    /* The image declares `User: 1000` and writes /media, /certs and /templates, so
       on a machine whose first user is not 1000 the server dies during its tenant
       migration with `Permission denied: '/media/public'`. */
    expect(setup).toMatch(/Authentik\/data\/media Authentik\/data\/certs Authentik\/data\/templates/);
    expect(setup).toMatch(/chown -R 1000:1000/);
  });

  it('writes every hostname the deployment serves into /etc/hosts', () => {
    /* The list held five names until Phase 4 added the identity provider and the
       dashboard — and the two that were missing are the two a sign-in cannot do
       without, because a browser that cannot resolve `auth.` never completes the
       redirect. Adding a hostname to the deployment means adding it here. */
    expect(setup).toMatch(/AUTHENTIK_HOST="\$\{AUTHENTIK_HOST:-/);
    expect(setup).toMatch(/TRAEFIK_HOST="\$\{TRAEFIK_HOST:-/);
    const block = setup.slice(
      setup.indexOf('add_hosts_entries() {'),
      setup.indexOf("ok 'added the deployment"),
    );
    for (const v of ['WORKCENTER_HOST', 'FILEBROWSER_HOST', 'CHAT_HOST', 'MAIL_HOST',
      'OFFICE_HOST', 'AUTHENTIK_HOST', 'TRAEFIK_HOST']) {
      expect(block).toContain(`\${${v}}`);
    }
  });

  it('replaces a stale host block instead of reporting it already present', () => {
    /* Append-only with a marker check is how a machine resolves five of seven names
       for ever: the guard passes, nothing is written, and the two it is missing are
       the ones identity needs. The block is compared to what the deployment serves
       and rewritten when it differs. */
    const block = setup.slice(setup.indexOf('add_hosts_entries() {'), setup.indexOf('remove_hosts_entries() {'));
    expect(block).toMatch(/\[\[ "\$\{current\}" == "\$\{wanted\}" && "\$\{stale\}" -eq 0 \]\]/);
    /* And the rewrite goes through the same stripper `--remove` uses, so it takes
       out the unmarked line an older version left rather than writing a second
       mapping alongside it. */
    expect(block).toMatch(/strip_workcenter_hosts "\$\{HOSTS_FILE\}" "\$\{tmp\}"/);
    expect(block).toMatch(/printf '%s\\n%s\\n%s\\n' "\$\{HOSTS_MARKER_BEGIN\}" "\$\{wanted\}" "\$\{HOSTS_MARKER_END\}"/);
  });

  it('can undo what it did', () => {
    expect(setup).toMatch(/--remove/);
    expect(setup).toMatch(/remove_hosts_entries/);
    expect(setup).toMatch(/remove_trusted_certificate/);
    /* Removing the marked block is not enough to undo it: an older version wrote
       the mapping without markers, so a line naming one of the deployment's
       hostnames comes out whether it is inside the block or not. */
    expect(setup).toMatch(/\$1 == "127\.0\.0\.1" \|\| \$1 == "::1" \|\| \$1 == "0\.0\.0\.0"/);
    expect(setup).toMatch(/if \(\$i == h\[j\]\) \{ dropped\+\+; next \}/);
  });
});

describe('Mailcow is configured by Mailcow', () => {
  it('runs the upstream configurator rather than writing a config itself', () => {
    /* `generate_config.sh` writes `mailcow.conf` from an inline heredoc — it never
       reads `mailcow.conf.example`, which is documentation. A harness that wrote
       its own would be testing a configuration Mailcow never produced, and would
       stop noticing when the real one changes. */
    expect(script).toMatch(/ensure_mailcow_config\(\)/);
    expect(script).toMatch(/\.\/generate_config\.sh --dev/);
    /* The four prompts, answered from the environment before they are reached. */
    for (const v of ['MAILCOW_HOSTNAME=', 'MAILCOW_TZ=', 'SKIP_CLAMD=y', 'SKIP_BRANCH=y']) {
      expect(script).toContain(v);
    }
  });

  it('never gives Mailcow one of the ports the stack itself binds', () => {
    /* Mailcow publishes its own web ports and an override cannot unpublish them
       (IN-6.4). The trap is timing: Mailcow is configured *before* Traefik starts,
       so 80 and 443 are genuinely free at the moment of asking and taken a minute
       later. "Is anything listening" therefore picks exactly the wrong two ports. */
    expect(script).toMatch(/mailcow_port_usable\(\)/);
    expect(script).toMatch(/port >= 1024 && port <= 65535/);
    expect(script).toMatch(/port != TRAEFIK_HTTP_PORT && port != TRAEFIK_HTTPS_PORT/);
    expect(script).toMatch(/readonly TRAEFIK_HTTP_PORT="\$\{TRAEFIK_HTTP_PORT:-80\}"/);
  });

  it('does not treat Mailcow’s data tree as state this harness created', () => {
    /* `Mailcow/data` looks like the other bind-mount targets and is not: the clone
       ships configuration templates, the web tree and the `ssl-example` assets
       under it, and the configurator writes into all three. Recording it for
       removal leaves a Mailcow that cannot be configured again, and it is silent
       until the next `generate_config.sh` fails on
       `data/assets/ssl-example/key.pem`. */
    const mounts = script.slice(
      script.indexOf('ensure_mount_points() {'),
      script.indexOf('set_compose_env() {'),
    );
    expect(mounts).not.toContain('${ROOT_DIR}/Mailcow/data');
    expect(mounts).toContain('Not `Mailcow/data`');
  });

  it('restores what a run overwrote, so --down leaves the checkout as it found it', () => {
    /* Mailcow is configured *in place*, and a half-restored Mailcow is worse than
       either state: the file has to match the database it was generated for. */
    expect(script).toMatch(/record_backup\(\)/);
    expect(script).toMatch(/for backups in "\$\{RUN_DIR\}"\/backups-\*\.manifest/);
    const down = script.slice(script.indexOf('stack_down() {'));
    expect(down).toMatch(/cp -a "\$\{store\}" "\$\{original\}"/);
  });

  it('can tear Mailcow down even when its configuration is gone', () => {
    /* Compose cannot parse the override without a readable `mailcow.conf` — it
       interpolates `${BASE_DOMAIN:?…}` and refuses the project. That is one of the
       states a run leaves behind, and `--down` is what reverts it, so the teardown
       cannot depend on the thing it is about to remove. */
    const down = script.slice(script.indexOf('stopping Mailcow'));
    expect(down).toMatch(/docker rm -f \$\(docker ps -aq --filter 'label=com\.docker\.compose\.project=mailcow'\)/);
  });
});

describe('the browser sign-in path', () => {
  /* Everything here exists because a full green run shipped a shell that could not
     sign anyone in. The checks proved the provider *issues* a good token and never
     proved an application could *use* one — different failures with the same
     symptom on screen. */
  it('attaches the built-in openid mapping, found by managed id', () => {
    /* Authentik intersects the scopes a client asks for with the ones the provider
       is configured for and silently drops the rest. Without `openid` the token is
       refused by `/userinfo/` with `403 Scope mismatch` while the id_token still
       verifies perfectly. Built-ins cannot be found by name — a built-in is called
       `authentik default OAuth Mapping: OpenID 'openid'` — so the lookup is by
       `managed`. */
    expect(library).toMatch(/authentik_find_builtin_scope_mapping\(\)/);
    expect(library).toContain('goauthentik.io/providers/oauth2/scope-openid');
    expect(library).toMatch(/mapping_pks\+=\("\$\{builtin\}"\)/);
  });

  it('supplies its own profile mapping instead of the built-in one', () => {
    /* Two constraints pulling in opposite directions, and the answer is a custom
       mapping rather than either built-in:
         * the built-in `profile` emits `groups` on 2026.8, and two mappings writing
           one claim are **concatenated** — `["workspaceusers","workspaceadmin",
           "workspaceusers",…]`;
         * dropping `profile` altogether loses `preferred_username`, and FileBrowser
           answers `500 no valid username found for identifier 'preferred_username'`
           without it. The shell falls back to the email address; FileBrowser does
           not.
       So the custom mapping carries the standard claims and leaves `groups` to the
       one mapping that owns it. */
    expect(library).not.toContain('goauthentik.io/providers/oauth2/scope-profile');
    expect(library).toMatch(/authentik_ensure_scope_mapping 'profile' 'profile'/);
    expect(library).toContain('preferred_username');
    /* And it must not reintroduce the duplicate it exists to avoid. */
    const start = library.indexOf("authentik_ensure_scope_mapping 'profile' 'profile'");
    const block = library.slice(
      start,
      library.indexOf("authentik_ensure_scope_mapping 'mailcow_template'", start),
    );
    expect(block).not.toMatch(/"groups":/);
  });

  it('calls userinfo the way a browser does, and requires it to be readable', () => {
    /* A Node client enforces neither authorisation-by-scope nor CORS, which is
       exactly how every check passed while the browser failed. The userinfo call
       has to be cross-origin and it has to check the header a browser needs. */
    expect(verifier).toMatch(/application\/o\/userinfo\//);
    expect(verifier).toMatch(/access-control-allow-origin/);
    expect(verifier).toMatch(/Origin: new URL\(args\.redirectUri\)\.origin/);
    expect(verifier).toMatch(/userinfo_ok/);
  });

  it('fails a token with a duplicated groups claim or no openid scope', () => {
    /* Membership tests pass either way, so neither defect is visible in an
       application — they have to be asserted on the claim itself. */
    expect(script).toMatch(/the groups claim has duplicates/);
    expect(script).toMatch(/the token has no 'openid' scope/);
  });

  it('drives each application’s own sign-in entry', () => {
    /* The blind spot that let all three panes fail at once. The token checks prove
       the **provider** issues something good; they say nothing about whether an
       application can start its own flow, and each of the three failures was a
       different cause that was invisible from the provider's side. */
    expect(script).toMatch(/app_entry.*entry_label.*entry_path.*expected_client/s);
    expect(script).toMatch(/Files sign-in\|/);
    expect(script).toMatch(/Mail sign-in\|/);
    expect(script).toMatch(/Chat sign-in\|/);
  });

  it('provisions each application at the identity the provider signs in as', () => {
    /* The fixtures live at `@wc.test` (Testing.md §7.1) and the deployment's own
       address is a different one. Provisioning the wrong one produces a failure in
       the application with nothing in its log: Mailcow answers `Login failed`
       because it matches a mailbox by exact address, and Zulip's realm ends up with
       no owner among the accounts that can actually sign in. */
    expect(script).toMatch(/mailbox="\$\{MAILCOW_MAILBOX:-\$\{AUTHENTIK_TEST_ADMIN_EMAIL\}\}"/);
    expect(script).toMatch(/identity_domain="\$\{mailbox##\*@\}"/);
    expect(script).toMatch(/AUTHENTIK_TEST_ADMIN_EMAIL\}\|owner\|/);
    expect(script).toMatch(/AUTHENTIK_TEST_USER_EMAIL\}\|member\|/);
  });

  it('hands Zulip’s sign-up decision to the layer that already makes it', () => {
    /* `invite_required` defaults to true, so an OIDC user who authenticates
       perfectly is stopped at "You need an invitation to join this organization."
       The gate that decides who may sign in is Authentik's application binding, so
       Zulip's own gate asks a question that has already been answered — one layer
       too late, and with no way for the user to answer it. */
    expect(script).toMatch(/do_set_realm_property\(realm, \\"invite_required\\", False/);
    expect(script).toMatch(/require_browser_preflight|ensure_zulip_members/);
  });

  it('redirects stdin on every call inside a read loop', () => {
    /* `compose exec` inherits the loop's stdin and **consumes it**, so a `while read`
       loop fed by a heredoc creates the first member and then ends — silently. One
       account, no error, and a second identity that never appears. It has to be
       counted, not trusted. */
    const members = script.slice(
      script.indexOf('ensure_zulip_members() {'),
      script.indexOf('\ncheck_http() {'),
    );
    expect(members).toMatch(/<\/dev\/null/);
  });

  it('reads the Mailcow claims from user attributes, as the integration requires', () => {
    /* The published integration reads `email_verified` and `mailcow_template` from
       `request.user.attributes`, so they are properties of the account rather than
       constants of the deployment — and `authentik_ensure_user` has to set them, or
       the expressions return `False` and the fallback. Zulip's `email_verified`
       check is the same trap from the other side. */
    expect(library).toMatch(/request\.user\.attributes\.get\("email_verified", False\)/);
    expect(library).toMatch(/request\.user\.attributes\.get\("mailcow_template", "default"\)/);
    expect(library).toMatch(/attributes: \{email_verified: true, mailcow_template: "default"\}/);
  });

  it('trusts the local authority the way PHP actually reads it', () => {
    /* `CURL_CA_BUNDLE` is honoured by libcurl's own tooling and by the Go and
       Python clients elsewhere in this stack, so setting it for Mailcow looked
       right and did nothing: the exchange failed with `cURL error 60: SSL
       certificate problem: unable to get local issuer certificate`, logged in
       Mailcow's own `logs` table rather than on stdout — which is why the UI could
       only say "login failed". PHP's curl extension takes its anchor from the
       `curl.cainfo` ini setting, so the mount that matters is an ini file in the
       directory the image scans. */
    expect(script).toContain('curl.cainfo=/certs/local-ca.crt');
    expect(script).toContain('/usr/local/etc/php/conf.d/');
    /* The env var stays, for the non-PHP curl paths, but it is not the fix. */
    expect(script).toMatch(/CURL_CA_BUNDLE: \/certs\/local-ca\.crt/);
  });

  it('sets a Mailcow administrator password and says which surface it is for', () => {
    /* Mailcow's admin page authenticates against its own `admin` table, which is
       deliberately separate from mailboxes — the SSO identity is a *mailbox*. It
       generates that account a password nobody knows, so the page is unreachable
       until one is set, which from the outside is indistinguishable from "the
       password is wrong". Printing it under its own heading is what stops it being
       confused with the SSO identity. */
    expect(script).toMatch(/MAILCOW_ADMIN_PASSWORD="\$\{MAILCOW_ADMIN_PASSWORD:-/);
    expect(script).toMatch(/edit\/admin/);
    expect(script).toMatch(/local credential, NOT the SSO identity/);
  });

  it('waits for every built-in the provider is built from, not the ones it has seen fail', () => {
    /* The gate named only the two flows, which were the objects that had failed
       *so far*. A blueprint does not create them all at once — the one carrying the
       scope mappings lands after the one carrying the flows — so the gate opened in
       the window between them and provisioning died on its next call:

         ✖ Authentik has no built-in scope mapping '.../scope-openid'

       A gate that lists the failures it happens to have seen is a gate that fails
       again on the next one. */
    expect(library).toMatch(/AUTHENTIK_READY_SCOPE_MAPPINGS=\(/);
    expect(library).toMatch(/'goauthentik\.io\/providers\/oauth2\/scope-openid'/);
    expect(library).toMatch(/AUTHENTIK_READY_FLOWS=\(/);
    /* The gate consults the lists… */
    expect(library).toMatch(/for slug in "\$\{AUTHENTIK_READY_FLOWS\[@\]\}"/);
    expect(library).toMatch(/for mapping in "\$\{AUTHENTIK_READY_SCOPE_MAPPINGS\[@\]\}"/);
    /* …and so does the provisioning, so the two cannot disagree about what has
       to exist before it can run. */
    expect(library).toMatch(/for mapping in "\$\{AUTHENTIK_READY_SCOPE_MAPPINGS\[@\]\}"; do\n    local builtin/);
    /* The signing key is the third built-in the provider needs, and it was
       ungated too. */
    expect(library).toMatch(/authentik_find_signing_key "\$\{AUTHENTIK_SIGNING_KEY_NAME\}"/);
  });

  it('removes container-owned state the way the contract says, in every place', () => {
    /* Nothing about removing generated state needs privilege: removal runs in a
       throwaway container, root **in its own namespace**, with the checkout bind
       mounted, so the same inodes go and the host never escalates (Testing.md,
       "Removing generated state"). `remove_generated_tree` is that mechanism.

       One loop used a bare `rm -rf` instead — the manifest pass, which is the one
       that runs first — so a directory a container owns came back as an error the
       host cannot act on:

         rm: cannot remove '.../Authentik/data/postgres': Permission denied

       It is not exotic state: Authentik's postgres directory is mode 700 owned by
       65534, and Zulip's database, rabbitmq and redis directories and OnlyOffice's
       data directory are the same. */
    expect(script).toMatch(/if \[\[ -e "\$\{path\}" \]\]; then remove_generated_tree "\$\{path\}" && removed=/);
    /* No bare `rm -rf` outside the helper that needs one and the two scratch
       directories under the run directory, which no container owns. */
    const bare = [...script.matchAll(/^\s*rm -rf (.+)$/gm)]
      .map((m) => m[1])
      .filter((t) => !/2>\/dev\/null|RUNTIME_STATE_IMAGE|RUN_DIR|"\/workcenter/.test(t));
    expect(bare, `bare rm -rf remains in: ${bare.join(' | ')}`).toEqual([]);
  });

  it('reports .env as a leftover only when a run actually created it', () => {
    /* `.env` is the one generated file an operator is invited to edit, so its
       existence is not evidence of anything. The check used to be bare existence,
       which reported the operator's own configuration as a failure on every
       teardown of a checkout the harness had ever bootstrapped — the manifest that
       recorded it belonging to a run whose run directory is long gone. */
    expect(script).toMatch(/if grep -qxF "\$\{path\}" <<<"\$\{manifest_claimed\}"; then/);
    expect(script).toMatch(/was not created by a run: kept/);
  });

  it('gives Mailcow the claim-to-template map its callback dereferences', () => {
    /* Mailcow's callback runs `array_search($info['mailcow_template'],
       $iam_settings['mappers'])` before any login logic, so a provider config
       without `mappers` does not degrade — it throws:

         array_search(): Argument #2 ($haystack) must be of type array, null given
         /web/inc/functions.inc.php:2916

       The pair maps the **value of the `mailcow_template` claim** onto a Mailcow
       mailbox template by position, and Mailcow writes neither unless the two
       arrays have equal length. */
    expect(script).toMatch(/mappers: \["default"\]/);
    expect(script).toMatch(/templates: \["Default"\]/);
  });

  it('walks the application’s own sign-in, not just the provider’s', () => {
    /* The check whose absence let this ship: every provider-side check passed
       while Mailcow answered every real sign-in with a blank page, because the
       provider issued a perfect token and the application threw before reading
       one. Only starting at the application's entry point can see that. */
    expect(script).toMatch(/--sso-entry/);
    expect(script).toMatch(/Mail SSO: \$\{AUTHENTIK_TEST_ADMIN_EMAIL\} landed inside SOGo/);
    /* And the landing URL is asserted, not just the status: Mailcow sends a
       signed-in user to `/SOGo/so/<address>/Mail/view`, so the address appearing
       there proves the session belongs to *this* account. */
    expect(script).toMatch(/\.landed \| contains\(\$e\)/);
  });

  it('lets each application reach the provider, and trust it', () => {
    /* Zulip fetches discovery through `requests`, so it needs the CA *and* a
       `no_proxy` entry: its supervisor starts the Django process with
       HTTP(S)_proxy pointed at Zulip's own go-camo image proxy, which refuses
       anything that is not an image with `407`. Mailcow performs the exchange in
       php-fpm, so that container has to be on the network the identity host
       resolves on — nginx was, for ingress, which is why the egress need was easy
       to miss. */
    const zulipCompose = fs.readFileSync(path.resolve(__dirname, '../../Zulip/compose.yaml'), 'utf8');
    expect(zulipCompose).toMatch(/NO_PROXY:.*AUTHENTIK_HOST/);
    expect(zulipCompose).toMatch(/no_proxy:.*AUTHENTIK_HOST/);
    const testCompose = fs.readFileSync(path.resolve(__dirname, '../../compose.test.yaml'), 'utf8');
    expect(testCompose).toMatch(/REQUESTS_CA_BUNDLE: \/certs\/local-ca\.crt/);
    const mailcowOverride = fs.readFileSync(
      path.resolve(__dirname, '../../Mailcow/docker-compose.override.yml'), 'utf8',
    );
    expect(mailcowOverride).toMatch(/php-fpm-mailcow:/);
    expect(mailcowOverride).toMatch(/- proxy/);
  });
});

describe('the provisioning library', () => {
  it('looks every object up before creating it, so a re-run converges', () => {
    /* Authentik's API has no upsert; a naive POST on a second run fails with a
       uniqueness error (production.md P-40). */
    expect(library).toMatch(/authentik_find_group\(\)/);
    expect(library).toMatch(/authentik_find_oauth2_provider\(\)/);
    expect(library).toMatch(/authentik_find_application\(\)/);
    expect(library).toMatch(/_authentik_require 201/);
  });

  it('lists applications with superuser_full_list', () => {
    /* Without it the endpoint returns only what the *caller* may see, and the
       `traefik` application is bound to `workspaceadmin` alone — so an automation
       would decide it does not exist and try to create it twice. */
    expect(library).toContain('superuser_full_list=true');
  });

  it('gives the embedded outpost its public URL', () => {
    /* Left blank it builds the browser's redirect from the address it was reached
       on, which behind Traefik is the container's own http://0.0.0.0:9000 — a
       host that does not exist, so the dashboard is unreachable however correct
       every other object is. */
    expect(library).toMatch(/authentik_ensure_outpost_host\(\)/);
    expect(library).toContain('authentik_host_browser');
  });

  it('makes the documented invalidation flow actually sign the user out', () => {
    /* `default-provider-invalidation-flow` ships with no stage bindings, so a
       provider naming it — as OIDC.md §4.4 requires — reaches the session-end
       screen without `logout()` ever running. The session survives, and nothing
       on screen says so. */
    expect(library).toMatch(/authentik_ensure_invalidation_logout\(\)/);
    expect(library).toContain('default-invalidation-logout');
    expect(library).toMatch(/default-provider-invalidation-flow/);
  });

  it('registers the shell as a public client and the rest as confidential', () => {
    /* The shell exchanges the code in the browser and has nowhere to keep a
       secret, so OIDC.md §4.4's "Confidential for every client" cannot hold for
       it; the token endpoint answers `invalid_client` otherwise. */
    expect(library).toMatch(/\[\[ "\$\{slug\}" == 'workcenter' \]\] && client_type='public'/);
    expect(library).toContain("local client_type='confidential'");
  });
});

describe('the SOGo theme check', () => {
  it('asserts the hook, the stylesheet, the registration and the selectors', () => {
    /* A theme is a set of CSS overrides, and an override whose selector no longer
       matches fails silently and looks exactly like success. The selectors were
       read out of the stylesheets SOGo 5.12 serves; this asserts that the check
       still compares them against SOGo rather than trusting the list. */
    expect(script).toMatch(/check_sogo_theme\(\)/);
    expect(script).toMatch(/SOGo theme: the hook is served and configured/);
    expect(script).toMatch(/SOGo theme: the stylesheet declares both modes/);
    expect(script).toMatch(/SOGo theme: the hook is registered in SOGoUIAdditionalJSFiles/);
    expect(script).toMatch(/SOGo theme: every selector the stylesheet uses still exists in SOGo/);
    expect(script).toMatch(/for selector in 'md-content' 'md-dialog' 'md-toolbar' 'md-button' 'ui-view'/);
  });

  it('does not look for the hook in the bundle SOGo does not put it in', () => {
    /* Measured, and it is the trap this check exists to avoid: `/cache/<hash>.js`
       is Mailcow's own AngularJS build, served by nginx's `try_files` falling
       through to `resource.php` in **php-fpm**, which returns `/tmp/<basename>`.
       It is not produced by SOGo, it does not carry `SOGoUIAdditionalJSFiles` —
       Mailcow's own `mc_logout` is absent from it too — and it is byte-identical
       across restarts. The additional JS files load in the authenticated app, so
       an unauthenticated fetch of `/SOGo/` can never show the hook. */
    /* Bounded from the comment block above the function to its own closing brace,
       so the slice cannot drift into the functions after it. */
    const start = script.indexOf('# Does the theme still apply?');
    const from = script.indexOf('check_sogo_theme() {', start);
    const to = script.indexOf('\n}\n', from);
    const check = script.slice(start, to);
    expect(from).toBeGreaterThan(-1);
    expect(to).toBeGreaterThan(from);
    /* The comment above the function *names* `/cache/` — that is the explanation
       of the trap. What must not is the code: no fetch may target it. */
    const code = check.split('\n').filter((l) => !l.trim().startsWith('#')).join('\n');
    expect(code).not.toMatch(/\/cache\//);
    expect(check).toMatch(/the hook loads matters/);
  });
});
