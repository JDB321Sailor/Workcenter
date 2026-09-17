<template>
  <nav class="side-bar">
    <div v-for="(section, index) in filteredSections" :key="index" class="side-bar-section">
      <!-- Section button -->
      <div @click="openSection(index)" class="side-bar-item-container">
        <SideBarItem
          class="item"
          :icon="section.icon"
          :title="section.name"
        />
      </div>
      <!-- Section inner -->
      <transition name="slide">
        <SideBarSection
          v-if="isOpen[index]"
          :items="visibleItems(section.items)"
          @launch-app="launchApp"
        />
      </transition>
    </div>
  </nav>
</template>

<script>

import SideBarItem from '@/components/Workspace/SideBarItem.vue';
import SideBarSection from '@/components/Workspace/SideBarSection.vue';
import { getCurrentUser, isLoggedInAsGuest } from '@/utils/auth/Auth';
import { isVisibleToUser } from '@/utils/IsVisibleToUser';

export default {
  name: 'SideBar',
  props: {
    sections: { type: Array, default: () => [] },
    initUrl: { type: String, default: '' },
  },
  emits: ['launch-app'],
  data() {
    return {
      isOpen: [],
    };
  },
  computed: {
    /* Return a list of sections that should be visible in the workspace */
    filteredSections() {
      if (!this.sections) return [];
      return this.sections.filter((section) => !section.displayData?.hideFromWorkspace);
    },
  },
  watch: {
    /* Update isOpen array when filtered sections change */
    filteredSections(newSections) {
      const newLength = newSections.length;
      if (newLength !== this.isOpen.length) {
        this.isOpen = new Array(newLength).fill(false);
      }
    },
  },
  components: {
    SideBarItem,
    SideBarSection,
  },
  methods: {
    /* Toggles the section clicked, and closes all other sections */
    openSection(index) {
      this.isOpen = this.isOpen.map((val, ind) => (ind !== index ? false : !val));
    },
    /* When item clicked, emit a launch event */
    launchApp(options) {
      this.$emit('launch-app', options);
    },
    /* If an initial URL is specified, then open the matching section */
    openDefaultSection() {
      if (!this.initUrl) return;
      const process = (url) => (url ? url.replace(/[^\w\s]/gi, '').toLowerCase() : undefined);
      const compare = (item) => (process(item.url) === process(this.initUrl));
      this.filteredSections.forEach((section, secIndx) => {
        if (!section.items) return;
        if (section.items.findIndex(compare) !== -1) this.openSection(secIndx);
        section.items.forEach((item) => {
          if (item.subItems && item.subItems.findIndex(compare) !== -1) this.openSection(secIndx);
        });
      });
    },
    /* Return the items in a section that the current user/guest can see
     * and that aren't explicitly hidden from the workspace view */
    visibleItems(allTiles) {
      if (!allTiles) return [];
      const currentUser = getCurrentUser();
      const isGuest = isLoggedInAsGuest();
      return allTiles.filter((tile) => !tile.displayData?.hideFromWorkspace
        && isVisibleToUser(tile.displayData || {}, currentUser, isGuest));
    },
  },
  mounted() {
    this.isOpen = new Array(this.filteredSections.length).fill(false);
    if (this.filteredSections.length === 1) { // If only 1 section, open it
      this.openSection(0);
    } else { // Otherwise, see if the user set a default section, and open that
      this.openDefaultSection();
    }
  },
};
</script>

<style lang="scss" scoped>

@import '@/styles/media-queries.scss';
@import '@/styles/style-helpers.scss';

nav.side-bar {
  position: fixed;
  display: flex;
  flex-direction: column;
  background: var(--side-bar-background);
  color: var(--side-bar-color);
  height: 100%;
  width: var(--side-bar-width);
  text-align: center;
  overflow: auto;
  @extend .scroll-bar;
  .side-bar-item-container {
    z-index: 5;
  }
  .item:not(:last-child) {
    border-bottom: 1px dashed var(--side-bar-color);
    z-index: 5;
  }
}

.slide-leave-active,
.slide-enter-active {
  transition: all 0.1s ease-in-out;
}
.slide-enter-from {
  transform: translate(0, -80%);
}
.slide-leave-to {
  transform: translate(0, -80%);
}

</style>
