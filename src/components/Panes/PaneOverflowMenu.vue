<template>
  <div class="wc-pane-menu" @keydown.esc="close">
    <button
      ref="trigger"
      type="button"
      class="wc-pane-menu__trigger"
      :aria-label="$t('pane.overflow.label')"
      :title="$t('pane.overflow.label')"
      aria-haspopup="menu"
      :aria-expanded="open ? 'true' : 'false'"
      @click="toggle"
      @keydown.down.prevent="openMenu"
    >
      <i class="fas fa-ellipsis" aria-hidden="true" />
    </button>

    <div
      v-if="open"
      class="wc-pane-menu__list"
      role="menu"
      :aria-label="$t('pane.overflow.label')"
      @keydown="onMenuKeydown"
    >
      <button type="button" class="wc-pane-menu__item" role="menuitem" @click="run('reload')">
        <i class="fas fa-rotate-right" aria-hidden="true" />
        {{ $t('pane.overflow.reload') }}
      </button>

      <a
        class="wc-pane-menu__item"
        role="menuitem"
        :href="url"
        target="_blank"
        rel="noopener noreferrer"
      >
        <i class="fas fa-arrow-up-right-from-square" aria-hidden="true" />
        {{ $t('pane.overflow.open') }}
      </a>

      <button type="button" class="wc-pane-menu__item" role="menuitem" @click="run('copy')">
        <i class="fas fa-link" aria-hidden="true" />
        {{ $t('pane.overflow.copy') }}
      </button>

      <button
        v-if="isAdmin"
        type="button"
        class="wc-pane-menu__item"
        role="menuitem"
        @click="run('health')"
      >
        <i class="fas fa-stethoscope" aria-hidden="true" />
        {{ $t('pane.overflow.health') }}
      </button>
    </div>
  </div>
</template>

<script>
import { isUserAdmin } from '@/utils/auth/Auth';
import ErrorHandler from '@/utils/logging/ErrorHandler';

/**
 * The pane's overflow menu: the escape hatch that means a user is never trapped
 * by an application that misbehaves inside a frame. Design.md D-7.
 *
 * The menu is a disclosure, not a route: it closes on Escape, returns focus to
 * its trigger, and every item is reachable by keyboard.
 */
export default {
  name: 'PaneOverflowMenu',
  props: {
    /* The pane's address, used by Open in new tab and Copy link. */
    url: { type: String, default: '' },
    /* The application's name, for the copy confirmation. */
    appName: { type: String, default: '' },
  },
  emits: ['reload', 'show-health'],
  data() {
    return {
      open: false,
    };
  },
  computed: {
    isAdmin() {
      return isUserAdmin();
    },
  },
  beforeUnmount() {
    document.removeEventListener('click', this.onDocumentClick);
  },
  methods: {
    toggle() {
      if (this.open) this.close();
      else this.openMenu();
    },
    openMenu() {
      this.open = true;
      // A click anywhere else closes the menu, as a popover should.
      setTimeout(() => document.addEventListener('click', this.onDocumentClick), 0);
    },
    close() {
      if (!this.open) return;
      this.open = false;
      document.removeEventListener('click', this.onDocumentClick);
      this.$refs.trigger?.focus();
    },
    onDocumentClick(event) {
      if (!this.$el.contains(event.target)) this.close();
    },
    /* Up and Down traverse the menu items; Escape closes and restores focus. */
    onMenuKeydown(event) {
      const items = Array.from(this.$el.querySelectorAll('.wc-pane-menu__item'));
      if (!items.length) return;
      const index = items.indexOf(document.activeElement);
      if (event.key === 'ArrowDown') {
        event.preventDefault();
        items[(index + 1) % items.length].focus();
      }
      if (event.key === 'ArrowUp') {
        event.preventDefault();
        items[(index - 1 + items.length) % items.length].focus();
      }
      if (event.key === 'Home') {
        event.preventDefault();
        items[0].focus();
      }
      if (event.key === 'End') {
        event.preventDefault();
        items[items.length - 1].focus();
      }
    },
    async run(action) {
      if (action === 'reload') {
        this.close();
        this.$emit('reload');
        return;
      }
      if (action === 'health') {
        this.close();
        this.$emit('show-health');
        return;
      }
      if (action === 'copy') {
        await this.copyLink();
      }
    },
    /* Copying is a courtesy: a refused clipboard is reported, never silent. */
    async copyLink() {
      try {
        await navigator.clipboard.writeText(this.url);
        this.$toast.success(this.$t('pane.overflow.copied'));
      } catch (e) {
        ErrorHandler(`[pane] could not copy the ${this.appName} link`, e);
        this.$toast.error(this.$t('pane.overflow.copy-failed'));
      }
      this.close();
    },
  },
};
</script>

<style lang="scss" scoped>
.wc-pane-menu {
  position: absolute;
  top: 0.5rem;
  right: 0.5rem;
  z-index: 5;
}

.wc-pane-menu__trigger {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 1.9rem;
  height: 1.9rem;
  padding: 0;
  border: 1px solid var(--wc-border);
  border-radius: var(--wc-radius);
  background: var(--wc-surface-raised);
  color: var(--wc-text-muted);
  cursor: pointer;
  opacity: 0;
  transition: opacity 120ms ease;

  &:focus-visible {
    opacity: 1;
    outline: 2px solid var(--wc-focus-ring);
    outline-offset: 2px;
  }
}

/* Revealed on hover or keyboard focus, but never removed from the tab order. */
:global(.wc-pane:hover) .wc-pane-menu__trigger,
.wc-pane-menu__trigger:focus {
  opacity: 1;
}

.wc-pane-menu__list {
  position: absolute;
  top: 2.2rem;
  right: 0;
  min-width: 13rem;
  padding: 0.25rem;
  border: 1px solid var(--wc-border);
  border-radius: var(--wc-radius);
  background: var(--wc-surface-raised);
  box-shadow: var(--wc-shadow-popover);
}

.wc-pane-menu__item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  width: 100%;
  padding: 0.4rem 0.5rem;
  border: none;
  border-radius: calc(var(--wc-radius) / 2);
  background: transparent;
  color: var(--wc-text);
  font: inherit;
  font-size: 0.8rem;
  text-align: left;
  text-decoration: none;
  cursor: pointer;

  &:hover {
    background: var(--side-bar-background-lighter);
  }

  &:focus-visible {
    outline: 2px solid var(--wc-focus-ring);
    outline-offset: -2px;
  }
}
</style>
