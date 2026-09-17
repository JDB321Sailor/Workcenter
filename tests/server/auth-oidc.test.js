// @vitest-environment node
import { describe, it, expect } from 'vitest';
import { deriveIsAdmin, loadOidcSettings } from '../../services/utils/auth-oidc';

const oidc = { kind: 'oidc', clientId: 'dashy', adminGroup: 'admins', adminRole: null };
const keycloak = { kind: 'keycloak', clientId: 'dashy', adminGroup: null, adminRole: 'admin' };

describe('deriveIsAdmin', () => {
  it('matches adminGroup against the standard groups claim', () => {
    expect(deriveIsAdmin({ groups: ['admins', 'users'] }, oidc)).toBe(true);
    expect(deriveIsAdmin({ groups: ['users'] }, oidc)).toBe(false);
  });

  it('matches adminGroup against GitLab groups_direct claim', () => {
    expect(deriveIsAdmin({ groups_direct: ['admins'] }, oidc)).toBe(true);
    expect(deriveIsAdmin({ groups_direct: ['users'] }, oidc)).toBe(false);
  });

  it('matches adminRole against top-level roles claim', () => {
    const settings = { ...oidc, adminGroup: null, adminRole: 'admin' };
    expect(deriveIsAdmin({ roles: ['admin'] }, settings)).toBe(true);
  });

  it('matches Keycloak realm and client roles', () => {
    expect(deriveIsAdmin({ realm_access: { roles: ['admin'] } }, keycloak)).toBe(true);
    expect(deriveIsAdmin({ resource_access: { dashy: { roles: ['admin'] } } }, keycloak)).toBe(true);
    expect(deriveIsAdmin({ realm_access: { roles: ['viewer'] } }, keycloak)).toBe(false);
  });

  it('is false on missing claims or no admin config', () => {
    expect(deriveIsAdmin(null, oidc)).toBe(false);
    expect(deriveIsAdmin({}, oidc)).toBe(false);
    expect(deriveIsAdmin({ groups: ['admins'] }, { ...oidc, adminGroup: null })).toBe(false);
  });
});

describe('loadOidcSettings allowedIssuers', () => {
  const base = { enableOidc: true, oidc: { endpoint: 'https://idp.example.com', clientId: 'dashy' } };

  it('defaults to null when not set', () => {
    expect(loadOidcSettings(base).allowedIssuers).toBe(null);
  });

  it('keeps a non-empty list of issuers', () => {
    const cfg = { ...base, oidc: { ...base.oidc, allowedIssuers: ['https://a.example.com', 'https://b.example.com'] } };
    expect(loadOidcSettings(cfg).allowedIssuers).toEqual(['https://a.example.com', 'https://b.example.com']);
  });

  it('is null for an empty or non-array value', () => {
    expect(loadOidcSettings({ ...base, oidc: { ...base.oidc, allowedIssuers: [] } }).allowedIssuers).toBe(null);
    expect(loadOidcSettings({ ...base, oidc: { ...base.oidc, allowedIssuers: 'nope' } }).allowedIssuers).toBe(null);
  });

  it('returns null when disableServerSideCheck is set', () => {
    expect(loadOidcSettings({ ...base, oidc: { ...base.oidc, disableServerSideCheck: true } })).toBe(null);
  });
});
