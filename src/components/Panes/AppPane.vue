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
    <!-- Once the frame has loaded, it stays mounted: switching applications
         toggles visibility only, so scroll position, drafts and sessions
         survive. Design.md D-7. -->
    <iframe
      v-show="state === 'ready'"
      ref="frame"
      class="wc-pane__frame"
      :src="url"
      :title="app.name"
      allow="fullscreen; clipboard-read; clipboard-write"
      referrerpolicy="same-origin"
      @load="onLoad"
      @error="onError"
    />

    <!-- Loading: only while the frame has never settled. -->
    <div v-if="state === 'loading'" class="wc-pane__loading">
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
      :detail="detail"
      :url="url"
      @retry="retry"
    />
  </div>
</template>

<script>
import PaneErrorCard from '@/components/Panes/PaneErrorCard.vue';
import HealthService, { HEALTH } from '@/utils/health/HealthService';

export default {
  name: 'AppPane',
  props: {
    app: { type: Object, required: true },
    /* The application's address. Empty means it is not configured. */
    url: { type: String, default: '' },
    isActive: { type: Boolean, default: false },
  },
  components: {
    PaneErrorCard,
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
    health() {
      return HealthService.forApp(this.app.id);
    },
  },
  watch: {
    /* The application's address changed: load it again from scratch. */
    url(next, previous) {
      if (next === previous) return;
      this.reset();
      if (this.isActive && next) this.beginLoad();
    },
    isActive(active) {
      if (active && this.state === 'idle' && this.url) this.beginLoad();
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
  },
  beforeUnmount() {
    this.clearTimers();
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

.wc-pane__spinner {
  width: 1.75rem;
  height: 1.75rem;
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
