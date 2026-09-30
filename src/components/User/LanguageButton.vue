<template>
  <div class="wc-lang">
    <button
      ref="trigger"
      type="button"
      class="wc-lang__button"
      :title="labelText"
      :aria-label="labelText"
      aria-haspopup="dialog"
      :aria-expanded="open ? 'true' : 'false'"
      @click="togglePopover"
      @keydown.down.prevent="openPopover"
    >
      <LanguageFlag :code="activeCode" :size="16" />
      <span class="wc-lang__code">{{ code }}</span>
    </button>

    <!-- The menu is deliberately larger than the button: it carries a flag, the
         language in its own characters and its English name (D-6.2). -->
    <LanguageMenu
      v-if="open"
      ref="menu"
      data-popover
      class="wc-lang__menu"
      :active="activeCode"
      @select="onSelect"
      @close="closePopover"
    />
  </div>
</template>

<script>
import LanguageFlag from '@/components/LanguageFlag.vue';
import LanguageMenu from '@/components/Settings/LanguageMenu.vue';
import PopoverMixin from '@/mixins/PopoverMixin';
import { getLanguage, iso639, setLanguage } from '@/utils/languages';

/**
 * The language control: a rounded flag and the ISO 639-1 code, opening the
 * language menu. Design.md D-6.2.
 *
 * The face shows the *code*, not the endonym, because it sits in a row four
 * characters wide; the endonym is the first thing the menu shows.
 */
export default {
  name: 'LanguageButton',
  components: { LanguageFlag, LanguageMenu },
  mixins: [PopoverMixin],
  props: {
    appConfig: { type: Object, default: () => ({}) },
  },
  emits: ['applied'],
  data() {
    return {
      triggerSelector: '.wc-lang__button',
      firstItemSelector: '.wc-lang-menu__filter, .wc-lang-menu__option',
    };
  },
  computed: {
    activeCode() {
      return this.$i18n.locale;
    },
    code() {
      return iso639(this.activeCode);
    },
    labelText() {
      const language = getLanguage(this.activeCode)?.name || this.activeCode;
      return this.$t('user.language.change', { language });
    },
  },
  methods: {
    async onSelect(code) {
      this.closePopover();
      const result = await setLanguage(code, this.appConfig);
      this.$emit('applied', result);
    },
  },
};
</script>

<style lang="scss" scoped>
.wc-lang {
  position: relative;
  flex: 0 0 auto;
}

.wc-lang__button {
  display: flex;
  align-items: center;
  gap: 0.25rem;
  height: 1.75rem;
  padding: 0 0.35rem;
  border: none;
  border-radius: var(--wc-radius);
  background: transparent;
  color: var(--wc-text-muted);
  font: inherit;
  font-size: 0.7rem;
  letter-spacing: 0.02em;
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

.wc-lang__code {
  /* Two letters, never wrapped and never squeezed: the code is the whole point
     of the face, and the row must not clip it (design.md D-6.2). */
  flex: 0 0 auto;
  white-space: nowrap;
  text-transform: lowercase;
}

/* Fixed, so the rail's overflow cannot clip it (D-6.5) — the same contract the
   user panel uses. */
.wc-lang__menu {
  position: fixed;
  bottom: calc(var(--user-menu-height) + 0.35rem);
  left: calc(var(--side-bar-width) + 0.4rem);
  z-index: 30;
}
</style>
