/**
 * This is the router config, which defined the location for
 * each page within the app, and how they should be loaded
 * Note that the page paths are defined in @/utils/config/defaults.js
 */

// Import vue router
import { createRouter, createWebHistory, createWebHashHistory } from 'vue-router';
import { Progress } from 'rsup-progress';

// Import helper functions, config data and defaults
import store from '@/store';
import Keys from '@/utils/StoreMutations';
import { isAuthEnabled, isLoggedIn, isGuestAccessEnabled } from '@/utils/auth/Auth';
import { isOidcEnabled } from '@/utils/auth/OidcAuth';
import { isKeycloakEnabled } from '@/utils/auth/KeycloakAuth';
import { isHeaderAuthEnabled } from '@/utils/auth/HeaderAuth';
import { routePaths } from '@/utils/config/defaults';
import ErrorHandler from '@/utils/logging/ErrorHandler';

const progress = new Progress({ color: 'var(--progress-bar)' });

/* True for ANY auth (OIDC, KC, HeaderAuth, etc) */
const isAnyAuthConfigured = () =>
  isAuthEnabled() || isOidcEnabled() || isKeycloakEnabled() || isHeaderAuthEnabled();

/* Returns true if user is already authenticated, or if auth is not enabled */
const isAuthenticated = () => {
  if (store.state.criticalError) return false;
  const authEnabled = isAnyAuthConfigured();
  const userLoggedIn = isLoggedIn();
  const guestEnabled = isGuestAccessEnabled();
  return (!authEnabled || userLoggedIn || guestEnabled);
};

/* Determines if the page URL is an OAuth2 redirect-back from OIDC or Keycloak
 * Passes through the auth guard, so the callback ?code reaches the handler */
const isOauthCallback = () =>
  new URLSearchParams(window.location.search).has('code')
  && (isOidcEnabled() || isKeycloakEnabled());


/* Routing mode, can be either 'hash', 'history' or 'abstract' */
const mode = import.meta.env.VITE_APP_ROUTING_MODE || 'history';

/* Map mode string to Vue Router 4 history function */
const history = mode === 'hash'
  ? createWebHashHistory(import.meta.env.BASE_URL)
  : createWebHistory(import.meta.env.BASE_URL);

/* The Workcenter route table.
 * Workcenter renders one view. The path segments are the three applications, so
 * each pane is deep-linkable, and every unknown path falls through to the view
 * rather than a second page. */
const router = createRouter({
  history,
  routes: [
    { path: '/', name: 'workspace', component: () => import('./views/Workspace.vue') },
    { path: routePaths.files, name: 'files', component: () => import('./views/Workspace.vue') },
    { path: routePaths.chat, name: 'chat', component: () => import('./views/Workspace.vue') },
    { path: routePaths.mail, name: 'mail', component: () => import('./views/Workspace.vue') },
    { // The login page
      path: routePaths.login,
      name: 'login',
      component: () => import('./views/Login.vue'),
      beforeEnter: (to, from, next) => {
        // If the user is already logged in and guest mode is not enabled, go to the workspace
        if (isAuthenticated() && !isGuestAccessEnabled()) router.push({ path: '/' });
        next();
      },
    },
    { // Any unknown path renders the workspace
      path: '/:pathMatch(.*)*',
      name: 'not-found',
      component: () => import('./views/Workspace.vue'),
    },
  ],
});

/**
 * On first page load, initialize and wait for the the config loading.
 * Also guards against silently leaving an active edit session for a
 * different config (unsaved edits would otherwise become untethered
 * from whatever page the user switched to).
 */
router.beforeEach(async (to, from, next) => {
  progress.start();
  try {
    if (!store.state.rootConfig && !store.state.criticalError) {
      await store.dispatch(Keys.INITIALIZE_CONFIG);
    }
    if (to.name !== 'login'
      && !isAuthenticated() && !isOauthCallback() && !isHeaderAuthEnabled()) {
      next({ name: 'login' });
    } else next();
  } catch (e) {
    ErrorHandler('Navigation guard failed', e);
    next();
  }
});

/* Stop the loading progress bar once navigation settles */
router.afterEach(() => {
  progress.end();
});

/* Catch navigation + lazy-import failures */
router.onError((err) => {
  progress.end();
  ErrorHandler('Navigation failed. Try hard-reload (Shift + F5)', err);
});

// All done - export the now configured router
export default router;
