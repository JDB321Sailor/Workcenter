# Workcenter — Design Specification

> **Scope:** every user-interface element of the Workcenter application: structure, layout, states,
> interaction, theming, accessibility and responsiveness.
> **Foundations:** [Dashy](https://github.com/lissy93/dashy)'s theming model, CSS custom properties and
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

Extends Dashy's `src/styles/dimensions.scss`.

| Token | Default | Meaning |
| --- | --- | --- |
| `--side-bar-width` | `16rem` | Rail width. Dashy's value is `3.5rem` (icons only); Workcenter widens it because its sidebars carry labels, not just icons. |
| `--side-bar-width-collapsed` | `3.5rem` | Rail width when collapsed to icons. Equals Dashy's `--side-bar-width`, so a collapsed Workcenter rail has exactly Dashy's geometry. |
| `--rail-header-height` | `3rem` | Brand header row. |
| `--switcher-height` | `4.5rem` | Application switcher region: the button row **and** the status indicator row plus its label. |
| `--switcher-button-height` | `2.5rem` | A single switcher button. |
| `--switcher-indicator-height` | `2rem` | The status indicator row and the `STATUS` label beneath the buttons. |
| `--sidebar-search-height` | `2.5rem` | Global search row. |
| `--user-menu-height` | `3rem` | User menu row. |
| `--header-height` | `0` | **Kept as a token, set to `0`.** Dashy shows a `6.3rem` header on the Workspace view and positions the iframe at `calc(100% - var(--header-height))`. Workcenter replaces that header with the rail's brand header (D-1) and sets this token to `0`, so every inherited `calc()` expression stays correct without editing any component. Re-introducing a top header means changing this token only. |
| `--pane-gutter` | `0` | No gutter between rail and surface — the embedded app owns its own padding. |
| `--rail-transition` | `180ms ease` | Width and collapse transitions. |

> **Rule D-L1:** the content surface is positioned at `left: var(--side-bar-width)` with width
> `calc(100% - var(--side-bar-width))` and height `calc(100% - var(--header-height))` — Dashy's exact
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

| Property | Value |
| --- | --- |
| Collapsed content | Avatar (or initials) + admin badge when applicable |
| Expanded content | Display name, email, group summary, theme switcher, language switcher, admin link (admin only), Logout |
| Admin badge | Small pill reading `Admin`; shown when the token carries `workspaceadmin` |
| Admin link | "Integrations" → Traefik dashboard (new tab), "Mail admin" → Mailcow UI (new tab), "Identity" → Authentik (new tab). **Admin only.** |
| Logout | Ends the Workcenter session and performs RP-initiated logout at Authentik so all panes end with it |
| Position | Anchored bottom of the rail; a popover, not a route |
| Keyboard | `Tab` reaches the trigger; `Enter` opens; arrow keys traverse; `Esc` closes and restores focus |

---

### D-7 — Content surface and panes

| Property | Value |
| --- | --- |
| Container | `PaneHost.vue` — holds one `AppPane.vue` per application, all mounted after first activation |
| Pane | `AppPane.vue` — an `<iframe>` plus loading, error and unavailable states |
| iframe attributes | `allow="fullscreen; clipboard-read; clipboard-write"`, `referrerpolicy="same-origin"`, `loading="eager"`, a stable `id` per application |
| Sizing | `position: absolute; inset: 0 0 0 var(--side-bar-width)`, matching Dashy's `WebContent.vue` contract |
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

Workcenter keeps Dashy's two-layer model:

1. **Palette layer** (`src/styles/color-palette.scss`) — raw colour values as CSS custom properties.
2. **Semantic layer** (`src/styles/workcenter/*.scss`) — meaning-bearing tokens that components use.

Components reference **semantic tokens only**. No component contains a colour literal.

### 4.2 Workcenter semantic tokens

| Token | Purpose |
| --- | --- |
| `--wc-surface` | Shell background behind panes |
| `--wc-surface-raised` | Cards, popovers, modals |
| `--wc-border` | Hairlines and dividers |
| `--wc-text` / `--wc-text-muted` | Primary and secondary text |
| `--wc-accent-files` | Files accent (blue) |
| `--wc-accent-chat` | Chat accent (violet) |
| `--wc-accent-mail` | Mail accent (teal) |
| `--wc-focus-ring` | Focus ring colour, ≥3:1 against both surface and accent |
| `--wc-scrim` | Modal backdrop |
| `--wc-status-healthy` / `--wc-status-degraded` / `--wc-status-unhealthy` / `--wc-status-unknown` | Application switcher status indicators |
| `--wc-radius` | Corner radius (Dashy's `--curve-factor` is aliased to this) |
| `--wc-shadow-popover` | Popover elevation |

Retained Dashy tokens (unchanged names, so Dashy themes keep working): `--side-bar-width`,
`--side-bar-background`, `--side-bar-background-lighter`, `--side-bar-color`,
`--side-bar-item-background`, `--side-bar-item-color`, `--workspace-web-content-background`,
`--curve-factor`.

### 4.3 Themes

| Theme | Notes |
| --- | --- |
| `workcenter-dark` | **Default.** Neutral near-black surface, accents at 60% lightness |
| `workcenter-light` | Neutral off-white surface, accents at 40% lightness |
| `workcenter-contrast` | High-contrast variant meeting WCAG AAA for shell chrome |
| Inherited Dashy themes | Kept where they only affect tokens; themes referencing removed components are deleted |

### 4.4 Theme bridge

The shell's theme is pushed into each application so panes do not clash with the frame:

| Application | Mechanism | Fallback |
| --- | --- | --- |
| FileBrowser Quantum | `userDefaults.ui.darkMode` in `config.yaml`, plus a per-user preference | User's own FileBrowser setting wins if they change it |
| Zulip | Deep-link the colour-scheme preference; Zulip remembers per user | User's own Zulip setting |
| SOGo | SOGo's own theme preference; Workcenter ships a matching CSS override where supported | SOGo default |

> **Rule D-T1:** the theme bridge is **advisory**. Workcenter never overwrites a user's explicit
> in-application preference.
> **Rule D-T2:** switching theme in the shell must not reload any pane.

### 4.5 Custom CSS

Administrators may inject a stylesheet through `appConfig.customCss` (Dashy's mechanism) and users
through their profile. Custom CSS is scoped to shell chrome; it cannot reach inside iframes.

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

| Ref | Requirement |
| --- | --- |
| D-I1 | Every shell string lives in `src/assets/locales/en.json` and is referenced with `$t('key')`. |
| D-I2 | Keys are namespaced by region: `switcher.*`, `sidebar.files.*`, `sidebar.chat.*`, `sidebar.mail.*`, `pane.*`, `status.*`, `transfer.*`, `user.*`. |
| D-I3 | Application names are **not** translated (they are proper nouns); their descriptors are. |
| D-I4 | Dates, file sizes and numbers are formatted with `Intl` using the active locale. |
| D-I5 | English is the master locale; adding a language requires no component changes. |

---

## 9. UI copy standard

| Rule | Example |
| --- | --- |
| Sentence case for all labels and headings | "Save to files", not "Save To Files" |
| Buttons are verb-first and name the object | "Attach from files", "Send to Zulip", "Save to files" |
| Errors state what happened and what to do | "Chat is not responding. Retry, or open Zulip in a new tab." |
| No exclamation marks, no blame, no jargon | "Your session for Mail has expired. Sign in again." |
| Empty states are actionable | "No files here yet. Upload one from FileBrowser, or save an attachment from Mail." |
| Never say "Dashy" | The product is Workcenter |

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
| `ThemeSwitcher.vue` / `LanguageSwitcher.vue` | Popover | §4, §8 |

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
- [ ] Does it respect `prefers-reduced-motion`?
- [ ] Does it have a Playwright assertion for its happy path and one failure path? (see [`Testing.md`](./Testing.md))
- [ ] Are the screenshots in the PR taken at a consistent viewport with before/after side by side?

---

<p align="center"><sub>Workcenter design specification · sidebar pattern after <a href="https://filebrowserquantum.com/en/docs/features/sidebar-links/">FileBrowser Quantum</a> · theming after <a href="https://github.com/lissy93/dashy">Dashy</a></sub></p>
