# Security Policy

Thanks for helping keep Dashy and the people who use it safe. If you've found something that could put users at risk, I really appreciate you taking the time to let me know.

## Reporting a security issue
If you think you've found a security problem, please securely reach-out, either:
- Open a [security advisory](https://github.com/lissy93/dashy/security/advisories/new) here on GitHub
- Or email me at `security@as93.net` (PGP: [`E10EE533A8E5D6F6E231BBCD4C8DEAFFCE3B8D03`](https://keys.openpgp.org/vks/v1/by-fingerprint/E10EE533A8E5D6F6E231BBCD4C8DEAFFCE3B8D03))

> [!IMPORTANT]
> Please do not report active security issues via public means, without first giving us 30 days to fix it.

Please write in English only.<br>
I'll usually get back to you within 48 hours, and give you a timeline for a fix (if applicable) - typically <30 days<br>
Once it's confirmed and fixed, I'm happy to credit you in the release notes if you'd like.

## What to include
To help me track it down quickly, it helps if you can include:
- What kind of issue it is (for example XSS, SQL injection, and so on)
- The source files or code involved, with a tag, branch or commit if you have one
- Any config needed to reproduce it
- Steps to reproduce
- A proof of concept, if you have one
- What an attacker could actually do with it

## Supported versions
The latest minor and patch versions are supported. Previous major versions (e.g. 3.x.x and below) don't receive official security updates.

## Keeping your own instance secure
Dashy's security posture and features are outlined in our [security docs](https://dashy.to/docs/security).
A lot of security comes down to how and where you deploy Dashy, so we've also documented some self-hosting best practices in the [management guide](https://dashy.to/docs/management/).

## Safe harbor
If you research and report in good faith, following this policy, I won't pursue legal action against you.
Just keep your testing to your own instance, don't access or disrupt anyone else's data, and give us time to fix things before going public.

## What not to report here
We get a LOT of false positives security reports, usually from AI scans. Be sure to verify your findings.

Please don't report issues which:
- Are not security issues (these can be raised as issue instead)
- Already have an open security advisory
- Are only vulnerable due to insecure deployment
- Are documented as known-limitations or false positives

Please don't over-state findings (like attaching an inflated CVS score). If a report is too many inaccurate or exaggerated findings, but still has valid findings, then I then need to go and create a fresh, valid report to publish (instead of publishing yours). This is inconvenient for both of us.
