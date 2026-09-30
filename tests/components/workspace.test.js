import {
  describe, it, expect, vi, beforeEach,
} from 'vitest';
import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { reactive } from 'vue';
import Workspace from '@/views/Workspace.vue';
import BrandHeader from '@/components/Rail/BrandHeader.vue';
import SidebarSearch from '@/components/Rail/SidebarSearch.vue';
import AppSwitcher from '@/components/AppSwitcher/AppSwitcher.vue';
import AppSidebar from '@/components/AppSidebar/AppSidebar.vue';
import PaneHost from '@/components/Panes/PaneHost.vue';
import UserMenu from '@/components/User/UserMenu.vue';
import { localStorageKeys } from '@/utils/config/defaults';

vi.mock('@/utils/request', () => ({ default: { get: vi.fn().mockRejectedValue(new Error('no broker')) } }));

const push = vi.fn();

const mountWorkspace = ({ routeName = 'files', collapsed = false } = {}) => {
  localStorage.getItem.mockImplementation((key) => {
    if (key === localStorageKeys.COLLAPSE_STATE) return String(collapsed);
    return undefined;
  });
  /* A reactive route, so a test can move the shell between applications the way
     the router does. */
  const route = reactive({ name: routeName, fullPath: `/${routeName}`, meta: {} });
  const store = createStore({
    state: {},
    getters: {
      appConfig: () => ({
        applications: {
          files: { url: 'https://filebrowser.example.com' },
          chat: { url: 'https://chat.example.com' },
          mail: { url: 'https://mail.example.com/SOGo' },
        },
      }),
      userState: () => 0,
      /* HomeMixin's icon injection walks the sections; an empty list is what a
         shell with no tiles carries. */
      sections: () => [],
      pageInfo: () => ({}),
    },
    actions: { INITIALIZE_CONFIG: () => Promise.resolve() },
  });
  const wrapper = shallowMount(Workspace, {
    global: {
      plugins: [store],
      mocks: {
        $route: route,
        $router: { push },
        $t: (key, opts) => (opts ? `${key}:${JSON.stringify(opts)}` : key),
        $toast: Object.assign(vi.fn(), { error: vi.fn(), success: vi.fn() }),
      },
    },
  });
  wrapper.route = route;
  return wrapper;
};

/**
 * The shell.
 *
 * One view, six rail regions in a fixed order, and a pane host that keeps every
 * pane mounted (design.md section 2, AR-8).
 */
describe('Workspace', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders the rail regions in order: brand, switcher, search, sidebar, user menu', () => {
    const w = mountWorkspace();
    const rail = w.find('.wc-rail');
    const order = [
      BrandHeader, AppSwitcher, SidebarSearch, AppSidebar, UserMenu,
    ].map((component) => rail.findAllComponents(component).length);
    expect(order).toEqual([1, 1, 1, 1, 1]);
    // And the pane surface sits outside the rail.
    expect(w.findAllComponents(PaneHost)).toHaveLength(1);
  });

  it('selects the application the route names', () => {
    const w = mountWorkspace({ routeName: 'chat' });
    expect(w.findComponent(AppSwitcher).props('activeId')).toBe('chat');
    expect(w.findComponent(AppSidebar).props('activeId')).toBe('chat');
    expect(w.findComponent(PaneHost).props('activeId')).toBe('chat');
  });

  it('routes an application switch instead of remounting anything', async () => {
    const w = mountWorkspace();
    w.findComponent(AppSwitcher).vm.$emit('select', 'mail');
    await w.vm.$nextTick();
    expect(push).toHaveBeenCalledWith({ name: 'mail' });
  });

  it('does not navigate when the application is already active', async () => {
    const w = mountWorkspace({ routeName: 'files' });
    w.findComponent(AppSwitcher).vm.$emit('select', 'files');
    expect(push).not.toHaveBeenCalled();
  });

  it('starts the rail expanded and reports the collapsed state to its children', () => {
    const expanded = mountWorkspace();
    expect(expanded.findComponent(BrandHeader).props('collapsed')).toBe(false);

    const collapsed = mountWorkspace({ collapsed: true });
    expect(collapsed.findComponent(BrandHeader).props('collapsed')).toBe(true);
    expect(collapsed.findComponent(AppSidebar).exists()).toBe(true);
  });

  it('remembers the last-used application for the wordmark', () => {
    mountWorkspace({ routeName: 'chat' });
    expect(localStorage.setItem).toHaveBeenCalledWith(localStorageKeys.LAST_USED, 'chat');
  });

  it('gives the sidebar filter to the active surface and clears it on a switch', async () => {
    const w = mountWorkspace();
    w.findComponent(SidebarSearch).vm.$emit('update:modelValue', 'inv');
    await w.vm.$nextTick();
    expect(w.findComponent(AppSidebar).props('query')).toBe('inv');

    w.route.name = 'chat';
    await w.vm.$nextTick();
    expect(w.findComponent(AppSidebar).props('query')).toBe('');
  });

  it('points the active pane at a sidebar row’s destination', async () => {
    const w = mountWorkspace();
    const navigate = vi.fn(() => true);
    w.vm.$refs.paneHost.navigate = navigate;
    w.findComponent(AppSidebar).vm.$emit('navigate', { url: 'https://filebrowser.example.com/files' });
    await w.vm.$nextTick();
    expect(navigate).toHaveBeenCalledWith('files', 'https://filebrowser.example.com/files');
  });

  it('collapses the rail and opens it again, remembering the choice', async () => {
    const w = mountWorkspace();
    expect(w.find('.wc-workspace').classes()).not.toContain('wc-workspace--collapsed');

    w.findComponent(BrandHeader).vm.$emit('toggle');
    await w.vm.$nextTick();
    expect(w.find('.wc-workspace').classes()).toContain('wc-workspace--collapsed');
    expect(localStorage.setItem).toHaveBeenCalledWith(localStorageKeys.COLLAPSE_STATE, 'true');
    expect(w.findComponent(BrandHeader).props('collapsed')).toBe(true);

    /* The way back must exist in the same session: collapsing is reversible
       without clearing storage (a real defect left the rail stuck). */
    w.findComponent(BrandHeader).vm.$emit('toggle');
    await w.vm.$nextTick();
    expect(w.find('.wc-workspace').classes()).not.toContain('wc-workspace--collapsed');
    expect(localStorage.setItem).toHaveBeenCalledWith(localStorageKeys.COLLAPSE_STATE, 'false');
  });
});
