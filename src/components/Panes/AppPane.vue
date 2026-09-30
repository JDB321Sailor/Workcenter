<template>
  <div
    class="wc-pane"
    :class="{ 'wc-pane--hidden': !isActive }"
    :id="`wc-pane-${app.id}`"
    role="tabpanel"
    :aria-labelledby="`wc-tab-${app.id}`"
    :hidden="!isActive"
    :data-pane-state="state"
  >
    <!-- A pane that has never been activated renders nothing: the frame is
         created on first activation, then kept mounted for the life of the
         shell, so switching toggles visibility only and scroll position, drafts
         and sessions survive. Design.md D-7, standards.md S-P-2. -->
    <iframe
      v-if="state !== 'idle'"
      v-show="state === 'ready'"
      ref="frame"
      class="wc-pane__frame"
      :src="targetUrl"
      :title="app.name"
      :data-pane-app="app.id"
      :data-pane-origin="origin"
      allow="fullscreen; clipboard-read; clipboard-write"
      referrerpolicy="same-origin"
      @load="onLoad"
      @error="onError"
    />

    <!-- Loading: only while the frame has never settled. -->
    <div v-if="state === 'loading'" class="wc-pane__loading">
      <AppMark class="wc-pane__loading-mark" :name="app.paneMark" :size="48" decorative />
      <span class="wc-pane__spinner" aria-hidden="true" />
      <p class="wc-pane__loading-title">{{ app.name }}</p>
      <p class="wc-pane__loading-host">{{ host }}</p>
      <p v-if="slow" class="wc-pane__loading-hint">{{ $t('pane.loading-hint') }}</p>
    </div>

    <!-- Anything that is not a successful load is explained, never blank. -->
    <PaneErrorCard
      v-if="state === 'error'"
      :reason="reason"
      :appName="app.name"
      :appMark="app.paneMark"
      :detail="detail"
      :url="url"
      @retry="retry"
    />

    <!-- The overflow menu is available in every state, including a failed one,
         so the user always has a way out. Design.md D-7. -->
    <PaneOverflowMenu
      :url="paneUrl"
      :appName="app.name"
      @reload="reloadPane"
      @show-health="showHealth = !showHealth"
    />

    <!-- Admin-only health detail, revealed from the overflow menu. -->
    <dl v-if="showHealth" class="wc-pane__health">
      <dt>{{ $t('status.tooltip.check') }}</dt>
      <dd>{{ health.check || $t('status.tooltip.never-checked') }}</dd>
      <dt>{{ healthStateLabel }}</dt>
      <dd>{{ health.endpoint || host }}</dd>
    </dl>
  </div>
</template>

<script>
import AppMark from '@/components/AppMark.vue';
import PaneErrorCard from '@/components/Panes/PaneErrorCard.vue';
import PaneOverflowMenu from '@/components/Panes/PaneOverflowMenu.vue';
import HealthService, { HEALTH } from '@/utils/health/HealthService';
import { registerPane } from '@/utils/Theming';
import { sanitizeUrl } from '@/utils/Sanitizer';
import ErrorHandler from '@/utils/logging/ErrorHandler';

/**
 * The URL signals that mean "the user has a document open in FileBrowser
 * Quantum's own editor".
 *
 * Verified against the pin: `frontend/src/router/index.ts` and
 * `frontend/src/store/getters.ts` expose the code editor as `#edit` and the
 * Markdown preview as `#preview`. The OnlyOffice editor is chosen from the
 * `onlyOfficeId` field of an API response and carries **no** URL marker, so a
 * host page cannot detect it from the reported navigation alone.
 */
const EDITOR_HASH_PATTERNS = [/#(?:edit|preview)$/];

export default {
  name: 'AppPane',
  props: {
    app: { type: Object, required: true },
    /* The application's address. Empty means it is not configured. */
    url: { type: String, default: '' },
    isActive: { type: Boolean, default: false },
  },
  components: {
    AppMark,
    PaneErrorCard,
    PaneOverflowMenu,
  },
  data() {
    return {
      /* idle | loading | ready | error */
      state: 'idle',
      /* unavailable | blocked | auth-error | timeout */
      reason: 'unavailable',
      detail: '',
      /* Set after the frame has been slow, so the hint appears only then. */
      slow: false,
      slowTimer: null,
      loadTimer: null,
      /* The path the embedded application last reported, used to restore the
         user's place when the pane has to be reloaded (design.md D-T6). */
      panePath: '',
      /* True while the pane is in a document editor, which defers a reload
         (design.md D-T7). */
      editorOpen: false,
      /* The admin-only health detail panel. */
      showHealth: false,
      /* What the frame is pointed at: the configured address, or a sidebar
         row's deep link once the user picks one. */
      targetUrl: this.url,
      /* Set by the bridge registration, called on unmount. */
      unregisterPane: null,
    };
  },
  computed: {
    host() {
      try {
        return new URL(this.url).host;
      } catch {
        return this.url;
      }
    },
    /* The address the pane is actually showing. FileBrowser Quantum reports a
       path (`to.fullPath`), not an absolute URL, so the reported path is
       resolved against the pane's origin before it is reused. */
    paneUrl() {
      if (!this.panePath) return this.url;
      if (this.panePath.startsWith('http')) return this.panePath;
      if (!this.origin || !this.panePath.startsWith('/')) return this.url;
      return `${this.origin}${this.panePath}`;
    },
    /* The pane's own origin, for the message check (design.md D-T8). */
    origin() {
      try {
        return new URL(this.url).origin;
      } catch {
        return '';
      }
    },
    health() {
      return HealthService.forApp(this.app.id);
    },
    /* Spelled out rather than built from the state string, so the locale
       checker can prove every key exists. */
    healthStateLabel() {
      const labels = {
        healthy: this.$t('status.state.healthy'),
        degraded: this.$t('status.state.degraded'),
        unhealthy: this.$t('status.state.unhealthy'),
        unknown: this.$t('status.state.unknown'),
      };
      return labels[this.health.state] || labels.unknown;
    },
  },
  watch: {
    /* The application's address changed: load it again from scratch. */
    url(next, previous) {
      if (next === previous) return;
      this.targetUrl = next;
      this.panePath = '';
      this.reset();
      if (this.isActive && next) this.beginLoad();
    },
    isActive(active) {
      if (active && this.state === 'idle' && this.url) this.beginLoad();
    },
    /* The health check knows things the frame cannot tell us across origins:
       whether the application refuses to be framed, and whether its session has
       expired. Surface it instead of showing a blank frame (design.md D-7.1). */
    health: {
      deep: true,
      handler(entry) {
        if (!this.isActive || this.state === 'idle') return;
        if (entry?.frameBlocked && this.state !== 'error') {
          this.fail('blocked');
        } else if (entry?.authError && this.state !== 'error') {
          this.fail('auth-error');
        }
      },
    },
  },
  mounted() {
    // A pane loads when it is first shown, not before: three frames loading at
    // once on start-up would compete for the same connection.
    if (this.isActive) {
      if (this.url) this.beginLoad();
      else this.fail('unavailable');
    } else if (!this.url) {
      this.state = 'idle';
    }
    window.addEventListener('message', this.onPaneMessage);
    // The shell's bridge needs the pane's origin, its window and a way to
    // reload it; the pane never talks to the application itself.
    this.unregisterPane = registerPane(this.app.id, {
      origin: this.origin,
      getWindow: () => this.$refs.frame?.contentWindow || null,
      refresh: () => this.refreshAtReportedPath(),
    });
  },
  beforeUnmount() {
    this.clearTimers();
    window.removeEventListener('message', this.onPaneMessage);
    if (this.unregisterPane) this.unregisterPane();
  },
  methods: {
    clearTimers() {
      if (this.slowTimer) clearTimeout(this.slowTimer);
      if (this.loadTimer) clearTimeout(this.loadTimer);
      this.slowTimer = null;
      this.loadTimer = null;
    },
    reset() {
      this.clearTimers();
      this.state = 'idle';
      this.reason = 'unavailable';
      this.detail = '';
      this.slow = false;
    },
    beginLoad() {
      this.clearTimers();
      this.state = 'loading';
      this.reason = 'unavailable';
      this.detail = '';
      this.slow = false;
      // A known framing refusal or an expired session is worth reporting before
      // waiting on a frame that cannot succeed (design.md D-7.1).
      if (this.health.frameBlocked) {
        this.fail('blocked');
        return;
      }
      if (this.health.authError) {
        this.fail('auth-error');
        return;
      }
      this.slowTimer = setTimeout(() => { this.slow = true; }, 5000);
      // A frame that never fires load is reported rather than spinning forever.
      this.loadTimer = setTimeout(() => this.fail('timeout'), 30000);
    },
    onLoad() {
      this.clearTimers();
      this.slow = false;
      this.state = 'ready';
    },
    onError() {
      this.fail('unavailable');
    },
    fail(reason, detail = '') {
      this.clearTimers();
      this.state = 'error';
      this.reason = reason;
      this.detail = detail || this.healthDetail();
    },
    /* A failing healthcheck supplies the reason shown on the card. */
    healthDetail() {
      const { state, check } = this.health;
      if (state === HEALTH.UNHEALTHY || state === HEALTH.DEGRADED) {
        return check || this.$t('pane.reason.unavailable.check-failed');
      }
      return '';
    },
    retry() {
      this.reset();
      this.beginLoad();
      // Reload the frame by reassigning its source.
      const frame = this.$refs.frame;
      if (frame) frame.src = this.url;
    },
    /* Navigate the pane to one of the application's own deep links, from a
       sidebar row. The application parses its own URL on load, so this is the
       shell's only way to reach a view inside a cross-origin frame. */
    navigateTo(target) {
      const url = sanitizeUrl(target);
      if (!url) {
        ErrorHandler(`[pane] refusing to navigate ${this.app.id} to an unusable address`);
        return false;
      }
      this.panePath = '';
      this.editorOpen = false;
      this.reset();
      this.targetUrl = url;
      this.beginLoad();
      return true;
    },
    /* Reload the pane from the overflow menu, restoring the path the embedded
       application last reported so the user lands where they were. */
    reloadPane() {
      if (!this.url) return;
      this.reset();
      this.beginLoad();
      this.$nextTick(() => {
        const frame = this.$refs.frame;
        if (frame) frame.src = this.paneUrl;
      });
    },
    /**
     * Listen to what an embedded application reports about itself.
     *
     * Only the exact pane origin is trusted, and only the one message the
     * application is documented to send is read. Nothing here carries a token,
     * a credential or user data (design.md D-T8).
     */
    onPaneMessage(event) {
      if (!this.origin || event.origin !== this.origin) return;
      if (this.$refs.frame && event.source !== this.$refs.frame.contentWindow) return;
      const data = event.data;
      if (!data || data.type !== 'filebrowser:navigation' || typeof data.url !== 'string') return;
      this.panePath = data.url;
      this.editorOpen = this.looksLikeEditor(data.url);
    },
    /* A document editor is open when the reported path carries one of the
       application's editor markers. */
    looksLikeEditor(pathname) {
      return EDITOR_HASH_PATTERNS.some((pattern) => pattern.test(pathname));
    },
    /* Reload the pane at the path it reported, unless an editor is open
       (design.md D-T7). Returns true when the reload happened. */
    refreshAtReportedPath() {
      if (this.editorOpen) return false;
      this.reloadPane();
      return true;
    },
    /* Hand keyboard focus to the embedded application. The switcher's status
       indicator uses this for a healthy pane (design.md D-2S). */
    focus() {
      this.$refs.frame?.focus();
    },
  },
};
</script>

<style lang="scss" scoped>
.wc-pane {
  position: absolute;
  inset: 0 0 0 var(--side-bar-width);
  height: calc(100% - var(--header-height));
  background: var(--workspace-web-content-background);
}

.wc-pane--hidden {
  display: none;
}

.wc-pane__frame {
  width: 100%;
  height: 100%;
  border: none;
  background: var(--workspace-web-content-background);
}

/* Admin-only health detail, revealed from the pane's overflow menu. */
.wc-pane__health {
  position: absolute;
  top: 0.5rem;
  right: 3rem;
  margin: 0;
  padding: 0.5rem 0.7rem;
  border: 1px solid var(--wc-border);
  border-radius: var(--wc-radius);
  background: var(--wc-surface-raised);
  box-shadow: var(--wc-shadow-popover);
  font-size: 0.75rem;

  dt {
    color: var(--wc-text-muted);
  }

  dd {
    margin: 0 0 0.35rem;
  }
}

.wc-pane__loading {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.4rem;
  background: var(--wc-surface);
  color: var(--wc-text);
}

.wc-pane__loading-mark {
  margin-bottom: 0.6rem;
}

.wc-pane__spinner {
  width: 1.5rem;
  height: 1.5rem;
  margin-bottom: 0.4rem;
  border: 3px solid var(--wc-border);
  border-top-color: var(--wc-focus-ring);
  border-radius: 50%;
  animation: wc-spin 0.9s linear infinite;
}

@keyframes wc-spin {
  to { transform: rotate(360deg); }
}

@media (prefers-reduced-motion: reduce) {
  .wc-pane__spinner { animation: none; }
}

.wc-pane__loading-title {
  margin: 0;
  font-size: 1rem;
}

.wc-pane__loading-host {
  margin: 0;
  font-size: 0.8rem;
  opacity: 0.7;
}

.wc-pane__loading-hint {
  margin: 0.6rem 0 0;
  max-width: 30rem;
  text-align: center;
  font-size: 0.78rem;
  opacity: 0.7;
}
</style>
