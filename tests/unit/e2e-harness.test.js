import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';

/**
 * The e2e harness's own guardrails.
 *
 * `scripts/e2e.sh` has no unit-testable surface — a person is the runner and
 * ShellCheck is the CI gate (`Testing.md` §6.5, §10) — so these assert the two
 * properties that failed in the field. They are deliberately narrow: the
 * behaviour itself is exercised by the harness's own checks when it runs.
 */
const script = fs.readFileSync(path.resolve(__dirname, '../../scripts/e2e.sh'), 'utf8');

describe('the e2e harness', () => {
  it('reads process arguments with basename without treating them as options', () => {
    /* `our_server_pids` sweeps /proc for this checkout's `node server.js`. A Node
       process launched as `node --import …` made the unguarded call print
       `basename: unrecognized option '--import'`, and fail to match. */
    expect(script).toMatch(/basename -- "\$\{argv0:-\}"/);
    expect(script).toMatch(/basename -- "\$\{argv1:-\}"/);
  });

  it('sets a deterministic Files admin password and asserts the login', () => {
    expect(script).toMatch(/export FILEBROWSER_ADMIN_PASSWORD="\$\{FILEBROWSER_ADMIN_PASSWORD:-admin\}"/);
    expect(script).toContain('/api/auth/login?username=admin');
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

  it('prints both test accounts', () => {
    expect(script).toMatch(/print_test_accounts\(\)/);
    expect(script).toMatch(/print_test_accounts$/m);
    expect(script).toContain('Zulip signs in with the email address');
  });
});
