import { describe, it, expect, beforeEach } from 'vitest';
import getApiAuthHeader, { getApiAuthState } from '@/utils/auth/getApiAuthHeader';
import { localStorageKeys } from '@/utils/config/defaults';

const part = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
const jwt = (claims) => `${part({ alg: 'RS256' })}.${part(claims)}.sig`;

describe('getApiAuthHeader', () => {
  beforeEach(() => {
    localStorage.getItem.mockReset();
  });

  it('returns a bearer header for a usable JWT', () => {
    const token = jwt({ exp: Math.floor(Date.now() / 1000) + 60 });
    localStorage.getItem.mockReturnValue(token);

    expect(getApiAuthHeader()).toEqual({ Authorization: `Bearer ${token}` });
    expect(getApiAuthState()).toMatchObject({ ok: true, reason: 'valid' });
  });

  it('classifies expired tokens', () => {
    localStorage.getItem.mockReturnValue(jwt({ exp: Math.floor(Date.now() / 1000) - 60 }));

    expect(getApiAuthHeader()).toBeNull();
    expect(getApiAuthState()).toEqual({ ok: false, reason: 'expired' });
  });

  it('classifies encrypted compact tokens as JWE', () => {
    localStorage.getItem.mockReturnValue('a.b.c.d.e');

    expect(getApiAuthState()).toEqual({ ok: false, reason: 'encrypted-jwe' });
  });

  it('classifies undecodable JWT payloads as malformed', () => {
    localStorage.getItem.mockReturnValue('a.not-json.c');

    expect(getApiAuthState()).toEqual({ ok: false, reason: 'malformed' });
  });

  it('classifies a null JSON payload as malformed without throwing', () => {
    localStorage.getItem.mockReturnValue(jwt(null));

    expect(() => getApiAuthState()).not.toThrow();
    expect(getApiAuthState()).toEqual({ ok: false, reason: 'malformed' });
  });

  it('classifies a missing token and reads the id_token key', () => {
    localStorage.getItem.mockReturnValue(null);

    expect(getApiAuthState()).toEqual({ ok: false, reason: 'missing' });
    expect(localStorage.getItem).toHaveBeenCalledWith(localStorageKeys.ID_TOKEN);
  });

  it('classifies unreadable storage', () => {
    localStorage.getItem.mockImplementation(() => { throw new Error('denied'); });

    expect(getApiAuthState()).toEqual({ ok: false, reason: 'storage' });
  });
});
