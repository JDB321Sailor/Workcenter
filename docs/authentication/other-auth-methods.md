# Other Auth Methods

If OIDC or our built-in auth doesn't suit your needs, there's plenty of other ways of protecting your dashboard from unauthenticated access.

- [Reverse Proxy Auth](#reverse-proxy-auth) - Authelia, Authentik, or similar sitting in front of Workcenter
- [Zero-Trust Tunnels](#zero-trust-tunnels) - Cloudflare Tunnel, Tailscale Funnel
- [VPN](#vpn) - Keep Workcenter off the internet entirely
- [IP-Based Access](#ip-based-access) - Restrict by source IP in your web server
- [Web Server Authentication](#web-server-authentication) - HTTP basic auth at the proxy level
- [Client Certificates (mTLS)](#client-certificates-mtls) - Require a client TLS certificate to connect
- [SSO / OAuth Providers](#sso--oauth-providers) - Cloud-hosted identity providers
- [Cloud Hosting Providers](#cloud-hosting-providers) - Built-in auth on hosting platforms

> [!IMPORTANT]
> Every method on this page except header auth authenticates at the network or proxy edge, not inside Workcenter. Workcenter's own server stays open to anything that can reach it directly, so don't expose its port publicly: bind it to localhost or an internal network and only let the proxy or tunnel through. If you want app-level auth with per-user roles, use [OIDC](./oidc.md), [built-in auth](./built-in.md), or [header auth](./header-auth.md) instead.

## Reverse proxy auth

The most common setup for self-hosters running multiple services. Your reverse proxy delegates login to an auth server (forward auth), which handles login, 2FA, and sessions for everything behind it. You configure it once, and all your apps get protected.

Workcenter has [Header Authentication](./header-auth.md) support, so when your proxy authenticates a user and forwards their identity via a header, Workcenter picks up the username and maps it to a configured user automatically. No separate Workcenter login needed.

**Authelia** is lightweight and Docker-friendly. It supports 2FA, per-path access rules, and multiple user backends. To get started quickly:

1. `git clone https://github.com/authelia/authelia.git`
2. `cd authelia/examples/compose/lite`
3. Edit `users_database.yml`, `configuration.yml`, and `docker-compose.yml` for your domain and users
4. `docker compose up -d`

See the [Authelia docs](https://www.authelia.com/docs/) for the full setup guide.

**Authentik** is heavier but gives you a proper admin UI, built-in OIDC/SAML support, and user self-service (password resets, enrollment flows, etc). Good if you want a single identity provider across many apps. See the [authentik Docker Compose install](https://docs.goauthentik.io/docs/installation/docker-compose) to get started, and the [authentik guide](./authentik.md) for Workcenter-specific OIDC config.

**OAuth2 Proxy** ([docs](https://oauth2-proxy.github.io/oauth2-proxy/)) is a thin forward-auth layer that puts any OIDC or OAuth2 provider (Google, GitHub, your own IdP) in front of apps that can't do it themselves. Point it at Workcenter's [header auth](./header-auth.md) and it forwards the authenticated username, so you get provider login without Workcenter needing to reach the provider directly. See the [oauth2-proxy example](./header-auth.md#example-oauth2-proxy-and-nginx) for the full nginx setup.

## Zero-trust tunnels

These let you expose Workcenter to the internet without opening inbound ports or configuring port forwarding. Auth is handled by the tunnel provider before traffic ever reaches your server.



### Service worker & offline use

If you run Workcenter behind any of the redirect-based proxies or tunnels above and also enable the service worker for offline use (`appConfig.enableServiceWorker: true`), set `appConfig.enableAuthProxyCompat: true` as well. Without it, when your proxy session expires the cached app can get stuck, with the service worker serving the old page instead of letting the proxy redirect you to its login screen. With it enabled, Workcenter detects the expiry on load and reloads so you can sign in again.

## VPN

A VPN keeps Workcenter off the public internet entirely. You connect to your home network remotely and access Workcenter like you're on the LAN. No auth to configure, no attack surface to worry about. The downside: you need the VPN running to see anything, and some networks (corporate WiFi, hotels) block VPN traffic.

[WireGuard](https://www.wireguard.com/) is fast and minimal. Most self-hosters run it through a UI like [wg-easy](https://github.com/wg-easy/wg-easy), which gives you a web interface for managing peers and generating QR codes for mobile.


[OpenVPN](https://openvpn.net/) still works fine if you already have it running, but for a new setup WireGuard or Tailscale are easier to get going.

## IP-based access

If you have a static IP or are already on a VPN, you can restrict access to Workcenter by source IP at the web server level. This works well as an extra layer on top of other auth methods.

NGINX:
```text
location / {
    proxy_pass http://dashy:8080;
    allow 192.168.1.0/24;
    allow 203.0.113.50;
    deny all;
}
```

Caddy ([request matchers docs](https://caddyserver.com/docs/caddyfile/matchers)):
```text
dashy.example.com {
    @blocked not remote_ip 192.168.1.0/24 203.0.113.50
    respond @blocked "Access denied" 403
    reverse_proxy dashy:8080
}
```

Apache (2.4+):
```text
<Location />
    Require ip 192.168.1.0/24
    Require ip 203.0.113.50
</Location>
```

## Web server authentication

Your reverse proxy can handle HTTP basic auth directly, no extra services needed. This gives you a browser login prompt in front of Workcenter. Make sure you're using HTTPS, as basic auth sends credentials base64-encoded (not encrypted) with every request.

NGINX ([auth module docs](https://nginx.org/en/docs/http/ngx_http_auth_basic_module.html)):
```text
location / {
    auth_basic "Workcenter";
    auth_basic_user_file /etc/nginx/conf.d/.htpasswd;
    proxy_pass http://dashy:8080;
}
```

Generate the password file with `htpasswd -c /etc/nginx/conf.d/.htpasswd alicia`.

Caddy ([basicauth directive](https://caddyserver.com/docs/caddyfile/directives/basicauth)):
```text
dashy.example.com {
    basicauth {
        alicia $2a$14$... # generate with: caddy hash-password
    }
    reverse_proxy dashy:8080
}
```

Apache:
```text
AuthType Basic
AuthName "Workcenter"
AuthUserFile /path/to/.htpasswd
Require valid-user
```

Generate the password file with `htpasswd -c /path/to/.htpasswd alicia`.

## Client certificates (mTLS)

Instead of a password, you can require a client TLS certificate to reach Workcenter. The browser presents a cert you've issued, the proxy rejects anyone without a valid one. It's strong and can't be phished, but you have to generate, hand out, and occasionally revoke the certs, so it fits a small fixed set of devices better than a large user base.

You'll need your own CA to sign the client certs. [mkcert](https://github.com/FiloSottile/mkcert) is fine for a handful, [step-ca](https://github.com/smallstep/certificates) if you want to manage them properly.

NGINX:
```text
server {
    ssl_client_certificate /etc/nginx/certs/ca.crt;
    ssl_verify_client on;
    location / {
        proxy_pass http://dashy:8080;
    }
}
```

Caddy and Apache do mTLS too, via `client_auth` and `SSLVerifyClient require` respectively.

## SSO / OAuth providers

Cloud identity providers like [Auth0](https://auth0.com/), [Okta](https://developer.okta.com/), [Ory](https://www.ory.sh/), and [Google Cloud Identity](https://cloud.google.com/identity) can work with Workcenter through its [OIDC support](./oidc.md). If your provider speaks OIDC (most do), just configure it as described in the OIDC section and you're set.

For providers that only support OAuth2 or SAML without an OIDC layer, you'll need something in between to translate. Authentik, Keycloak, and Authelia can all bridge from SAML/OAuth2 to OIDC.

## Cloud hosting providers

If you're running Workcenter on a cloud platform, most have their own auth options you can enable without touching Workcenter's config. See your provider's docs: [Cloudflare Access](https://www.cloudflare.com/teams/access/), [Netlify Password Protection](https://docs.netlify.com/visitor-access/password-protection/), [AWS Cognito](https://aws.amazon.com/cognito/), [Azure App Service Authentication](https://learn.microsoft.com/en-us/azure/app-service/overview-authentication-authorization), and [Vercel Password Protection](https://vercel.com/docs/security/password-protection).
