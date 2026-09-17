/**
 * Shared behaviour for the three sidebar surfaces.
 *
 * Each application supplies its own groups of rows; this mixin resolves the
 * application's configured address, builds the deep link for a row, and tracks
 * which row is selected. Keeping it here means the three surfaces differ only
 * in their data, so they cannot drift apart visually. Design.md D-4.
 */

import { deepLink, appUrl } from '@/utils/apps/urls';
import ErrorHandler from '@/utils/logging/ErrorHandler';

export default {
  props: {
    app: { type: Object, required: true },
    appConfig: { type: Object, default: () => ({}) },
  },
  data() {
    return {
      /* The row currently selected, by id. */
      activeItemId: '',
    };
  },
  computed: {
    /** The application's address, or an empty string when it is not set. */
    baseUrl() {
      return appUrl(this.appConfig, this.app.id);
    },
    /** True when the application has no usable address, so the sidebar explains. */
    isUnconfigured() {
      return this.baseUrl === '';
    },
    /** The groups this surface renders. Supplied by the component. */
    groups() {
      return this.sidebarGroups || [];
    },
  },
  methods: {
    /** The absolute URL for a row, or an empty string. */
    urlFor(item) {
      if (!item || !item.path) return this.baseUrl;
      return deepLink(this.appConfig, this.app.id, item.path);
    },
    /**
     * Open a row.
     *
     * A sidebar row navigates the pane. Until the panes are driven by their
     * applications' APIs (roadmap Phase 6), a row opens the application at the
     * right place in a new tab, which is the honest behaviour: the shell is not
     * yet able to scroll the embedded application to an arbitrary location.
     */
    select(item) {
      if (!item) return;
      this.activeItemId = item.id || '';
      const url = this.urlFor(item);
      if (!url) return;
      this.$emit('navigate', { item, url });
      window.open(url, '_blank', 'noopener,noreferrer');
    },
    /** Report a problem without breaking the shell. */
    warn(message) {
      ErrorHandler(`[sidebar:${this.app.id}] ${message}`);
    },
  },
};
