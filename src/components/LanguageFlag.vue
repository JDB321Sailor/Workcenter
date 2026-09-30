<template>
  <img
    v-if="source"
    class="wc-flag"
    :class="`wc-flag--${shape}`"
    :src="source"
    :width="size"
    :height="size"
    :alt="alt"
    :aria-hidden="decorative ? 'true' : undefined"
    loading="lazy"
    decoding="async"
  />
  <!-- A language with no country of its own keeps the registry's glyph rather
       than wearing someone else's flag (design.md D-6.2). -->
  <span
    v-else
    class="wc-flag wc-flag--glyph"
    :style="{ fontSize: `${Math.round(size * 0.8)}px` }"
    :aria-hidden="decorative ? 'true' : undefined"
    :role="decorative ? undefined : 'img'"
    :aria-label="decorative ? undefined : label"
  >{{ glyph }}</span>
</template>

<script>
import ae from '@icons/flags/ae.svg?url';
import az from '@icons/flags/az.svg?url';
import bd from '@icons/flags/bd.svg?url';
import bg from '@icons/flags/bg.svg?url';
import cn from '@icons/flags/cn.svg?url';
import cz from '@icons/flags/cz.svg?url';
import de from '@icons/flags/de.svg?url';
import dk from '@icons/flags/dk.svg?url';
import es from '@icons/flags/es.svg?url';
import fr from '@icons/flags/fr.svg?url';
import gb from '@icons/flags/gb.svg?url';
import gr from '@icons/flags/gr.svg?url';
import hu from '@icons/flags/hu.svg?url';
import india from '@icons/flags/in.svg?url';
import it from '@icons/flags/it.svg?url';
import jp from '@icons/flags/jp.svg?url';
import kg from '@icons/flags/kg.svg?url';
import kr from '@icons/flags/kr.svg?url';
import nl from '@icons/flags/nl.svg?url';
import no from '@icons/flags/no.svg?url';
import pl from '@icons/flags/pl.svg?url';
import pt from '@icons/flags/pt.svg?url';
import ro from '@icons/flags/ro.svg?url';
import ru from '@icons/flags/ru.svg?url';
import se from '@icons/flags/se.svg?url';
import si from '@icons/flags/si.svg?url';
import sk from '@icons/flags/sk.svg?url';
import tr from '@icons/flags/tr.svg?url';
import ua from '@icons/flags/ua.svg?url';
import { flagCode, getLanguage } from '@/utils/languages';

/**
 * The flag that stands for a language. Design.md D-6.2.
 *
 * Flags are committed square SVGs reached through the `@icons` alias, so a
 * missing flag is a build failure rather than a broken image at runtime
 * (D-2I.3) and nothing is fetched from a third-party CDN. Every import is
 * listed rather than globbed for exactly that reason: a glob would skip a file
 * that is not there without saying so.
 *
 * The shape is a CSS crop, never a distortion — `circle` crops the square to a
 * disc, `rounded` keeps the square with softened corners.
 */
const SOURCES = {
  ae, az, bd, bg, cn, cz, de, dk, es, fr, gb, gr, hu, in: india, it, jp, kg, kr, nl, no, pl, pt, ro, ru, se, si, sk, tr, ua,
};

export default {
  name: 'LanguageFlag',
  props: {
    /* A locale code from the registry (`en`, `de`, `zh-CN`). */
    code: { type: String, required: true },
    size: { type: Number, default: 18 },
    shape: { type: String, default: 'circle' }, // circle | rounded
    /* Decorative beside the language's own name; named when it stands alone. */
    decorative: { type: Boolean, default: true },
    label: { type: String, default: '' },
  },
  computed: {
    source() {
      const iso = flagCode(this.code);
      return iso ? SOURCES[iso] || null : null;
    },
    /* The registry's own glyph, for a language with no single flag. */
    glyph() {
      return getLanguage(this.code)?.flag || '🌐';
    },
    alt() {
      return this.decorative ? undefined : this.label;
    },
  },
};
</script>

<style lang="scss" scoped>
.wc-flag {
  flex: 0 0 auto;
  display: inline-block;
  object-fit: cover;
  background: var(--wc-surface);
}

.wc-flag--circle {
  border-radius: 50%;
}

.wc-flag--rounded {
  border-radius: 3px;
}

.wc-flag--glyph {
  line-height: 1;
  text-align: center;
}
</style>
