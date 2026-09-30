/**
 * The integrated applications.
 *
 * Workcenter renders one view with three panes. This registry is the single
 * source of truth for which applications exist, how they are labelled, where
 * they point, and which sidebar surface each one supplies.
 *
 * See design.md D-2 for the switcher and D-2S for the status indicators.
 */

/* Identifiers are stable: they appear in routes, in `conf.yml` and in the
 * health endpoint's response, so they are never renamed or reused. */
export const APP_IDS = Object.freeze({
  FILES: 'files',
  CHAT: 'chat',
  MAIL: 'mail',
});

export const APP_LIST = Object.freeze([
  {
    id: APP_IDS.FILES,
    /* Not translated: an application name is a proper noun. */
    name: 'Files',
    descriptionKey: 'apps.files.description',
    icon: 'fas fa-folder-open',
    /* The application's brand mark under `icons/`, reached through `@icons`
     * (design.md D-2I). Rendered by AppMark.vue, never recoloured. */
    mark: 'filebrowser-quantum',
    /* The mark a pane's own loading and error states use. For Files and Chat
     * the application mark is the pane mark; Mail's pane is SOGo, which has its
     * own mark (design.md D-2I). */
    paneMark: 'filebrowser-quantum',
    /* The CSS custom property carrying this application's accent colour. */
    accentVar: '--wc-accent-files',
    /* The key this application occupies in `appConfig.applications`. */
    configKey: 'files',
    /* The key its health is reported under. */
    healthKey: 'filebrowser',
    /* The pane route. */
    routeName: 'files',
    /* Which sidebar surface to render when this application is active. */
    sidebar: 'files',
  },
  {
    id: APP_IDS.CHAT,
    name: 'Chat',
    descriptionKey: 'apps.chat.description',
    icon: 'fas fa-comments',
    mark: 'zulip',
    paneMark: 'zulip',
    accentVar: '--wc-accent-chat',
    configKey: 'chat',
    healthKey: 'zulip',
    routeName: 'chat',
    sidebar: 'chat',
  },
  {
    id: APP_IDS.MAIL,
    name: 'Mail',
    descriptionKey: 'apps.mail.description',
    icon: 'fas fa-envelope',
    /* Mailcow is the deployment that serves SOGo webmail, so the switcher
     * carries Mailcow's mark and the pane carries SOGo's. */
    mark: 'mailcow',
    paneMark: 'sogo',
    accentVar: '--wc-accent-mail',
    configKey: 'mail',
    healthKey: 'mailcow',
    routeName: 'mail',
    sidebar: 'mail',
  },
]);

/** Look up an application by its identifier. */
export const getApp = (id) => APP_LIST.find((app) => app.id === id) || null;

/** Look up an application by the route name of its pane. */
export const getAppByRoute = (routeName) => APP_LIST.find((app) => app.routeName === routeName) || null;

/** True when the identifier names an integrated application. */
export const isAppId = (id) => APP_LIST.some((app) => app.id === id);

/** The identifiers, in rail order. */
export const appIds = () => APP_LIST.map((app) => app.id);

export default APP_LIST;
