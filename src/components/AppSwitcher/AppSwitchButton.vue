<template>
  <button
    type="button"
    class="wc-switch-button"
    :class="{ 'is-active': isActive, 'is-unavailable': !available }"
    :style="accentStyle"
    role="tab"
    :aria-selected="isActive ? 'true' : 'false'"
    :aria-current="isActive ? 'page' : undefined"
    :aria-controls="`wc-pane-${app.id}`"
    :id="`wc-tab-${app.id}`"
    :tabindex="isActive ? 0 : -1"
    :title="available ? label : unavailableTitle"
    :aria-label="collapsed ? label : undefined"
    @click="$emit('select', app.id)"
  >
    <AppMark :name="app.mark" :size="24" decorative />
    <span v-if="!collapsed" class="wc-switch-button__label">{{ label }}</span>
    <span class="wc-switch-button__underline" aria-hidden="true" />
  </button>
</template>

<script>
import AppMark from '@/components/AppMark.vue';
import { appUrl } from '@/utils/apps/urls';

/**
 * One application's button in the switcher.
 *
 * The mark is the button's visual identity; the label names it. When the rail is
 * collapsed the label is not rendered, so the button carries the application
 * name as its accessible name instead (design.md D-2I.6) — a 24px mark on its
 * own would otherwise be an unlabelled control.
 */
export default {
  name: 'AppSwitchButton',
  components: {
    AppMark,
  },
  props: {
    app: { type: Object, required: true },
    activeId: { type: String, default: '' },
    appConfig: { type: Object, default: () => ({}) },
    /* The rail is icon-only, so the label is not rendered. */
    collapsed: { type: Boolean, default: false },
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
  methods: {
    /* The switcher moves focus between the tabs itself (roving tabindex). */
    focusButton() {
      this.$el.focus();
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
  /* The height is a floor, not a cap: a mark, the gap and a label need more
     room than the token alone reserves, and a clipped label is worse than a
     slightly taller button. */
  height: auto;
  min-height: var(--switcher-button-height);
  padding: 0.35rem 0.15rem;
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

.wc-switch-button__label {
  font-size: 0.7rem;
  /* An explicit line box, so descenders are never cut by the button's edge. */
  line-height: 1.2;
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
