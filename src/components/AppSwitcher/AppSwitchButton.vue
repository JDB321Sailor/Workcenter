<template>
  <button
    type="button"
    class="wc-switch-button"
    :class="{ 'is-active': isActive, 'is-unavailable': !available }"
    :style="accentStyle"
    role="tab"
    :aria-selected="isActive ? 'true' : 'false'"
    :aria-controls="`wc-pane-${app.id}`"
    :id="`wc-tab-${app.id}`"
    :tabindex="isActive ? 0 : -1"
    :title="available ? label : unavailableTitle"
    @click="$emit('select', app.id)"
  >
    <i :class="app.icon" class="wc-switch-button__icon" aria-hidden="true" />
    <span class="wc-switch-button__label">{{ label }}</span>
    <span class="wc-switch-button__underline" aria-hidden="true" />
  </button>
</template>

<script>
import { appUrl } from '@/utils/apps/urls';

export default {
  name: 'AppSwitchButton',
  props: {
    app: { type: Object, required: true },
    activeId: { type: String, default: '' },
    appConfig: { type: Object, default: () => ({}) },
  },
  emits: ['select'],
  computed: {
    isActive() {
      return this.activeId === this.app.id;
    },
    /* An application is available when it has a usable configured address. */
    available() {
      return appUrl(this.appConfig, this.app.id) !== '';
    },
    label() {
      return this.app.name;
    },
    unavailableTitle() {
      return this.$t('switcher.unavailable', { app: this.app.name });
    },
    accentStyle() {
      return { '--wc-app-accent': `var(${this.app.accentVar})` };
    },
  },
};
</script>

<style lang="scss" scoped>
@import '@/styles/media-queries.scss';

.wc-switch-button {
  position: relative;
  flex: 1 1 0;
  min-width: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.15rem;
  height: var(--switcher-button-height);
  padding: 0.25rem 0.15rem;
  border: none;
  border-radius: var(--wc-radius);
  background: transparent;
  color: var(--side-bar-color);
  font: inherit;
  cursor: pointer;
  opacity: 0.7;
  transition: background 120ms ease, opacity 120ms ease;

  &:hover:not(.is-unavailable) {
    background: var(--side-bar-background-lighter);
    opacity: 1;
  }

  &:focus-visible {
    outline: 2px solid var(--wc-focus-ring);
    outline-offset: 2px;
  }

  &.is-active {
    color: var(--wc-app-accent);
    opacity: 1;
  }

  &.is-unavailable {
    opacity: 0.4;
    cursor: not-allowed;
  }
}

.wc-switch-button__icon {
  font-size: 1.05rem;
  line-height: 1;
}

.wc-switch-button__label {
  font-size: 0.7rem;
  letter-spacing: 0.02em;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

/* The underline is the active affordance, so it is never the only signal:
 * the icon and label also take the accent colour. */
.wc-switch-button__underline {
  position: absolute;
  left: 18%;
  right: 18%;
  bottom: 0;
  height: 3px;
  border-radius: 3px 3px 0 0;
  background: transparent;
}

.wc-switch-button.is-active .wc-switch-button__underline {
  background: var(--wc-app-accent);
}

@include phone {
  .wc-switch-button__label {
    display: none;
  }
}
</style>
