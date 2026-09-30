<template>
  <div class="wc-user-row" :class="{ 'wc-user-row--collapsed': collapsed }">
    <!-- The initials are the trigger in both states: expanded it sits beside the
         name, collapsed it is the whole row (design.md D-6, D-6.5). -->
    <button
      ref="trigger"
      type="button"
      class="wc-user-row__initials"
      :title="collapsed ? displayName : undefined"
      :aria-label="$t('user.trigger-label', { name: displayName })"
      aria-haspopup="dialog"
      :aria-expanded="open ? 'true' : 'false'"
      @click="$emit('toggle')"
      @keydown.down.prevent="$emit('open')"
    >
      {{ initials }}
    </button>

    <span v-if="!collapsed" class="wc-user-row__names">
      <span class="wc-user-row__name">{{ firstName }}</span>
      <span v-if="lastName" class="wc-user-row__name">{{ lastName }}</span>
    </span>

    <!-- The two preference buttons, right-hand group, mode inboard of language
         (design.md D-6.1, D-6.2). Not rendered when collapsed: the panel carries
         them instead (D-6.5). -->
    <span v-if="!collapsed" class="wc-user-row__controls">
      <ModeToggleButton @applied="$emit('mode-applied', $event)" />
      <LanguageButton :appConfig="appConfig" @applied="$emit('language-applied', $event)" />
    </span>
  </div>
</template>

<script>
import ModeToggleButton from '@/components/User/ModeToggleButton.vue';
import LanguageButton from '@/components/User/LanguageButton.vue';

/**
 * The rail footer's row: who is signed in, and the two preference buttons.
 * Design.md D-6, D-6.3.
 *
 * The name is stacked first-over-last and cut at `NAME_MAX_LENGTH` characters a
 * line. The cut is done here rather than left to CSS because a hard cut cannot
 * reflow the row, and the ellipsis tells the user that something was cut.
 */
export const NAME_MAX_LENGTH = 14;

/* Cuts to the cap, spending one of the characters on the ellipsis so the
   visible text never exceeds it. */
export const truncateName = (value) => {
  const text = (value || '').trim();
  if (text.length <= NAME_MAX_LENGTH) return text;
  return `${text.slice(0, NAME_MAX_LENGTH - 1)}…`;
};

export default {
  name: 'UserRow',
  components: { ModeToggleButton, LanguageButton },
  props: {
    collapsed: { type: Boolean, default: false },
    open: { type: Boolean, default: false },
    displayName: { type: String, default: '' },
    email: { type: String, default: '' },
    appConfig: { type: Object, default: () => ({}) },
  },
  emits: ['toggle', 'open', 'mode-applied', 'language-applied'],
  computed: {
    parts() {
      const name = (this.displayName || '').trim();
      /* No name at all: the email's local part identifies the row instead, so a
         session without a name claim is never anonymous (D-6.3). Neither means
         nobody is signed in, and the row says so rather than showing a blank. */
      if (!name) {
        const local = (this.email || '').split('@')[0];
        return { first: local || this.$t('user.not-signed-in'), last: '' };
      }
      const [first, ...rest] = name.split(/\s+/);
      return { first, last: rest.join(' ') };
    },
    firstName() {
      return truncateName(this.parts.first);
    },
    lastName() {
      return truncateName(this.parts.last);
    },
    /* Initials, never a photograph: the shell stores no avatar. */
    initials() {
      const source = this.displayName || this.email || '?';
      return source
        .split(/[\s.@_-]+/)
        .filter(Boolean)
        .slice(0, 2)
        .map((part) => part[0].toUpperCase())
        .join('');
    },
  },
};
</script>

<style lang="scss" scoped>
.wc-user-row {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  width: 100%;
  min-height: var(--user-menu-height);
  /* The distance from the language button to the edge of the rail. The controls
     reuse it below, so the two buttons read as one group (design.md D-6.6). */
  --wc-user-row-edge: 0.75rem;
  padding: 0.25rem var(--wc-user-row-edge);
}

.wc-user-row__initials {
  flex: 0 0 auto;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 1.6rem;
  height: 1.6rem;
  padding: 0;
  border: none;
  border-radius: 50%;
  background: var(--wc-accent-files);
  color: var(--wc-surface);
  font: inherit;
  font-size: 0.66rem;
  font-weight: 700;
  cursor: pointer;

  &:focus-visible {
    outline: 2px solid var(--wc-focus-ring);
    outline-offset: 2px;
  }
}

/* Two lines, first over last. The column is sized for NAME_MAX_LENGTH
   characters and never pushes the controls out of the row. */
.wc-user-row__names {
  display: flex;
  flex-direction: column;
  flex: 1 1 auto;
  min-width: 0;
  line-height: 1.15;
}

.wc-user-row__name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.75rem;
}

.wc-user-row__controls {
  flex: 0 0 auto;
  display: flex;
  align-items: center;
  /* The sun/moon glyph is centred inside its 1.75rem tap target, so the glyph
     itself starts 0.325rem in from that button's edge. Subtracting that slack
     makes the space between the glyph and the flag equal to the space between
     the language code and the rail edge — the same distance, measured the way
     the eye measures it. */
  gap: calc(var(--wc-user-row-edge, 0.75rem) - (1.75rem - 1.1rem) / 2);
}

/* Collapsed: the initials button is the whole row. */
.wc-user-row--collapsed {
  justify-content: center;
  padding: 0;
}
</style>
