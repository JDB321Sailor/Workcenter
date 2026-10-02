/* ---------------------------------------------------------------------------
 * Workcenter — SOGo appearance hook (Mailcow / SOGo 5.12)
 *
 * WHAT THIS IS
 *   The one UI-extension hook SOGo 5.12 has: a JavaScript file listed in SOGo's
 *   own `SOGoUIAdditionalJSFiles`. SOGo has no custom-CSS setting, no dark mode
 *   and no appearance API, so the Workcenter palette has to be *supplied* —
 *   this file links it and tells it which mode to paint
 *   (roadmap I-MC-11/I-MC-12, integration.md IN-6.22/IN-6.23, broker.md §6.3).
 *
 * WHAT IT DOES, EXACTLY — four things, in order:
 *   1. reads the `wc_mode` cookie (the shell publishes it for the shared parent
 *      domain) and sets `data-wc-mode` on <html> before first paint, so the pane
 *      does not flash the wrong palette;
 *   2. injects one <link rel="stylesheet"> pointing at the Workcenter stylesheet,
 *      once, guarded by an id;
 *   3. listens for the shell's `workcenter:mode` pane message and updates the
 *      attribute, so an open Mail pane follows a mode switch;
 *   4. nothing else.
 *
 *   This file contains no palette and applies no styling of its own. The palette
 *   lives in the stylesheet, which selects on `html[data-wc-mode="dark"]` /
 *   `html[data-wc-mode="light"]`; if the stylesheet never loads, the Mail pane
 *   keeps SOGo's own appearance and nothing breaks.
 *
 * WHAT IT DELIBERATELY DOES NOT DO
 *   * It never hides, moves, disables or re-labels a control. Restyling is
 *     allowed; re-purposing is a defect (broker.md BR-6.3).
 *   * It never touches mail content, addresses, subjects or credentials, and it
 *     never reads or writes anything but the two literal mode values.
 *   * It never calls eval, Function, innerHTML or a dynamic import; the only
 *     external resource it can ever request is the stylesheet URL below.
 *   * It does not decide the mode: the shell owns the mode, this mirrors it. If
 *     the cookie is absent it changes nothing and lets SOGo paint its default.
 *
 * DEPLOYMENT
 *   Mounted by Mailcow/docker-compose.override.yml into SOGo's web resources as
 *   js/workcenter-theme.js, and registered in Mailcow/data/conf/sogo/sogo.conf
 *   (`SOGoUIAdditionalJSFiles`) — or appended to the already-registered
 *   data/conf/sogo/custom-sogo.js. `sogo-mailcow` must be restarted afterwards,
 *   because bootstrap-sogo.sh rsyncs the web resources into nginx's volume at
 *   container start (IN-6.26, P-32).
 *
 * CONFIGURATION
 *   The two tokens below are substituted with real values when this file is
 *   deployed (setup.sh `--brand`), from the same base URL the shell is served
 *   from. Until they are substituted the hook stays inert and says so once in
 *   the console: it must never guess an origin.
 *
 *   WORKCENTER_ORIGIN  scheme + host of the Workcenter shell, e.g.
 *                      https://example.com. It is the only accepted sender of a
 *                      `workcenter:mode` message.
 *   STYLESHEET_URL     either an absolute, Workcenter-served URL — the default,
 *                      e.g. https://example.com/sogo/workcenter-sogo.css — or a
 *                      root-relative path when the stylesheet is instead mounted
 *                      into SOGo's own web resources, e.g.
 *                      /SOGo/css/workcenter-sogo.css. Absolute is preferred (the
 *                      shell owns the palette and can restyle without redeploying
 *                      Mailcow); root-relative keeps working when the shell is
 *                      down. If the serving origin ever sends a CSP, its
 *                      `style-src` must include whichever origin this points at.
 * ------------------------------------------------------------------------- */

(function () {
  'use strict';

  /* Tokens: replaced at deployment. A real URL or path, not a placeholder,
   * means "configured" — see the header. */
  var WORKCENTER_ORIGIN = '__WORKCENTER_ORIGIN__';
  var STYLESHEET_URL = '__WORKCENTER_STYLESHEET_URL__';

  var COOKIE_NAME = 'wc_mode';
  var ATTRIBUTE = 'data-wc-mode';
  var LINK_ID = 'workcenter-sogo-stylesheet';
  var MODES = ['dark', 'light']; /* the only two values ever accepted */

  function configured(value) {
    if (typeof value !== 'string' || value.indexOf('__') === 0) {
      return false;
    }
    return value.indexOf('://') > 0 || value.charAt(0) === '/';
  }

  if (!configured(WORKCENTER_ORIGIN) || !configured(STYLESHEET_URL)) {
    /* Inert on purpose: without a real origin the message check below could not
     * be safe, and a guessed stylesheet URL is worse than no styling. */
    if (window.console && console.warn) {
      console.warn('[workcenter] SOGo appearance hook is not configured; no styling applied.');
    }
    return;
  }

  /* Only the two literals are honoured. Anything else — including anything that
   * looks like markup or a path — is ignored, so a stray cookie value cannot
   * change what is loaded. */
  function normalize(mode) {
    return MODES.indexOf(mode) === -1 ? null : mode;
  }

  function cookieMode() {
    var parts = String(document.cookie || '').split(';');
    for (var i = 0; i < parts.length; i += 1) {
      var pair = parts[i].trim().split('=');
      if (pair[0] === COOKIE_NAME) {
        return normalize(decodeURIComponent(pair.slice(1).join('=')));
      }
    }
    return null;
  }

  function apply(mode) {
    var value = normalize(mode);
    if (value) {
      document.documentElement.setAttribute(ATTRIBUTE, value);
    }
  }

  function linkStylesheet() {
    if (document.getElementById(LINK_ID)) {
      return;
    }
    var link = document.createElement('link');
    link.id = LINK_ID;
    link.rel = 'stylesheet';
    link.type = 'text/css';
    link.href = STYLESHEET_URL;
    /* If the Workcenter stylesheet is unreachable the pane keeps SOGo's own
     * appearance; nothing here depends on it loading. */
    (document.head || document.documentElement).appendChild(link);
  }

  /* The message contract the shell uses for every pane (design.md D-6.1): the
   * pane's own origin is the only accepted sender, and the payload is read for
   * exactly `type` and `mode`. */
  function onMessage(event) {
    if (event.origin !== WORKCENTER_ORIGIN || !event.data) {
      return;
    }
    if (event.data.type !== 'workcenter:mode') {
      return;
    }
    apply(event.data.mode);
  }

  /* First paint: attribute first, stylesheet second — the attribute is what the
   * stylesheet selects on, so a slow stylesheet must not delay the mode. */
  apply(cookieMode());
  linkStylesheet();
  window.addEventListener('message', onMessage, false);
})();
