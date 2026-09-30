<template>
  <div ref="root" class="wc-user" :class="{ 'wc-user--collapsed': collapsed }">
    <UserRow
      :collapsed="collapsed"
      :open="open"
      :displayName="profile.displayName"
      :email="profile.email"
      :appConfig="appConfig"
      @toggle="togglePopover"
      @open="openPopover"
      @mode-applied="onApplied('mode', $event)"
      @language-applied="onApplied('language', $event)"
    />

    <!-- The panel: identity, feedback, the admin links and Logout. It carries no
         appearance or language control while the rail is expanded — those are in
         the row above (design.md D-6). -->
    <div
      v-if="open"
      data-popover
      class="wc-user__panel"
      role="dialog"
      :aria-label="$t('user.menu-label')"
      @keydown.esc.stop.prevent="closePopover"
      @keydown="onPopoverKeydown"
    >
      <div class="wc-user__identity">
        <p class="wc-user__name">{{ profile.displayName || $t('user.not-signed-in') }}</p>
        <p v-if="profile.email" class="wc-user__email">{{ profile.email }}</p>
        <p v-if="summary" class="wc-user__groups">{{ summary }}</p>
      </div>

      <!-- Collapsed, the row has no space for the two buttons, so the panel
           carries them: a collapsed rail must still reach the language menu
           (design.md D-6.5). The mode and the language are per-browser choices,
           so they are offered whether or not a session is present. -->
      <div v-if="collapsed" class="wc-user__section wc-user__preferences">
        <ModeToggleButton @applied="onApplied('mode', $event)" />
        <LanguageButton :appConfig="appConfig" @applied="onApplied('language', $event)" />
        <span class="wc-user__preferences-hint">{{ $t('user.preferences-hint') }}</span>
      </div>

      <!-- What the last change did to the panes, stated once (D-6.1). -->
      <p v-if="notice" class="wc-user__notice" role="status">{{ notice }}</p>

      <!-- Admin links are hidden, not disabled, for everyone else. -->
      <div v-if="profile.isAdmin" class="wc-user__section wc-user__links">
        <a
          v-for="link in adminLinks"
          :key="link.id"
          class="wc-user__link"
          :href="link.url"
          target="_blank"
          rel="noopener noreferrer"
        >
          <AppMark :name="link.mark" :size="20" decorative />
          <span class="wc-user__link-label">{{ link.label }}</span>
          <i class="fas fa-arrow-up-right-from-square wc-user__link-external" aria-hidden="true" />
        </a>
      </div>

      <div class="wc-user__section wc-user__footer">
        <button type="button" class="wc-user__signout" @click="signOutNow">
          <i class="fas fa-right-from-bracket" aria-hidden="true" />
          {{ $t('user.sign-out') }}
        </button>
        <p class="wc-user__signout-note">{{ $t('user.sign-out-note') }}</p>
      </div>
    </div>
  </div>
</template>

<script>
import UserRow from '@/components/User/UserRow.vue';
import ModeToggleButton from '@/components/User/ModeToggleButton.vue';
import LanguageButton from '@/components/User/LanguageButton.vue';
import AppMark from '@/components/AppMark.vue';
import PopoverMixin from '@/mixins/PopoverMixin';
import { getUserProfile } from '@/utils/auth/Auth';
import signOut from '@/utils/auth/Logout';
import { appUrls } from '@/utils/apps/urls';
import { getLanguage } from '@/utils/languages';

/**
 * The rail footer: the user row, and the menu behind it. Design.md D-6.
 *
 * The row owns the mode and language buttons while the rail is expanded; the
 * panel owns them while it is collapsed, because the collapsed row is the
 * initials button alone. Everything else — identity, the admin links, Logout —
 * is in the panel in both states.
 */
export default {
  name: 'UserMenu',
  components: {
    UserRow,
    ModeToggleButton,
    LanguageButton,
    AppMark,
  },
  mixins: [PopoverMixin],
  props: {
    collapsed: { type: Boolean, default: false },
    appConfig: { type: Object, default: () => ({}) },
  },
  emits: ['preferences-applied', 'language-applied'],
  data() {
    return {
      triggerSelector: '.wc-user-row__initials',
      firstItemSelector: 'button, input',
      /* The last outcome, reported in the panel (D-6.1 feedback). */
      lastApplied: null,
    };
  },
  computed: {
    /* Re-reads when the session changes: getUserState is the store's
       auth-revision-dependent getter. */
    profile() {
      void this.$store.getters.userState;
      return getUserProfile();
    },
    signedIn() {
      return this.profile.username !== '';
    },
    /* The group summary line: the group model is two groups, so this is short. */
    summary() {
      return this.profile.groups.join(', ');
    },
    /* What the last mode or language change did, in one line. The `$t` calls are
       written out rather than looked up from a map, so the i18n checker can see
       which keys the shell uses. */
    notice() {
      if (!this.lastApplied) return '';
      const { kind, apps } = this.lastApplied;
      const names = { files: 'Files', chat: 'Chat', mail: 'Mail' };
      const failed = Object.entries(apps || {}).find(([, state]) => state !== 'ok');
      if (!failed) {
        return kind === 'language'
          ? this.$t('user.language.helper-bridge')
          : this.$t('user.appearance.helper-applied');
      }
      const [appId, state] = failed;
      const app = names[appId] || appId;
      if (kind === 'language') {
        if (state === 'unsupported') return this.$t('user.language.helper-unmapped', { app });
        if (state === 'unavailable') return this.$t('user.language.unavailable', { app });
        return this.$t('user.language.failed', { app });
      }
      if (state === 'deferred') return this.$t('user.appearance.deferred');
      if (state === 'unsupported') return this.$t('user.appearance.unsupported', { app });
      if (state === 'unavailable') return this.$t('user.appearance.unavailable', { app });
      return this.$t('user.appearance.failed', { app });
    },
    /* Admin links point at the deployment's own surfaces, from the configured
       addresses, and never at a hard-coded host (design.md D-6.4). */
    adminLinks() {
      const urls = appUrls(this.appConfig);
      return [
        {
          id: 'traefik',
          label: this.$t('user.links.integrations'),
          mark: 'traefik',
          url: this.traefikUrl,
        },
        {
          id: 'mailcow',
          label: this.$t('user.links.mail-admin'),
          mark: 'mailcow',
          url: urls.mail,
        },
        {
          id: 'authentik',
          label: this.$t('user.links.identity'),
          mark: 'authentik',
          url: this.identityUrl,
        },
      ].filter((link) => link.url);
    },
    /* Traefik and Authentik are derived from the deployment's addresses: the
       dashboard replaces the Workcenter host's first label with `traefik`, the
       identity provider is the configured OIDC issuer. */
    traefikUrl() {
      try {
        const host = new URL(this.appConfig?.applications?.files?.url || window.location.origin);
        const labels = host.hostname.split('.');
        if (labels.length < 2) return '';
        labels[0] = 'traefik';
        return `${host.protocol}//${labels.join('.')}`;
      } catch {
        return '';
      }
    },
    identityUrl() {
      const endpoint = this.appConfig?.auth?.oidc?.endpoint || '';
      if (!endpoint) return '';
      try {
        return new URL(endpoint).origin;
      } catch {
        return '';
      }
    },
    /* The language in use, for the row's tooltip. */
    languageName() {
      return getLanguage(this.$i18n.locale)?.name || this.$i18n.locale;
    },
  },
  methods: {
    onApplied(kind, result) {
      this.lastApplied = {
        kind,
        /* The mode path reports a `panes` map; the language path an `apps` map. */
        apps: result?.panes || result?.apps || {},
      };
      this.$emit(kind === 'mode' ? 'preferences-applied' : 'language-applied', result);
    },
    signOutNow() {
      this.closePopover();
      signOut(this.$store);
    },
  },
};
</script>

<style lang="scss" scoped>
.wc-user {
  position: relative;
  flex: 0 0 auto;
  border-top: 1px solid var(--wc-border);
}

/* Fixed rather than absolute: the rail clips its own overflow, and the panel has
   to be readable beside a collapsed rail too (D-6.5).
   Expanded, it opens upward **inside the rail column**, directly above the
   initials button: that is where the user is looking, and a panel beside the rail
   reads as a second surface. Its width is the rail's width less the inset, so it
   never overhangs the content surface. */
.wc-user__panel {
  position: fixed;
  bottom: calc(var(--user-menu-height) + 0.35rem);
  left: 0.4rem;
  width: calc(var(--side-bar-width) - 0.8rem);
  z-index: 30;
  max-height: 70vh;
  overflow-y: auto;
  padding: 0.5rem;
  border: 1px solid var(--wc-border);
  border-radius: var(--wc-radius);
  background: var(--wc-surface-raised);
  color: var(--wc-text);
  box-shadow: var(--wc-shadow-popover);
}

/* Collapsed, the row is 3.5rem wide: the panel opens beside the rail at its full
   width instead, where there is room for it. Unchanged from the collapsed
   behaviour the design already specifies. */
.wc-user--collapsed .wc-user__panel {
  left: calc(var(--side-bar-width) + 0.4rem);
  width: 17rem;
}

.wc-user__identity {
  padding: 0.35rem 0.4rem 0.5rem;
  border-bottom: 1px solid var(--wc-border);
}

.wc-user__name {
  margin: 0;
  font-size: 0.85rem;
  font-weight: 600;
}

.wc-user__email,
.wc-user__groups {
  margin: 0.15rem 0 0;
  font-size: 0.72rem;
  color: var(--wc-text-muted);
  overflow-wrap: anywhere;
}

.wc-user__section {
  padding: 0.5rem 0.4rem;
  border-bottom: 1px solid var(--wc-border);

  &:last-child {
    border-bottom: none;
  }
}

/* Collapsed rail only: the two preference buttons, with their names beside
   them, since the panel has the room the row does not. */
.wc-user__preferences {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.wc-user__preferences-hint {
  flex: 1 1 auto;
  min-width: 0;
  font-size: 0.7rem;
  color: var(--wc-text-muted);
}

.wc-user__notice {
  margin: 0;
  padding: 0.5rem 0.4rem;
  border-bottom: 1px solid var(--wc-border);
  font-size: 0.7rem;
  line-height: 1.35;
  color: var(--wc-text-muted);
}

.wc-user__links {
  display: flex;
  flex-direction: column;
  gap: 0.1rem;
}

.wc-user__link {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.35rem 0.3rem;
  border-radius: calc(var(--wc-radius) / 2);
  color: var(--wc-text);
  font-size: 0.78rem;
  text-decoration: none;

  &:hover {
    background: var(--side-bar-background-lighter);
  }

  &:focus-visible {
    outline: 2px solid var(--wc-focus-ring);
    outline-offset: -2px;
  }
}

.wc-user__link-label {
  flex: 1 1 auto;
}

.wc-user__link-external {
  font-size: 0.62rem;
  opacity: 0.6;
}

.wc-user__footer {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

/* Logout is last and separated, so it is never hit by accident. */
.wc-user__signout {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  width: 100%;
  padding: 0.45rem 0.3rem;
  border: 1px solid var(--wc-border);
  border-radius: calc(var(--wc-radius) / 2);
  background: transparent;
  color: var(--wc-text);
  font: inherit;
  font-size: 0.8rem;
  cursor: pointer;

  &:hover {
    background: var(--side-bar-background-lighter);
  }

  &:focus-visible {
    outline: 2px solid var(--wc-focus-ring);
    outline-offset: 2px;
  }
}

.wc-user__signout-note {
  margin: 0;
  font-size: 0.66rem;
  line-height: 1.35;
  color: var(--wc-text-muted);
}
</style>
