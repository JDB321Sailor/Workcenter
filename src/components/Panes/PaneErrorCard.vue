<template>
  <div class="wc-pane-error" role="alert">
    <i class="wc-pane-error__icon" :class="icon" aria-hidden="true" />

    <h2 class="wc-pane-error__title">{{ title }}</h2>
    <p class="wc-pane-error__body">{{ message }}</p>

    <ul v-if="detail" class="wc-pane-error__detail">
      <li v-for="(line, i) in detailLines" :key="i">{{ line }}</li>
    </ul>

    <div class="wc-pane-error__actions">
      <button type="button" class="wc-pane-error__button" @click="$emit('retry')">
        {{ $t('pane.retry') }}
      </button>
      <a
        v-if="url"
        class="wc-pane-error__button wc-pane-error__button--secondary"
        :href="url"
        target="_blank"
        rel="noopener noreferrer"
      >
        {{ $t('pane.open-new-tab') }}
      </a>
    </div>
  </div>
</template>

<script>
/**
 * The diagnostic card a pane shows instead of a blank frame.
 *
 * Design.md D-7 requires that a pane which cannot load says what failed and
 * offers Retry, and that Open in new tab is always available so a user is never
 * trapped by an application that misbehaves inside a frame.
 */
export default {
  name: 'PaneErrorCard',
  props: {
    /* unavailable | blocked | auth-error | timeout */
    reason: { type: String, default: 'unavailable' },
    appName: { type: String, default: '' },
    /* Extra lines: the failing check, or the header that needs changing. */
    detail: { type: String, default: '' },
    /* Where Open in new tab goes. */
    url: { type: String, default: '' },
  },
  emits: ['retry'],
  computed: {
    icon() {
      if (this.reason === 'auth-error') return 'fas fa-key';
      if (this.reason === 'blocked') return 'fas fa-shield-halved';
      if (this.reason === 'timeout') return 'fas fa-clock';
      return 'fas fa-plug-circle-xmark';
    },
    title() {
      return this.$t(`pane.reason.${this.reason}.title`, { app: this.appName });
    },
    message() {
      return this.$t(`pane.reason.${this.reason}.message`, { app: this.appName });
    },
    detailLines() {
      return this.detail ? this.detail.split('\n').filter(Boolean) : [];
    },
  },
};
</script>

<style lang="scss" scoped>
.wc-pane-error {
  position: absolute;
  inset: 0 0 0 var(--side-bar-width);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.6rem;
  padding: 2rem;
  text-align: center;
  background: var(--wc-surface);
  color: var(--wc-text);
}

.wc-pane-error__icon {
  font-size: 1.8rem;
  color: var(--wc-status-unhealthy);
}

.wc-pane-error__title {
  margin: 0;
  font-size: 1.1rem;
  color: var(--wc-text);
}

.wc-pane-error__body {
  margin: 0;
  max-width: 34rem;
  line-height: 1.5;
  opacity: 0.85;
}

.wc-pane-error__detail {
  margin: 0;
  padding: 0.6rem 0.9rem;
  list-style: none;
  max-width: 34rem;
  text-align: left;
  font-size: 0.8rem;
  background: var(--wc-surface-raised);
  border: 1px solid var(--wc-border);
  border-radius: var(--wc-radius);
}

.wc-pane-error__actions {
  display: flex;
  gap: 0.5rem;
  margin-top: 0.4rem;
}

.wc-pane-error__button {
  padding: 0.4rem 0.9rem;
  border: 1px solid var(--wc-focus-ring);
  border-radius: var(--wc-radius);
  background: var(--wc-focus-ring);
  color: var(--wc-surface);
  font: inherit;
  font-size: 0.85rem;
  text-decoration: none;
  cursor: pointer;

  &:focus-visible {
    outline: 2px solid var(--wc-focus-ring);
    outline-offset: 2px;
  }

  &--secondary {
    background: transparent;
    color: var(--wc-focus-ring);
  }
}
</style>
