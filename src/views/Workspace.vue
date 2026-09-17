<template>
  <div class="wc-workspace">
    <!-- The rail: the application switcher with its status indicators, then the
         active application's own navigator. -->
    <nav class="wc-rail" :aria-label="$t('shell.rail-label')">
      <AppSwitcher
        :activeId="activeId"
        :appConfig="appConfig"
        @select="goToApp"
        @unavailable="onUnavailable"
      />
      <AppSidebar :activeId="activeId" :appConfig="appConfig" @navigate="onNavigate" />
    </nav>

    <!-- The content surface. Every pane stays mounted, so switching is a
         visibility change rather than a reload. -->
    <PaneHost :activeId="activeId" :urls="urls" />
  </div>
</template>

<script>
import HomeMixin from '@/mixins/HomeMixin';
import AppSwitcher from '@/components/AppSwitcher/AppSwitcher.vue';
import AppSidebar from '@/components/AppSidebar/AppSidebar.vue';
import PaneHost from '@/components/Panes/PaneHost.vue';
import { APP_LIST, getAppByRoute, getApp } from '@/utils/apps/registry';
import { appUrls } from '@/utils/apps/urls';
import HealthService from '@/utils/health/HealthService';
import ErrorHandler from '@/utils/logging/ErrorHandler';

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
    AppSwitcher,
    AppSidebar,
    PaneHost,
  },
  data() {
    return {
      healthService: HealthService,
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
      if (this.$route.name !== app.routeName) this.$router.push({ name: app.routeName });
    },
    onNavigate() {
      // A sidebar row opened in a new tab; nothing to do in the shell yet.
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
  min-height: 100vh;
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
}
</style>
