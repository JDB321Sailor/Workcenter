<template>
  <div class="wc-brand" :class="{ 'wc-brand--collapsed': collapsed }">
    <!-- The wordmark returns the shell to the application the user last had
         open, so leaving and coming back does not lose their place. -->
    <button
      type="button"
      class="wc-brand__home"
      :title="$t('brand.home', { app: lastAppName })"
      @click="$emit('home')"
    >
      <span class="wc-brand__mark" aria-hidden="true">WC</span>
      <span v-if="!collapsed" class="wc-brand__titles">
        <span class="wc-brand__wordmark">Workcenter</span>
        <!-- Who the user is, stated once, here (design.md D-1.1). Smaller than
             the wordmark on purpose: it is a qualifier, not a title. -->
        <template v-if="role">
          <span class="wc-brand__dash" aria-hidden="true">-</span>
          <span class="wc-brand__role">{{ role }}</span>
        </template>
      </span>
    </button>

    <!-- The rail collapses sideways, so the control points the way it moves:
         left to collapse, right to open again (design.md D-1). It stays visible
         and clickable in both states — a collapse control that hides itself is a
         control the user cannot undo. -->
    <button
      type="button"
      class="wc-brand__toggle"
      :aria-expanded="collapsed ? 'false' : 'true'"
      :aria-label="collapsed ? $t('brand.expand') : $t('brand.collapse')"
      :title="collapsed ? $t('brand.expand') : $t('brand.collapse')"
      @click="$emit('toggle')"
    >
      <ArrowIcon class="wc-brand__toggle-icon" :class="{ 'is-flipped': collapsed }" />
    </button>
  </div>
</template>

<script>
/* A committed glyph rather than a font icon: the collapse control has to render
   whether or not the icon font has loaded. It points left — the direction the
   rail collapses in — and is flipped to point right when the rail is closed, so
   the arrow always shows what the click will do. */
import ArrowIcon from '@/assets/interface-icons/back-arrow.svg';
import { getUserProfile } from '@/utils/auth/Auth';

/**
 * The rail's brand header: the product mark, the wordmark, the role label and
 * the control that collapses the rail to icons. Design.md D-1, D-1.1.
 *
 * The wordmark is the only place the product name appears in the shell, and it
 * is a proper noun: it is never translated (design.md D-I3). The role label
 * beside it is translated and is the only statement of who the user is — the
 * user menu shows the identity and the admin links, not the role.
 */
export default {
  name: 'BrandHeader',
  components: {
    ArrowIcon,
  },
  props: {
    collapsed: { type: Boolean, default: false },
    /* The name of the application the wordmark returns to, for its tooltip. */
    lastAppName: { type: String, default: '' },
  },
  emits: ['home', 'toggle'],
  computed: {
    /* `User` or `Admin`, from the same session profile the user menu reads. A
       signed-out shell claims neither. */
    role() {
      void this.$store.getters.userState;
      const profile = getUserProfile();
      if (!profile.username) return '';
      return profile.isAdmin ? this.$t('brand.role-admin') : this.$t('brand.role-user');
    },
  },
};
</script>

<style lang="scss" scoped>
.wc-brand {
  position: relative;
  flex: 0 0 auto;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.25rem;
  height: var(--rail-header-height);
  padding: 0 0.4rem;
  border-bottom: 1px solid var(--wc-border);
}

.wc-brand__home {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  min-width: 0;
  padding: 0.25rem;
  border: none;
  border-radius: var(--wc-radius);
  background: transparent;
  color: var(--wc-text);
  font: inherit;
  cursor: pointer;

  &:hover {
    background: var(--side-bar-background-lighter);
  }

  &:focus-visible {
    outline: 2px solid var(--wc-focus-ring);
    outline-offset: 2px;
  }
}

/* A typographic monogram rather than an invented brand asset: the repository
 * commits marks for the integrated applications, not for Workcenter itself. */
.wc-brand__mark {
  flex: 0 0 auto;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 1.75rem;
  height: 1.75rem;
  border-radius: var(--wc-radius);
  background: var(--wc-accent-files);
  color: var(--wc-surface);
  font-size: 0.7rem;
  font-weight: 700;
  letter-spacing: 0.02em;
}

.wc-brand__titles {
  display: flex;
  align-items: baseline;
  gap: 0.3rem;
  min-width: 0;
}

.wc-brand__wordmark {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.9rem;
  font-weight: 600;
}

/* Smaller than the wordmark, and the first thing to give way when the row is
   narrow, so the collapse toggle is never pushed out of the header. */
.wc-brand__role {
  flex: 0 1 auto;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.72rem;
  color: var(--wc-text-muted);
}

.wc-brand__dash {
  flex: 0 0 auto;
  font-size: 0.72rem;
  color: var(--wc-text-muted);
}

.wc-brand__toggle {
  flex: 0 0 auto;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 1.75rem;
  height: 1.75rem;
  padding: 0;
  border: none;
  border-radius: var(--wc-radius);
  background: transparent;
  color: var(--wc-text-muted);
  cursor: pointer;

  &:hover {
    background: var(--side-bar-background-lighter);
    color: var(--wc-text);
  }

  &:focus-visible {
    outline: 2px solid var(--wc-focus-ring);
    outline-offset: 2px;
  }
}

.wc-brand__toggle-icon {
  width: 0.9rem;
  height: 0.9rem;
  transition: transform 160ms ease;
}

/* Collapsed: the arrow points right, back towards the wordmark. */
.wc-brand__toggle-icon.is-flipped {
  transform: rotate(180deg);
}

@media (prefers-reduced-motion: reduce) {
  .wc-brand__toggle-icon {
    transition: none;
  }
}

/* Collapsed: the mark sits above the toggle rather than beside it. Both stay
   visible and clickable — the way out of the collapsed rail is never hidden. */
.wc-brand--collapsed {
  flex-direction: column;
  justify-content: center;
  gap: 0.1rem;
  height: auto;
  min-height: var(--rail-header-height);
  padding: 0.3rem 0;

  .wc-brand__home {
    flex: 0 0 auto;
    justify-content: center;
  }
}
</style>
