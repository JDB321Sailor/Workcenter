/**
 * Pane URLs.
 *
 * Workcenter never hard-codes an application's address in a component. The
 * addresses come from `appConfig.applications` in `conf.yml`, so an operator
 * can point a pane at any host without touching the code.
 */

import { APP_LIST, getApp } from '@/utils/apps/registry';
import { sanitizeUrl } from '@/utils/Sanitizer';

/**
 * The configured URL for one application, or an empty string when it is not
 * configured or the value is not a usable http(s) URL.
 */
export const appUrl = (appConfig, appId) => {
  const app = getApp(appId);
  if (!app) return '';
  const configured = appConfig?.applications?.[app.configKey];
  const url = typeof configured === 'string' ? configured : configured?.url;
  if (!url) return '';
  return sanitizeUrl(url) || '';
};

/** Every application with its configured URL, in rail order. */
export const appUrls = (appConfig) => APP_LIST.reduce((acc, app) => {
  acc[app.id] = appUrl(appConfig, app.id);
  return acc;
}, {});

/** True when the application has a usable address and can be shown. */
export const isAppConfigured = (appConfig, appId) => appUrl(appConfig, appId) !== '';

/**
 * Expand a deep link against an application's address.
 *
 * `path` is appended to the application's base URL, so a sidebar row can point
 * at a folder in FileBrowser or a channel in Zulip without knowing the host.
 */
export const deepLink = (appConfig, appId, path = '') => {
  const base = appUrl(appConfig, appId);
  if (!base) return '';
  if (!path) return base;
  const trimmedBase = base.endsWith('/') ? base.slice(0, -1) : base;
  const trimmedPath = String(path).replace(/^\/+/, '');
  return sanitizeUrl(`${trimmedBase}/${trimmedPath}`) || '';
};

export default appUrl;
