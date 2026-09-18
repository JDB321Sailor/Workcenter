# Workcenter — Design Specification

> **Scope:** every user-interface element of the Workcenter application: structure, layout, states,
> interaction, theming, accessibility and responsiveness.
> **Foundations:** [Workcenter](https://github.com/JDB321Sailor/Workcenter)'s theming model, CSS custom properties and
> Workspace view layout; [FileBrowser Quantum's sidebar](https://filebrowserquantum.com/en/docs/features/sidebar-links/)
> as the sidebar interaction pattern.
> **Companions:** [`roadmap.md`](./roadmap.md) · [`architecture.md`](./architecture.md) · [`standards.md`](./standards.md)

---

## 1. Design principles

| # | Principle | What it means in practice |
| --- | --- | --- |
| P1 | **The applications are the content; Workcenter is the frame** | Chrome is neutral, thin and quiet. Nothing in the shell competes with the embedded application for attention. |
| P2 | **One rail, always in the same place** | The left rail never moves, never collapses unexpectedly and never changes width between applications. Only its *contents* change. |
| P3 | **Switching is not navigating** | Moving between Files, Chat and Mail is a mode change, not a page load. State is preserved: scroll position, open drafts, half-typed messages, expanded folders. |
| P4 | **The three applications must be instantly distinguishable** | Each carries an accent colour, an icon and a label, applied consistently on the switcher, the sidebar's active affordance and the pane's loading state. |
| P5 | **File movement is a first-class action, not a settings trip** | The four transfer actions appear where the file already is — on the attachment, in the compose box, in the message action menu. |
| P6 | **Failure is visible, never blank** | A pane that cannot load shows a diagnostic card with the failing check and a Retry. A silent empty iframe is a bug. |
| P7 | **Theme once, apply everywhere** | The shell owns the theme; the theme bridge pushes light/dark into each application where the application supports it. |
| P8 | **Keyboard-first is a supported mode** | Every shell action is reachable without a pointer. |

---

## 2. Screen structure

Workcenter renders **one screen**. There are no sub-pages, no modals that replace the screen, and no
second navigation level beyond the rail.

```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│ ┌───────────────────┐ ┌─────────────────────────────────────────────────────────────┐ │
│ │  BRAND / HEADER   │ │                                                             │ │
│ │  Workcenter  [◧]  │ │                                                             │ │
│ ├───────────────────┤ │                                                             │ │
│ │  APP SWITCHER     │ │                                                             │ │
│ │  ┌─────┬─────┬──┐ │ │                                                             │ │
│ │  │Files│Chat │Ma│ │ │                    CONTENT SURFACE                          │ │
│ │  └─────┴─────┴──┘ │ │                                                             │ │
│ │    ●     ●    ●   │ │      the active application, embedded in a persistent      │ │
│ │      STATUS       │ │      iframe. Panes stay mounted; switching toggles           │ │
│ ├───────────────────┤ │      visibility only.                                       │ │
│ │                   │ │                                                             │ │
│ │  SEARCH (global)  │ │                                                             │ │
│ ├───────────────────┤ │                                                             │ │
│ │                   │ │                                                             │ │
│ │  SIDEBAR BODY     │ │                                                             │ │
│ │  (swaps with the  │ │                                                             │ │
│ │   active app)     │ │                                                             │ │
│ │                   │ │                                                             │ │
│ │  • Files  → sources, folders, links                                           │ │
│ │  • Chat   → channels, topics, DMs                                             │ │
│ │  • Mail   → mail folders, calendars, address books                            │ │
│ │                   │ │                                                             │ │
│ ├───────────────────┤ │                                                             │ │
│ │  USER MENU        │ │                                                             │ │
│ └───────────────────┘ └─────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────────────────┘
        RAIL (fixed, --side-bar-width)          SURFACE (fluid)
```

### 2.1 Regions

| Region | Component | Fixed/Fluid | Scrolls | Ref |
| --- | --- | --- | --- | --- |
| Brand header | `AppSwitcher` container header | Fixed height `--rail-header-height` | No | D-1 |
| Application switcher **with status indicators** | `AppSwitcher.vue` | Fixed height `--switcher-height` | No | D-2 |
| Global search | `SidebarSearch.vue` | Fixed height | No | D-3 |
| Sidebar body | `AppSidebar.vue` | Fluid | **Yes** | D-4 |
| User menu | `UserMenu.vue` | Fixed height | No | D-6 |
| Content surface | `PaneHost.vue` | Fluid, fills remainder | Per pane | D-7 |

The rail has **six** regions. Switcher and status share one region: the indicators are part of the
application switcher, not a separate row.


### 2.2 Layout tokens

Extends Workcenter's `src/styles/dimensions.scss`.

| Token | Default | Meaning |
| --- | --- | --- |
| `--side-bar-width` | `16rem` | Rail width. Workcenter's value is `3.5rem` (icons only); Workcenter widens it because its sidebars carry labels, not just icons. |
| `--side-bar-width-collapsed` | `3.5rem` | Rail width when collapsed to icons. Equals Workcenter's `--side-bar-width`, so a collapsed Workcenter rail has exactly Workcenter's geometry. |
| `--rail-header-height` | `3rem` | Brand header row. |
| `--switcher-height` | `4.5rem` | Application switcher region: the button row **and** the status indicator row plus its label. |
| `--switcher-button-height` | `2.5rem` | A single switcher button. |
| `--switcher-indicator-height` | `2rem` | The status indicator row and the `STATUS` label beneath the buttons. |
| `--sidebar-search-height` | `2.5rem` | Global search row. |
| `--user-menu-height` | `3rem` | User menu row. |
| `--header-height` | `0` | **Kept as a token, set to `0`.** Workcenter shows a `6.3rem` header on the Workspace view and positions the iframe at `calc(100% - var(--header-height))`. Workcenter replaces that header with the rail's brand header (D-1) and sets this token to `0`, so every inherited `calc()` expression stays correct without editing any component. Re-introducing a top header means changing this token only. |
| `--pane-gutter` | `0` | No gutter between rail and surface — the embedded app owns its own padding. |
| `--rail-transition` | `180ms ease` | Width and collapse transitions. |

> **Rule D-L1:** the content surface is positioned at `left: var(--side-bar-width)` with width
> `calc(100% - var(--side-bar-width))` and height `calc(100% - var(--header-height))` — Workcenter's exact
> positioning contract, preserved so inherited layout code and themes keep working. No element may
> overlap the rail.

---

## 3. Element specification

### D-1 — Brand header

| Property | Value |
| --- | --- |
| Content | Workcenter mark + wordmark "Workcenter" (hidden when collapsed) |
| Height | `--rail-header-height` |
| Behaviour | Clicking the wordmark returns the shell to the last-used application |
| Right affordance | Rail collapse/expand toggle (`aria-expanded`) |
| Collapsed state | Mark only, centred |

The wordmark is the only place the product name appears in the shell. No page title bar, no breadcrumb.

---

### D-2 — Application switcher

**The defining element of Workcenter.** Sits directly above the sidebar body, at the top of the rail.
It combines the three application buttons with the per-application status indicators in a single
element.

```
┌──────────────────────────────────────────┐
│  ┌────────────┐ ┌────────────┐ ┌───────┐ │
│  │ 🗂  Files  │ │ 💬  Chat   │ │ ✉ Mail│ │
│  │  ▔▔▔▔▔▔▔▔  │ │            │ │       │ │
│  └────────────┘ └────────────┘ └───────┘ │
│      ●              ●             ●      │
│                 STATUS                   │
└──────────────────────────────────────────┘
   active: accent underline + accent text
   indicator: one per button, directly beneath it
```

| Property | Specification |
| --- | --- |
| Element | `AppSwitcher.vue`, containing three `AppSwitchButton.vue` and three `StatusIndicator.vue` |
| Count | Exactly **three** applications: `files`, `chat`, `mail` |
| Button contents | Icon (24px) above or beside a label; label is always visible unless the rail is collapsed |
| Active indicator | 3px accent underline **plus** accent-coloured icon and label **plus** `aria-current="page"` — never colour alone |
| Accent per application | Files = `--wc-accent-files` (blue), Chat = `--wc-accent-chat` (violet), Mail = `--wc-accent-mail` (teal) |
| Inactive state | `--side-bar-color` at 70% opacity |
| Hover state | Background `--side-bar-background-lighter`, icon at 100% opacity |
| Focus state | 2px visible ring using `--wc-focus-ring`, offset 2px |
| Disabled state | Only when the application is **unavailable**: 40% opacity, `cursor: not-allowed`, tooltip explaining why, and an `unhealthy` indicator |
| Layout | Equal-width flex row; wraps to a vertical icon-only stack when the rail is collapsed |
| Keyboard | `Alt+1` Files, `Alt+2` Chat, `Alt+3` Mail; `Tab`/`Shift+Tab` traverse; `Enter`/`Space` activate |
| Announcement | `role="tablist"` with `role="tab"` buttons and a `role="tabpanel"` surface; the active tab is `aria-selected="true"` |

**Behaviour on activation**

1. The shell records the previous application's scroll position and focus target.
2. The pane for the new application becomes visible; the previous pane is hidden but **kept mounted**.
3. The sidebar body swaps instantly to the new application's navigator (no loading spinner — the sidebar is shell-local data).
4. The route updates to `/files`, `/chat` or `/mail` so the view is linkable and survives reload.
5. If the target pane has never loaded, its iframe is created at this moment and shows the pane loading state (D-7).

> **Rule D-2.1:** the switcher must never trigger a full page reload.
> **Rule D-2.2:** activating the already-active application is a no-op except that it re-focuses the pane.

#### D-2I — Switcher icons

Each switcher button carries the **real brand mark** of the application behind it, so the button names
the product the user is about to see. The marks are committed to the repository; the shell never
fetches an icon from a third-party CDN at runtime.

| Button | Asset | Represents |
| --- | --- | --- |
| Files | `icons/filebrowser-quantum.svg` | FileBrowser Quantum |
| Chat | `icons/zulip.svg` | Zulip |
| Mail | `icons/mailcow.svg` | Mailcow (the deployment that serves SOGo webmail) |

The same set covers the rest of the shell's application references:

| Asset | Used by |
| --- | --- |
| `icons/sogo.svg` | The Mail pane's loading and `auth-error` states, where the surface being reached is SOGo itself |
| `icons/onlyoffice.svg` | The Files pane's editor hand-off state |
| `icons/traefik.svg` | User menu → **Integrations** (admin only, D-6.3) |
| `icons/authentik.svg` | User menu → **Identity** (admin only, D-6.3) |

| Ref | Requirement |
| --- | --- |
| D-2I.1 | Icons live in `icons/` at the repository root — one SVG per application, named for the application, and are the single source of truth for every application mark in the shell. |
| D-2I.2 | Every mark is sourced from [Dashboard Icons](https://dashboardicons.com) in its **base (SVG)** variant, keeping the upstream filename so a refresh is a straight re-download. Attribution is recorded in [`docs/credits.md`](./docs/credits.md). |
| D-2I.3 | Components reference them through the `@icons` path alias (`@icons/zulip.svg`), so the bundler emits them as hashed assets and a missing file is a **build** failure rather than a broken image at runtime. |
| D-2I.4 | A brand mark is rendered as an `<img>` at its own colours and is **never recoloured, tinted or masked** — active state is carried by the underline, the label colour and `aria-current` (D-2), not by the mark. |
| D-2I.5 | Marks are rendered at 24px in the switcher, 20px in sidebar rows and user-menu rows, and 48px in pane loading and error states. The SVG scales; no second raster asset is committed. |
| D-2I.6 | A brand mark is decorative whenever it sits next to its own text label (`aria-hidden="true"`); where it appears without a label — the collapsed rail — the button carries the application name as its accessible name. |
| D-2I.7 | Marks are identical in light and dark mode. Where a mark would fail the 3:1 non-text contrast check against the rail in one mode, the **button**, not the mark, gains a neutral `--wc-icon-plate` backing. |
| D-2I.8 | No SVG in `icons/` may contain a `<script>`, an event-handler attribute or a reference to a remote resource. This is checked in CI alongside lint. |

---

### D-2S — Status indicators (inside the application switcher)

Per-application health lives **inside** the application switcher, directly beneath the buttons, so a
user sees at a glance which applications are working before clicking.

```
   ┌────────────┐ ┌────────────┐ ┌────────────┐
   │ 🗂  Files  │ │ 💬  Chat   │ │ ✉  Mail   │
   └────────────┘ └────────────┘ └────────────┘
         ●              ●              ●
                    STATUS
```

| Property | Specification |
| --- | --- |
| Element | `StatusIndicator.vue` — one per application, rendered by `AppSwitcher.vue` |
| Placement | **Directly beneath its own application button**, horizontally centred on that button's axis |
| Row | A single row of three indicators, one per button, aligned to the buttons above them |
| Label | A single `STATUS` label centred beneath the indicator row, so the indicators' purpose is known. Uppercase, `--wc-text-muted`, letter-spaced, `0.625rem`, non-interactive, `aria-hidden="true"` (the indicators carry their own accessible names) |
| Shape | 8px filled circle |
| States | `healthy` (green), `degraded` (amber — reachable but a sub-check is failing, e.g. Zulip's event long-poll), `unhealthy` (red), `unknown` (grey — first poll pending) |
| Tooltip | Service name, the check that produced the state, last check time, and — for a non-healthy indicator — the failing endpoint |
| Click | A non-healthy indicator opens that pane's diagnostic card (D-7); a healthy indicator focuses the pane. Clicking the indicator must not change the active application |
| Update | Polled by `HealthService.js`; default interval 30s, exponential backoff to 5 minutes while healthy |
| Collapsed rail | The indicator row and the `STATUS` label remain visible beneath the icon stack; the label may be omitted when the rail is collapsed |
| Accessibility | Each indicator is a `<button>` with the application name and state in its accessible name (for example `Chat status: healthy`), so state is never conveyed by colour alone. The group is `role="group"` labelled `STATUS`. A state change announces politely on the group |

> **Rule D-2S.1:** the indicators never block the UI. A failed health poll marks its indicator
> `unknown` and logs to the console; it never throws into the shell.
> **Rule D-2S.2:** the indicator row is part of `--switcher-height`. It is never a separate rail
> region and never scrolls.
> **Rule D-2S.3:** every indicator has exactly one corresponding button, in the same order.

---

### D-3 — Sidebar search

| Property | Value |
| --- | --- |
| Purpose | Filter the **sidebar body** of the active application; never searches across applications |
| Placeholder | `Search files…` / `Search chats…` / `Search mail…`, driven by the active application |
| Behaviour | Type-to-filter, debounce 150ms, results replace the sidebar list in place |
| Empty result | "No matches in `<application>`" with a hint to search inside the application itself |
| Clearing | `Esc` restores the unfiltered list and returns focus to the field |
| Shortcut | `Ctrl/Cmd+K` focuses the field |

Search is a **shell-local filter over already-known sidebar entries**. Deep search inside an
application is that application's own job; the shell offers an "Open search in `<application>`" row
at the bottom of the results that deep-links into the embedded app.

---

### D-4 — Sidebar body (swaps per application)

The sidebar body is a slot host. Each application supplies a navigator that follows the **same visual
grammar**, honouring the FileBrowser Quantum sidebar pattern:

| Grammar rule | Specification |
| --- | --- |
| Row | `SidebarItem.vue` — icon (20px) + label, 32px tall, 8px horizontal padding, 6px radius |
| Group | Optionally collapsible, with a chevron and a persisted open/closed state per user |
| Divider | 1px `--side-bar-color` at 12% opacity, with optional group label |
| Active row | Background `--side-bar-item-background`, accent left border 2px, label at full opacity |
| Hover | Background `--side-bar-background-lighter` |
| Badge | Right-aligned pill (unread count for Chat, unread count for Mail, indexing status for Files) |
| Indentation | One level only (group → item). No third level; deeper navigation happens inside the pane |
| Long labels | Single line, ellipsis, full text in `title` and on focus tooltip |
| Scroll | The body scrolls; the switcher (including its status indicators), search and user menu do not |

#### D-4.1 Files sidebar (`FilesSidebar.vue`)

| Group | Contents | Source |
| --- | --- | --- |
| **Sources** | One row per configured FileBrowser source, with a usage bar and a status dot (green ready / amber indexing / red unavailable) | FileBrowser Quantum sources API |
| **Quick access** | User-pinned folders (the same concept as FileBrowser's custom sidebar links) | User profile |
| **Tools** | Deep links into FileBrowser Quantum's tools (search, size viewer, activity) | Static registry |
| **Actions** | "New folder", "Upload" — both deep-link into the FileBrowser pane with the appropriate action primed | Static registry |

Selecting a source or folder navigates the **Files pane** to that path and marks the row active.

#### D-4.2 Chat sidebar (`ChatSidebar.vue`)

| Group | Contents | Source |
| --- | --- | --- |
| **Views** | Inbox, Recent conversations, Combined feed, Mentions, Starred, Drafts | Deep links into Zulip |
| **Channels** | Subscribed channels, unread badge, collapsible "more" | Zulip API (`/api/v1/users/me/subscriptions`) |
| **Direct messages** | Recent DM conversations | Zulip API |
| **Files** | "Send a file from my files" action (F4 entry point) | Broker |

#### D-4.3 Mail sidebar (`MailSidebar.vue`)

| Group | Contents | Source |
| --- | --- | --- |
| **Mail** | Inbox, Drafts, Sent, Junk, Trash, Archive, with unread counts | SOGo / Mailcow |
| **Calendars** | Personal and shared calendars with a colour swatch | SOGo |
| **Address books** | Personal and shared contacts | SOGo |
| **Files** | "Save an attachment to my files" hint row that opens the Mail pane and explains the flow (F1 entry point) | Broker |

> **Rule D-4.1:** sidebar data is loaded by the shell through the broker's read-only endpoints and
> cached in the `apps` Vuex module; a failed fetch degrades to a static, still-usable list.
> **Rule D-4.2:** every sidebar row is a real link (`<a>` with an `href` where an in-app route
> exists), so middle-click and "copy link" behave as users expect.

---

### D-6 — User menu

The rail's footer. A trigger row that is always visible, and a popover that holds identity, the two
preference controls Workcenter owns — **appearance** and **language** — the admin links, and Logout.

```
┌────────────────────────────────────┐
│  Jane Doe                          │
│  jane@example.com                  │
│  Workspace user · Admin            │
├────────────────────────────────────┤
│  Appearance      [ ☾ Dark ][ ☀ ]   │   D-6.1  dark is the default
│  Language        English   [ 🏴 ▾ ]│   D-6.2  language in use + flag button
├────────────────────────────────────┤
│  Integrations                    ↗ │   D-6.3  admin only
│  Mail admin                      ↗ │
│  Identity                        ↗ │
├────────────────────────────────────┤
│  Sign out                          │
└────────────────────────────────────┘
          ▲ anchored to the trigger row
┌────────────────────────────────────┐
│  ⬤  Jane Doe              Admin    │   the trigger row, in the rail footer
└────────────────────────────────────┘
```

| Property | Value |
| --- | --- |
| Collapsed content | Avatar (or initials) + admin badge when applicable |
| Expanded content | Display name, email, group summary, **appearance control (D-6.1)**, **language control (D-6.2)**, admin links (admin only, D-6.3), Logout |
| Admin badge | Small pill reading `Admin`; shown when the token carries `workspaceadmin` |
| Logout | Ends the Workcenter session and performs RP-initiated logout at Authentik so all panes end with it |
| Position | Anchored bottom of the rail; a popover, not a route |
| Keyboard | `Tab` reaches the trigger; `Enter` opens; arrow keys traverse; `Esc` closes and restores focus |
| Order | Identity → appearance → language → admin links → Logout. Logout is always last and always separated by a divider, so it is never hit by accident |
| Collapsed rail | The trigger becomes the avatar alone; the popover is unchanged and opens to the right of the rail |

> **Rule D-6.1:** the user menu is the **only** place in the shell that changes appearance or
> language. There is no settings route, no configuration modal and no second entry point.
> **Rule D-6.2:** both controls apply immediately. Neither has an Apply button and neither reloads the
> Workcenter page. A pane is refreshed only in the narrow case D-T6 allows, and never while work is
> unsaved (D-T7).

#### D-6.1 — Appearance: the light/dark mode switcher

| Property | Specification |
| --- | --- |
| Element | `ThemeSwitcher.vue`, rendered in the user-menu popover |
| Shape | A two-option segmented control, both options always visible, so the current mode is readable without opening a menu |
| Options | **Dark** (moon glyph) and **Light** (sun glyph) |
| Default | **Dark.** A user who has never chosen lands in `workcenter-dark` |
| Expressing the default | The dark option is labelled `Dark (default)` until the user makes a choice, and the row's helper text reads `Dark is the Workcenter default — switch any time.` After an explicit choice the suffix is dropped and the helper text names where the mode is applied: `Applied to Workcenter, Files, Chat and Mail.` |
| State | The active option carries the accent background, the accent text colour, `aria-checked="true"` and a check glyph — never colour alone |
| Semantics | `role="radiogroup"` labelled `Appearance`, with two `role="radio"` options; `←`/`→` move between them, `Space` selects |
| Scope | Changes the shell **and** every embedded application, through the theme bridge in [§4.4](#44-the-theme-bridge-forwarding-the-mode-switch) |
| Persistence | Written to the user's Workcenter profile (server-side, so the mode follows the user to another browser) and mirrored into `localStorage` so the first paint after a reload is already correct and never flashes |
| Feedback | The switch is instant for the shell. Each pane reports back through the bridge; a pane that does not confirm within 3 s is listed in a quiet inline note: `Chat is still switching…`, replaced by `Chat could not switch — open Zulip to change it there` on failure |
| Reduced motion | The colour transition is suppressed under `prefers-reduced-motion: reduce`; the change is still instant |

> **Rule D-6.3:** light/dark is the **only** look-and-feel control Workcenter offers a user. There is
> no theme gallery, no accent picker and no per-application appearance override in the shell. Every
> other visual decision is made once, at deployment, by [§4.6](#46-branding-the-embedded-applications).
> **Rule D-6.4:** the mode switch never discards a draft, an upload or an open editor inside a pane.
> Where applying the mode needs a pane refresh, that refresh waits (D-T7).

#### D-6.2 — Language: language in use, and the flag button

| Property | Specification |
| --- | --- |
| Element | `LanguageSwitcher.vue`, rendered directly beneath the appearance control |
| Row contents | The label `Language`, the **language in use** written in its own endonym (`English`, `Deutsch`, `Français`), and a **flag button** to its right |
| Flag button | A button whose face is the flag of the active language, with a small chevron; activating it opens the language menu |
| Why a flag | The rail is narrow and the row is scanned, not read. The flag makes the current language recognisable at a glance to a user who cannot read the shell's current language well enough to find the setting |
| Flag source | The active language's flag emoji, taken from the locale registry in `src/utils/languages.js`. It is a font glyph, not an image asset, so it costs nothing and needs no icon set |
| Fallback | A language with no single unambiguous flag uses a globe glyph (`🌐`). The registry, not the component, decides |
| Accessibility | The flag is decorative (`aria-hidden="true"`). The button's accessible name is `Change language — currently English`, so the flag never carries meaning on its own (D-A5) |
| Menu | A listbox anchored to the button: one row per available language, each showing flag + endonym + English name, the active row marked with a check and `aria-selected="true"` |
| Menu keyboard | `↑`/`↓` move, `Home`/`End` jump, typing filters by endonym or English name, `Enter` selects, `Esc` closes and returns focus to the flag button |
| Filter field | Shown only when more than twelve languages are available |
| On selection | The shell swaps its strings immediately, sets `document.documentElement.lang` (D-A9), re-formats dates, sizes and numbers through `Intl`, and forwards the choice to the panes through the language bridge in [§8.2](#82-the-language-bridge) |
| Persistence | Identical to the mode: user profile first, `localStorage` mirror second |
| First run | With no stored preference the shell uses the browser's preferred language when a translation exists, and English otherwise |
| Not translated | Application names (`Files`, `Chat`, `Mail` are labels and *are* translated; `FileBrowser Quantum`, `Zulip`, `Mailcow`, `SOGo` are proper nouns and are not — D-I3) |

> **Rule D-6.5:** the language in use is always written in its own language. A user who has landed in
> the wrong language must be able to recognise the way back.
> **Rule D-6.6:** changing language never changes the mode, and changing the mode never changes the
> language. The two controls are independent.

#### D-6.3 — Admin links

| Property | Value |
| --- | --- |
| Links | "Integrations" → Traefik dashboard, "Mail admin" → Mailcow UI, "Identity" → Authentik. Each opens in a new tab with an external-link glyph and `rel="noopener"` |
| Icons | `icons/traefik.svg`, `icons/mailcow.svg`, `icons/authentik.svg` at 20px (D-2I.5) |
| Visibility | **Admin only** — rendered only when the token carries `workspaceadmin`. Hidden, not disabled |

---

### D-7 — Content surface and panes

| Property | Value |
| --- | --- |
| Container | `PaneHost.vue` — holds one `AppPane.vue` per application, all mounted after first activation |
| Pane | `AppPane.vue` — an `<iframe>` plus loading, error and unavailable states |
| iframe attributes | `allow="fullscreen; clipboard-read; clipboard-write"`, `referrerpolicy="same-origin"`, `loading="eager"`, a stable `id` per application |
| Sizing | `position: absolute; inset: 0 0 0 var(--side-bar-width)`, matching Workcenter's `WebContent.vue` contract |
| Visibility | Inactive panes get `.wc-pane--hidden { display: none }`; state inside the iframe is untouched |
| Background | `--workspace-web-content-background` (kept from Dashy), so an app's own white/dark surface does not flash the shell colour |

#### Pane states

| State | Appearance | Exit |
| --- | --- | --- |
| `idle` | Not yet activated. Nothing rendered. | Activation creates the iframe |
| `loading` | Rail-accent spinner centred, application name, "Connecting to `<host>`", and a hint after 5s | Load event or timeout |
| `ready` | The iframe, at full size | — |
| `unavailable` | App not deployed or health `unhealthy`: icon, name, one-line reason, **Retry**, and a **Open in new tab** fallback | Retry re-runs the health check and reloads the iframe |
| `blocked` | The app refuses to be framed: explain that the application must allow framing from the Workcenter origin, name the header to change, and link to `docs/troubleshooting.md` | Manual; documented fix |
| `auth-error` | The pane redirected to a login page: "Your session for `<app>` has expired" with a **Sign in again** action that opens the app's OIDC entry point in a new tab | Re-authentication |

> **Rule D-7.1:** the shell always detects "the iframe loaded a login page" and shows the `auth-error`
> state instead of a login form nested inside the shell.
> **Rule D-7.2:** **Open in new tab** is always available from the pane's overflow menu, so the user
> is never trapped by an application that misbehaves inside a frame.

#### Pane overflow menu

A small `⋯` button in the pane's top-right hotspot (revealed on hover/focus, always keyboard
reachable) with: Reload pane, Open in new tab, Copy link to this view, and — admin only — "Show
health detail".

---

### D-8 — File-movement elements

These are the UI for the four flows in [`roadmap.md` §7.2](./roadmap.md#72-the-four-flows).

#### D-8.1 Attachment row action (F1 — Mail → Files)

| Property | Value |
| --- | --- |
| Placement | Injected next to each attachment in the Mail pane, and listed in the shell's Mail-pane attachment panel |
| Label | **Save to files** with a download-to-folder icon |
| Interaction | Click → destination confirmation (folder + filename, de-duplicated) → progress → success toast with **Open folder** |
| Duplicate handling | If an identical file exists, the confirmation reads `report.pdf already exists — save as report (2).pdf` |

#### D-8.2 File picker modal (F2, F4 — Files → Mail, Files → Zulip)

| Property | Value |
| --- | --- |
| Trigger | **Attach from files** in the mail compose window; **Send from files** in the Zulip compose box |
| Shape | Centred modal, max-width 40rem, max-height 70vh, backdrop `--wc-scrim` |
| Contents | Breadcrumb of the FileBrowser path, a list of folders/files, a search field, size and modified date per row |
| Multi-select | Supported for mail attachments; single-select for Zulip send |
| Size guard | Files above the configured cap are shown disabled with the reason |
| Confirm | Primary button reads `Attach` or `Send`; disabled until a valid selection exists |
| Keyboard | `↑`/`↓` move, `→` enters a folder, `←` goes up, `Enter` confirms, `Esc` cancels |

#### D-8.3 Transfer progress

| Property | Value |
| --- | --- |
| Placement | A compact card in the rail beneath the application switcher, plus an optional toast |
| Contents | Direction icon, source → destination, filename, progress bar, byte counter, **Cancel** |
| States | `queued`, `running`, `finalising`, `done`, `cancelled`, `failed` |
| Failure | Reason in plain language plus a **Retry** where the failure is transient |
| Completion | Toast: `<filename> saved to Files` with **Open folder** / **Open message** |
| Concurrency | Multiple simultaneous transfers render as a stack, newest first |
| Persistence | Transfers survive application switching (they belong to the shell, not the pane) |

#### D-8.4 Notification toasts

| Property | Value |
| --- | --- |
| Position | Bottom-right of the content surface, above the pane |
| Duration | 5s for success, persistent until dismissed for failures |
| Content | Icon, one-line message, up to two actions, dismiss button |
| Accessibility | `role="status"` for success, `role="alert"` for failure |

---

## 4. Theming

### 4.1 Token architecture

Workcenter keeps Workcenter's two-layer model:

1. **Palette layer** (`src/styles/color-palette.scss`) — raw colour values as CSS custom properties.
2. **Semantic layer** (`src/styles/workcenter/*.scss`) — meaning-bearing tokens that components use.

Components reference **semantic tokens only**. No component contains a colour literal.

### 4.2 Workcenter semantic tokens

| Token | Purpose |
| --- | --- |
| `--wc-surface` | Shell background behind panes |
| `--wc-surface-raised` | Cards, popovers, modals |
| `--wc-surface-sunken` | Inset surfaces: search field, pane letterbox, icon wells |
| `--wc-border` | Hairlines and dividers |
| `--wc-text` / `--wc-text-muted` | Primary and secondary text |
| `--wc-accent-files` | Files accent (blue) |
| `--wc-accent-chat` | Chat accent (violet) |
| `--wc-accent-mail` | Mail accent (teal) |
| `--wc-icon-plate` | Neutral backing behind a brand mark that would otherwise fail contrast against the rail (D-2I.7) |
| `--wc-focus-ring` | Focus ring colour, ≥3:1 against both surface and accent |
| `--wc-scrim` | Modal backdrop |
| `--wc-status-healthy` / `--wc-status-degraded` / `--wc-status-unhealthy` / `--wc-status-unknown` | Application switcher status indicators |
| `--wc-radius` | Corner radius (Workcenter's `--curve-factor` is aliased to this) |
| `--wc-shadow-popover` | Popover elevation |

Retained Workcenter tokens (unchanged names, so Workcenter themes keep working): `--side-bar-width`,
`--side-bar-background`, `--side-bar-background-lighter`, `--side-bar-color`,
`--side-bar-item-background`, `--side-bar-item-color`, `--workspace-web-content-background`,
`--curve-factor`.

### 4.3 Themes

| Theme | Notes |
| --- | --- |
| `workcenter-dark` | **Default.** Neutral near-black surface, accents at 60% lightness |
| `workcenter-light` | Neutral off-white surface, accents at 40% lightness |
| `workcenter-contrast` | High-contrast variant meeting WCAG AAA for shell chrome |
| Inherited Workcenter themes | Kept where they only affect tokens; themes referencing removed components are deleted |

A user chooses between **dark** and **light** only, from the user menu (D-6.1). `workcenter-contrast`
is selected by the operator in `user-data/conf.yml` or by the user's own
`prefers-contrast: more`; it is not a third button in the shell.

#### 4.3.1 Where the palette comes from

**FileBrowser Quantum is the appearance standard.** It occupies the Files pane, it is the surface a
user sees most, and it is the only one of the three applications whose light and dark palettes are
configurable. Workcenter therefore adopts FileBrowser Quantum's own values as the reference and
derives everything else — its own tokens, and the branding it pushes into the other applications —
from them.

The reference values, read from the pinned FileBrowser Quantum 2.0.6-beta image (its palette is
emitted into `:root` and `.dark-mode` in the served `index.html`):

| FileBrowser variable | Light | Dark | Workcenter token |
| --- | --- | --- | --- |
| `--background` | `#f5f5f5` | `#141D24` | `--wc-surface` |
| `--surfacePrimary` | `#ebebeb` | `#20292F` | `--wc-surface-raised` |
| `--surfaceSecondary` | `lightgray` | `#3A4147` | `--wc-surface-sunken` |
| `--textPrimary` | `#546e7a` | `rgba(255,255,255,0.87)` | `--wc-text` |
| `--textSecondary` | `gray` | `rgba(255,255,255,0.6)` | `--wc-text-muted` |
| `--divider` | `lightgray` | `rgba(255,255,255,0.12)` | `--wc-border` |
| `--primaryColor` | `#2196f3` (`var(--blue)`) | `#2196f3` | `--wc-accent-files` |

| Ref | Requirement |
| --- | --- |
| D-T3 | The shell's `--wc-surface`, `--wc-surface-raised`, `--wc-text`, `--wc-text-muted` and `--wc-border` values in each mode are the FileBrowser Quantum values above. A change to one is a change to both, in the same PR. |
| D-T4 | `--wc-accent-files` is FileBrowser Quantum's `--primaryColor`, so the Files accent and the Files pane agree exactly. `--wc-accent-chat` and `--wc-accent-mail` are chosen to sit at the same lightness and chroma as that blue in each mode, so no application looks louder than another. |

### 4.4 The theme bridge: forwarding the mode switch

The user switches mode once, in the user menu (D-6.1). The shell's job is to make that one switch
visible **everywhere** — its own chrome and all three embedded applications — because a dark rail
wrapped around a white mail client is worse than either choice made consistently.

The three applications expose three different capabilities, and the bridge is built around what each
one actually supports rather than around a single mechanism that would have to be faked:

| Application | What it supports | How Workcenter drives it | Live? |
| --- | --- | --- | --- |
| **FileBrowser Quantum** | A per-user `darkMode` boolean. The SPA applies it from its own store; there is no inbound message channel and no theme query parameter | The broker calls `PATCH /api/users?username=<login>` with `{"which":["darkMode"],"data":{"darkMode":<bool>}}` (→ `204`), then the shell re-loads that pane at its current path | After a pane refresh |
| **Zulip** | A per-user `color_scheme` setting, pushed to every open client over its event queue | The broker calls `PATCH /api/v1/settings` with `color_scheme=2` (dark) or `3` (light). Zulip's client swaps the `dark-theme` class on `:root` from the resulting `user_settings` event | **Yes — no reload** |
| **SOGo** | Nothing. SOGo 5.12 has no dark mode, no theme preference and no appearance setting | Workcenter's own stylesheet, injected by the SOGo JavaScript hook provisioned at setup ([§4.6](#46-branding-the-embedded-applications)), which flips a `data-wc-mode` attribute | **Yes — no reload** |

#### 4.4.1 The switch, step by step

1. The shell sets `data-wc-mode="dark"` or `"light"` on `<html>`. Chrome repaints from tokens; nothing
   is fetched and nothing is remounted.
2. The shell stores the choice: the user's Workcenter profile, a `localStorage` mirror, and the
   **mode cookie** (4.4.2).
3. The shell posts `{ type: 'workcenter:mode', mode }` to every mounted pane's `contentWindow` with
   that pane's **exact origin** as `targetOrigin` — never `'*'`. Only SOGo listens; the other two
   ignore it harmlessly.
4. The shell calls `POST /api/broker/preferences` with the new mode. The broker fans out to
   FileBrowser Quantum and Zulip as in the table above, in parallel, and returns a per-application
   result.
5. Zulip and SOGo are already correct. The Files pane is refreshed once the broker reports `204`,
   reloading the **same path** the pane was last known to be on, so the user lands where they were.
6. Any application that failed is reported in the user menu's inline note (D-6.1), never as a modal
   and never as a silent failure.

#### 4.4.2 The mode cookie

First paint matters: an embedded application that loads light and then flips to dark is a flash of
the wrong colour on every pane load.

| Property | Value |
| --- | --- |
| Name | `wc_mode` |
| Values | `dark` \| `light` |
| Attributes | `Domain=.<base domain>`, `Path=/`, `SameSite=Lax`, `Secure`, `Max-Age` one year, **not** `HttpOnly` — the SOGo hook reads it from JavaScript |
| Purpose | Lets any Workcenter-owned host render in the right mode on its **first** paint, before any message arrives |
| Contents | The literal string `dark` or `light`. It carries no identity, no token and no personal datum, and nothing may ever be added to it |

> **Rule D-T5:** the shell's own repaint is instant and reloads nothing. The shell never blocks the
> user's chrome on an application's response.
> **Rule D-T6 (supersedes D-T2):** a pane is refreshed **only** where the application offers no live
> channel — today that is the Files pane alone — and only after the preference has been persisted, so
> the refresh lands on the new value. The refresh restores the pane's current path.
> **Rule D-T7:** the Files pane refresh is **deferred** while that pane is in a document editor
> (Workcenter knows the pane's path from the `filebrowser:navigation` message FileBrowser Quantum
> posts to its parent on every route change). While deferred, the user menu reads
> `Files will switch when you close the editor.` Unsaved work is never discarded to apply a colour.
> **Rule D-T8:** a pane message is always posted to an exact origin taken from the configured
> application URL. A listener inside an application must verify `event.origin` against the Workcenter
> origin and must act on nothing but the mode/language values. No pane message ever carries a token,
> a credential or user data.
> **Rule D-T2 (withdrawn):** superseded by D-T5 and D-T6. It required that no pane ever reload on a
> theme change; that is not achievable for FileBrowser Quantum, which has no live channel, and the
> user-visible requirement is that the mode change reaches every application.

#### 4.4.3 Not overwriting the user

> **Rule D-T1:** the theme bridge is **advisory**. Workcenter never overwrites a user's explicit
> in-application preference.

Enforcement is per application, not a single flag:

| Application | How D-T1 is honoured |
| --- | --- |
| Zulip | The realm-wide pass run by `setup.sh` uses `target_users` with `skip_if_already_edited: true`, which Zulip evaluates per setting against its own audit log: a user who has ever changed their own `color_scheme` is skipped. A user-initiated switch from the Workcenter user menu is that user's own explicit choice, so it always applies |
| FileBrowser Quantum | The bridge writes only in response to a user-initiated switch. The instance default (`userDefaults.ui.darkMode`) is written once at setup and never re-imposed on an existing user |
| SOGo | There is no user preference to overwrite |

### 4.5 Custom CSS

Administrators may inject a stylesheet through `appConfig.customCss` (Workcenter's mechanism) and users
through their profile. Custom CSS is scoped to shell chrome; it cannot reach inside iframes.

### 4.6 Branding the embedded applications

The bridge in §4.4 carries the **mode**. It cannot carry a look: three applications built by three
projects do not become one product because they are all dark. The remaining work — palette, logo,
name, corner radius — is done **once, at deployment, by `setup.sh`**, so that a running Workcenter
reads as one system. The operator contract, stage by stage, is in
[`production.md` §5.2a](./production.md#52a-stage-b1--branding-the-embedded-applications); the
mechanisms are:

| Application | What `setup.sh` sets | Mechanism |
| --- | --- | --- |
| **FileBrowser Quantum** | The reference palette itself, the Workcenter accent, the product name and the shell's corner radius | `frontend.styling.lightBackground`, `frontend.styling.darkBackground`, `frontend.styling.customCSS` (a path to a Workcenter stylesheet), `frontend.name`, `frontend.favicon`, `frontend.loginIcon`, and `userDefaults.ui.themeColor` in `Filebrowser/config.yaml` |
| **SOGo** | The whole Workcenter palette, in both modes — SOGo has none of its own | A Workcenter stylesheet mounted into SOGo's web resources, plus a block appended to Mailcow's SOGo JavaScript hook (`data/conf/sogo/custom-sogo.js`, already loaded through `SOGoUIAdditionalJSFiles`) that links the stylesheet, reads `wc_mode` for first paint and listens for `workcenter:mode`. Logos go in Mailcow's existing `data/conf/sogo/custom-fulllogo.svg` and `custom-shortlogo.svg` mounts |
| **Mailcow UI** | Palette and logo, so the authentication hand-off to SOGo and the admin surface match | `data/web/css/build/0081-custom-mailcow.css` (untracked upstream, survives `update.sh`), the Bootswatch theme selected by `$UI_THEME` in `data/web/inc/vars.local.inc.php` (also untracked), and the light/dark logos uploaded in **Configuration → Customize** |
| **Zulip** | Organisation name, icon and both logos | `PATCH /api/v1/realm` for the name, `POST /api/v1/realm/icon`, and `POST /api/v1/realm/logo` twice — `night=false` for the light logo and `night=true` for the dark one, so Zulip swaps logos with the theme. Zulip's new-user default is set with `PATCH /api/v1/realm/user_settings_defaults` (`color_scheme=2`) |

| Ref | Requirement |
| --- | --- |
| D-T9 | Every value `setup.sh` writes into an application's branding is **derived from the same palette source** ([§4.3.1](#431-where-the-palette-comes-from)). There is no second place where a Workcenter colour is decided. |
| D-T10 | Branding is **idempotent and re-appliable**: re-running `setup.sh` changes nothing if the branding is already current, and re-applies it after an application upgrade has reverted a file. |
| D-T11 | Branding never edits an upstream file that upstream also edits. Where the only available surface is such a file, the change is a delimited, re-appliable block and the fact is recorded in [`production.md` §10](./production.md#10-upgrading). |
| D-T12 | **Zulip cannot be restyled.** It ships no custom-CSS mechanism, and its production tarball contains no editable CSS. Workcenter brands Zulip with name, icon, logos and theme only, and does not fork it for appearance. Documentation must not imply otherwise. |
| D-T13 | Branding must never reduce contrast below the D-A1 floor inside an embedded application. Where a Workcenter colour would fail there, the application keeps its own value. |

---

## 5. Responsive behaviour

| Breakpoint | Behaviour |
| --- | --- |
| `≥ 1280px` | Full layout: expanded rail (16rem), labels visible, status indicators with the `STATUS` label |
| `1024–1279px` | Rail narrows to 14rem; sidebar badges compact |
| `768–1023px` | Rail auto-collapses to icons (3.5rem); switcher becomes a vertical icon stack with each indicator directly beneath its icon; tooltips carry labels; the `STATUS` label is omitted |
| `< 768px` | Rail becomes an overlay drawer opened from a persistent hamburger button; the pane occupies the full width; the switcher pins to the top of the drawer. **Declared a degraded experience** — the three applications are desktop-first and the shell does not attempt to reproduce them on small screens |

> **Rule D-R1:** the shell must never be the reason an application is unusable. On small screens the
> primary affordance becomes **Open in new tab**.

---

## 6. Motion

| Interaction | Motion |
| --- | --- |
| Application switch | Pane cross-fade 120ms; sidebar body swaps with no motion (it must feel instantaneous) |
| Rail collapse/expand | Width transition `--rail-transition` |
| Sidebar group expand | Height + opacity 140ms ease-out |
| Modal | Backdrop fade 120ms, panel scale 0.98→1 140ms |
| Toast | Slide-in from right 160ms, auto-dismiss fade 200ms |
| Progress bar | Linear, no easing; indeterminate state uses a 1.2s sweep |
| Status indicator change | Colour cross-fade 200ms |

> **Rule D-M1:** honour `prefers-reduced-motion: reduce` by disabling all non-essential motion
> (cross-fades, scale, slide) while keeping state changes visible.

---

## 7. Accessibility

| Ref | Requirement |
| --- | --- |
| D-A1 | The shell meets **WCAG 2.1 AA**: 4.5:1 for body text, 3:1 for large text, icons and UI borders. |
| D-A2 | The switcher is a proper tablist; the surface is its tabpanel; `aria-current`/`aria-selected` track the active application. |
| D-A3 | Every interactive element is reachable and operable by keyboard, in a logical order: brand → switcher → search → sidebar → status → user menu → pane. |
| D-A4 | Focus is always visible and is never trapped; when a modal closes, focus returns to the element that opened it. |
| D-A5 | Status is never conveyed by colour alone: each status indicator carries the application name and its state in its accessible name; active rows carry `aria-current`. |
| D-A6 | All icons that convey meaning have an accessible name; decorative icons are `aria-hidden`. |
| D-A7 | Live regions announce pane state changes, transfer progress milestones and health changes politely. |
| D-A8 | Text scales to 200% without loss of function; the rail collapses gracefully. |
| D-A9 | The shell declares `lang` and passes language changes to the document element. |
| D-A10 | Embedded applications are third-party surfaces: the shell provides an accessible **Open in new tab** escape and never claims the pane's content is accessible. |

---

## 8. i18n

### 8.1 Shell strings

| Ref | Requirement |
| --- | --- |
| D-I1 | Every shell string lives in `src/assets/locales/en.json` and is referenced with `$t('key')`. |
| D-I2 | Keys are namespaced by region: `switcher.*`, `sidebar.files.*`, `sidebar.chat.*`, `sidebar.mail.*`, `pane.*`, `status.*`, `transfer.*`, `user.*`. |
| D-I3 | Application names are **not** translated (they are proper nouns); their descriptors are. |
| D-I4 | Dates, file sizes and numbers are formatted with `Intl` using the active locale. |
| D-I5 | English is the master locale; adding a language requires no component changes. |
| D-I6 | Every language offered by the shell's switcher (D-6.2) has an entry in the locale registry carrying its endonym, its English name, its flag glyph, and the identifier each embedded application uses for the same language. A language with no mapping for an application is still offered — the shell simply cannot forward it there. |

### 8.2 The language bridge

Language forwards the same way the mode does, and for the same reason: a user who has put the shell
into German should not have to find three more language settings. The mechanism differs per
application because — as with appearance — each one names languages differently, and only two of the
four surfaces can be set programmatically at all.

| Application | Identifier space | How Workcenter drives it | Live? |
| --- | --- | --- | --- |
| **FileBrowser Quantum** | Its own internal keys, **not** BCP-47 (`en`, `de`, `fr`, `ptBR`, `zhCN`, `svSE`) | The broker calls `PATCH /api/users?username=<login>` with `{"which":["locale"],"data":{"locale":"<key>"}}` — the same endpoint the mode bridge uses, so one call can carry both | After a pane refresh |
| **Zulip** | Django language codes (`en`, `de`, `zh-hans`) | The broker calls `PATCH /api/v1/settings` with `default_language`. Zulip emits the setting change to the open client but **cannot** re-render without a reload — its own source says so — so the Chat pane is refreshed once the call succeeds | After a pane refresh |
| **SOGo** | SOGo language **names** (`English`, `German`, `BrazilianPortuguese`) — not tags | Not driven. SOGo resolves the user's own `SOGoLanguage` preference first, and otherwise takes the first of the browser's `Accept-Language` values that it supports, which already follows the user's browser | Not applicable |
| **Mailcow UI** | IETF tags of its own (`en-gb`, `de-de`) | Not driven. The admin links open it in a new tab where its own switcher applies | Not applicable |

| Ref | Requirement |
| --- | --- |
| D-I7 | The language bridge is **advisory**, exactly as D-T1 makes the theme bridge advisory. A user who has set a language inside an application keeps it. |
| D-I8 | A language change forwards in **one** broker call per application, batched with the mode when both changed, so the panes refresh at most once. |
| D-I9 | Refreshing a pane for a language change obeys D-T7: it waits for an open editor or an in-flight transfer. |
| D-I10 | Where an application cannot be driven (SOGo, the Mailcow UI), the shell says so plainly in the language menu's footer rather than silently doing nothing: `Mail follows your browser's language.` |
| D-I11 | The **language cookie** `wc_lang` mirrors `wc_mode` (4.4.2): same attributes, value is a BCP-47 tag, contents carry no identity. It exists so a Workcenter-owned surface can render in the right language on first paint. |

---

## 9. UI copy standard

| Rule | Example |
| --- | --- |
| Sentence case for all labels and headings | "Save to files", not "Save To Files" |
| Buttons are verb-first and name the object | "Attach from files", "Send to Zulip", "Save to files" |
| Errors state what happened and what to do | "Chat is not responding. Retry, or open Zulip in a new tab." |
| No exclamation marks, no blame, no jargon | "Your session for Mail has expired. Sign in again." |
| Empty states are actionable | "No files here yet. Upload one from FileBrowser, or save an attachment from Mail." |
| Never say "Workcenter" | The product is Workcenter |

---

## 10. Component inventory

| Component | Region | Spec |
| --- | --- | --- |
| `AppSwitcher.vue` | Rail | D-2 |
| `AppSwitchButton.vue` | Rail | D-2 |
| `StatusIndicator.vue` | Rail (inside `AppSwitcher`) | D-2S |
| `BrandHeader.vue` | Rail | D-1 |
| `SidebarSearch.vue` | Rail | D-3 |
| `AppSidebar.vue` | Rail | D-4 |
| `FilesSidebar.vue` | Rail | D-4.1 |
| `ChatSidebar.vue` | Rail | D-4.2 |
| `MailSidebar.vue` | Rail | D-4.3 |
| `SidebarItem.vue` | Rail | D-4 |
| `UserMenu.vue` / `UserBadge.vue` | Rail | D-6 |
| `PaneHost.vue` | Surface | D-7 |
| `AppPane.vue` | Surface | D-7 |
| `PaneErrorCard.vue` | Surface | D-7 |
| `PaneOverflowMenu.vue` | Surface | D-7 |
| `AttachmentRow.vue` | Overlay | D-8.1 |
| `FilePickerModal.vue` | Overlay | D-8.2 |
| `TransferProgress.vue` | Rail | D-8.3 |
| `TransferToasts.vue` | Surface | D-8.4 |
| `ThemeSwitcher.vue` | Popover | D-6.1 |
| `LanguageSwitcher.vue` | Popover | D-6.2 |
| `LanguageMenu.vue` | Popover | D-6.2 |
| `AppMark.vue` | Rail / Surface | D-2I |

Two non-component modules carry the bridges, so no component talks to an application directly:

| Module | Responsibility |
| --- | --- |
| `src/utils/Theming.js` | Owns `data-wc-mode`, the `localStorage` mirror and the `wc_mode` cookie; posts `workcenter:mode` to the panes; calls the broker |
| `src/utils/i18n.js` + `src/utils/languages.js` | The locale registry of D-I6 — endonym, English name, flag glyph and the per-application identifier — plus the same cookie/post/broker path for language |

---

## 11. Design review checklist

Every UI pull request is reviewed against this list:

- [ ] Does it change a **shell** element only — never the interior of an embedded application?
- [ ] Are the switcher, the sidebar contents and the pane all consistent with the active application?
- [ ] Does every application button still have exactly one status indicator directly beneath it?
- [ ] Is the new state distinguishable without colour?
- [ ] Is it keyboard reachable, with a visible focus ring?
- [ ] Does it survive a rail collapse and each breakpoint in §5?
- [ ] Are all strings in `en.json`?
- [ ] Are all colours and dimensions tokens, not literals?
- [ ] Does it look right in **both** modes, and does anything it adds to a pane still look right after the mode is forwarded (§4.4)?
- [ ] Does every brand mark come from `icons/` through the `@icons` alias, unrecoloured (D-2I)?
- [ ] Does it respect `prefers-reduced-motion`?
- [ ] Does it have a Playwright assertion for its happy path and one failure path? (see [`Testing.md`](./Testing.md))
- [ ] Are the screenshots in the PR taken at a consistent viewport with before/after side by side?

---

<p align="center"><sub>Workcenter design specification · sidebar pattern after <a href="https://filebrowserquantum.com/en/docs/features/sidebar-links/">FileBrowser Quantum</a> · theming after <a href="https://github.com/JDB321Sailor/Workcenter">Workcenter</a></sub></p>
