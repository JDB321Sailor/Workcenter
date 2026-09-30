<template>
  <div class="wc-sidebar-group">
    <button
      v-if="collapsible"
      type="button"
      class="wc-sidebar-group__label wc-sidebar-group__toggle"
      :aria-expanded="open ? 'true' : 'false'"
      :aria-controls="`wc-sidebar-group-${group.id}`"
      @click="toggle"
    >
      <i class="fas fa-chevron-down wc-sidebar-group__chevron" :class="{ 'is-closed': !open }" aria-hidden="true" />
      {{ label }}
    </button>
    <p v-else class="wc-sidebar-group__label">{{ label }}</p>

    <div v-show="open" :id="`wc-sidebar-group-${group.id}`">
      <SidebarItem
        v-for="item in items"
        :key="item.id"
        :item="item"
        :isActive="item.id === activeItemId"
        @select="select"
      />
    </div>
  </div>
</template>

<script>
import SidebarItem from '@/components/AppSidebar/SidebarItem.vue';
import { localStorageKeys } from '@/utils/config/defaults';
import ErrorHandler from '@/utils/logging/ErrorHandler';

/**
 * A group of sidebar rows. Groups collapse, and the open/closed state follows
 * the user between visits. Design.md D-4.
 */
export default {
  name: 'SidebarGroup',
  props: {
    group: { type: Object, required: true },
    activeItemId: { type: String, default: '' },
  },
  emits: ['select'],
  components: {
    SidebarItem,
  },
  data() {
    return {
      /* Default open: a collapsed-by-default navigator hides its own content. */
      open: this.readStoredState(),
    };
  },
  computed: {
    label() {
      return this.group.labelKey ? this.$t(this.group.labelKey) : (this.group.label || '');
    },
    items() {
      return this.group.items || [];
    },
    collapsible() {
      return this.group.collapsible !== false && this.items.length > 0;
    },
  },
  methods: {
    /* The whole map of group states is stored under one key. */
    readStoredState() {
      try {
        const stored = JSON.parse(localStorage.getItem(localStorageKeys.SIDEBAR_GROUPS) || '{}');
        return stored[this.group.id] !== false;
      } catch (e) {
        ErrorHandler('Could not read the saved sidebar group state', e);
        return true;
      }
    },
    toggle() {
      this.open = !this.open;
      try {
        const stored = JSON.parse(localStorage.getItem(localStorageKeys.SIDEBAR_GROUPS) || '{}');
        stored[this.group.id] = this.open;
        localStorage.setItem(localStorageKeys.SIDEBAR_GROUPS, JSON.stringify(stored));
      } catch (e) {
        ErrorHandler('Could not save the sidebar group state', e);
      }
    },
    select(item) {
      this.$emit('select', item);
    },
  },
};
</script>

<style lang="scss" scoped>
.wc-sidebar-group {
  padding: 0.35rem 0;

  & + & {
    border-top: 1px solid var(--wc-border);
  }
}

.wc-sidebar-group__label {
  margin: 0;
  padding: 0.25rem 0.6rem;
  font-size: 0.62rem;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  opacity: 0.55;
}

.wc-sidebar-group__toggle {
  display: flex;
  align-items: center;
  gap: 0.3rem;
  width: 100%;
  border: none;
  background: transparent;
  color: inherit;
  font: inherit;
  font-size: 0.62rem;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  text-align: left;
  cursor: pointer;

  &:hover {
    opacity: 0.8;
  }

  &:focus-visible {
    outline: 2px solid var(--wc-focus-ring);
    outline-offset: -2px;
  }
}

.wc-sidebar-group__chevron {
  font-size: 0.58rem;
  transition: transform 140ms ease;

  &.is-closed {
    transform: rotate(-90deg);
  }
}

@media (prefers-reduced-motion: reduce) {
  .wc-sidebar-group__chevron {
    transition: none;
  }
}
</style>
