<template>
  <div class="wc-pane-host">
    <!--
      Every pane is rendered from the start and stays mounted for the life of the
      shell. Switching applications toggles visibility, so a half-written message
      or a scrolled file list is exactly where it was. Design.md D-7 and U-4.
    -->
    <AppPane
      v-for="app in apps"
      :key="app.id"
      :app="app"
      :url="urls[app.id] || ''"
      :isActive="app.id === activeId"
    />
  </div>
</template>

<script>
import AppPane from '@/components/Panes/AppPane.vue';
import { APP_LIST } from '@/utils/apps/registry';

export default {
  name: 'PaneHost',
  props: {
    activeId: { type: String, default: '' },
    /* Application id to configured URL, from utils/apps/urls. */
    urls: { type: Object, default: () => ({}) },
  },
  components: {
    AppPane,
  },
  data() {
    return {
      apps: APP_LIST,
    };
  },
};
</script>

<style lang="scss" scoped>
.wc-pane-host {
  position: relative;
  flex: 1 1 auto;
  min-width: 0;
  height: 100%;
}
</style>
