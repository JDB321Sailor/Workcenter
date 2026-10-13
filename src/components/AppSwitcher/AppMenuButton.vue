<template>
  <div class="wc-app-menu" @keydown.esc="close">
    <!--
      The trigger sits **under its own application's icon**, not in the pane.
      The pane is the application's own document, and a control drawn over it
      belonged to the shell while appearing to belong to the embedded page — it
      sat in the frame's top-right corner, where an application's own toolbar
      lives, and every application rendered underneath it. Here it is
      unambiguously part of the switcher: one row, one application, one menu.
    -->
    <button
      ref="trigger"
      type="button"
      class="wc-app-menu__trigger"
      :aria-label="$t('switcher.menu.label', { app: app.name })"
      :title="$t('switcher.menu.label', { app: app.name })"
      aria-haspopup="menu"
      :aria-expanded="open ? 'true' : 'false'"
      :disabled="!url"
      @click="toggle"
      @keydown.down.prevent="openMenu"
    >
      <!--
        Three dots, drawn rather than set in an icon font. Font Awesome is a
        network dependency (a kit loaded from kit.fontawesome.com), and this is a
        control's *only* affordance: with the kit unreachable the trigger would
        render as an empty button and the menu would be unreachable, which is a
        worse failure than a missing decoration. The menu items keep the font —
        they are decoration beside a label.
      -->
      <span class="wc-app-menu__dots" aria-hidden="true">
        <span /><span /><span />
      </span>
    </button>

    <!--
      Teleported to `body`, and this is not a stylistic choice. The rail is
      `overflow: hidden` and 16rem wide, while the menu is 13rem wide starting at
      the dots — so for the right-hand application the menu ran past the rail's
      edge and was **clipped**: the part that fitted drew over the pane, and the
      rest was simply missing. A larger `z-index` cannot fix that, because
      clipping is not a stacking problem and a popover inside a clipping ancestor
      can never escape it. At the body it is subject to neither that nor the
      rail's own stacking context, and it is positioned from the trigger's box so
      it still opens upward from the dots that were clicked.
    -->
    <Teleport to="body">
      <div
        v-if="open"
        ref="menu"
        class="wc-app-menu__list"
        role="menu"
        :aria-label="$t('switcher.menu.label', { app: app.name })"
        :style="menuStyle"
        @keydown="onMenuKeydown"
      >
      <!--
        Reversed, because the menu opens **upward**: the item nearest the dots is
        the one the hand reaches for last, so Reload sits at the bottom — closest
        to the trigger — and the least-used entry is furthest away.
      -->
      <button
        v-if="isAdmin"
        type="button"
        class="wc-app-menu__item"
        role="menuitem"
        @click="run('health')"
      >
        <i class="fas fa-stethoscope" aria-hidden="true" />
        {{ $t('switcher.menu.health') }}
      </button>

      <button type="button" class="wc-app-menu__item" role="menuitem" @click="run('copy')">
        <i class="fas fa-link" aria-hidden="true" />
        {{ $t('switcher.menu.copy') }}
      </button>

      <a
        class="wc-app-menu__item"
        role="menuitem"
        :href="url"
        target="_blank"
        rel="noopener noreferrer"
      >
        <i class="fas fa-arrow-up-right-from-square" aria-hidden="true" />
        {{ $t('switcher.menu.open') }}
      </a>

      <button type="button" class="wc-app-menu__item" role="menuitem" @click="run('reload')">
        <i class="fas fa-rotate-right" aria-hidden="true" />
        {{ $t('switcher.menu.reload') }}
      </button>
      </div>
    </Teleport>
  </div>
</template>

<script>
import { isUserAdmin } from '@/utils/auth/Auth';
import ErrorHandler from '@/utils/logging/ErrorHandler';

/**
 * One application's menu, in the switcher.
 *
 * This is the escape hatch that means a user is never trapped by an application
 * that misbehaves inside a frame (design.md D-7): reload it, leave it for a real
 * tab, copy where it is, or ask what its health check last said. It is a
 * disclosure, not a route — it closes on Escape, returns focus to its trigger,
 * and every item is reachable by keyboard.
 *
 * It lives here rather than in the pane because the pane is the application's
 * own document. A control positioned over it is drawn in the same corner an
 * application puts its own toolbar, so it read as part of the page and covered
 * it. Moving it to the switcher was a move, not a hide: the floating control was
 * removed outright.
 */
export default {
  name: 'AppMenuButton',
  props: {
    app: { type: Object, required: true },
    /* The application's configured address. Empty disables the menu: there is
       nothing to reload, open or copy. */
    url: { type: String, default: '' },
  },
  emits: ['reload', 'show-health'],
  data() {
    return {
      open: false,
      /* Three 3px dots and two 2px gaps. In `data`, not a root option: Vue 3 does
         not expose custom options on `this`, and reading it from an option made
         the menu's computed `left` a `NaN` that silently vanished — the menu then
         opened with no horizontal anchor at all. Kept in step with the stylesheet
         by the component's tests. */
      dotsWidth: 13,
      /* The teleported menu's viewport position, measured from the trigger when
         it opens. `null` until then; the menu is not rendered before that. */
      position: null,
    };
  },
  computed: {
    isAdmin() {
      return isUserAdmin();
    },
    /* Anchored upward from the dots and left-aligned to the leftmost one, which
       is what the trigger's own box gives: the dots are centred inside it and are
       `--wc-dots-width` wide. `bottom` is measured from the viewport's bottom
       edge, the way `position: fixed` reads it, so the menu grows upward. */
    menuStyle() {
      if (!this.position) return {};
      return {
        left: `${this.position.left}px`,
        bottom: `${this.position.bottom}px`,
      };
    },
  },
  beforeUnmount() {
    this.unbind();
  },
  methods: {
    toggle() {
      if (this.open) this.close();
      else this.openMenu();
    },
    openMenu() {
      if (!this.url) return;
      this.measure();
      this.open = true;
      // A click anywhere else closes the menu, as a popover should. A scroll or a
      // resize **moves** it rather than closing it: the menu is positioned from
      // the trigger's viewport box, so it would otherwise point at nothing — but
      // closing on any scroll anywhere in the shell made it vanish on the way
      // open, which is worse than the problem it solved.
      setTimeout(() => {
        document.addEventListener('click', this.onDocumentClick);
        window.addEventListener('scroll', this.onViewportChange, true);
        window.addEventListener('resize', this.onViewportChange);
      }, 0);
    },
    onViewportChange() {
      if (this.open) this.measure();
    },
    /* Where the dots are, in viewport coordinates. */
    measure() {
      const trigger = this.$refs.trigger;
      if (!trigger) return;
      const box = trigger.getBoundingClientRect();
      const dots = this.dotsWidth;
      this.position = {
        left: box.left + (box.width - dots) / 2,
        bottom: window.innerHeight - (box.top + box.height / 2) + 4,
      };
    },
    close() {
      if (!this.open) return;
      this.open = false;
      this.unbind();
      this.$refs.trigger?.focus();
    },
    unbind() {
      document.removeEventListener('click', this.onDocumentClick);
      window.removeEventListener('scroll', this.onViewportChange, true);
      window.removeEventListener('resize', this.onViewportChange);
    },
    /* The menu is at the body, so it is no longer inside `$el`: a click inside it
       is not a click outside the control. */
    onDocumentClick(event) {
      if (this.$el.contains(event.target)) return;
      if (this.$refs.menu?.contains(event.target)) return;
      this.close();
    },
    /* Up and Down traverse the menu items; Escape closes and restores focus. The
       items are in the teleported menu, not in this component's own element. */
    onMenuKeydown(event) {
      const items = Array.from(this.$refs.menu?.querySelectorAll('.wc-app-menu__item') || []);
      if (!items.length) return;
      const index = items.indexOf(document.activeElement);
      if (event.key === 'ArrowDown') {
        event.preventDefault();
        items[(index + 1) % items.length].focus();
      }
      if (event.key === 'ArrowUp') {
        event.preventDefault();
        items[(index - 1 + items.length) % items.length].focus();
      }
      if (event.key === 'Home') {
        event.preventDefault();
        items[0].focus();
      }
      if (event.key === 'End') {
        event.preventDefault();
        items[items.length - 1].focus();
      }
    },
    async run(action) {
      if (action === 'reload') {
        this.close();
        this.$emit('reload', this.app.id);
        return;
      }
      if (action === 'health') {
        this.close();
        this.$emit('show-health', this.app.id);
        return;
      }
      if (action === 'copy') {
        await this.copyLink();
      }
    },
    /* Copying is a courtesy: a refused clipboard is reported, never silent. */
    async copyLink() {
      try {
        await navigator.clipboard.writeText(this.url);
        this.$toast.success(this.$t('switcher.menu.copied'));
      } catch (e) {
        ErrorHandler(`[switcher] could not copy the ${this.app.name} link`, e);
        this.$toast.error(this.$t('switcher.menu.copy-failed'));
      }
      this.close();
    },
  },
};
</script>

<style lang="scss" scoped>
.wc-app-menu {
  position: relative;
  flex: 1 1 0;
  display: flex;
  justify-content: center;
}

.wc-app-menu__trigger {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  height: 0.95rem;
  padding: 0;
  border: none;
  background: transparent;
  color: var(--wc-text-muted);
  line-height: 1;
  cursor: pointer;
  opacity: 0.55;
  transition: opacity 120ms ease;

  &:hover,
  &:focus-visible {
    opacity: 1;
  }

  &:focus-visible {
    outline: 2px solid var(--wc-focus-ring);
    outline-offset: 1px;
    border-radius: var(--wc-radius);
  }

  &:disabled {
    opacity: 0.2;
    cursor: default;
  }
}

/* Three dots in a row, centred, so the **middle** dot sits on the column's axis —
   directly beneath the status indicator above it. */
.wc-app-menu__dots {
  display: flex;
  flex-direction: row;
  align-items: center;
  gap: 2px;
}

.wc-app-menu__dots > span {
  width: 3px;
  height: 3px;
  border-radius: 50%;
  background: currentColor;
}

/* Fixed, because the menu is teleported to the body and positioned from the
   trigger's viewport box. It was `absolute` inside the rail, which is
   `overflow: hidden` — so anything past the rail's right edge was clipped away
   rather than drawn over the pane. */
.wc-app-menu__list {
  position: fixed;
  z-index: 60;
  min-width: 13rem;
  padding: 0.25rem;
  border: 1px solid var(--wc-border);
  border-radius: var(--wc-radius);
  background: var(--wc-surface-raised);
  box-shadow: var(--wc-shadow-popover);
}

.wc-app-menu__item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  width: 100%;
  padding: 0.4rem 0.5rem;
  border: none;
  border-radius: calc(var(--wc-radius) / 2);
  background: transparent;
  color: var(--wc-text);
  font: inherit;
  font-size: 0.8rem;
  text-align: left;
  text-decoration: none;
  cursor: pointer;

  &:hover {
    background: var(--side-bar-background-lighter);
  }

  &:focus-visible {
    outline: 2px solid var(--wc-focus-ring);
    outline-offset: -2px;
  }
}
</style>
