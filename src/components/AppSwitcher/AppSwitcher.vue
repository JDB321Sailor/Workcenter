<template>
  <div class="wc-switcher">
    <!-- The three applications. Each button swaps the sidebar and the pane. -->
    <div
      class="wc-switcher__buttons"
      :class="{ 'is-collapsed': collapsed }"
      role="tablist"
      :aria-label="$t('switcher.label')"
      @keydown="onTablistKeydown"
    >
      <AppSwitchButton
        v-for="app in apps"
        :key="app.id"
        ref="buttons"
        :app="app"
        :activeId="activeId"
        :appConfig="appConfig"
        :collapsed="collapsed"
        @select="select"
      />
    </div>

    <!--
      One status indicator per button, directly beneath it, with a STATUS label
      so the row's purpose is known. The indicators are part of the switcher:
      there is no separate status region. See design.md D-2S.
    -->
    <div
      class="wc-switcher__status"
      role="group"
      :aria-label="$t('status.label')"
      aria-live="polite"
    >
      <div class="wc-switcher__status-row">
        <StatusIndicator
          v-for="app in apps"
          :key="app.id"
          :app="app"
          :state="healthFor(app.id).state"
          :check="healthFor(app.id).check"
          :endpoint="healthFor(app.id).endpoint"
          :since="healthFor(app.id).since"
          @activate="activateIndicator"
        />
      </div>
      <span v-if="!collapsed" class="wc-switcher__status-label" aria-hidden="true">{{ $t('status.label') }}</span>
    </div>
  </div>
</template>

<script>
import AppSwitchButton from '@/components/AppSwitcher/AppSwitchButton.vue';
import StatusIndicator from '@/components/AppSwitcher/StatusIndicator.vue';
import { APP_LIST } from '@/utils/apps/registry';
import { appUrl } from '@/utils/apps/urls';
import HealthService, { HEALTH } from '@/utils/health/HealthService';

export default {
  name: 'AppSwitcher',
  props: {
    activeId: { type: String, default: '' },
    appConfig: { type: Object, default: () => ({}) },
    /* The rail is icon-only: labels are hidden and the STATUS label is dropped. */
    collapsed: { type: Boolean, default: false },
  },
  emits: ['select', 'unavailable', 'focus-pane'],
  components: {
    AppSwitchButton,
    StatusIndicator,
  },
  data() {
    return {
      apps: APP_LIST,
      /* Kept in data so the indicators re-render when the service updates. */
      health: HealthService.state,
      healthService: HealthService,
      /* The keyboard's position in the tablist. It follows the active
         application and moves ahead of it on the arrow keys, so a fast double
         press walks the tabs rather than landing on the same one twice. */
      focusIndex: 0,
    };
  },
  watch: {
    activeId: {
      immediate: true,
      handler(appId) {
        const index = this.apps.findIndex((app) => app.id === appId);
        if (index !== -1) this.focusIndex = index;
      },
    },
  },
  mounted() {
    window.addEventListener('keydown', this.onGlobalKeydown);
  },
  beforeUnmount() {
    window.removeEventListener('keydown', this.onGlobalKeydown);
  },
  methods: {
    healthFor(appId) {
      return this.healthService.forApp(appId);
    },
    /* Alt+1/2/3 reaches the three applications from anywhere in the shell
       (design.md D-2, U-12). Keys pressed inside a pane's iframe belong to that
       application and cannot be seen here. */
    onGlobalKeydown(event) {
      if (!event.altKey || event.ctrlKey || event.metaKey) return;
      const index = ['1', '2', '3'].indexOf(event.key);
      if (index === -1 || !this.apps[index]) return;
      event.preventDefault();
      this.select(this.apps[index].id);
    },
    /* Arrow keys traverse the tablist and activate as they move, which is the
       pattern the tab role promises. */
    onTablistKeydown(event) {
      const keys = ['ArrowLeft', 'ArrowRight', 'Home', 'End'];
      if (!keys.includes(event.key)) return;
      const last = this.apps.length - 1;
      let next = this.focusIndex;
      if (event.key === 'ArrowLeft') next = this.focusIndex <= 0 ? last : this.focusIndex - 1;
      if (event.key === 'ArrowRight') next = this.focusIndex >= last ? 0 : this.focusIndex + 1;
      if (event.key === 'Home') next = 0;
      if (event.key === 'End') next = last;
      const app = this.apps[next];
      if (!app) return;
      event.preventDefault();
      this.focusIndex = next;
      this.$refs.buttons?.[next]?.focusButton?.();
      this.select(app.id);
    },
    /* Selecting an application that has no address tells the shell to explain. */
    select(appId) {
      if (appUrl(this.appConfig, appId) === '') {
        this.$emit('unavailable', appId);
        return;
      }
      this.$emit('select', appId);
    },
    /* A healthy indicator focuses the pane it belongs to — and never changes
       which application is active. A non-healthy indicator opens that
       application, so its diagnostic card is what the user sees. Design.md
       D-2S. */
    activateIndicator(appId) {
      const { state } = this.healthFor(appId);
      if (state === HEALTH.HEALTHY) {
        if (appId === this.activeId) this.$emit('focus-pane', appId);
        return;
      }
      this.select(appId);
    },
  },
};
</script>

<style lang="scss" scoped>
@import '@/styles/media-queries.scss';

.wc-switcher {
  flex: 0 0 auto;
  min-height: var(--switcher-height);
  padding: 0.4rem 0.4rem 0.25rem;
  border-bottom: 1px solid var(--wc-border);
}

.wc-switcher__buttons {
  display: flex;
  align-items: stretch;
  gap: 0.25rem;
}

/* Collapsed rail: the three applications stack, so each mark keeps its own row
   instead of three 24px marks competing for 3.5rem of width (design.md D-2). */
.wc-switcher__buttons.is-collapsed {
  flex-direction: column;
  gap: 0.15rem;
}

.wc-switcher__buttons.is-collapsed :deep(.wc-switch-button) {
  flex: 0 0 auto;
  width: 100%;
}

.wc-switcher__status {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.05rem;
  margin-top: 0.15rem;
}

.wc-switcher__status-row {
  display: flex;
  align-items: center;
  width: 100%;
}

.wc-switcher__status-label {
  font-size: 0.625rem;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--wc-text-muted);
  opacity: 0.6;
}

/* Collapsed rail: the buttons become an icon stack and the label is dropped,
   but every indicator stays beneath its own button. */
@include phone {
  .wc-switcher__status-label {
    display: none;
  }
}
</style>
