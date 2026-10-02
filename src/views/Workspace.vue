<template>
  <div class="wc-workspace" :class="{ 'wc-workspace--collapsed': railCollapsed }">
    <!-- The rail: brand header, the application switcher with its status
         indicators, the sidebar filter, the active application's navigator, and
         the user menu. Design.md section 2.1. -->
    <nav class="wc-rail" :aria-label="$t('shell.rail-label')">
      <BrandHeader
        :collapsed="railCollapsed"
        :lastAppName="lastAppName"
        @home="goToLastApp"
        @toggle="toggleRail"
      />
      <AppSwitcher
        :activeId="activeId"
        :appConfig="appConfig"
        :collapsed="railCollapsed"
        @select="goToApp"
        @unavailable="onUnavailable"
        @focus-pane="onFocusPane"
      />
      <SidebarSearch
        ref="sidebarSearch"
        v-model="sidebarQuery"
        :appId="activeId"
        :appName="activeAppName"
        :collapsed="railCollapsed"
        @expand="expandRailForSearch"
      />
      <AppSidebar
        :activeId="activeId"
        :appConfig="appConfig"
        :query="sidebarQuery"
        @navigate="onNavigate"
      />

      <UserMenu
        :collapsed="railCollapsed"
        :appConfig="appConfig"
        @preferences-applied="onPreferencesApplied"
      />
    </nav>

    <!-- The content surface. Every pane stays mounted, so switching is a
         visibility change rather than a reload. -->
    <PaneHost ref="paneHost" :activeId="activeId" :urls="urls" />
  </div>
</template>

<script>
import HomeMixin from '@/mixins/HomeMixin';
import BrandHeader from '@/components/Rail/BrandHeader.vue';
import SidebarSearch from '@/components/Rail/SidebarSearch.vue';
import AppSwitcher from '@/components/AppSwitcher/AppSwitcher.vue';
import AppSidebar from '@/components/AppSidebar/AppSidebar.vue';
import PaneHost from '@/components/Panes/PaneHost.vue';
import UserMenu from '@/components/User/UserMenu.vue';
import { APP_LIST, getAppByRoute, getApp } from '@/utils/apps/registry';
import { appUrls } from '@/utils/apps/urls';
import HealthService from '@/utils/health/HealthService';
import ErrorHandler from '@/utils/logging/ErrorHandler';
import { localStorageKeys } from '@/utils/config/defaults';

/**
 * The rail's collapsed state, read before the first render so the rail never
 * flashes expanded for a user who collapsed it.
 */
const readStoredRailState = () => {
  try {
    return localStorage.getItem(localStorageKeys.COLLAPSE_STATE) === 'true';
  } catch {
    return false; // Storage unavailable: the rail simply starts expanded.
  }
};

/**
 * The Workcenter shell: one view, three applications.
 *
 * The rail carries the switcher; the sidebar body follows the active
 * application; the panes stay mounted behind it. Design.md section 2.
 */
export default {
  name: 'Workspace',
  mixins: [HomeMixin],
  components: {
    BrandHeader,
    SidebarSearch,
    AppSwitcher,
    AppSidebar,
    PaneHost,
    UserMenu,
  },
  data() {
    return {
      healthService: HealthService,
      /* The sidebar filter, owned here so it survives an application switch and
         so the search row and the sidebar body agree on one value. */
      sidebarQuery: '',
      railCollapsed: readStoredRailState(),
    };
  },
  computed: {
    appConfig() {
      return this.$store.getters.appConfig;
    },
    /* The configured address of each application. */
    urls() {
      return appUrls(this.appConfig);
    },
    /* The application whose pane the current route selects. */
    activeId() {
      const app = getAppByRoute(this.$route.name);
      return app ? app.id : APP_LIST[0].id;
    },
    activeAppName() {
      const app = getApp(this.activeId);
      return app ? app.name : '';
    },
    /* The application the rail's wordmark returns to. */
    lastAppName() {
      const app = getApp(this.lastAppId);
      return app ? app.name : this.activeAppName;
    },
    lastAppId() {
      return localStorage.getItem(localStorageKeys.LAST_USED) || this.activeId;
    },
  },
  watch: {
    activeId: {
      immediate: true,
      handler(next, previous) {
        /* Remember where the user was, so the wordmark can take them back. */
        localStorage.setItem(localStorageKeys.LAST_USED, next);
        /* A filter narrowed to one application makes no sense in another. */
        if (previous !== undefined && next !== previous) this.sidebarQuery = '';
      },
    },
  },
  mounted() {
    // Guarded icon injection from HomeMixin; never inject unconditionally.
    this.initiateFontAwesome();
    this.initiateMaterialDesignIcons();
    // Poll integration health for the status indicators.
    this.healthService.start();
  },
  beforeUnmount() {
    this.healthService.stop();
  },
  methods: {
    /* Switching application is a route change, so the pane is deep-linkable and
       a reload restores the same application. Design.md D-2. */
    goToApp(appId) {
      const app = getApp(appId);
      if (!app) return;
      if (this.$route.name !== app.routeName) {
        this.$router.push({ name: app.routeName });
        return;
      }
      // Re-activating the application already on screen is a no-op except that
      // it returns focus to the pane (design.md D-2.2).
      this.onFocusPane(appId);
    },
    /* The wordmark returns to the last-used application. */
    goToLastApp() {
      this.goToApp(this.lastAppId);
    },
    toggleRail() {
      this.setRailCollapsed(!this.railCollapsed);
    },
    setRailCollapsed(collapsed) {
      this.railCollapsed = collapsed;
      localStorage.setItem(localStorageKeys.COLLAPSE_STATE, String(collapsed));
    },
    /* Ctrl/Cmd+K on a collapsed rail expands it, then focuses the field. */
    expandRailForSearch() {
      this.setRailCollapsed(false);
      this.$nextTick(() => this.$refs.sidebarSearch?.focus());
    },
    /* A healthy status indicator focuses the pane it belongs to; it never
       changes which application is active (design.md D-2S). */
    onFocusPane(appId) {
      this.$refs.paneHost?.focusPane?.(appId);
    },
    /* The appearance switch has already repainted the shell and told the
       panes; the Files pane's reload, if any, is the bridge's business. */
    onPreferencesApplied(state) {
      if (state?.panes?.files === 'deferred') {
        ErrorHandler('[theme] the Files pane deferred its reload until the editor closes.');
      }
    },
    onNavigate({ url } = {}) {
      // A sidebar row points the active pane at the view it names.
      if (url) this.$refs.paneHost?.navigate?.(this.activeId, url);
    },
    onUnavailable(appId) {
      const app = getApp(appId);
      const name = app ? app.name : appId;
      ErrorHandler(`[shell] ${name} has no address configured.`);
      this.$toast.error(this.$t('switcher.unavailable', { app: name }));
    },
  },
};
</script>

<style lang="scss" scoped>
.wc-workspace {
  position: relative;
  display: flex;
  /* A definite height, not `min-height`. The pane is absolutely positioned at
     `height: calc(100% - var(--header-height))` against `PaneHost` (design.md
     D-L1, D-7), and a percentage height needs a definite containing block:
     `min-height: 100vh` left the workspace `height: auto`, so the pane host
     resolved to zero and every frame loaded into nothing. `100vh` here is the
     workspace's share of the viewport; the pane still subtracts
     `--header-height` itself, which is why that token stays honoured. */
  height: 100vh;
}

/* Collapsing the rail changes the layout token every region derives from, so
   the rail and the pane surface move together with no component edits. */
.wc-workspace--collapsed {
  --side-bar-width: var(--side-bar-width-collapsed);
}

.wc-rail {
  position: fixed;
  top: 0;
  left: 0;
  bottom: 0;
  z-index: 12;
  display: flex;
  flex-direction: column;
  width: var(--side-bar-width);
  background: var(--side-bar-background);
  color: var(--side-bar-color);
  overflow: hidden;
  transition: width var(--rail-transition);
}
</style>
