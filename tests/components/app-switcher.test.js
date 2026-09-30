import { describe, it, expect, beforeEach, vi } from 'vitest';
import { shallowMount, mount } from '@vue/test-utils';
import fs from 'node:fs';
import path from 'node:path';
import AppSwitcher from '@/components/AppSwitcher/AppSwitcher.vue';
import AppSwitchButton from '@/components/AppSwitcher/AppSwitchButton.vue';
import StatusIndicator from '@/components/AppSwitcher/StatusIndicator.vue';
import { APP_LIST } from '@/utils/apps/registry';
import HealthService, { HEALTH } from '@/utils/health/HealthService';

vi.mock('@/utils/request', () => ({ default: { get: vi.fn() } }));

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
