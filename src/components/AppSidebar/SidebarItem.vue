<template>
  <button
    type="button"
    class="wc-sidebar-item"
    :class="{ 'is-active': isActive, 'is-child': isChild }"
    :aria-current="isActive ? 'page' : undefined"
    :title="title || label"
    @click="$emit('select', item)"
  >
    <i v-if="item.icon" :class="item.icon" class="wc-sidebar-item__icon" aria-hidden="true" />
    <span class="wc-sidebar-item__label">{{ label }}</span>
    <span v-if="item.badge" class="wc-sidebar-item__badge">{{ item.badge }}</span>
  </button>
</template>

<script>
/**
 * One row in a sidebar. Every application's navigator uses this primitive, so
 * the three surfaces share a single visual grammar. Design.md D-4.
 */
export default {
  name: 'SidebarItem',
  props: {
    item: { type: Object, required: true },
    isActive: { type: Boolean, default: false },
    /* Rendered indented, for an item inside a group. */
    isChild: { type: Boolean, default: false },
  },
  emits: ['select'],
  computed: {
    label() {
      /* Application-defined labels are used as written; anything the shell
       * supplies has a translation key. */
      return this.item.labelKey ? this.$t(this.item.labelKey) : (this.item.label || '');
    },
    title() {
      return this.item.title || '';
    },
  },
};
</script>

<style lang="scss" scoped>
.wc-sidebar-item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  width: 100%;
  height: 32px;
  padding: 0 0.5rem;
  border: none;
  border-left: 2px solid transparent;
  background: transparent;
  color: var(--side-bar-color);
  font: inherit;
  font-size: 0.82rem;
  text-align: left;
  cursor: pointer;

  &:hover {
    background: var(--side-bar-background-lighter);
  }

  &:focus-visible {
    outline: 2px solid var(--wc-focus-ring);
    outline-offset: -2px;
  }

  &.is-child {
    padding-left: 1.5rem;
  }

  /* The active row is never signalled by colour alone: it also carries
   * aria-current and a left border. */
  &.is-active {
    background: var(--side-bar-item-background);
    border-left-color: var(--wc-focus-ring);
    font-weight: 600;
  }
}

.wc-sidebar-item__icon {
  flex: 0 0 auto;
  width: 1rem;
  text-align: center;
  opacity: 0.85;
}

.wc-sidebar-item__label {
  flex: 1 1 auto;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.wc-sidebar-item__badge {
  flex: 0 0 auto;
  padding: 0.05rem 0.35rem;
  border-radius: 999px;
  background: var(--side-bar-background-lighter);
  font-size: 0.68rem;
  font-variant-numeric: tabular-nums;
}
</style>
