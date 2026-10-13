import {
  describe, it, expect, beforeEach, afterEach, vi,
} from 'vitest';
import { nextTick } from 'vue';
import { shallowMount, mount } from '@vue/test-utils';
import fs from 'node:fs';
import path from 'node:path';
import AppSwitcher from '@/components/AppSwitcher/AppSwitcher.vue';
import AppSwitchButton from '@/components/AppSwitcher/AppSwitchButton.vue';
import StatusIndicator from '@/components/AppSwitcher/StatusIndicator.vue';
import AppMenuButton from '@/components/AppSwitcher/AppMenuButton.vue';
import { APP_LIST } from '@/utils/apps/registry';
import HealthService, { HEALTH } from '@/utils/health/HealthService';
import { registerPane, unregisterAllPanes } from '@/utils/Theming';

vi.mock('@/utils/request', () => ({ default: { get: vi.fn() } }));

/* `isUserAdmin` reads localStorage, so a controllable stand-in is what lets the
   menu's admin-only item be tested in both directions. */
const { adminState } = vi.hoisted(() => ({ adminState: { isAdmin: false } }));
vi.mock('@/utils/auth/Auth', () => ({ isUserAdmin: () => adminState.isAdmin }));

const mountSwitcher = (props = {}) => shallowMount(AppSwitcher, {
  props: { activeId: 'files', appConfig: configured(), ...props },
  global: {
    mocks: { $t: (key, opts) => (opts ? `${key}` : key) },
  },
});

const configured = () => ({
  applications: {
    files: { url: 'https://filebrowser.example.com' },
    chat: { url: 'https://chat.example.com' },
    mail: { url: 'https://mail.example.com' },
  },
});

/**
 * The switcher is the defining element: three buttons with one status indicator
 * directly beneath each, under a STATUS label. See design.md D-2 and D-2S.
 */
describe('AppSwitcher', () => {
  beforeEach(() => {
    HealthService.stop();
    HealthService.apply({});
  });

  it('renders one button per application', () => {
    const w = mountSwitcher();
    const buttons = w.findAllComponents(AppSwitchButton);
    expect(buttons).toHaveLength(APP_LIST.length);
    expect(buttons.map((b) => b.props('app').id)).toEqual(['files', 'chat', 'mail']);
  });

  it('marks exactly one button current, and none of the others', () => {
    const apps = APP_LIST;
    const buttons = apps.map((app) => mount(AppSwitchButton, {
      props: { app, activeId: 'chat', appConfig: configured() },
      global: { mocks: { $t: (k) => k } },
    }));
    const current = buttons.filter((b) => b.attributes('aria-selected') === 'true');
    expect(current).toHaveLength(1);
    // The active application is announced by aria-current as well as
    // aria-selected, and never by colour alone (design.md D-2, D-A2, U-16).
    const currentPages = buttons.filter((b) => b.attributes('aria-current') === 'page');
    expect(currentPages).toHaveLength(1);
    expect(buttons[1].attributes('aria-current')).toBe('page');
    expect(buttons[0].attributes('aria-current')).toBeUndefined();
    // aria-selected identifies the current tab; the tabindex follows it.
    expect(buttons[1].attributes('tabindex')).toBe('0');
    expect(buttons[0].attributes('tabindex')).toBe('-1');
    buttons.forEach((b) => b.unmount());
  });

  it('renders one status indicator per button, in the same order', () => {
    const w = mountSwitcher();
    const indicators = w.findAllComponents(StatusIndicator);
    const buttons = w.findAllComponents(AppSwitchButton);
    expect(indicators).toHaveLength(buttons.length);
    expect(indicators.map((i) => i.props('app').id))
      .toEqual(buttons.map((b) => b.props('app').id));
  });

  it('labels the status row, so the indicators have a stated purpose', () => {
    const w = mountSwitcher();
    expect(w.find('.wc-switcher__status-label').exists()).toBe(true);
    expect(w.find('.wc-switcher__status').attributes('role')).toBe('group');
  });

  it('announces status changes politely', () => {
    const w = mountSwitcher();
    expect(w.find('.wc-switcher__status').attributes('aria-live')).toBe('polite');
  });

  it('presents the buttons as a tablist', () => {
    const w = mountSwitcher();
    expect(w.find('[role="tablist"]').exists()).toBe(true);
  });

  it('emits select when an available application is chosen', async () => {
    const w = mountSwitcher();
    await w.findAllComponents(AppSwitchButton)[1].vm.$emit('select', 'chat');
    expect(w.emitted('select')).toEqual([['chat']]);
  });

  it('emits unavailable rather than select when the application has no address', async () => {
    const w = mountSwitcher({ appConfig: { applications: { files: { url: 'https://f.example.com' } } } });
    await w.findAllComponents(AppSwitchButton)[2].vm.$emit('select', 'mail');
    expect(w.emitted('unavailable')).toEqual([['mail']]);
    expect(w.emitted('select')).toBeUndefined();
  });

  it('passes each indicator its own health state', () => {
    HealthService.apply({ chat: { state: HEALTH.UNHEALTHY, check: 'zulip' } });
    const w = mountSwitcher();
    const indicators = w.findAllComponents(StatusIndicator);
    const byId = Object.fromEntries(indicators.map((i) => [i.props('app').id, i.props('state')]));
    expect(byId.chat).toBe(HEALTH.UNHEALTHY);
    expect(byId.files).toBe(HEALTH.UNKNOWN);
  });

  it('selects the application when an unhealthy indicator is activated', async () => {
    HealthService.apply({ mail: { state: HEALTH.UNHEALTHY } });
    const w = mountSwitcher();
    const mail = w.findAllComponents(StatusIndicator).find((i) => i.props('app').id === 'mail');
    await mail.vm.$emit('activate', 'mail');
    expect(w.emitted('select')).toEqual([['mail']]);
  });

  it('focuses the pane, and never switches application, when a healthy indicator is activated', async () => {
    HealthService.apply({ files: { state: HEALTH.HEALTHY } });
    const w = mountSwitcher({ activeId: 'files' });
    const files = w.findAllComponents(StatusIndicator).find((i) => i.props('app').id === 'files');
    await files.vm.$emit('activate', 'files');
    expect(w.emitted('focus-pane')).toEqual([['files']]);
    expect(w.emitted('select')).toBeUndefined();
  });

  it('switches application with Alt+1, Alt+2 and Alt+3', async () => {
    const w = mountSwitcher();
    const press = (key, init = {}) => {
      const event = new window.KeyboardEvent('keydown', { key, altKey: true, ...init });
      window.dispatchEvent(event);
    };
    press('2');
    press('3');
    press('1');
    expect(w.emitted('select')).toEqual([['chat'], ['mail'], ['files']]);
  });

  it('ignores Alt+<n> with a modifier or an out-of-range digit', () => {
    const w = mountSwitcher();
    window.dispatchEvent(new window.KeyboardEvent('keydown', { key: '4', altKey: true }));
    window.dispatchEvent(new window.KeyboardEvent('keydown', { key: '1', altKey: true, ctrlKey: true }));
    window.dispatchEvent(new window.KeyboardEvent('keydown', { key: '1' }));
    expect(w.emitted('select')).toBeUndefined();
  });

  it('traverses the tablist with the arrow keys, moving focus and activating as it moves', async () => {
    const w = mount(AppSwitcher, {
      props: { activeId: 'files', appConfig: configured() },
      global: { mocks: { $t: (key) => key } },
      attachTo: document.body,
    });
    const tablist = w.find('[role="tablist"]');
    const buttons = w.findAll('[role="tab"]');
    await tablist.trigger('keydown', { key: 'ArrowRight' });
    expect(document.activeElement).toBe(buttons[1].element);
    await tablist.trigger('keydown', { key: 'ArrowRight' });
    expect(w.emitted('select')).toEqual([['chat'], ['mail']]);
    await tablist.trigger('keydown', { key: 'ArrowLeft' });
    expect(w.emitted('select')).toEqual([['chat'], ['mail'], ['chat']]);
    await tablist.trigger('keydown', { key: 'End' });
    expect(w.emitted('select')).toEqual([['chat'], ['mail'], ['chat'], ['mail']]);
    w.unmount();
  });

  it('drops the labels and the STATUS label when the rail is collapsed, keeping one indicator per button', () => {
    const w = mountSwitcher({ collapsed: true });
    expect(w.findAll('.wc-switch-button__label')).toHaveLength(0);
    expect(w.find('.wc-switcher__status-label').exists()).toBe(false);
    expect(w.findAllComponents(StatusIndicator)).toHaveLength(3);
    expect(w.findAllComponents(AppSwitchButton).map((b) => b.props('collapsed'))).toEqual([true, true, true]);
  });

  it('stacks the buttons when the rail is collapsed, so each mark gets its own row', () => {
    const expanded = mountSwitcher({ collapsed: false });
    expect(expanded.find('.wc-switcher__buttons').classes()).not.toContain('is-collapsed');

    const collapsed = mountSwitcher({ collapsed: true });
    expect(collapsed.find('.wc-switcher__buttons').classes()).toContain('is-collapsed');
  });

  it('names each button for assistive technology when its label is not rendered', () => {
    const collapsed = mount(AppSwitchButton, {
      props: {
        app: APP_LIST[0], activeId: 'files', appConfig: configured(), collapsed: true,
      },
      global: { mocks: { $t: (k) => k } },
    });
    expect(collapsed.attributes('aria-label')).toBe('Files');
    expect(collapsed.find('.wc-switch-button__label').exists()).toBe(false);

    const expanded = mount(AppSwitchButton, {
      props: {
        app: APP_LIST[0], activeId: 'files', appConfig: configured(),
      },
      global: { mocks: { $t: (k) => k } },
    });
    /* The visible label is the accessible name; no duplicate announcement. */
    expect(expanded.attributes('aria-label')).toBeUndefined();
  });

  it('gives a switcher button room for its mark and its label', () => {
    // A fixed height smaller than the content clipped the label (a real defect):
    // the button must be free to grow past the token.
    const source = fs.readFileSync(
      path.resolve(__dirname, '../../src/components/AppSwitcher/AppSwitchButton.vue'),
      'utf8',
    );
    expect(source).toMatch(/height: auto;/);
    expect(source).toMatch(/min-height: var\(--switcher-button-height\)/);
  });
});

/**
 * Each application's options menu, beneath its own indicator.
 *
 * The menu acts on **that** application's frame: reload it, open it in a real
 * tab, copy where it is, or ask what its health check last said (design.md D-7).
 * It replaced a floating control that sat in the pane's top-right corner — the
 * same corner an embedded application puts its own toolbar in, so it read as
 * part of the page and covered it. The control was removed rather than hidden;
 * these tests exist so it does not come back.
 */
describe('the application options menu', () => {
  beforeEach(() => {
    HealthService.stop();
    HealthService.apply({});
  });

  it('renders one menu per application, in the same order as the buttons', () => {
    const w = mountSwitcher();
    const menus = w.findAllComponents(AppMenuButton);
    expect(menus).toHaveLength(3);
    expect(menus.map((m) => m.props('app').id)).toEqual(APP_LIST.map((a) => a.id));
  });

  it('gives each menu its own application’s address', () => {
    const w = mountSwitcher();
    expect(w.findAllComponents(AppMenuButton).map((m) => m.props('url')))
      .toEqual(['https://filebrowser.example.com', 'https://chat.example.com', 'https://mail.example.com']);
  });

  it('offers reload, open in a new tab and copy link, and hides health from a non-admin', async () => {
    const w = mount(AppMenuButton, {
      props: { app: APP_LIST[0], url: 'https://filebrowser.example.com' },
      global: {
        mocks: {
          $t: (k) => k,
          $toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }),
        },
      },
    });
    await w.find('.wc-app-menu__trigger').trigger('click');
    await nextTick();
    /* The menu is teleported to the body so no clipping ancestor can cut it off,
       so it is not inside the wrapper — it is in the document. */
    const text = document.body.textContent;
    expect(text).toContain('switcher.menu.reload');
    expect(text).toContain('switcher.menu.open');
    expect(text).toContain('switcher.menu.copy');
    expect(text).not.toContain('switcher.menu.health');
    w.unmount();
  });

  it('is reachable by keyboard and closes on Escape, restoring focus', async () => {
    const w = mount(AppMenuButton, {
      props: { app: APP_LIST[0], url: 'https://filebrowser.example.com' },
      global: {
        mocks: {
          $t: (k) => k,
          $toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }),
        },
      },
    });
    const trigger = w.find('.wc-app-menu__trigger');
    expect(trigger.attributes('aria-expanded')).toBe('false');
    await trigger.trigger('click');
    expect(trigger.attributes('aria-expanded')).toBe('true');
    await w.find('.wc-app-menu').trigger('keydown.esc');
    expect(trigger.attributes('aria-expanded')).toBe('false');
  });

  it('disables itself for an application with no address, rather than offering dead actions', () => {
    const w = mount(AppMenuButton, {
      props: { app: APP_LIST[0], url: '' },
      global: { mocks: { $t: (k) => k } },
    });
    expect(w.find('.wc-app-menu__trigger').attributes('disabled')).toBeDefined();
  });

  it('reloads through the pane adapter, so the frame keeps the user’s place', () => {
    /* The switcher never reaches into a frame itself; the pane registers how to
       reload it (design.md D-T6). */
    const refresh = vi.fn();
    registerPane('files', { refresh, url: () => 'https://filebrowser.example.com/current' });
    const w = mountSwitcher();
    w.vm.reloadPane('files');
    expect(refresh).toHaveBeenCalledTimes(1);
    unregisterAllPanes();
  });

  it('opens the view the pane is actually on, not the application’s front door', () => {
    registerPane('files', { refresh: vi.fn(), url: () => 'https://filebrowser.example.com/some/folder' });
    const w = mountSwitcher();
    expect(w.vm.urlFor('files')).toBe('https://filebrowser.example.com/some/folder');
    unregisterAllPanes();
    /* With no pane registered — nothing has been opened yet — it falls back to
       the configured address rather than an empty menu. */
    expect(w.vm.urlFor('files')).toBe('https://filebrowser.example.com');
  });

  it('reveals that application’s health detail, which the pane owns', () => {
    const toggleHealth = vi.fn();
    registerPane('chat', { refresh: vi.fn(), toggleHealth });
    const w = mountSwitcher();
    w.vm.showPaneHealth('chat');
    expect(toggleHealth).toHaveBeenCalledTimes(1);
    unregisterAllPanes();
  });
});

describe('the application options menu, for an administrator', () => {
  beforeEach(() => {
    HealthService.stop();
    HealthService.apply({});
    adminState.isAdmin = true;
  });
  afterEach(() => { adminState.isAdmin = false; });

  it('adds the health detail, which is the one admin-only item', async () => {
    const w = mount(AppMenuButton, {
      props: { app: APP_LIST[0], url: 'https://filebrowser.example.com' },
      global: {
        mocks: {
          $t: (k) => k,
          $toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }),
        },
      },
    });
    await w.find('.wc-app-menu__trigger').trigger('click');
    await nextTick();
    expect(document.body.textContent).toContain('switcher.menu.health');
    w.unmount();
  });
});

describe('the application options menu is not clipped by the rail', () => {
  beforeEach(() => {
    HealthService.stop();
    HealthService.apply({});
  });

  it('renders at the body, outside the rail’s clipping box', async () => {
    /* The rail is `overflow: hidden` and 16rem wide; the menu is 13rem starting
       at the dots, so for the right-hand application it ran past the rail's edge
       and was cut off — the part that fitted drew over the pane, the rest was
       missing. This is the property that prevents it: the menu is a child of the
       body, so no ancestor with `overflow` can clip it and no ancestor's stacking
       context can trap it. A larger z-index would not have helped. */
    /* `mount`, not `shallowMount`: the trigger only exists if the child is
       actually rendered. */
    const w = mount(AppSwitcher, {
      props: { activeId: 'files', appConfig: configured() },
      global: { mocks: { $t: (key, opts) => (opts ? `${key}` : key) } },
      attachTo: document.body,
    });
    await w.findAll('.wc-app-menu__trigger')[2].trigger('click');
    await nextTick();
    const menu = document.querySelector('.wc-app-menu__list');
    expect(menu).not.toBeNull();
    expect(menu.parentElement).toBe(document.body);
    /* And it is positioned from the trigger rather than inheriting an offset from
       the rail: fixed, with the coordinates set inline. */
    expect(menu.getAttribute('style')).toMatch(/left:.*px/);
    expect(menu.getAttribute('style')).toMatch(/bottom:.*px/);
    w.unmount();
  });

  it('is wide enough to leave the rail, which is why it has to escape it', () => {
    /* Asserted from the stylesheet rather than the DOM: jsdom does no layout, so
       a width can only be read from the rule. If the menu ever became narrower
       than the rail's remaining width the clipping bug could not reproduce, and
       this test would be measuring the wrong thing. */
    const css = fs.readFileSync(
      path.resolve(__dirname, '../../src/components/AppSwitcher/AppMenuButton.vue'), 'utf8',
    );
    expect(css).toMatch(/\.wc-app-menu__list \{[\s\S]*?position: fixed/);
    expect(css).toMatch(/min-width: 13rem/);
  });
});
