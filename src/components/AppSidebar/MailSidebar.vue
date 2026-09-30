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

      <p v-if="hasNoMatches" class="wc-app-sidebar__notice">
        {{ $t('sidebar.search.no-matches', { app: app.name }) }}
        <span class="wc-app-sidebar__hint">{{ $t('sidebar.search.no-matches-hint', { app: app.name }) }}</span>
      </p>

      <p v-else class="wc-app-sidebar__footnote">{{ $t('sidebar.mail.footnote') }}</p>
    </template>
  </div>
</template>

<script>
import SidebarGroup from '@/components/AppSidebar/SidebarGroup.vue';
import SidebarMixin from '@/mixins/SidebarMixin';
import { getUserProfile } from '@/utils/auth/Auth';

/**
 * The Mail navigator: the SOGo modules and mail folders.
 *
 * SOGo addresses a user's own folder tree as
 * `/SOGo/so/<mailbox>/<Module>/view#!/<module state>`, verified against SOGo
 * 5.12 (`UI/SOGoUI/UIxComponent.m` for the base, `Mailer.app.js`,
 * `Scheduler.app.js` and `Contacts.app.js` for the states). `<mailbox>` is the
 * signed-in user's mailbox address, which the shell takes from the session; with
 * no address it falls back to the module root, which SOGo resolves itself.
 *
 * A folder whose name SOGo does not know falls back to the module's default
 * view (`$urlServiceProvider.rules.otherwise`), so an unfamiliar mailbox naming
 * scheme lands somewhere usable rather than erroring.
 *
 * SOGo has no URL form for selecting an individual calendar, so the calendar
 * row opens the calendar module; per-calendar selection stays SOGo's own
 * business (design.md D-4.3).
 */
export default {
  name: 'MailSidebar',
  mixins: [SidebarMixin],
  components: {
    SidebarGroup,
  },
  computed: {
    /* The signed-in mailbox, when the session carries an address. Re-read when
       the session changes: getUserState is the auth-revision getter. */
    mailbox() {
      void this.$store.getters.userState;
      const { email, username } = getUserProfile();
      if (email) return email;
      return username.includes('@') ? username : '';
    },
    /* `/SOGo/so/<mailbox>/…`, or the module root when the mailbox is unknown. */
    userBase() {
      /* Only the separator is escaped: an address is a legal path segment, and
         escaping `@` would make the URL unreadable for no gain. */
      return this.mailbox ? `so/${this.mailbox.replace(/\//g, '%2F')}` : '';
    },
    sidebarGroups() {
      const folders = [
        ['inbox', 'INBOX'],
        ['drafts', 'Drafts'],
        ['sent', 'Sent'],
        ['junk', 'Junk'],
        ['trash', 'Trash'],
        ['archive', 'Archive'],
      ].map(([id, folder]) => ({
        id,
        labelKey: `sidebar.mail.${id}`,
        icon: this.folderIcon(id),
        path: this.mailPath(folder),
      }));

      return [
        { id: 'mail', labelKey: 'sidebar.mail.folders', items: folders },
        {
          id: 'calendars',
          labelKey: 'sidebar.mail.calendars',
          items: [
            {
              id: 'calendar',
              labelKey: 'sidebar.mail.calendar',
              icon: 'fas fa-calendar-days',
              path: this.modulePath('Calendar', '#!/calendar/week'),
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
              path: this.modulePath('Contacts', '#!/addressbooks/personal'),
            },
          ],
        },
      ];
    },
  },
  methods: {
    folderIcon(id) {
      const icons = {
        inbox: 'fas fa-inbox',
        drafts: 'fas fa-pen',
        sent: 'fas fa-paper-plane',
        junk: 'fas fa-ban',
        trash: 'fas fa-trash',
        archive: 'fas fa-box-archive',
      };
      return icons[id] || 'fas fa-folder';
    },
    /* A mail folder: `…/Mail/view#!/Mail/0/<encoded folder path>`. */
    mailPath(folder) {
      return this.modulePath('Mail', `#!/Mail/0/${encodeURIComponent(folder)}`);
    },
    /* A SOGo module with an optional state fragment, rooted at the mailbox. */
    modulePath(module, hash) {
      const prefix = this.userBase ? `${this.userBase}/` : '';
      return `${prefix}${module}/view${hash}`;
    },
  },
};
</script>

<style lang="scss" scoped>
@import '@/components/AppSidebar/sidebar-shared.scss';
</style>
