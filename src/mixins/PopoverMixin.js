/**
 * Popover behaviour for the shell's two menus. Design.md D-6.
 *
 * The user menu and the language menu are the same interaction: a trigger that
 * opens a panel, a click outside or `Esc` that closes it, arrow keys that move
 * through its controls, and focus that returns to the trigger on close. Writing
 * that twice would mean fixing it twice.
 *
 * The component supplies:
 *   - `triggerSelector` — how to find the trigger inside its own root, for focus
 *     restoration;
 *   - `firstItemSelector` — the control that takes focus when the panel opens.
 */
export default {
  data() {
    return {
      open: false,
    };
  },
  beforeUnmount() {
    document.removeEventListener('click', this.onPopoverDocumentClick);
  },
  methods: {
    togglePopover() {
      if (this.open) this.closePopover();
      else this.openPopover();
    },
    openPopover() {
      this.open = true;
      /* The listener is attached on the next tick, so the click that opened the
         panel does not immediately close it. */
      setTimeout(() => {
        document.addEventListener('click', this.onPopoverDocumentClick);
        this.focusFirstPopoverItem();
      }, 0);
    },
    closePopover() {
      if (!this.open) return;
      this.open = false;
      document.removeEventListener('click', this.onPopoverDocumentClick);
      this.$el.querySelector(this.triggerSelector)?.focus();
    },
    onPopoverDocumentClick(event) {
      if (!this.$el.contains(event.target)) this.closePopover();
    },
    /* Arrow keys traverse whatever controls the panel actually contains. */
    onPopoverKeydown(event) {
      if (!['ArrowDown', 'ArrowUp'].includes(event.key)) return;
      const items = this.popoverItems();
      if (!items.length) return;
      event.preventDefault();
      const index = items.indexOf(document.activeElement);
      const next = event.key === 'ArrowDown'
        ? items[(index + 1) % items.length]
        : items[(index - 1 + items.length) % items.length];
      next.focus();
    },
    popoverItems() {
      const selector = this.popoverItemSelector
        || 'a, button, input, [tabindex]:not([tabindex="-1"])';
      return Array.from(this.$el.querySelectorAll(`[data-popover] ${selector}`))
        .filter((el) => !el.disabled);
    },
    focusFirstPopoverItem() {
      const first = this.$el.querySelector(`[data-popover] ${this.firstItemSelector || 'button, input'}`);
      first?.focus();
    },
  },
};
