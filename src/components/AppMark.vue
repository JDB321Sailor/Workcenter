<template>
  <img
    v-if="src"
    class="wc-app-mark"
    :src="src"
    :alt="alt"
    :width="size"
    :height="size"
    :aria-hidden="decorative ? 'true' : undefined"
    :draggable="false"
  >
</template>

<script>
/**
 * An application's brand mark, rendered at its own colours.
 *
 * The marks are committed under `icons/` at the repository root and reached
 * through the `@icons` alias, so a missing file fails the build instead of
 * producing a broken image at runtime, and nothing is fetched from a
 * third-party CDN. A mark is never recoloured, tinted or masked: the active
 * state is carried by the underline, the label colour and `aria-current`.
 * Design.md D-2I.
 */
import filebrowserMark from '@icons/filebrowser-quantum.svg?url';
import zulipMark from '@icons/zulip.svg?url';
import mailcowMark from '@icons/mailcow.svg?url';
import sogoMark from '@icons/sogo.svg?url';
import onlyofficeMark from '@icons/onlyoffice.svg?url';
import traefikMark from '@icons/traefik.svg?url';
import authentikMark from '@icons/authentik.svg?url';

/* The single map from a registry `mark` key to the committed asset. */
const MARKS = Object.freeze({
  'filebrowser-quantum': filebrowserMark,
  zulip: zulipMark,
  mailcow: mailcowMark,
  sogo: sogoMark,
  onlyoffice: onlyofficeMark,
  traefik: traefikMark,
  authentik: authentikMark,
});

export default {
  name: 'AppMark',
  props: {
    /* The registry's mark key, for example `zulip`. */
    name: { type: String, required: true },
    /* Rendered size in pixels: 24 in the switcher, 20 in rows, 48 in panes. */
    size: { type: Number, default: 24 },
    /* A mark beside its own text label is decorative (design.md D-2I.6). */
    decorative: { type: Boolean, default: true },
    /* The accessible name when the mark is the only label. */
    label: { type: String, default: '' },
  },
  computed: {
    src() {
      return MARKS[this.name] || '';
    },
    alt() {
      if (this.decorative) return '';
      return this.label || this.name;
    },
  },
};
</script>

<style lang="scss" scoped>
.wc-app-mark {
  display: block;
  object-fit: contain;
  /* A mark keeps its own colours in both modes (design.md D-2I.7). */
  user-select: none;
}
</style>
