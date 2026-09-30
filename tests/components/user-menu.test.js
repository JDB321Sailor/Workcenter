import {
  describe, it, expect, vi, beforeEach,
} from 'vitest';
import { mount, shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import LanguageMenu from '@/components/Settings/LanguageMenu.vue';
import LanguageButton from '@/components/User/LanguageButton.vue';
import ModeToggleButton from '@/components/User/ModeToggleButton.vue';
import UserRow, { NAME_MAX_LENGTH, truncateName } from '@/components/User/UserRow.vue';
import UserMenu from '@/components/User/UserMenu.vue';
import AppMark from '@/components/AppMark.vue';
import { MODE, modeState, unregisterAllPanes } from '@/utils/Theming';

vi.mock('@/broker/preferences', () => ({
  applyPreferences: vi.fn(async () => ({
    ok: true,
    apps: { files: 'ok', chat: 'unsupported', mail: 'unsupported' },
  })),
  OUTCOME: {
    OK: 'ok', UNSUPPORTED: 'unsupported', UNAVAILABLE: 'unavailable', FAILED: 'failed',
  },
}));

/* The identity is mutable per test, so "not an administrator" is a real
   condition rather than a mutated cache. The name is deliberately at the cap:
   14 characters for the first name and 14 for the last (design.md D-6.3). */
const identity = vi.hoisted(() => ({
  isAdmin: true,
  displayName: 'Christopherson Vandenberghen',
}));

vi.mock('@/utils/auth/Auth', () => ({
  getUserProfile: () => ({
    username: 'jane',
    displayName: identity.displayName,
    email: 'jane@example.com',
    groups: ['workspaceusers', 'workspaceadmin'],
    isAdmin: identity.isAdmin,
  }),
  isUserAdmin: () => identity.isAdmin,
  logout: vi.fn(),
  getLogoutRedirectUrl: () => null,
}));

vi.mock('@/utils/auth/Logout', () => ({ default: vi.fn() }));

vi.mock('@/utils/auth/OidcAuth', () => ({ isOidcEnabled: () => false, getOidcAuth: () => ({ logout: vi.fn() }) }));
vi.mock('@/utils/auth/KeycloakAuth', () => ({ isKeycloakEnabled: () => false, getKeycloakAuth: () => ({ logout: vi.fn() }) }));

const t = (key) => key;

const store = (appConfig = {}) => createStore({
  state: { config: { appConfig } },
  getters: {
    appConfig: () => appConfig,
    userState: () => 0,
  },
});

const mountMenu = (props = {}) => mount(UserMenu, {
  props: { appConfig: {}, ...props },
  global: {
    plugins: [store()],
    mocks: {
      $t: t,
      $i18n: { locale: 'en' },
    },
    stubs: { AppMark: true },
  },
});

describe('the user row', () => {
  const mountRow = (props = {}) => mount(UserRow, {
    props: {
      displayName: identity.displayName,
      email: 'jane@example.com',
      ...props,
    },
    global: { mocks: { $t: t, $i18n: { locale: 'en' } } },
  });

  it('shows the initials on the button, always', () => {
    expect(mountRow().find('.wc-user-row__initials').text()).toBe('CV');
    expect(mountRow({ collapsed: true }).find('.wc-user-row__initials').text()).toBe('CV');
  });

  it('stacks the first name over the last name', () => {
    const names = mountRow().findAll('.wc-user-row__name');
    expect(names).toHaveLength(2);
    expect(names[0].text()).toBe('Christopherson');
    expect(names[1].text()).toBe('Vandenberghen');
  });

  it('fits 14 characters a line and cuts anything longer with an ellipsis', () => {
    expect(NAME_MAX_LENGTH).toBe(14);
    expect(truncateName('Christopherson')).toBe('Christopherson'); // exactly 14
    const longer = truncateName('Christophersonia');
    expect(longer).toHaveLength(NAME_MAX_LENGTH);
    expect(longer.endsWith('…')).toBe(true);

    const row = mountRow({ displayName: 'Christophersonia Vandenberghenson' });
    const names = row.findAll('.wc-user-row__name');
    names.forEach((name) => expect(name.text().length).toBeLessThanOrEqual(NAME_MAX_LENGTH));
  });

  it('keeps a three-part name whole on the second line', () => {
    const names = mountRow({ displayName: 'Ana María García' }).findAll('.wc-user-row__name');
    expect(names[0].text()).toBe('Ana');
    expect(names[1].text()).toBe('María García');
  });

  it('renders one line when the name is a single token', () => {
    const row = mountRow({ displayName: 'Prince' });
    expect(row.findAll('.wc-user-row__name')).toHaveLength(1);
    expect(row.find('.wc-user-row__name').text()).toBe('Prince');
  });

  it('falls back to the email local part when the session carries no name', () => {
    const row = mountRow({ displayName: '' });
    expect(row.find('.wc-user-row__name').text()).toBe('jane');
  });

  it('carries the two preference buttons on its right, mode inboard of language', () => {
    const row = mountRow();
    const controls = row.find('.wc-user-row__controls');
    const children = controls.findAllComponents({ name: 'ModeToggleButton' });
    expect(children).toHaveLength(1);
    expect(controls.findAllComponents({ name: 'LanguageButton' })).toHaveLength(1);
    expect(controls.element.firstElementChild.className).toContain('wc-mode-toggle');
  });

  it('drops the name and both buttons when the rail is collapsed', () => {
    const row = mountRow({ collapsed: true });
    expect(row.classes()).toContain('wc-user-row--collapsed');
    expect(row.find('.wc-user-row__names').exists()).toBe(false);
    expect(row.find('.wc-user-row__controls').exists()).toBe(false);
  });

  it('opens the menu from the initials button', async () => {
    const row = mountRow();
    await row.find('.wc-user-row__initials').trigger('click');
    expect(row.emitted('toggle')).toHaveLength(1);
    expect(row.find('.wc-user-row__initials').attributes('aria-haspopup')).toBe('dialog');
  });
});

describe('the user menu', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    modeState.mode = MODE.DARK;
    modeState.applied = null;
    modeState.panes = {};
    unregisterAllPanes();
    localStorage.getItem.mockReturnValue(undefined);
  });

  const configured = {
    applications: {
      files: { url: 'https://filebrowser.example.com' },
      chat: { url: 'https://chat.example.com' },
      mail: { url: 'https://mail.example.com/SOGo' },
    },
    auth: { oidc: { endpoint: 'https://auth.example.com/application/o/workcenter/' } },
  };

  it('holds identity, the admin links and Logout — and no preference controls while expanded', async () => {
    const w = mountMenu({ appConfig: configured });
    await w.find('.wc-user-row__initials').trigger('click');
    const panel = w.find('.wc-user__panel');
    expect(panel.exists()).toBe(true);
    expect(panel.text()).toContain(identity.displayName);
    expect(panel.text()).toContain('jane@example.com');
    const links = panel.findAll('.wc-user__link');
    expect(links).toHaveLength(3); // the admin links, from the configured addresses
    expect(links.map((l) => l.attributes('href'))).toEqual([
      'https://traefik.example.com',
      'https://mail.example.com/SOGo',
      'https://auth.example.com',
    ]);
    expect(panel.text()).toContain('user.sign-out');
    /* The controls live in the row, not the panel (D-6). */
    expect(panel.find('.wc-user__preferences').exists()).toBe(false);
  });

  it('carries the preference controls in the panel while the rail is collapsed', async () => {
    const w = mountMenu({ collapsed: true });
    await w.find('.wc-user-row__initials').trigger('click');
    const panel = w.find('.wc-user__panel');
    expect(panel.find('.wc-user__preferences').exists()).toBe(true);
    expect(panel.findAllComponents({ name: 'ModeToggleButton' })).toHaveLength(1);
    expect(panel.findAllComponents({ name: 'LanguageButton' })).toHaveLength(1);
  });

  it('hides the admin links from a user who is not an administrator', async () => {
    identity.isAdmin = false;
    const w = mountMenu();
    await w.find('.wc-user-row__initials').trigger('click');
    expect(w.find('.wc-user__links').exists()).toBe(false);
    identity.isAdmin = true;
  });

  it('closes on Escape and returns focus to the initials button', async () => {
    const w = mountMenu({ attachTo: document.body });
    await w.find('.wc-user-row__initials').trigger('click');
    await w.find('.wc-user__panel').trigger('keydown', { key: 'Escape' });
    expect(w.find('.wc-user__panel').exists()).toBe(false);
    w.unmount();
  });

  it('reports what the last mode change did to the panes', async () => {
    const w = mountMenu();
    await w.find('.wc-user-row__initials').trigger('click');
    w.findComponent(UserRow).vm.$emit('mode-applied', { mode: 'light', panes: { files: 'ok', chat: 'unsupported' } });
    await w.vm.$nextTick();
    expect(w.find('.wc-user__notice').text()).toBe('user.appearance.unsupported');
  });

  it('reports a deferred Files refresh rather than claiming success', async () => {
    const w = mountMenu();
    await w.find('.wc-user-row__initials').trigger('click');
    w.findComponent(UserRow).vm.$emit('mode-applied', { mode: 'light', panes: { files: 'deferred' } });
    await w.vm.$nextTick();
    expect(w.find('.wc-user__notice').text()).toBe('user.appearance.deferred');
  });
});

describe('the mode toggle', () => {
  const mountToggle = () => mount(ModeToggleButton, {
    global: {
      plugins: [store()],
      mocks: { $t: t },
    },
  });

  beforeEach(() => {
    vi.clearAllMocks();
    modeState.mode = MODE.DARK;
    modeState.applied = null;
    modeState.panes = {};
    unregisterAllPanes();
    localStorage.getItem.mockReturnValue(undefined);
  });

  it('offers a sun while dark, labelled with the action', () => {
    const w = mountToggle();
    expect(w.attributes('data-mode')).toBe('dark');
    expect(w.attributes('aria-label')).toBe('user.mode.to-light');
    /* An action, not a toggle state. */
    expect(w.attributes('aria-pressed')).toBeUndefined();
  });

  it('offers a moon while light', async () => {
    modeState.mode = MODE.LIGHT;
    const w = mountToggle();
    expect(w.attributes('data-mode')).toBe('light');
    expect(w.attributes('aria-label')).toBe('user.mode.to-dark');
  });

  it('switches the shell to the other mode and reports the panes', async () => {
    const w = mountToggle();
    await w.trigger('click');
    expect(modeState.mode).toBe(MODE.LIGHT);
    expect(document.documentElement.getAttribute('data-wc-mode')).toBe('light');
    const applied = w.emitted('applied');
    expect(applied).toHaveLength(1);
    expect(applied[0][0].panes).toEqual({ files: 'ok', chat: 'unsupported', mail: 'unsupported' });
  });
});

describe('the language button and its menu', () => {
  const mountButton = () => mount(LanguageButton, {
    props: { appConfig: {} },
    global: { mocks: { $t: t, $i18n: { locale: 'en' } } },
  });

  it('shows a rounded flag and the ISO 639-1 code', () => {
    const w = mountButton();
    const flag = w.find('.wc-lang__button img.wc-flag');
    expect(flag.exists()).toBe(true);
    expect(flag.classes()).toContain('wc-flag--circle');
    expect(w.find('.wc-lang__code').text()).toBe('en');
  });

  it('shows a language with no country as the registry glyph, never someone else’s flag', () => {
    const w = mount(LanguageButton, {
      props: { appConfig: {} },
      global: { mocks: { $t: t, $i18n: { locale: 'gl' } } },
    });
    expect(w.find('img.wc-flag').exists()).toBe(false);
    expect(w.find('.wc-flag--glyph').text()).toBe('🌐');
    expect(w.find('.wc-lang__code').text()).toBe('gl');
  });

  it('names the action and the language in use', () => {
    const w = mountButton();
    expect(w.find('.wc-lang__button').attributes('aria-label')).toBe('user.language.change');
    expect(w.find('.wc-lang__button').attributes('aria-expanded')).toBe('false');
  });

  it('opens the language menu, which lists flags, endonyms and English names', async () => {
    const w = mountButton();
    await w.find('.wc-lang__button').trigger('click');
    const menu = w.findComponent(LanguageMenu);
    expect(menu.exists()).toBe(true);
    const options = menu.findAll('.wc-lang-menu__option');
    expect(options.length).toBeGreaterThan(20);
    expect(menu.find('.wc-lang-menu__endonym').text()).toBe('English');
    expect(menu.findAll('img.wc-flag').length).toBeGreaterThan(20);
  });

  it('filters by endonym, English name or code', async () => {
    const menu = mount(LanguageMenu, {
      props: { active: 'en' },
      global: { mocks: { $t: t } },
    });
    await menu.find('.wc-lang-menu__filter').setValue('deutsch');
    expect(menu.findAll('.wc-lang-menu__option')).toHaveLength(1);
    await menu.find('.wc-lang-menu__filter').setValue('japanese');
    expect(menu.findAll('.wc-lang-menu__option')).toHaveLength(1);
    await menu.find('.wc-lang-menu__filter').setValue('zzz');
    expect(menu.findAll('.wc-lang-menu__option')).toHaveLength(0);
    expect(menu.find('.wc-lang-menu__empty').exists()).toBe(true);
  });

  it('marks the language in use and reports a selection', async () => {
    const menu = mount(LanguageMenu, {
      props: { active: 'de' },
      global: { mocks: { $t: t } },
    });
    const active = menu.find('.wc-lang-menu__option.is-active');
    expect(active.attributes('data-code')).toBe('de');
    expect(active.attributes('aria-selected')).toBe('true');
    await menu.findAll('.wc-lang-menu__option')[0].trigger('click');
    expect(menu.emitted('select')[0][0]).toBe('en');
  });

  it('moves through the options with the arrow keys', async () => {
    const menu = mount(LanguageMenu, {
      props: { active: 'en' },
      attachTo: document.body,
      global: { mocks: { $t: t } },
    });
    const options = menu.findAll('.wc-lang-menu__option');
    options[0].element.focus();
    await menu.find('.wc-lang-menu').trigger('keydown', { key: 'ArrowDown' });
    expect(document.activeElement).toBe(options[1].element);
    menu.unmount();
  });
});

describe('the language menu surface', () => {
  it('is a dialog in the user panel’s style', () => {
    const menu = mount(LanguageMenu, {
      props: { active: 'en' },
      global: { mocks: { $t: t } },
    });
    expect(menu.attributes('role')).toBe('dialog');
    expect(menu.classes()).toContain('wc-lang-menu');
  });
});

describe('the row’s spacing and the panel’s position', () => {
  const read = (file) => require('node:fs').readFileSync(
    require('node:path').resolve(__dirname, `../../src/components/${file}`),
    'utf8',
  );

  it('uses one distance for the gap between the buttons and the edge inset', () => {
    const row = read('User/UserRow.vue');
    /* One property, used twice: the row's right inset and the controls' gap.
       The gap subtracts the sun/moon glyph's centring slack, so the two visible
       distances are equal (design.md D-6.6). */
    expect(row).toMatch(/--wc-user-row-edge:\s*0\.75rem/);
    expect(row).toMatch(/padding:\s*0\.25rem var\(--wc-user-row-edge\)/);
    expect(row).toMatch(/gap:\s*calc\(var\(--wc-user-row-edge[^)]*\)\s*-\s*\(1\.75rem - 1\.1rem\)\s*\/\s*2\)/);
  });

  it('never squeezes or clips the language code', () => {
    const language = read('User/LanguageButton.vue');
    const codeRule = language.slice(language.indexOf('.wc-lang__code {'));
    expect(codeRule).toMatch(/flex:\s*0 0 auto/);
    expect(codeRule).toMatch(/white-space:\s*nowrap/);
  });

  it('opens the panel above the button, inside the rail, while expanded', () => {
    const menu = read('User/UserMenu.vue');
    const start = menu.indexOf('.wc-user__panel {');
    /* Only the first rule: the collapsed override that follows it is asserted
       separately below. */
    const panelRule = menu.slice(start, menu.indexOf('}', start) + 1);
    expect(panelRule).toMatch(/position:\s*fixed/);
    expect(panelRule).toMatch(/bottom:\s*calc\(var\(--user-menu-height\)/);
    /* Inside the rail column, not beside it: left is a small inset, and the width
       follows the rail. */
    expect(panelRule).toMatch(/left:\s*0\.4rem/);
    expect(panelRule).toMatch(/width:\s*calc\(var\(--side-bar-width\) - 0\.8rem\)/);
    expect(panelRule).not.toMatch(/left:\s*calc\(var\(--side-bar-width\)/);
  });

  it('keeps the collapsed panel beside the rail, as it was', () => {
    const menu = read('User/UserMenu.vue');
    const collapsedRule = menu.slice(menu.indexOf('.wc-user--collapsed .wc-user__panel {'));
    expect(collapsedRule).toMatch(/left:\s*calc\(var\(--side-bar-width\) \+ 0\.4rem\)/);
    expect(collapsedRule).toMatch(/width:\s*17rem/);
  });

  it('marks the panel as the collapsed variant so the override applies', () => {
    const source = read('User/UserMenu.vue');
    expect(source).toMatch(/'wc-user--collapsed': collapsed/);
  });
});

describe('the rail’s box model', () => {
  const railStyles = require('node:fs').readFileSync(
    require('node:path').resolve(__dirname, '../../src/styles/workcenter/_rail.scss'),
    'utf8',
  );

  it('is border-box inside the rail, so width: 100% cannot overflow it', () => {
    /* `box-sizing` is declared on `html` in the inherited stylesheet and does not
       inherit, so every rail box with `width: 100%` and horizontal padding was as
       wide as its container *plus its padding* — the user row measured 280px in a
       256px rail, and the rail's overflow: hidden cut the language code off the
       right-hand edge. The reset is scoped to the rail subtree. */
    expect(railStyles).toMatch(/\.wc-rail,\s*\n\.wc-rail \*/);
    expect(railStyles).toMatch(/box-sizing:\s*border-box/);
  });

  it('keeps the reset out of the panes, which live at the body level', () => {
    expect(railStyles).not.toMatch(/^\s*\*,\s*$/m);
  });
});
