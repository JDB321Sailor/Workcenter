# Theming

Themes style the shell: the header, the application switcher, the status indicators, the
sidebars and the frame the panes sit in. They do not reach inside a pane. Each embedded
application — FileBrowser Quantum, Zulip, SOGo — is a separate product rendered in its own iframe,
and its appearance is set in that product's own settings.

Changing a theme is a configuration change, not a UI action: Workcenter renders no theme
switcher. See [`configuring.md`](./configuring.md) for where `conf.yml` lives.

## Choosing a theme

| Key | Type | Description |
| --- | --- | --- |
| `theme` | `string` | The theme to apply. `default` is the shell's own palette. |
| `dayTheme` | `string` | Used when the operating system prefers a light colour scheme. Takes precedence over `theme` in that state. |
| `nightTheme` | `string` | Used when the operating system prefers a dark colour scheme. Takes precedence over `theme` in that state. |

```yaml
appConfig:
  theme: default
  dayTheme: minimal-light
  nightTheme: one-dark
```

The day and night themes are selected with the CSS media query `prefers-color-scheme`, so they
follow the operating system setting and need no browser reload when it changes.

The theme is chosen in this order, highest first:

1. A theme name stored in the browser's local storage under the `theme` key.
2. `dayTheme` or `nightTheme`, whichever matches the operating system.
3. `appConfig.theme`.
4. `default`.

Nothing in the shell writes that local storage key, so the first entry only matters on a browser
that holds a value from an earlier deployment. Clearing site data for the Workcenter origin
removes it, and the config file then applies again.

## Built-in themes

The built-in themes are listed in `builtInThemes` in
[`src/utils/config/defaults.js`](https://github.com/JDB321Sailor/Workcenter/blob/Dev/src/utils/config/defaults.js)
and defined as `html[data-theme='<name>']` blocks in
[`src/styles/color-themes.scss`](https://github.com/JDB321Sailor/Workcenter/blob/Dev/src/styles/color-themes.scss).

```
default            glass              callisto           material
material-dark      colorful           dracula            one-dark
lissy              cherry-blossom     nord-frost         nord
argon              fallout            whimsy             oblivion
adventure          crayola            deep-ocean         minimal-dark
minimal-light      thebe              matrix             matrix-red
color-block        raspberry-jam      bee                tiger
glow               glow-dark          vaporware          cyberpunk
material-original  material-dark-original                high-contrast-dark
high-contrast-light                   adventure-basic    basic
tama               neomorphic         glass-2            night-bat
tokyo-night        gruvbox            rose-pine          parchment
aurora             zinc               solarized-dark     solarized-light
brutalist          midnight           catppuccin
```

A theme is applied by setting `data-theme` on the document element, and every colour in the shell
is a CSS custom property, so a theme is a list of variable values and nothing else.

## Changing individual colours

`appConfig.customColors` overrides single variables of a named theme. The values are applied as
inline custom properties on the document element, so they win over the theme's own values.

```yaml
appConfig:
  customColors:
    one-dark:
      primary: '#4c9be8'
      background: '#101418'
    default:
      primary: rebeccapurple
```

| Ref | Rule |
| --- | --- |
| T-1 | The key under `customColors` is a theme name. Overrides apply only while that theme is active. |
| T-2 | The values under it are CSS variable names, without the leading `--`. Any variable in [`color-palette.scss`](https://github.com/JDB321Sailor/Workcenter/blob/Dev/src/styles/color-palette.scss) can be set. |
| T-3 | Quote hex values. YAML reads an unquoted `#4c9be8` as a comment. |

## Writing a theme

A theme is a set of variable values under a `data-theme` selector. There are two places to put
one, and the difference is whether the browser has to rebuild the bundle.

### In the stylesheet

Add the block to
[`src/styles/user-defined-themes.scss`](https://github.com/JDB321Sailor/Workcenter/blob/Dev/src/styles/user-defined-themes.scss),
which is compiled into the bundle, then run `yarn build` and redeploy.

```css
html[data-theme='my-theme'] {
  --primary: #00ccb4;
  --background: #141b33;
  --background-darker: #060913;
}
```

Name the theme under `appConfig.cssThemes` so the shell treats it as a theme that exists, then
select it:

```yaml
appConfig:
  theme: my-theme
  cssThemes: [my-theme]
```

### From a CSS file you host

A theme can also be a stylesheet outside the bundle, which is the right choice for a theme you want
to edit without rebuilding.

```css
/* user-data/my-theme.css */
html[data-theme='my-theme'] {
  --primary: #00ccb4;
  --background: #141b33;
}
```

The `user-data/` directory is served at the site root, so that file is fetchable at
`/my-theme.css`:

```yaml
appConfig:
  theme: my-theme
  cssThemes: [my-theme]
  externalStyleSheet: /my-theme.css
```

Both keys are needed. `cssThemes` makes the name selectable, and `externalStyleSheet` loads the
file that defines it.

## External stylesheets

`appConfig.externalStyleSheet` loads one stylesheet, or an array of them, into the shell document.
It accepts an absolute `https://` URL or a path on the Workcenter origin.

```yaml
appConfig:
  externalStyleSheet: 'https://example.com/my-stylesheet.css'
```

```yaml
appConfig:
  externalStyleSheet: ['/themes/one.css', '/themes/two.css']
```

A stylesheet loaded this way can also be selected as the theme directly, by using the label the
shell gives it — `External Stylesheet`, or `External Stylesheet 1`, `External Stylesheet 2` and so
on for an array — as the value of `appConfig.theme`. Selecting an external stylesheet as a theme
clears `data-theme`, so the built-in theme variables stop applying and the file is the only source
of styling.

Stylesheets load into the shell document only. They cannot restyle an embedded application, which
is cross-origin to Workcenter and renders in its own frame.

## Custom CSS

`appConfig.customCss` takes CSS as a **string** and injects it as a `<style>` element. It is not a
file path.

```yaml
appConfig:
  customCss: |
    .wc-rail { border-right: 2px solid var(--primary); }
    .wc-switcher__button { letter-spacing: 0.02em; }
```

| Ref | Rule |
| --- | --- |
| T-4 | The string is inserted into the document after tags are stripped out, so a value that looks like HTML is discarded rather than executed. |
| T-5 | Prefer `customColors` for colour changes. Reach for `customCss` only for what a variable cannot express. |
| T-6 | Target the shell's own class names, which are prefixed `wc-`. A selector for an embedded application's markup has no effect. |

## Typography

Three typefaces are bundled in `src/assets/fonts/` and declared in
[`src/styles/typography.scss`](https://github.com/JDB321Sailor/Workcenter/blob/Dev/src/styles/typography.scss):
Inconsolata Light, PT Mono Regular and Raleway. A theme selects between them by setting
`--font-primary`, `--font-secondary` and `--font-monospace`.

Fonts that the active theme does not use are not fetched, so a set of themes with different
typefaces costs nothing on a page load that uses one of them.

## Browser tab colour

`pageInfo.color` sets the `theme-color` meta tag, which tints the address bar and the task switcher
on browsers that support it: `#ff00a7`, `rebeccapurple` and `rgb(40, 60, 120)` are all valid. The
value is validated as a CSS colour before it is applied. Support is limited to some mobile
browsers, and the tint does not apply to an installed app.

## CSS variables

Every colour, radius and shadow in the shell is a CSS custom property, so a theme changes values in
one place. The complete set is in
[`src/styles/color-palette.scss`](https://github.com/JDB321Sailor/Workcenter/blob/Dev/src/styles/color-palette.scss)
and [`src/styles/dimensions.scss`](https://github.com/JDB321Sailor/Workcenter/blob/Dev/src/styles/dimensions.scss).

Variables are defined as `--background: #0b1021;` and used as
`background: var(--background);`.

### Base

These four define the shell's palette. Every other colour derives from them unless a theme
overrides it.

| Variable | Description |
| --- | --- |
| `--primary` | The accent colour: headings, focus rings, active states. |
| `--foreground` | Default text colour. Defaults to `--primary`. |
| `--background` | Page background. |
| `--background-darker` | Header, rail and sidebar fill. |

### Shell

The shell's own tokens. Each one maps to a base variable, which is what makes a theme work without
knowing the shell's markup.

| Variable | Description |
| --- | --- |
| `--wc-surface` | Pane and page surface. Defaults to `--background`. |
| `--wc-surface-raised` | Header, rail and sidebar surface. Defaults to `--background-darker`. |
| `--wc-border` | Separator between the shell's regions. |
| `--wc-text` | Shell text. Defaults to `--foreground`. |
| `--wc-text-muted` | Secondary text, such as the status label. |
| `--wc-accent-files` | The Files application's accent. |
| `--wc-accent-chat` | The Chat application's accent. |
| `--wc-accent-mail` | The Mail application's accent. |
| `--wc-focus-ring` | The ring drawn around a focused control. Defaults to `--primary`. |
| `--wc-scrim` | The dimming layer behind an overlay. |
| `--wc-status-healthy` | Status indicator for a healthy application. Defaults to `--success`. |
| `--wc-status-degraded` | Status indicator for a degraded application. Defaults to `--warning`. |
| `--wc-status-unhealthy` | Status indicator for an unhealthy application. Defaults to `--danger`. |
| `--wc-status-unknown` | Status indicator for an application whose state is not known. Defaults to `--medium-grey`. |
| `--wc-radius` | Corner radius for shell controls. Defaults to `--curve-factor`. |
| `--wc-shadow-popover` | Shadow under a shell popover. |

### Shape and transparency

| Variable | Default | Description |
| --- | --- | --- |
| `--curve-factor` | `5px` | Corner radius used across the shell. |
| `--curve-factor-navbar` | `16px` | Corner radius of the header. |
| `--curve-factor-small` | `2px` | Corner radius of small controls. |
| `--dimming-factor` | `0.7` | Opacity applied to inactive elements. |
| `--scroll-bar-width` | `8px` | Width of the scroll bars. |
| `--transparent-70`, `--transparent-50`, `--transparent-30` | — | Black at 70%, 50% and 30% opacity. |
| `--transparent-white-70`, `--transparent-white-50`, `--transparent-white-30`, `--transparent-white-10` | — | White at the same range of opacities. |

### Components

| Variable | Description |
| --- | --- |
| `--heading-text-color` | Page title and description. Defaults to `--foreground`. |
| `--nav-link-text-color` | Header navigation links. |
| `--nav-link-background-color` | Header navigation link fill. |
| `--nav-link-text-color-hover` | Header navigation links, hovered. |
| `--nav-link-background-color-hover` | Header navigation link fill, hovered. |
| `--nav-link-border-color` | Header navigation link outline. |
| `--nav-link-border-color-hover` | Header navigation link outline, hovered. |
| `--side-bar-background` | Application sidebar fill. Defaults to `--background-darker`. |
| `--side-bar-color` | Sidebar row text and icons. Defaults to `--primary`. |
| `--item-text-color-hover` | Sidebar row text, hovered. |
| `--login-form-color` | Login page text. |
| `--login-form-background` | Login page field fill. |
| `--login-form-background-secondary` | Login page surface. |
| `--toast-background` | Toast fill. Defaults to `--primary`. |
| `--toast-color` | Toast text. Defaults to `--background`. |
| `--scroll-bar-color` | Scroll bar thumb. |
| `--scroll-bar-background` | Scroll bar track. |
| `--highlight-background` | Highlighted text fill. |
| `--highlight-color` | Highlighted text. |
| `--progress-bar` | The progress bar shown during navigation. |
| `--loading-screen-color` | Splash screen text. |
| `--loading-screen-background` | Splash screen background. |
| `--outline-color` | Outline for focused elements. Defaults to `none`. |

### Action colours

Intent colours. They are rarely themed, and the status indicators are the main consumer.

| Variable | Default | Meaning |
| --- | --- | --- |
| `--info` | `#04e4f4` | Information |
| `--success` | `#20e253` | Success, and the healthy status |
| `--warning` | `#f6f000` | Warning, and the degraded status |
| `--danger` | `#f80363` | Error, and the unhealthy status |
| `--medium-grey` | `#5e6474` | The unknown status |
| `--neutral` | `#272f4d` | Neutral |
| `--white` / `--black` | `#fff` / `#000` | Plain white and black |

## Read next

- [`configuring.md`](./configuring.md) — every option in `user-data/conf.yml`
- [`security.md`](./security.md) — what a custom stylesheet can reach
- [`design.md` §4](../design.md#4-theming) — the token architecture, the theme bridge and how the
  embedded applications are branded to match
