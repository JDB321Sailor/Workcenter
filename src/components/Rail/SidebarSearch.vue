<template>
  <div class="wc-search" role="search">
    <!-- Collapsed rail: the field has no room, so the row becomes the button
         that brings it back. -->
    <button
      v-if="collapsed"
      type="button"
      class="wc-search__collapsed"
      :aria-label="$t('sidebar.search.label', { app: appName })"
      :title="$t('sidebar.search.label', { app: appName })"
      @click="$emit('expand')"
    >
      <i class="fas fa-magnifying-glass" aria-hidden="true" />
    </button>

    <template v-else>
      <i class="fas fa-magnifying-glass wc-search__icon" aria-hidden="true" />
      <input
        ref="input"
        v-model="draft"
        type="search"
        class="wc-search__input"
        :placeholder="placeholder"
        :aria-label="$t('sidebar.search.label', { app: appName })"
        autocomplete="off"
        @keydown.esc.prevent="clear"
      >
      <button
        v-if="draft"
        type="button"
        class="wc-search__clear"
        :aria-label="$t('sidebar.search.clear')"
        :title="$t('sidebar.search.clear')"
        @click="clear"
      >
        <i class="fas fa-xmark" aria-hidden="true" />
      </button>
    </template>
  </div>
</template>

<script>
/**
 * The rail's filter row. It narrows the active application's sidebar body to the
 * rows whose labels match; it never searches inside an embedded application.
 * Design.md D-3.
 *
 * The draft value is debounced before it reaches the sidebar, so typing does not
 * re-filter the surfaces on every keystroke.
 */
const DEBOUNCE_MS = 150;

export default {
  name: 'SidebarSearch',
  props: {
    /* The active application's id, which selects the placeholder. */
    appId: { type: String, required: true },
    /* The active application's name, for the accessible label. */
    appName: { type: String, default: '' },
    /* The applied filter, owned by the shell. */
    modelValue: { type: String, default: '' },
    collapsed: { type: Boolean, default: false },
  },
  emits: ['update:modelValue', 'expand'],
  data() {
    return {
      draft: this.modelValue,
      debounceTimer: null,
    };
  },
  computed: {
    placeholder() {
      return this.$t(`sidebar.search.placeholder-${this.appId}`);
    },
  },
  watch: {
    /* Keep in step when the shell clears or replaces the filter. */
    modelValue(next) {
      if (next !== this.draft) this.draft = next;
    },
    /* Apply the filter once typing pauses. */
    draft(next) {
      this.clearTimer();
      this.debounceTimer = setTimeout(() => {
        if (next !== this.modelValue) this.$emit('update:modelValue', next);
      }, DEBOUNCE_MS);
    },
  },
  mounted() {
    window.addEventListener('keydown', this.onShortcut);
  },
  beforeUnmount() {
    window.removeEventListener('keydown', this.onShortcut);
    this.clearTimer();
  },
  methods: {
    clearTimer() {
      if (this.debounceTimer) clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    },
    /* Ctrl/Cmd+K reaches the field from anywhere in the shell. */
    onShortcut(event) {
      if (!(event.ctrlKey || event.metaKey) || event.key.toLowerCase() !== 'k') return;
      event.preventDefault();
      if (this.collapsed) this.$emit('expand');
      else this.focus();
    },
    /* Called by the shell after it has expanded the rail for the shortcut. */
    focus() {
      this.$refs.input?.focus();
    },
    /* Escape restores the unfiltered list and returns focus to the field. */
    clear() {
      this.clearTimer();
      this.draft = '';
      this.$emit('update:modelValue', '');
      this.focus();
    },
  },
};
</script>

<style lang="scss" scoped>
.wc-search {
  position: relative;
  flex: 0 0 auto;
  display: flex;
  align-items: center;
  height: var(--sidebar-search-height);
  padding: 0 0.4rem;
  border-bottom: 1px solid var(--wc-border);
}

.wc-search__icon {
  position: absolute;
  left: 0.85rem;
  font-size: 0.72rem;
  color: var(--wc-text-muted);
  pointer-events: none;
}

.wc-search__input {
  width: 100%;
  height: 1.75rem;
  padding: 0 1.75rem 0 1.9rem;
  border: 1px solid var(--wc-border);
  border-radius: var(--wc-radius);
  background: var(--wc-surface-sunken, var(--side-bar-background-lighter));
  color: var(--wc-text);
  font: inherit;
  font-size: 0.78rem;

  &::placeholder {
    color: var(--wc-text-muted);
    opacity: 0.7;
  }

  &:focus-visible {
    outline: 2px solid var(--wc-focus-ring);
    outline-offset: 1px;
  }

  /* The browser's own clear affordance would sit beside ours. */
  &::-webkit-search-cancel-button {
    display: none;
  }
}

.wc-search__clear,
.wc-search__collapsed {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  border: none;
  background: transparent;
  color: var(--wc-text-muted);
  cursor: pointer;

  &:hover {
    color: var(--wc-text);
  }

  &:focus-visible {
    outline: 2px solid var(--wc-focus-ring);
    outline-offset: 1px;
  }
}

.wc-search__clear {
  position: absolute;
  right: 0.6rem;
  width: 1.25rem;
  height: 1.25rem;
  border-radius: 50%;
}

.wc-search__collapsed {
  width: 100%;
  height: 1.75rem;
  border-radius: var(--wc-radius);
  font-size: 0.8rem;

  &:hover {
    background: var(--side-bar-background-lighter);
  }
}
</style>
