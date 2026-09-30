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
    /* The shell's sidebar filter, from SidebarSearch. Design.md D-3. */
    query: { type: String, default: '' },
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
    /** The filter, normalised for a case-insensitive comparison. */
    normalizedQuery() {
      return this.query.trim().toLowerCase();
    },
    /**
     * The groups this surface renders, each row carrying the URL it points at
     * and narrowed to the rows that match the filter. A group with no matching
     * row is dropped, so the body never shows an empty heading.
     */
    groups() {
      const all = this.sidebarGroups || [];
      const decorated = all.map((group) => ({
        ...group,
        items: (group.items || [])
          .map((item) => ({ ...item, url: this.urlFor(item) }))
          .filter((item) => this.matchesQuery(item)),
      }));
      return decorated.filter((group) => group.items.length > 0);
    },
    /** True when a filter is applied and nothing matches it. */
    hasNoMatches() {
      return this.normalizedQuery !== '' && this.groups.length === 0;
    },
  },
  methods: {
    /** True when a row's visible label contains the filter. */
    matchesQuery(item) {
      const label = item.labelKey ? this.$t(item.labelKey) : (item.label || '');
      return String(label).toLowerCase().includes(this.normalizedQuery);
    },
    /** The absolute URL for a row, or an empty string. */
    urlFor(item) {
      if (!item || !item.path) return this.baseUrl;
      return deepLink(this.appConfig, this.app.id, item.path);
    },
    /**
     * Open a row.
     *
     * A row navigates the pane it belongs to, at the path the row names: the
     * shell is honest about what it can address, and every path here was read
     * from the application's own router (see each surface). Rows with no
     * verified path are not rendered at all rather than pointing somewhere
     * arbitrary.
     */
    select(item) {
      if (!item) return;
      this.activeItemId = item.id || '';
      const url = item.url || this.urlFor(item);
      if (!url) return;
      this.$emit('navigate', { item, url });
    },
    /** Report a problem without breaking the shell. */
    warn(message) {
      ErrorHandler(`[sidebar:${this.app.id}] ${message}`);
    },
  },
};
