import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';

/**
 * Workcenter is derived from Dashy with only the Workspace view carried forward.
 * These tests fail if a removed view, subsystem or brand string is reintroduced.
 *
 * See architecture.md section 3.3 for the removal list.
 */

const root = path.resolve(__dirname, '../..');

const exists = (rel) => fs.existsSync(path.join(root, rel));

const walk = (dir, out = []) => {
  for (const entry of fs.readdirSync(path.join(root, dir), { withFileTypes: true })) {
    const rel = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(rel, out);
    else out.push(rel);
  }
  return out;
};

const sourceFiles = () => [
  ...walk('src'),
  ...(exists('services') ? walk('services') : []),
].filter((f) => /\.(js|vue|json|scss)$/.test(f));

/** Files that legitimately retain upstream attribution. */
const ATTRIBUTION_ALLOWLIST = new Set([
  'src/directives/ClickOutside.js',
  'src/directives/LongPress.js',
  'src/utils/Search.js',
]);

describe('the removed views stay removed', () => {
  it('has no Default, Minimal or config-download view', () => {
    expect(exists('src/views/Home.vue')).toBe(false);
    expect(exists('src/views/Minimal.vue')).toBe(false);
    expect(exists('src/views/DownloadConfig.vue')).toBe(false);
  });

  it('ships only the view files a single-view application needs', () => {
    const views = fs.readdirSync(path.join(root, 'src/views')).sort();
    expect(views).toEqual(['404.vue', 'Login.vue', 'Workspace.vue']);
  });

  it('has no routes for the removed views', () => {
    const router = fs.readFileSync(path.join(root, 'src/router.js'), 'utf8');
    expect(router).not.toMatch(/views\/Home\.vue/);
    expect(router).not.toMatch(/views\/Minimal\.vue/);
    expect(router).not.toMatch(/views\/DownloadConfig\.vue/);
    expect(router).not.toMatch(/['"]\/minimal['"]/);
  });

  it('routes the three panes and the workspace root', () => {
    const defaults = fs.readFileSync(path.join(root, 'src/utils/config/defaults.js'), 'utf8');
    for (const route of ['workspace', 'files', 'chat', 'mail', 'login']) {
      expect(defaults).toMatch(new RegExp(`${route}: '[^']+'`));
    }
  });
});

describe('the removed subsystems stay removed', () => {
  const removedPaths = [
    'src/components/MinimalView',
    'src/components/Widgets',
    'src/components/InteractiveEditor',
    'src/components/Charts',
    'src/components/Workspace/WidgetView.vue',
    'src/components/Settings/ViewSwitcher.vue',
    'src/components/Settings/OptionsPanel.vue',
    'src/components/Settings/SettingsContainer.vue',
    'src/components/Configuration/JsonEditor.vue',
    'src/components/LinkItems/Item.vue',
    'src/components/LinkItems/Section.vue',
    'src/components/LinkItems/StatusIndicator.vue',
    'src/mixins/MasonryItem.js',
    'src/mixins/WidgetMixin.js',
    'src/mixins/ChartingMixin.js',
    'src/mixins/GlancesMixin.js',
    'src/mixins/NextcloudMixin.js',
    'src/utils/CloudBackup.js',
    'src/utils/CheckPageVisibility.js',
    'src/utils/CheckItemVisibility.js',
    'services/endpoints/status-check.js',
    'services/endpoints/ping-check.js',
    'services/endpoints/status-ping.js',
    'Dockerfile-postgresql',
    'CNAME',
    'netlify.toml',
    'render.yaml',
  ];

  it.each(removedPaths)('%s is gone', (rel) => {
    expect(exists(rel)).toBe(false);
  });

  it('no source file imports a removed component or mixin', () => {
    const banned = [
      'MinimalView', 'components/Widgets', 'InteractiveEditor', 'WidgetView',
      'ViewSwitcher', 'OptionsPanel', 'SettingsContainer', 'JsonEditor',
      'MasonryItem', 'WidgetMixin', 'ChartingMixin', 'GlancesMixin',
      'NextcloudMixin', 'CloudBackup', 'CheckPageVisibility', 'CheckItemVisibility',
    ];
    const offenders = [];
    for (const file of sourceFiles()) {
      const text = fs.readFileSync(path.join(root, file), 'utf8');
      for (const term of banned) {
        if (text.includes(term)) offenders.push(`${file}: ${term}`);
      }
    }
    expect(offenders).toEqual([]);
  });

  it('declares no widget, status-check or ping-check configuration', () => {
    const schema = JSON.parse(
      fs.readFileSync(path.join(root, 'src/utils/config/ConfigSchema.json'), 'utf8'),
    );
    const appConfig = Object.keys(schema.properties.appConfig.properties);
    for (const key of ['startingView', 'enableMultiTasking', 'widgetsAlwaysUseProxy']) {
      expect(appConfig).not.toContain(key);
    }
    expect(appConfig.filter((k) => /statusCheck|pingCheck/.test(k))).toEqual([]);

    const section = Object.keys(schema.properties.sections.items.properties);
    expect(section).not.toContain('widgets');
    expect(section).not.toContain('filteredItems');

    const item = schema.properties.sections.items.properties.items.items.properties;
    expect(Object.keys(item).filter((k) => /statusCheck|pingCheck/.test(k))).toEqual([]);
  });

  it('serves no status-check or ping-check route', () => {
    const app = fs.readFileSync(path.join(root, 'services/app.js'), 'utf8');
    expect(app).not.toMatch(/status-check/);
    expect(app).not.toMatch(/ping-check/);
    expect(app).not.toMatch(/status-ping/);
  });
});

describe('the product is branded Workcenter', () => {
  it('uses the Workcenter package identity', () => {
    const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
    expect(pkg.name).toBe('workcenter');
    expect(pkg.license).toBe('MIT');
  });

  it('titles the document Workcenter', () => {
    const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
    expect(html).toMatch(/<title>Workcenter<\/title>/);
    expect(html).not.toMatch(/<title>Dashy<\/title>/);
  });

  it('roots the app on #workcenter', () => {
    const app = fs.readFileSync(path.join(root, 'src/App.vue'), 'utf8');
    expect(app).toMatch(/id="workcenter"/);
    expect(app).not.toMatch(/id="dashy"/);
  });

  it('names the product Workcenter in the master locale', () => {
    const en = JSON.parse(fs.readFileSync(path.join(root, 'src/assets/locales/en.json'), 'utf8'));
    expect(JSON.stringify(en)).not.toMatch(/Dashy/);
  });

  it('carries no stale product name outside the attribution allowlist', () => {
    const offenders = [];
    for (const file of sourceFiles()) {
      if (ATTRIBUTION_ALLOWLIST.has(file)) continue;
      const text = fs.readFileSync(path.join(root, file), 'utf8');
      if (/Dashy/.test(text)) offenders.push(file);
    }
    expect(offenders).toEqual([]);
  });

  it('preserves the upstream MIT licence and attribution', () => {
    // The licence requires the copyright notice to be retained.
    const licence = fs.readFileSync(path.join(root, 'LICENSE'), 'utf8');
    expect(licence).toMatch(/MIT License/);
    expect(licence).toMatch(/Alicia Sykes/);
  });
});
