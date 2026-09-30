<template>
  <button
    type="button"
    class="wc-status-indicator"
    :class="`is-${state}`"
    :aria-label="accessibleName"
    :title="tooltip"
    @click="$emit('activate', app.id)"
  >
    <span class="wc-status-indicator__dot" aria-hidden="true" />
  </button>
</template>

<script>
import { HEALTH } from '@/utils/health/HealthService';

export default {
  name: 'StatusIndicator',
  props: {
    app: { type: Object, required: true },
    /* One of HEALTH: healthy, degraded, unhealthy, unknown. */
    state: { type: String, default: HEALTH.UNKNOWN },
    /* The check that produced the state, surfaced in the tooltip. */
    check: { type: String, default: '' },
    /* The failing endpoint, shown only when the state is not healthy. */
    endpoint: { type: String, default: '' },
    /* ISO timestamp of the last check that produced this state. */
    since: { type: String, default: '' },
  },
  emits: ['activate'],
  computed: {
    /* The state is in the accessible name, never colour alone. */
    accessibleName() {
      return this.$t('status.indicator-label', {
        app: this.app.name,
        state: this.$t(`status.state.${this.state}`),
      });
    },
    /* Service name, the check, when it last ran, and — when the state is not
       healthy — the endpoint that failed. Design.md D-2S. */
    tooltip() {
      const lines = [`${this.app.name}: ${this.$t(`status.state.${this.state}`)}`];
      if (this.check) lines.push(this.$t('status.tooltip.check', { check: this.check }));
      if (this.endpoint && this.state !== HEALTH.HEALTHY) {
        lines.push(this.$t('status.tooltip.endpoint', { endpoint: this.endpoint }));
      }
      lines.push(this.since
        ? this.$t('status.tooltip.last-checked', { time: this.lastCheckedLabel })
        : this.$t('status.tooltip.never-checked'));
      return lines.join('\n');
    },
    /* Formatted with the active locale, never a fixed format (design.md D-I4). */
    lastCheckedLabel() {
      try {
        return new Intl.DateTimeFormat(this.$i18n.locale, {
          dateStyle: 'short',
          timeStyle: 'medium',
        }).format(new Date(this.since));
      } catch {
        return this.since;
      }
    },
  },
};
</script>

<style lang="scss" scoped>
.wc-status-indicator {
  flex: 1 1 0;
  display: flex;
  align-items: center;
  justify-content: center;
  height: 1rem;
  padding: 0;
  border: none;
  background: transparent;
  cursor: pointer;

  &:focus-visible {
    outline: 2px solid var(--wc-focus-ring);
    outline-offset: 1px;
    border-radius: 50%;
  }
}

.wc-status-indicator__dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--wc-status-unknown);
  transition: background 200ms ease;
}

.wc-status-indicator.is-healthy .wc-status-indicator__dot {
  background: var(--wc-status-healthy);
}

.wc-status-indicator.is-degraded .wc-status-indicator__dot {
  background: var(--wc-status-degraded);
}

.wc-status-indicator.is-unhealthy .wc-status-indicator__dot {
  background: var(--wc-status-unhealthy);
}

.wc-status-indicator.is-unknown .wc-status-indicator__dot {
  background: var(--wc-status-unknown);
}
</style>
