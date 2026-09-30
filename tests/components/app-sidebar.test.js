import {
  describe, it, expect, beforeEach, vi,
} from 'vitest';
import { shallowMount, mount } from '@vue/test-utils';
import AppSidebar from '@/components/AppSidebar/AppSidebar.vue';
import FilesSidebar from '@/components/AppSidebar/FilesSidebar.vue';
import ChatSidebar from '@/components/AppSidebar/ChatSidebar.vue';
import MailSidebar from '@/components/AppSidebar/MailSidebar.vue';
import SidebarItem from '@/components/AppSidebar/SidebarItem.vue';
import SidebarGroup from '@/components/AppSidebar/SidebarGroup.vue';
import { getApp } from '@/utils/apps/registry';

/* The mail navigator reads the signed-in mailbox; the real Auth module pulls in
   the whole config pipeline, which a component test does not need. */
vi.mock('@/utils/auth/Auth', () => ({
  getUserProfile: () => ({
    username: 'jane@example.com',
    displayName: 'Jane Doe',
    email: 'jane@example.com',
    groups: ['workspaceusers'],
    isAdmin: false,
  }),
  isUserAdmin: () => false,
  isLoggedIn: () => true,
  isLoggedInAsGuest: () => false,
  isAuthEnabled: () => true,
  getLogoutRedirectUrl: () => null,
  logout: vi.fn(),
}));

const appConfig = {
  applications: {
    files: { url: 'https://filebrowser.example.com' },
    chat: { url: 'https://chat.example.com' },
    mail: { url: 'https://mail.example.com/SOGo' },
  },
};

const mountSurface = (component, { query = '' } = {}) => shallowMount(component, {
  props: { app: getApp(component === FilesSidebar ? 'files' : component === ChatSidebar ? 'chat' : 'mail'), appConfig, query },
  global: {
    mocks: {
      $t: (key, opts) => (opts ? `${key}` : key),
      $store: { getters: { userState: 0 } },
    },
  },
});

/**
 * The sidebar contracts: the body swaps with the active application, every row
 * carries a real destination, and the filter narrows rows in place
 * (design.md D-3, D-4).
 */
describe('the sidebar host', () => {
  it('renders the surface that the active application names', () => {
    const w = shallowMount(AppSidebar, {
      props: { activeId: 'chat', appConfig },
      global: { mocks: { $t: (k) => k } },
    });
    expect(w.findComponent(ChatSidebar).exists()).toBe(true);
    expect(w.findComponent(FilesSidebar).exists()).toBe(false);
  });

  it('forwards a row selection as a navigation', async () => {
    const w = shallowMount(AppSidebar, {
      props: { activeId: 'files', appConfig },
      global: { mocks: { $t: (k) => k } },
    });
    const payload = { url: 'https://filebrowser.example.com/files' };
    w.findComponent(FilesSidebar).vm.$emit('navigate', payload);
    expect(w.emitted('navigate')).toEqual([[payload]]);
  });

  it('explains an application with no configured address instead of listing dead rows', () => {
    const w = mountSurface(FilesSidebar).findComponent(FilesSidebar);
    const bare = shallowMount(FilesSidebar, {
      props: { app: getApp('files'), appConfig: {} },
      global: { mocks: { $t: (k) => k } },
    });
    expect(w.exists()).toBe(true);
    expect(bare.find('.wc-app-sidebar__notice').exists()).toBe(true);
  });
});

describe('the Files navigator', () => {
  it('points every row at a real FileBrowser route', () => {
    const w = shallowMount(FilesSidebar, {
      props: { app: getApp('files'), appConfig },
      global: { mocks: { $t: (k) => k } },
    });
    const rows = w.vm.groups.flatMap((group) => group.items.map((item) => item.url));
    expect(rows).toContain('https://filebrowser.example.com/files');
    expect(rows).toContain('https://filebrowser.example.com/tools/advancedSearch');
    rows.forEach((url) => expect(url.startsWith('https://filebrowser.example.com/')).toBe(true));
  });
});

describe('the Chat navigator', () => {
  it('points every row at a verified Zulip view fragment', () => {
    const w = shallowMount(ChatSidebar, {
      props: { app: getApp('chat'), appConfig },
      global: { mocks: { $t: (k) => k } },
    });
    const rows = w.vm.groups.flatMap((group) => group.items.map((item) => item.url));
    expect(rows).toEqual([
      'https://chat.example.com/#inbox',
      'https://chat.example.com/#recent',
      'https://chat.example.com/#feed',
      'https://chat.example.com/#narrow/is/mentioned',
      'https://chat.example.com/#narrow/is/starred',
      'https://chat.example.com/#drafts',
    ]);
  });
});

describe('the Mail navigator', () => {
  it('addresses the user’s own SOGo folder tree, without doubling /SOGo', () => {
    const w = shallowMount(MailSidebar, {
      props: { app: getApp('mail'), appConfig },
      global: { mocks: { $t: (k) => k, $store: { getters: { userState: 0 } } } },
    });
    const rows = w.vm.groups.flatMap((group) => group.items.map((item) => item.url));
    expect(rows).toContain('https://mail.example.com/SOGo/so/jane@example.com/Mail/view#!/Mail/0/INBOX');
    expect(rows).toContain('https://mail.example.com/SOGo/so/jane@example.com/Calendar/view#!/calendar/week');
    expect(rows).toContain('https://mail.example.com/SOGo/so/jane@example.com/Contacts/view#!/addressbooks/personal');
    rows.forEach((url) => expect(url).not.toContain('/SOGo/SOGo'));
  });
});

describe('the sidebar filter', () => {
  it('narrows the active surface to matching rows', () => {
    const w = shallowMount(ChatSidebar, {
      props: { app: getApp('chat'), appConfig, query: 'star' },
      global: { mocks: { $t: (k) => k } },
    });
    const labels = w.vm.groups.flatMap((group) => group.items.map((item) => item.labelKey));
    expect(labels).toEqual(['sidebar.chat.starred']);
  });

  it('matches case-insensitively and ignores surrounding space', () => {
    const w = shallowMount(ChatSidebar, {
      props: { app: getApp('chat'), appConfig, query: '  DRAFTS ' },
      global: { mocks: { $t: (k) => k } },
    });
    expect(w.vm.groups.flatMap((g) => g.items).map((i) => i.labelKey)).toEqual(['sidebar.chat.drafts']);
  });

  it('reports no matches rather than an empty body', () => {
    const w = mount(ChatSidebar, {
      props: { app: getApp('chat'), appConfig, query: 'zzz' },
      global: {
        mocks: { $t: (k) => k, $store: { getters: { userState: 0 } } },
        stubs: { SidebarGroup: true },
      },
    });
    expect(w.vm.hasNoMatches).toBe(true);
    expect(w.find('.wc-app-sidebar__notice').exists()).toBe(true);
  });
});

describe('a sidebar row', () => {
  beforeEach(() => {
    localStorage.getItem.mockReturnValue(undefined);
  });

  it('is a real link when it has a destination, so copy-link and middle-click work', () => {
    const w = mount(SidebarItem, {
      props: { item: { id: 'x', labelKey: 'sidebar.chat.inbox', url: 'https://chat.example.com/#inbox' } },
      global: { mocks: { $t: (k) => k } },
    });
    const link = w.find('a');
    expect(link.exists()).toBe(true);
    expect(link.attributes('href')).toBe('https://chat.example.com/#inbox');
  });

  it('is a button when it names an action rather than a destination', () => {
    const w = mount(SidebarItem, {
      props: { item: { id: 'x', labelKey: 'sidebar.chat.inbox' } },
      global: { mocks: { $t: (k) => k } },
    });
    expect(w.find('button').exists()).toBe(true);
    expect(w.find('a').exists()).toBe(false);
  });

  it('marks the active row with aria-current, never colour alone', () => {
    const w = mount(SidebarItem, {
      props: { item: { id: 'x', labelKey: 'sidebar.chat.inbox' }, isActive: true },
      global: { mocks: { $t: (k) => k } },
    });
    expect(w.attributes('aria-current')).toBe('page');
  });
});

describe('a sidebar group', () => {
  it('collapses, announces it, and remembers the state', async () => {
    const w = mount(SidebarGroup, {
      props: { group: { id: 'views', labelKey: 'sidebar.chat.views', items: [{ id: 'a', label: 'A' }] } },
      global: { mocks: { $t: (k) => k }, stubs: { SidebarItem: true } },
    });
    const toggle = w.find('.wc-sidebar-group__toggle');
    expect(toggle.attributes('aria-expanded')).toBe('true');
    await toggle.trigger('click');
    expect(toggle.attributes('aria-expanded')).toBe('false');
    expect(localStorage.setItem).toHaveBeenCalled();
  });
});
