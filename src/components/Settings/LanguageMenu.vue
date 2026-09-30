<template>
  <div
    class="wc-lang-menu"
    role="dialog"
    :aria-label="$t('user.language.menu-label')"
    @keydown.esc.stop.prevent="$emit('close')"
    @keydown="onMenuKeydown"
  >
    <label class="wc-lang-menu__filter-row">
      <i class="fas fa-magnifying-glass wc-lang-menu__filter-icon" aria-hidden="true" />
      <input
        ref="filter"
        v-model="query"
        class="wc-lang-menu__filter"
        type="search"
        autocomplete="off"
        :placeholder="$t('user.language.filter')"
        :aria-label="$t('user.language.filter')"
        @keydown.down.prevent="focusFirstOption"
      />
    </label>

    <ul class="wc-lang-menu__list" role="listbox" :aria-label="$t('user.language.menu-label')">
      <li v-for="language in matches" :key="language.code" class="wc-lang-menu__row">
        <button
          type="button"
          class="wc-lang-menu__option"
          :class="{ 'is-active': language.code === active }"
          role="option"
          :aria-selected="language.code === active ? 'true' : 'false'"
          :data-code="language.code"
          @click="$emit('select', language.code)"
        >
          <!-- Flags on the left, the language in its own characters and
               spelling, its English name beneath (design.md D-6.2). -->
          <LanguageFlag :code="language.code" :size="20" class="wc-lang-menu__flag" />
          <span class="wc-lang-menu__names">
            <span class="wc-lang-menu__endonym">{{ language.name }}</span>
            <span v-if="language.englishName !== language.name" class="wc-lang-menu__english">
              {{ language.englishName }}
            </span>
          </span>
          <i
            v-if="language.code === active"
            class="fas fa-check wc-lang-menu__check"
            aria-hidden="true"
          />
        </button>
      </li>
    </ul>

    <p v-if="!matches.length" class="wc-lang-menu__empty">
      {{ $t('user.language.no-matches') }}
    </p>
  </div>
</template>

<script>
import LanguageFlag from '@/components/LanguageFlag.vue';
import { languages } from '@/utils/languages';

/**
 * The language menu. Design.md D-6.2.
 *
 * Every language is offered in its own characters and spelling, with its English
 * name beneath for a user who cannot read the endonym yet. A language the shell
 * cannot forward to any application is still offered — rule D-I10 says the shell
 * states what it could not do rather than hiding the choice.
 */
export default {
  name: 'LanguageMenu',
  components: { LanguageFlag },
  props: {
    active: { type: String, default: 'en' },
  },
  emits: ['select', 'close'],
  data() {
    return { query: '' };
  },
  computed: {
    matches() {
      const needle = this.query.trim().toLowerCase();
      if (!needle) return languages;
      return languages.filter((language) => [
        language.name, language.englishName, language.code,
      ].some((field) => field.toLowerCase().includes(needle)));
    },
  },
  methods: {
    onMenuKeydown(event) {
      if (!['ArrowDown', 'ArrowUp'].includes(event.key)) return;
      const options = this.options();
      if (!options.length) return;
      event.preventDefault();
      const index = options.indexOf(document.activeElement);
      const next = event.key === 'ArrowDown'
        ? options[(index + 1) % options.length]
        : options[(index - 1 + options.length) % options.length];
      next.focus();
    },
    options() {
      return Array.from(this.$el.querySelectorAll('.wc-lang-menu__option'));
    },
    focusFirstOption() {
      this.options()[0]?.focus();
    },
  },
};
</script>

<style lang="scss" scoped>
/* The user panel's surface, one size wider: this menu holds two text columns
   (design.md D-6.2). */
.wc-lang-menu {
  width: 22rem;
  max-height: 60vh;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  border: 1px solid var(--wc-border);
  border-radius: var(--wc-radius);
  background: var(--wc-surface-raised);
  color: var(--wc-text);
  box-shadow: var(--wc-shadow-popover);
}

.wc-lang-menu__filter-row {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.5rem 0.6rem;
  border-bottom: 1px solid var(--wc-border);
}

.wc-lang-menu__filter-icon {
  font-size: 0.7rem;
  color: var(--wc-text-muted);
}

.wc-lang-menu__filter {
  flex: 1 1 auto;
  min-width: 0;
  padding: 0.15rem 0;
  border: none;
  background: transparent;
  color: var(--wc-text);
  font: inherit;
  font-size: 0.78rem;

  &:focus-visible {
    outline: none;
  }

  &::placeholder {
    color: var(--wc-text-muted);
  }
}

.wc-lang-menu__list {
  flex: 1 1 auto;
  overflow-y: auto;
  margin: 0;
  padding: 0.3rem;
  list-style: none;
}

.wc-lang-menu__row {
  margin: 0;
}

.wc-lang-menu__option {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  width: 100%;
  padding: 0.4rem 0.45rem;
  border: none;
  border-radius: calc(var(--wc-radius) / 2);
  background: transparent;
  color: var(--wc-text);
  font: inherit;
  text-align: left;
  cursor: pointer;

  &:hover {
    background: var(--side-bar-background-lighter);
  }

  &:focus-visible {
    outline: 2px solid var(--wc-focus-ring);
    outline-offset: -2px;
  }

  &.is-active {
    background: var(--side-bar-item-background);
  }
}

.wc-lang-menu__flag {
  flex: 0 0 auto;
}

.wc-lang-menu__names {
  display: flex;
  flex-direction: column;
  flex: 1 1 auto;
  min-width: 0;
  line-height: 1.2;
}

.wc-lang-menu__endonym {
  font-size: 0.82rem;
}

.wc-lang-menu__english {
  font-size: 0.68rem;
  color: var(--wc-text-muted);
}

.wc-lang-menu__check {
  flex: 0 0 auto;
  font-size: 0.7rem;
  color: var(--wc-accent-files);
}

.wc-lang-menu__empty {
  margin: 0;
  padding: 0.8rem 0.6rem;
  font-size: 0.75rem;
  color: var(--wc-text-muted);
}
</style>
