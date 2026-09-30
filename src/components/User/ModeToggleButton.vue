<template>
  <button
    type="button"
    class="wc-mode-toggle"
    :title="label"
    :aria-label="label"
    :data-mode="mode"
    @click="switchMode"
  >
    <!-- The glyph states the action, not the current state: a sun while the
         shell is dark (bring light), a moon while it is light (bring dark).
         Design.md D-6.1. -->
    <SunIcon v-if="mode === 'dark'" class="wc-mode-toggle__glyph" />
    <MoonIcon v-else class="wc-mode-toggle__glyph" />
  </button>
</template>

<script>
import SunIcon from '@icons/ui/sun.svg';
import MoonIcon from '@icons/ui/moon.svg';
import { MODE, modeState, setMode } from '@/utils/Theming';

/**
 * The appearance control: one button that switches the mode. Design.md D-6.1.
 *
 * It is an action, not a toggle state, so it carries no `aria-pressed`: its
 * accessible name says what the click will do (`Switch to light mode`).
 *
 * The glyphs are committed SVGs inlined as components, so they take
 * `currentColor` and follow the mode. They do not depend on the icon font.
 */
export default {
  name: 'ModeToggleButton',
  components: { SunIcon, MoonIcon },
  emits: ['applied'],
  computed: {
    mode() {
      return modeState.mode;
    },
    label() {
      return this.mode === MODE.DARK
        ? this.$t('user.mode.to-light')
        : this.$t('user.mode.to-dark');
    },
  },
  methods: {
    async switchMode() {
      const next = this.mode === MODE.DARK ? MODE.LIGHT : MODE.DARK;
      /* `setMode` returns the mode state: `{ mode, applied, panes }`. The panes
         map is what the shell reports back, so it is passed on unchanged. */
      const state = await setMode(next, this.$store.state.config.appConfig || {});
      this.$emit('applied', state || { mode: next, panes: {} });
    },
  },
};
</script>

<style lang="scss" scoped>
.wc-mode-toggle {
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

.wc-mode-toggle__glyph {
  width: 1.1rem;
  height: 1.1rem;
  fill: currentColor;
}
</style>
