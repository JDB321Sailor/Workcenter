/**
 * Signing out.
 *
 * One action must end the session everywhere it can: the shell's own session
 * first, then the identity provider's, so the applications that support
 * RP-initiated logout are signed out with it (roadmap A-7, design.md D-6).
 */

import router from '@/router';
import Keys from '@/utils/StoreMutations';
import { logout as clearShellSession, getLogoutRedirectUrl } from '@/utils/auth/Auth';
import { getOidcAuth, isOidcEnabled } from '@/utils/auth/OidcAuth';
import { getKeycloakAuth, isKeycloakEnabled } from '@/utils/auth/KeycloakAuth';
import ErrorHandler from '@/utils/logging/ErrorHandler';
import { toast } from '@/utils/Toast';
import i18n from '@/utils/i18n';

/* The shell clears its own state, then hands over to the provider. */
const HANDOVER_MS = 500;

const tellTheUser = () => toast(i18n.global.t('login.logout-message'));

/**
 * End the session and, where the provider supports it, the provider session too.
 *
 * The caller supplies the store so the auth-dependent getters re-run; nothing
 * else about the shell is touched.
 */
export const signOut = (store) => {
  tellTheUser();

  if (isOidcEnabled()) {
    store.commit(Keys.AUTH_CHANGED);
    // oidc-client-ts performs RP-initiated logout: it clears its own state and
    // redirects to the provider's end-session endpoint.
    setTimeout(() => getOidcAuth().logout(), HANDOVER_MS);
    return;
  }

  if (isKeycloakEnabled()) {
    store.commit(Keys.AUTH_CHANGED);
    setTimeout(() => getKeycloakAuth().logout(), HANDOVER_MS);
    return;
  }

  clearShellSession();
  store.commit(Keys.AUTH_CHANGED);
  const redirectUrl = getLogoutRedirectUrl();
  setTimeout(() => {
    if (redirectUrl) window.location.href = redirectUrl;
    else router.push({ path: '/login' }).catch((e) => ErrorHandler('Logout redirect failed', e));
  }, HANDOVER_MS);
};

export default signOut;
