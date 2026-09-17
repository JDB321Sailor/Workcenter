<template>
  <div class="wc-app-sidebar">
    <p v-if="isUnconfigured" class="wc-app-sidebar__notice">
      {{ $t('sidebar.mail.unconfigured') }}
    </p>

    <template v-else>
      <SidebarGroup
        v-for="group in groups"
        :key="group.id"
        :group="group"
        :activeItemId="activeItemId"
        @select="select"
      />

      <p class="wc-app-sidebar__footnote">{{ $t('sidebar.mail.footnote') }}</p>
    </template>
  </div>
</template>

<script>
import SidebarGroup from '@/components/AppSidebar/SidebarGroup.vue';
import SidebarMixin from '@/mixins/SidebarMixin';

/**
 * The Mail navigator: the SOGo sidebar.
 *
 * Mail folders, calendars and address books. SOGo has no public API for these
 * lists, so the shell carries the folders every mailbox has, and the calendars
 * and address books that Mailcow creates by default.
 */
export default {
  name: 'MailSidebar',
  mixins: [SidebarMixin],
  components: {
    SidebarGroup,
  },
  computed: {
    sidebarGroups() {
      return [
        {
          id: 'mail',
          labelKey: 'sidebar.mail.folders',
          items: [
            { id: 'inbox', labelKey: 'sidebar.mail.inbox', icon: 'fas fa-inbox', path: 'SOGo/' },
            { id: 'drafts', labelKey: 'sidebar.mail.drafts', icon: 'fas fa-pen', path: 'SOGo/' },
            { id: 'sent', labelKey: 'sidebar.mail.sent', icon: 'fas fa-paper-plane', path: 'SOGo/' },
            { id: 'junk', labelKey: 'sidebar.mail.junk', icon: 'fas fa-ban', path: 'SOGo/' },
            { id: 'trash', labelKey: 'sidebar.mail.trash', icon: 'fas fa-trash', path: 'SOGo/' },
            { id: 'archive', labelKey: 'sidebar.mail.archive', icon: 'fas fa-box-archive', path: 'SOGo/' },
          ],
        },
        {
          id: 'calendars',
          labelKey: 'sidebar.mail.calendars',
          items: [
            {
              id: 'calendar',
              labelKey: 'sidebar.mail.calendar',
              icon: 'fas fa-calendar-days',
              path: 'SOGo/',
            },
          ],
        },
        {
          id: 'contacts',
          labelKey: 'sidebar.mail.contacts',
          items: [
            {
              id: 'address-book',
              labelKey: 'sidebar.mail.address-book',
              icon: 'fas fa-address-book',
              path: 'SOGo/',
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
