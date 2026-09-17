<template>
  <div class="wc-switcher">
    <!-- The three applications. Each button swaps the sidebar and the pane. -->
    <div class="wc-switcher__buttons" role="tablist" :aria-label="$t('switcher.label')">
      <AppSwitchButton
        v-for="app in apps"
        :key="app.id"
        :app="app"
        :activeId="activeId"
        :appConfig="appConfig"
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
          @activate="activateIndicator"
        />
      </div>
      <span class="wc-switcher__status-label" aria-hidden="true">{{ $t('status.label') }}</span>
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
  },
  emits: ['select', 'unavailable'],
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
    };
  },
  methods: {
    healthFor(appId) {
      return this.healthService.forApp(appId);
    },
    /* Selecting an application that has no address tells the shell to explain. */
    select(appId) {
      if (appUrl(this.appConfig, appId) === '') {
        this.$emit('unavailable', appId);
        return;
      }
      this.$emit('select', appId);
    },
    /* A healthy indicator focuses the pane; an unhealthy one selects the
       application so its diagnostic card is visible. Design.md D-2S. */
    activateIndicator(appId) {
      const { state } = this.healthFor(appId);
      if (state === HEALTH.UNHEALTHY || state === HEALTH.DEGRADED) {
        this.select(appId);
        return;
      }
      this.$emit('select', appId);
    },
  },
};
</script>

<style lang="scss" scoped>
@import '@/styles/media-queries.scss';

.wc-switcher {
  flex: 0 0 auto;
  padding: 0.4rem 0.4rem 0.25rem;
  border-bottom: 1px solid var(--wc-border);
}

.wc-switcher__buttons {
  display: flex;
  align-items: stretch;
  gap: 0.25rem;
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
