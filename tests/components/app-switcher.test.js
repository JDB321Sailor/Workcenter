import { describe, it, expect, beforeEach, vi } from 'vitest';
import { shallowMount, mount } from '@vue/test-utils';
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
    expect(buttons[1].attributes('aria-current')).toBeUndefined();
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
});
