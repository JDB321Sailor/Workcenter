<template>
  <div class="wc-app-sidebar">
    <!-- An application with no address cannot be shown, so the sidebar says so
         rather than offering rows that go nowhere. -->
    <p v-if="isUnconfigured" class="wc-app-sidebar__notice">
      {{ $t('sidebar.files.unconfigured') }}
    </p>

    <template v-else>
      <SidebarGroup
        v-for="group in groups"
        :key="group.id"
        :group="group"
        :activeItemId="activeItemId"
        @select="select"
      />

      <p class="wc-app-sidebar__footnote">{{ $t('sidebar.files.footnote') }}</p>
    </template>
  </div>
</template>

<script>
import SidebarGroup from '@/components/AppSidebar/SidebarGroup.vue';
import SidebarMixin from '@/mixins/SidebarMixin';

/**
 * The Files navigator: the FileBrowser Quantum sidebar.
 *
 * Each row deep-links into the Files pane. The row list is the shell's own
 * navigation, so it is available even when the embedded application is slow to
 * load.
 */
export default {
  name: 'FilesSidebar',
  mixins: [SidebarMixin],
  components: {
    SidebarGroup,
  },
  computed: {
    sidebarGroups() {
      return [
        {
          id: 'sources',
          labelKey: 'sidebar.files.sources',
          items: [
            {
              id: 'all-files',
              labelKey: 'sidebar.files.all-files',
              icon: 'fas fa-hard-drive',
              path: '',
            },
            {
              id: 'recent',
              labelKey: 'sidebar.files.recent',
              icon: 'fas fa-clock-rotate-left',
              path: '',
            },
            {
              id: 'shared',
              labelKey: 'sidebar.files.shared',
              icon: 'fas fa-share-nodes',
              path: '',
            },
            {
              id: 'favourites',
              labelKey: 'sidebar.files.favourites',
              icon: 'fas fa-star',
              path: '',
            },
          ],
        },
        {
          id: 'tools',
          labelKey: 'sidebar.files.tools',
          items: [
            {
              id: 'search',
              labelKey: 'sidebar.files.search',
              icon: 'fas fa-magnifying-glass',
              path: '',
            },
            {
              id: 'size-viewer',
              labelKey: 'sidebar.files.size-viewer',
              icon: 'fas fa-chart-pie',
              path: '',
            },
            {
              id: 'activity',
              labelKey: 'sidebar.files.activity',
              icon: 'fas fa-list-check',
              path: '',
            },
          ],
        },
      ];
    },
  },
};
</script>

<style lang="scss" scoped>
@import '@/components/AppSidebar/sidebar-shared.scss';
</style>
