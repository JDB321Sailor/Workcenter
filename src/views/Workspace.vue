<template>
  <div class="work-space">
    <SideBar
      :sections="sections"
      :initUrl="getInitialUrl()"
      @launch-app="launchApp"
    />
    <PaneHost :url="url" />
  </div>
</template>

<script>
import HomeMixin from '@/mixins/HomeMixin';
import SideBar from '@/components/Workspace/SideBar';
import PaneHost from '@/components/Workspace/PaneHost';
import ErrorHandler from '@/utils/logging/ErrorHandler';
import { sanitizeUrl } from '@/utils/Sanitizer';

export default {
  name: 'Workspace',
  mixins: [HomeMixin],
  data: () => ({
    url: '',
  }),
  computed: {
    sections() {
      return this.$store.getters.sections;
    },
    appConfig() {
      return this.$store.getters.appConfig;
    },
  },
  components: {
    SideBar,
    PaneHost,
  },
  methods: {
    launchApp(options) {
      if (options.target === 'newtab') {
        window.open(options.url, '_blank');
      } else if (options.target === 'newwindow') {
        const { width, height } = window.screen;
        window.open(options.url, '_blank', `width=${width},height=${height},noopener,noreferrer`);
      } else if (options.target === 'clipboard') {
        if (navigator.clipboard) {
          navigator.clipboard.writeText(options.url);
          this.$toast.success(this.$t('context-menus.item.copied-toast'));
        } else {
          ErrorHandler('Clipboard access requires HTTPS. See: https://bit.ly/3N5WuAA');
          this.$toast.error('Unable to copy, see log');
        }
        return;
      } else {
        this.url = options.url;
      }
    },
    /* Returns a service URL, if set as a URL param, or if user has specified landing URL */
    getInitialUrl() {
      const route = this.$route;
      if (route.query && route.query.url) {
        return sanitizeUrl(decodeURI(route.query.url)) || undefined;
      } else if (this.appConfig.workspaceLandingUrl) {
        return this.appConfig.workspaceLandingUrl;
      }
      return undefined;
    },
  },
  mounted() {
    // Guarded icon injection from HomeMixin; never inject unconditionally.
    this.initiateFontAwesome();
    this.initiateMaterialDesignIcons();
    this.url = this.getInitialUrl();
  },
};

</script>

<style scoped lang="scss">
.work-space {
  min-height: fit-content;
}
</style>
