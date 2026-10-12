import {
  describe, it, expect, afterAll,
} from 'vitest';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

/**
 * `setup-testing.sh --remove` is the one operation in this repository that must be
 * *exactly* right and that nobody can rehearse: it needs root, so the only way to
 * see it work is to run it against the machine you were trying to restore. That is
 * a poor way to find out it was wrong.
 *
 * So the logic that decides which lines come out of `/etc/hosts` is a pure function
 * over a file, and it is exercised here against fixtures instead of described. The
 * functions are lifted out of the script by name, so this cannot drift into testing
 * a copy.
 *
 * The bug these exist for: an older version wrote the mapping **without** markers,
 * and a marked block only replaces itself. `--remove` deleted the block, reported
 * success, and left the older line resolving a subset of the deployment — the
 * machine was not returned to its prior state, which is the entire contract.
 */
const script = fs.readFileSync(path.resolve(__dirname, '../../scripts/setup-testing.sh'), 'utf8');

/** Lift a shell function out of the script by name. */
const shellFunction = (name) => {
  const match = script.match(new RegExp(`^${name}\\(\\) \\{[\\s\\S]*?^\\}`, 'm'));
  if (!match) throw new Error(`${name}() is not in setup-testing.sh`);
  return match[0];
};

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'wc-hosts-'));
afterAll(() => fs.rmSync(tmp, { recursive: true, force: true }));

/**
 * Run the stripper over `before` and return what came out and how many lines it
 * said it dropped.
 */
const strip = (before) => {
  const src = path.join(tmp, 'hosts');
  const dst = path.join(tmp, 'hosts.out');
  fs.writeFileSync(src, before);
  const program = `
    set -Eeuo pipefail
    HOSTS_MARKER_BEGIN="# >>> workcenter e2e >>>"
    HOSTS_MARKER_END="# <<< workcenter e2e <<<"
    WORKCENTER_HOST=workcenter.local
    FILEBROWSER_HOST=filebrowser.workcenter.local
    CHAT_HOST=chat.workcenter.local
    MAIL_HOST=mail.workcenter.local
    OFFICE_HOST=office.workcenter.local
    AUTHENTIK_HOST=auth.workcenter.local
    TRAEFIK_HOST=traefik.workcenter.local
    ${shellFunction('workcenter_hostnames')}
    ${shellFunction('strip_workcenter_hosts')}
    strip_workcenter_hosts "$1" "$2"
    printf 'DROPPED=%s\\n' "\${HOSTS_DROPPED}"
  `;
  const out = execFileSync('bash', ['-c', program, 'bash', src, dst], { encoding: 'utf8' });
  return {
    after: fs.readFileSync(dst, 'utf8'),
    dropped: Number(out.match(/DROPPED=(\d+)/)[1]),
  };
};

const SEVEN = 'workcenter.local filebrowser.workcenter.local chat.workcenter.local '
  + 'mail.workcenter.local office.workcenter.local auth.workcenter.local traefik.workcenter.local';
const FIVE = 'workcenter.local filebrowser.workcenter.local chat.workcenter.local '
  + 'mail.workcenter.local office.workcenter.local';

describe('setup-testing.sh --remove', () => {
  it('takes out the marked block', () => {
    const before = `127.0.0.1\tlocalhost\n# >>> workcenter e2e >>>\n127.0.0.1 ${SEVEN}\n# <<< workcenter e2e <<<\n`;
    const { after, dropped } = strip(before);
    expect(after).toBe('127.0.0.1\tlocalhost\n');
    /* Three lines: the two markers and the mapping between them. The count is what
       the script reports to the operator, so it has to match what actually went. */
    expect(dropped).toBe(3);
  });

  it('takes out an older, unmarked entry as well', () => {
    /* The case that was live on a real machine: a five-name line written before the
       markers existed, sitting above the current block. */
    const before = `127.0.0.1\tlocalhost\n127.0.0.1 ${FIVE}\n`
      + `# >>> workcenter e2e >>>\n127.0.0.1 ${SEVEN}\n# <<< workcenter e2e <<<\n`;
    const { after, dropped } = strip(before);
    expect(after).toBe('127.0.0.1\tlocalhost\n');
    expect(dropped).toBe(4);
  });

  it('leaves everything that is not this deployment’s alone', () => {
    /* The match is on the first field being a loopback address *and* a later field
       being one of the seven names. A comment that merely mentions the name, or a
       stanza pointing somewhere else, is not this script's to remove. */
    const before = [
      '127.0.0.1\tlocalhost',
      '127.0.1.1\tworkstation',
      '::1     localhost ip6-localhost ip6-loopback',
      '# a comment mentioning workcenter.local must survive',
      '192.168.1.50  nas.local  # workcenter.local is elsewhere',
      '::1     workcenter.local',
      '',
    ].join('\n');
    const { after, dropped } = strip(before);
    expect(dropped).toBe(1); // only the ::1 mapping, which is this deployment's
    expect(after).toContain('# a comment mentioning workcenter.local must survive');
    expect(after).toContain('192.168.1.50  nas.local  # workcenter.local is elsewhere');
    expect(after).toContain('127.0.1.1\tworkstation');
    expect(after).not.toContain('::1     workcenter.local');
  });

  it('changes nothing, and says so, when there is nothing of ours', () => {
    const before = '127.0.0.1\tlocalhost\n10.0.0.9 unrelated.example\n';
    const { after, dropped } = strip(before);
    expect(after).toBe(before);
    expect(dropped).toBe(0);
  });

  it('does not treat a partial name as a match', () => {
    /* `notworkcenter.local` ends with the deployment's name. Matching on fields
       rather than substrings is what keeps a neighbouring hostname out of it. */
    const before = '127.0.0.1 notworkcenter.local\n127.0.0.1 other.local workcenter.local.evil\n';
    const { after, dropped } = strip(before);
    expect(dropped).toBe(0);
    expect(after).toBe(before);
  });
});
