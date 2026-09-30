<template>
  <div class="wc-app-sidebar">
    <p v-if="isUnconfigured" class="wc-app-sidebar__notice">
      {{ $t('sidebar.chat.unconfigured') }}
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

      <p v-else class="wc-app-sidebar__footnote">{{ $t('sidebar.chat.footnote') }}</p>
    </template>
  </div>
</template>

<script>
import SidebarGroup from '@/components/AppSidebar/SidebarGroup.vue';
import SidebarMixin from '@/mixins/SidebarMixin';

/**
 * The Chat navigator: Zulip's views.
 *
 * Every hash below is a Zulip view fragment, verified against the pinned
 * client (`web/src/navigation_views.ts`, `web/src/hashchange.ts`):
 * `#inbox`, `#recent`, `#feed`, `#narrow/is/mentioned`, `#narrow/is/starred`
 * and `#drafts`. Zulip's own client parses them on load, so a pane navigation
 * lands on the right view.
 *
 * Channels and direct messages are read from the user's subscriptions by the
 * broker's Zulip adapter (`GET /api/v1/users/me/subscriptions`, roadmap Phase
 * 6); their URL grammar is `#narrow/channel/<id>-<slug>[/topic/<topic>]` and
 * `#narrow/dm/<ids>`, and the shell will build those rows when it has them.
 */
export default {
  name: 'ChatSidebar',
  mixins: [SidebarMixin],
  components: {
    SidebarGroup,
  },
  computed: {
    sidebarGroups() {
      return [
        {
          id: 'views',
          labelKey: 'sidebar.chat.views',
          items: [
            { id: 'inbox', labelKey: 'sidebar.chat.inbox', icon: 'fas fa-inbox', path: '#inbox' },
            {
              id: 'recent',
              labelKey: 'sidebar.chat.recent',
              icon: 'fas fa-clock-rotate-left',
              path: '#recent',
            },
            {
              id: 'combined',
              labelKey: 'sidebar.chat.combined',
              icon: 'fas fa-layer-group',
              path: '#feed',
            },
            {
              id: 'mentions',
              labelKey: 'sidebar.chat.mentions',
              icon: 'fas fa-at',
              path: '#narrow/is/mentioned',
            },
            {
              id: 'starred',
              labelKey: 'sidebar.chat.starred',
              icon: 'fas fa-star',
              path: '#narrow/is/starred',
            },
            { id: 'drafts', labelKey: 'sidebar.chat.drafts', icon: 'fas fa-pen', path: '#drafts' },
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
