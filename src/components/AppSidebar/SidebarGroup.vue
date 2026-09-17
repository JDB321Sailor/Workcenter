<template>
  <div class="wc-sidebar-group">
    <p class="wc-sidebar-group__label">{{ label }}</p>
    <SidebarItem
      v-for="item in items"
      :key="item.id"
      :item="item"
      :isActive="item.id === activeItemId"
      @select="select"
    />
  </div>
</template>

<script>
import SidebarItem from '@/components/AppSidebar/SidebarItem.vue';

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
  computed: {
    label() {
      return this.group.labelKey ? this.$t(this.group.labelKey) : (this.group.label || '');
    },
    items() {
      return this.group.items || [];
    },
  },
  methods: {
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
</style>
