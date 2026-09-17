# Other Auth Methods

Workcenter implements four authentication mechanisms: OIDC, header auth, the built-in user list and
Keycloak. Anything else belongs in front of it — at the proxy, the tunnel, the VPN or the network.

This page lists what an operator can put there, and what each one does for the workspace.

## What Workcenter does not implement

| Not implemented | Why it matters |
| --- | --- |
| SAML 2.0 | Workcenter speaks OIDC. A SAML identity provider needs a broker in front of it, or a provider that also speaks OIDC. |
| LDAP and Active Directory directly | No bind, no directory lookup. Authentik's LDAP outpost is for Mailcow, not for the shell. |
| Local two-factor authentication | MFA belongs to the identity provider. Authentik does it; the `users` list cannot. |
| Certificate authentication | No client-certificate handling in the shell or the server. |
| Rate limiting and account lockout | Neither the login form nor the server throttles attempts. |

## Putting something in front

**Workcenter is a single page that embeds three applications as iframes.** That shapes which proxy
and tunnel options fit, and it is the reason some of the usual recommendations do not apply here.

| Method | Fits | Notes |
| --- | --- | --- |
| Forward auth | Yes | Traefik with Authentik, nginx with `auth_request`, Caddy with `forward_auth`. Pair it with [header auth](./header-auth.md) so the shell learns who the proxy authenticated. This is the shape to use for an internet-facing deployment. |
| Proxy basic auth | Yes | A password prompt for the whole workspace, for example nginx `auth_basic` or Caddy `basicauth`. Nothing inside the shell knows the username. |
| IP allow-listing | Yes | Cheap extra layer, and the only one that needs no user interaction. Use it on top of a real mechanism, not instead of one. |
| VPN | Yes | The strongest reduction in attack surface: nothing is exposed. Remote users need the tunnel before they can load anything. |
| Client certificates (mTLS) | Partly | The proxy can require a certificate. A browser prompts for the certificate on a top-level navigation, so the prompt may not appear for a pane's own requests. |
| Cloud tunnel with an access policy | Yes | Cloudflare Access and similar gate the request before it reaches the host. |
| Platform password protection | No | Host-level password features on a managed static host have no equivalent here: Workcenter is served by its own Express server, and a pane is a frame on another origin. |
| An identity provider that only speaks SAML or plain OAuth 2.0 | Needs a bridge | Put Authentik, Keycloak or Authelia in front of it and let the shell use the OIDC it provides. |

## One layer, or two

An edge mechanism protects the shell. It does not sign anyone in to the three applications, because a
pane is a separate origin with its own session. Two layers are therefore normal:

1. **The edge** keeps unauthenticated traffic away from the host.
2. **Authentik over OIDC** gives the shell and each application the same identity.

Configuring only the edge leaves three independent logins inside the workspace. Configuring only
Authentik leaves the shell exposed to anyone who can reach it. See [`authentik.md`](./authentik.md)
and [`OIDC.md`](../../OIDC.md) for the second layer.

## Avoiding the framing traps

The three applications are embedded as iframes, so an edge device must not break framing:

- **Do not inject an authentication interstitial into an application's responses.** A pane that
  receives a login page instead of the application shows as unavailable, and the session inside it
  never starts.
- **Do not strip the applications' own security headers.** Each application decides who may frame it;
  Workcenter does not and cannot override that.
- **Give each application its own hostname.** Workcenter expects FileBrowser Quantum, Zulip and SOGo
  on their own origins, which is also what keeps them isolated from one another.

If a proxy session expires, the shell's panes keep showing their last state until they are reloaded.
`appConfig.enableAuthProxyCompat` exists for that: with the service worker enabled, it drops the
cached shell when a proxy redirects, so the proxy can re-authenticate the user.

## Read next

- [`header-auth.md`](./header-auth.md) — let an upstream proxy identify the user
- [`authentik.md`](./authentik.md) — the identity provider for the whole workspace
- [`security.md`](../security.md) — the intended deployment and its trust boundaries
