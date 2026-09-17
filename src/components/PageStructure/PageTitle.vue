<template>
  <router-link to="/" class="page-titles">
    <!-- Optional page logo image -->
    <img v-if="logo" :src="logo" class="site-logo" />
    <!-- Page heading and sub-heading -->
    <div class="text">
      <h1>{{ title }}</h1>
      <span class="subtitle">{{ description }}</span>
    </div>
  </router-link>
</template>

<script>
export default {
  name: 'PageTitle',
  props: {
    title: { type: String, default: '' },
    description: { type: String, default: '' },
    logo: { type: String, default: '' },
  },
};
</script>

<style scoped lang="scss">
@import '@/styles/media-queries.scss';

.page-titles {
  display: flex;
  flex-direction: row;
  align-items: center;
  min-width: 0;
  overflow: hidden;
  text-decoration: none;
  position: relative;
  .text { min-width: 0; }
  h1 {
    color: var(--heading-text-color);
    font-size: clamp(1.4rem, 0.5rem + 3vw, 2.5rem);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    margin: 0;
  }
  span.subtitle {
    color: var(--heading-text-color);
    font-style: italic;
    text-shadow: 1px 1px 2px #130f2347;
    opacity: var(--dimming-factor);
  }
  img.site-logo {
    margin: 0.2rem 0.5rem 0.2rem 0;
    max-width: 3.5rem;
    height: fit-content;
  }
  @include phone {
    flex-direction: column;
    text-align: center;
    padding: 0.25rem 0;
  }
}
</style>
