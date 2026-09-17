/**
 * Shared behaviour for the Workcenter view: config loading, icon library
 * injection, and the route-to-sub-config resolution the store depends on.
 */

import Defaults, { localStorageKeys, iconCdns } from '@/utils/config/defaults';
import Keys from '@/utils/StoreMutations';
import { resolveRouteIntent, PAGE_STATUS } from '@/utils/config/ConfigHelpers';

const HomeMixin = {
  computed: {
    sections() {
      return this.$store.getters.sections;
    },
    appConfig() {
      return this.$store.getters.appConfig;
    },
    pageInfo() {
      return this.$store.getters.pageInfo;
    },
    pageId() {
      return this.$store.state.currentConfigInfo?.confId || 'home';
    },
    /* True when the server returned a stripped bootstrap config (e.g. expired token) */
    isBootstrap() {
      return this.$store.state.rootConfig?._bootstrap?.authenticated === false;
    },
  },
  watch: {
    async $route() {
      this.loadUpConfig();
    },
  },
  async created() {
    this.loadUpConfig();
  },
  methods: {
    /* When page loaded / sub-page changed, initiate config fetch.
     * For ROOT / LEGACY_SECTION intent the store loads the root config
     * for KNOWN the store loads the matching sub-config
     * for UNKNOWN the store triggers the critical error modal */
    async loadUpConfig() {
      const subPage = this.determineConfigFile();
      const current = this.$store.state.currentConfigInfo?.confId || null;
      if ((subPage || null) === current) return; // Already on this config, no reload
      await this.$store.dispatch(Keys.INITIALIZE_CONFIG, subPage);
    },
    /* Resolve which sub-config the current route targets.
     * Returns a page id from makePageName, or null for the root config */
    determineConfigFile() {
      const { status, pageId } = resolveRouteIntent(this.$route, this.$store);
      if (status === PAGE_STATUS.ROOT || status === PAGE_STATUS.LEGACY_SECTION) return null;
      return pageId; // KNOWN -> load sub-config; UNKNOWN -> store raises critical error
    },
    /* Checks if any sections or items use icons from a given CDN */
    checkIfIconLibraryNeeded(prefix) {
      if (!this.sections) return false;
      let isNeeded = false; // Will be set to true if prefix found in icon name
      this.sections.forEach((section) => {
        if (section && section.icon && section.icon.includes(prefix)) isNeeded = true;
        if (section && section.items) {
          section.items.forEach((item) => {
            if (item.icon && item.icon.includes(prefix)) isNeeded = true;
          });
        }
      });
      return isNeeded;
    },
    /* Checks if any of the icons are Font Awesome glyphs */
    checkIfFontAwesomeNeeded() {
      if (this.appConfig.enableFontAwesome === false) return false;
      if (this.appConfig.enableFontAwesome) return true;
      let isNeeded = this.checkIfIconLibraryNeeded('fa-');
      const currentTheme = localStorage[localStorageKeys.THEME]; // Some themes require FA
      if (['material', 'material-dark'].includes(currentTheme)) isNeeded = true;
      return isNeeded;
    },
    /* Injects font-awesome's script tag, only if needed */
    initiateFontAwesome() {
      if (this.checkIfFontAwesomeNeeded()) {
        const fontAwesomeScript = document.createElement('script');
        const faKey = this.appConfig.fontAwesomeKey || Defaults.fontAwesomeKey;
        fontAwesomeScript.setAttribute('src', `${iconCdns.fa}/${faKey}.js`);
        document.head.appendChild(fontAwesomeScript);
      }
    },
    /* Checks if any of the icons are Material Design Icons */
    checkIfMdiNeeded() {
      const userOverride = this.appConfig.enableMaterialDesignIcons;
      if (userOverride === false) return false;
      return userOverride || this.checkIfIconLibraryNeeded('mdi-');
    },
    /* Injects Material Design Icons, only if needed */
    initiateMaterialDesignIcons() {
      if (this.checkIfMdiNeeded()) {
        const mdiStylesheet = document.createElement('link');
        mdiStylesheet.setAttribute('rel', 'stylesheet');
        mdiStylesheet.setAttribute('href', iconCdns.mdi);
        document.head.appendChild(mdiStylesheet);
      }
    },
  },
};

export default HomeMixin;
