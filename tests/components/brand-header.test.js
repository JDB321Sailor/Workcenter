import {
  describe, it, expect, vi, beforeEach,
} from 'vitest';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import BrandHeader from '@/components/Rail/BrandHeader.vue';

/**
 * The brand header, including the role label. Design.md D-1, D-1.1.
 *
 * The shell states who the user is exactly once, here: `Workcenter - User` or
 * `Workcenter - Admin`. The user menu does not repeat it (D-6).
 */
const identity = vi.hoisted(() => ({ isAdmin: false, username: 'jane' }));

vi.mock('@/utils/auth/Auth', () => ({
  getUserProfile: () => ({
    username: identity.username,
    displayName: 'Jane Doe',
    email: 'jane@example.com',
    groups: identity.isAdmin ? ['workspaceusers', 'workspaceadmin'] : ['workspaceusers'],
    isAdmin: identity.isAdmin,
  }),
  isUserAdmin: () => identity.isAdmin,
  logout: vi.fn(),
  getLogoutRedirectUrl: () => null,
}));

const t = (key) => key;

const mountBrand = (props = {}) => mount(BrandHeader, {
  props: { lastAppName: 'Files', ...props },
  global: {
    plugins: [createStore({ state: {}, getters: { userState: () => 0 } })],
    mocks: { $t: t },
  },
});

describe('the brand header', () => {
  beforeEach(() => {
    identity.isAdmin = false;
    identity.username = 'jane';
  });

  it('reads Workcenter - User for a user without the admin group', () => {
    const w = mountBrand();
    expect(w.find('.wc-brand__wordmark').text()).toBe('Workcenter');
    expect(w.find('.wc-brand__dash').text()).toBe('-');
    expect(w.find('.wc-brand__role').text()).toBe('brand.role-user');
  });

  it('reads Workcenter - Admin for an administrator', () => {
    identity.isAdmin = true;
    expect(mountBrand().find('.wc-brand__role').text()).toBe('brand.role-admin');
  });

  it('claims no role when nobody is signed in', () => {
    identity.username = '';
    expect(mountBrand().find('.wc-brand__role').exists()).toBe(false);
  });

  it('drops the whole label, not just the word, when the rail is collapsed', () => {
    const w = mountBrand({ collapsed: true });
    expect(w.find('.wc-brand__role').exists()).toBe(false);
    expect(w.find('.wc-brand__wordmark').exists()).toBe(false);
    expect(w.find('.wc-brand__titles').exists()).toBe(false);
    /* The mark and the way back stay. */
    expect(w.find('.wc-brand__mark').exists()).toBe(true);
    expect(w.find('.wc-brand__toggle').exists()).toBe(true);
  });

  it('points the collapse control the way the rail will move', async () => {
    const expanded = mountBrand();
    expect(expanded.find('.wc-brand__toggle-icon').classes()).not.toContain('is-flipped');
    expect(expanded.find('.wc-brand__toggle').attributes('aria-expanded')).toBe('true');

    const collapsed = mountBrand({ collapsed: true });
    expect(collapsed.find('.wc-brand__toggle-icon').classes()).toContain('is-flipped');
    expect(collapsed.find('.wc-brand__toggle').attributes('aria-expanded')).toBe('false');
  });

  it('keeps the collapse control visible and clickable in both states', () => {
    /* A collapse control that hides itself is a rail the user cannot leave: the
       stylesheet must not fade it out or disable pointer events (D-2S). */
    const source = require('node:fs').readFileSync(
      require('node:path').resolve(__dirname, '../../src/components/Rail/BrandHeader.vue'),
      'utf8',
    );
    const toggleRules = source.slice(source.indexOf('.wc-brand__toggle {'));
    expect(toggleRules).not.toMatch(/opacity:\s*0/);
    expect(toggleRules).not.toMatch(/pointer-events:\s*none/);
  });

  it('emits home and toggle from its two controls', async () => {
    const w = mountBrand();
    await w.find('.wc-brand__home').trigger('click');
    await w.find('.wc-brand__toggle').trigger('click');
    expect(w.emitted('home')).toHaveLength(1);
    expect(w.emitted('toggle')).toHaveLength(1);
  });
});
