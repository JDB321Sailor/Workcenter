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

      <p class="wc-app-sidebar__footnote">{{ $t('sidebar.chat.footnote') }}</p>
    </template>
  </div>
</template>

<script>
import SidebarGroup from '@/components/AppSidebar/SidebarGroup.vue';
import SidebarMixin from '@/mixins/SidebarMixin';

/**
 * The Chat navigator: the Zulip left sidebar.
 *
 * Views, channels and direct messages. Zulip builds this list from the signed-in
 * user's subscriptions, which the shell can read once the broker carries the
 * Zulip adapter (roadmap Phase 6); until then the rows are the views every Zulip
 * account has.
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
            { id: 'inbox', labelKey: 'sidebar.chat.inbox', icon: 'fas fa-inbox', path: '' },
            {
              id: 'recent',
              labelKey: 'sidebar.chat.recent',
              icon: 'fas fa-clock-rotate-left',
              path: '',
            },
            {
              id: 'combined',
              labelKey: 'sidebar.chat.combined',
              icon: 'fas fa-layer-group',
              path: '',
            },
            {
              id: 'mentions',
              labelKey: 'sidebar.chat.mentions',
              icon: 'fas fa-at',
              path: '',
            },
            { id: 'starred', labelKey: 'sidebar.chat.starred', icon: 'fas fa-star', path: '' },
            { id: 'drafts', labelKey: 'sidebar.chat.drafts', icon: 'fas fa-pen', path: '' },
          ],
        },
        {
          id: 'messages',
          labelKey: 'sidebar.chat.messages',
          items: [
            {
              id: 'direct',
              labelKey: 'sidebar.chat.direct',
              icon: 'fas fa-comment-dots',
              path: '',
            },
            {
              id: 'new-topic',
              labelKey: 'sidebar.chat.new-topic',
              icon: 'fas fa-plus',
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
