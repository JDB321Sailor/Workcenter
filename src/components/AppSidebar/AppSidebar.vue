<template>
  <nav class="wc-sidebar" :aria-label="$t('sidebar.label', { app: appName })">
    <!-- The active application's own navigator. -->
    <div class="wc-sidebar__body">
      <component :is="surface" v-if="surface" :app="app" :appConfig="appConfig" />
    </div>
  </nav>
</template>

<script>
import FilesSidebar from '@/components/AppSidebar/FilesSidebar.vue';
import ChatSidebar from '@/components/AppSidebar/ChatSidebar.vue';
import MailSidebar from '@/components/AppSidebar/MailSidebar.vue';
import { getApp } from '@/utils/apps/registry';

/* Which surface renders for each application's `sidebar` key. */
const SURFACES = {
  files: FilesSidebar,
  chat: ChatSidebar,
  mail: MailSidebar,
};

export default {
  name: 'AppSidebar',
  props: {
    activeId: { type: String, default: '' },
    appConfig: { type: Object, default: () => ({}) },
  },
  components: {
    FilesSidebar,
    ChatSidebar,
    MailSidebar,
  },
  computed: {
    app() {
      return getApp(this.activeId) || { name: '', sidebar: '' };
    },
    appName() {
      return this.app.name;
    },
    surface() {
      return SURFACES[this.app.sidebar] || null;
    },
  },
};
</script>

<style lang="scss" scoped>
@import '@/styles/style-helpers.scss';

.wc-sidebar {
  flex: 1 1 auto;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background: var(--side-bar-background);
  color: var(--side-bar-color);
}

.wc-sidebar__body {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
  @extend .scroll-bar;
}
</style>
