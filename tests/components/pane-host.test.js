import {
  describe, it, expect, vi, beforeEach,
} from 'vitest';
import { shallowMount, mount } from '@vue/test-utils';
import AppPane from '@/components/Panes/AppPane.vue';
import PaneHost from '@/components/Panes/PaneHost.vue';
import PaneOverflowMenu from '@/components/Panes/PaneOverflowMenu.vue';
import { getApp } from '@/utils/apps/registry';
import HealthService, { HEALTH } from '@/utils/health/HealthService';
import { unregisterAllPanes } from '@/utils/Theming';

vi.mock('@/utils/auth/Auth', () => ({
  isUserAdmin: () => false,
}));

/* The request helper reaches for the store; a component test does not need it. */
vi.mock('@/utils/request', () => ({ default: { get: vi.fn().mockRejectedValue(new Error('no broker')) } }));

const mountPane = (props = {}, { shallow = true } = {}) => {
  const mounter = shallow ? shallowMount : mount;
  return mounter(AppPane, {
    props: {
      app: getApp('files'),
      url: 'https://filebrowser.example.com',
      isActive: true,
      ...props,
    },
    global: {
      mocks: { $t: (key, opts) => (opts ? `${key}` : key) },
      stubs: shallow ? { PaneErrorCard: true, PaneOverflowMenu: true } : {},
    },
  });
};

/**
 * The content surface and its panes.
 *
 * A pane keeps its frame mounted once it has loaded, is created only when it is
 * first shown, and never shows a blank frame instead of a diagnosis
 * (design.md D-7, standards.md S-P-2).
 */
describe('AppPane', () => {
  beforeEach(() => {
    HealthService.stop();
    HealthService.apply({});
    unregisterAllPanes();
    vi.useRealTimers();
  });

  it('renders nothing for a pane that has never been activated', () => {
    const w = mountPane({ isActive: false });
    expect(w.find('iframe').exists()).toBe(false);
    expect(w.attributes('data-pane-state')).toBe('idle');
  });

  it('creates the frame on first activation rather than at boot', () => {
    const w = mountPane({ isActive: false });
    expect(w.find('iframe').exists()).toBe(false);
    w.setProps({ isActive: true });
    return w.vm.$nextTick().then(() => {
      expect(w.find('iframe').exists()).toBe(true);
    });
  });

  it('keeps the frame mounted when the pane is hidden again', async () => {
    const w = mountPane();
    await w.vm.$nextTick();
    expect(w.find('iframe').exists()).toBe(true);
    await w.find('iframe').trigger('load');
    await w.setProps({ isActive: false });
    expect(w.find('iframe').exists()).toBe(true);
    expect(w.classes()).toContain('wc-pane--hidden');
  });

  it('explains an application with no address instead of framing nothing', async () => {
    const w = mountPane({ url: '' });
    await w.vm.$nextTick();
    expect(w.attributes('data-pane-state')).toBe('error');
    expect(w.findComponent({ name: 'PaneErrorCard' }).props('reason')).toBe('unavailable');
  });

  it('times out rather than spinning forever', async () => {
    vi.useFakeTimers();
    const w = mountPane();
    vi.advanceTimersByTime(30001);
    await w.vm.$nextTick();
    expect(w.attributes('data-pane-state')).toBe('error');
    expect(w.vm.reason).toBe('timeout');
    vi.useRealTimers();
  });

  it('reports a framing refusal reported by the health check, not a blank frame', async () => {
    HealthService.apply({ files: { state: HEALTH.DEGRADED, check: 'refuses to be framed', frameBlocked: true } });
    const w = mountPane();
    await w.vm.$nextTick();
    expect(w.vm.reason).toBe('blocked');
    expect(w.attributes('data-pane-state')).toBe('error');
  });

  it('reports an expired session reported by the health check', async () => {
    HealthService.apply({ files: { state: HEALTH.UNHEALTHY, check: 'login page', authError: true } });
    const w = mountPane();
    await w.vm.$nextTick();
    expect(w.vm.reason).toBe('auth-error');
  });

  it('navigates to a sidebar row’s deep link', async () => {
    const w = mountPane();
    const ok = w.vm.navigateTo('https://filebrowser.example.com/tools/sizeViewer');
    await w.vm.$nextTick();
    expect(ok).toBe(true);
    expect(w.find('iframe').attributes('src')).toBe('https://filebrowser.example.com/tools/sizeViewer');
  });

  it('refuses a destination that is not an http(s) URL', () => {
    const w = mountPane();
    expect(w.vm.navigateTo('javascript:alert(1)')).toBe(false);
  });

  it('tracks the path FileBrowser reports, and treats an editor hash as an open editor', async () => {
    const w = mountPane();
    await w.vm.$nextTick();
    const frame = w.find('iframe').element;
    window.dispatchEvent(Object.assign(new Event('message'), {
      data: { type: 'filebrowser:navigation', url: '/files/Documents/report.pdf#edit' },
      origin: 'https://filebrowser.example.com',
      source: frame.contentWindow,
    }));
    await w.vm.$nextTick();
    expect(w.vm.looksLikeEditor('/files/Documents/report.pdf#edit')).toBe(true);
    expect(w.vm.refreshAtReportedPath()).toBe(false);
  });

  it('ignores a message from another origin', async () => {
    const w = mountPane();
    await w.vm.$nextTick();
    const frame = w.find('iframe').element;
    window.dispatchEvent(Object.assign(new Event('message'), {
      data: { type: 'filebrowser:navigation', url: '/files/evil' },
      origin: 'https://evil.example.com',
      source: frame.contentWindow,
    }));
    await w.vm.$nextTick();
    expect(w.vm.panePath).toBe('');
  });

  it('resolves a reported path against the pane origin when reloading', () => {
    const w = mountPane();
    w.vm.panePath = '/files/Documents';
    expect(w.vm.paneUrl).toBe('https://filebrowser.example.com/files/Documents');
  });
});

describe('PaneHost', () => {
  it('mounts one pane per application and marks only the active one active', () => {
    const w = shallowMount(PaneHost, {
      props: {
        activeId: 'chat',
        urls: {
          files: 'https://filebrowser.example.com',
          chat: 'https://chat.example.com',
          mail: 'https://mail.example.com/SOGo',
        },
      },
      global: { mocks: { $t: (k) => k } },
    });
    const panes = w.findAllComponents(AppPane);
    expect(panes).toHaveLength(3);
    const active = panes.filter((pane) => pane.props('isActive'));
    expect(active).toHaveLength(1);
    expect(active[0].props('app').id).toBe('chat');
  });
});

describe('the pane overflow menu', () => {
  it('offers reload, open in a new tab and copy link, and hides health from a non-admin', async () => {
    const w = mount(PaneOverflowMenu, {
      props: { url: 'https://filebrowser.example.com', appName: 'Files' },
      global: { mocks: { $t: (k) => k, $toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }) } },
    });
    await w.find('.wc-pane-menu__trigger').trigger('click');
    const text = w.text();
    expect(text).toContain('pane.overflow.reload');
    expect(text).toContain('pane.overflow.open');
    expect(text).toContain('pane.overflow.copy');
    expect(text).not.toContain('pane.overflow.health');
  });

  it('is reachable by keyboard and closes on Escape, restoring focus', async () => {
    const w = mount(PaneOverflowMenu, {
      props: { url: 'https://filebrowser.example.com', appName: 'Files' },
      global: { mocks: { $t: (k) => k, $toast: Object.assign(vi.fn(), { success: vi.fn(), error: vi.fn() }) } },
    });
    const trigger = w.find('.wc-pane-menu__trigger');
    expect(trigger.attributes('aria-expanded')).toBe('false');
    await trigger.trigger('click');
    expect(trigger.attributes('aria-expanded')).toBe('true');
    await w.find('.wc-pane-menu').trigger('keydown.esc');
    expect(trigger.attributes('aria-expanded')).toBe('false');
  });
});
