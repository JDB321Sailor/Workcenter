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

      <p v-if="hasNoMatches" class="wc-app-sidebar__notice">
        {{ $t('sidebar.search.no-matches', { app: app.name }) }}
        <span class="wc-app-sidebar__hint">{{ $t('sidebar.search.no-matches-hint', { app: app.name }) }}</span>
      </p>

      <p v-else class="wc-app-sidebar__footnote">{{ $t('sidebar.files.footnote') }}</p>
    </template>
  </div>
</template>

<script>
import SidebarGroup from '@/components/AppSidebar/SidebarGroup.vue';
import SidebarMixin from '@/mixins/SidebarMixin';

/**
 * The Files navigator: the FileBrowser Quantum sidebar.
 *
 * Every path below is one of FileBrowser Quantum's own routes, read from
 * `frontend/src/router/index.ts` and `frontend/src/utils/constants.js` at the
 * pinned version: `files` (with an optional path), and the tool routes
 * `tools/advancedSearch`, `tools/sizeViewer`, `tools/duplicateFinder`,
 * `tools/fileWatcher` and `tools/activityViewer`.
 *
 * The source list belongs to the broker's FileBrowser adapter (roadmap Phase 6,
 * design.md D-4.1): the shell cannot read the user's sources without the user's
 * own FileBrowser session, so it is not invented here.
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
          id: 'browse',
          labelKey: 'sidebar.files.sources',
          items: [
            {
              id: 'all-files',
              labelKey: 'sidebar.files.all-files',
              icon: 'fas fa-hard-drive',
              path: 'files',
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
              path: 'tools/advancedSearch',
            },
            {
              id: 'size-viewer',
              labelKey: 'sidebar.files.size-viewer',
              icon: 'fas fa-chart-pie',
              path: 'tools/sizeViewer',
            },
            {
              id: 'duplicate-finder',
              labelKey: 'sidebar.files.duplicate-finder',
              icon: 'fas fa-clone',
              path: 'tools/duplicateFinder',
            },
            {
              id: 'file-watcher',
              labelKey: 'sidebar.files.file-watcher',
              icon: 'fas fa-eye',
              path: 'tools/fileWatcher',
            },
            {
              id: 'activity',
              labelKey: 'sidebar.files.activity',
              icon: 'fas fa-list-check',
              path: 'tools/activityViewer',
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
