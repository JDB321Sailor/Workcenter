// @vitest-environment node
import fs from 'fs';
import os from 'os';
import path from 'path';
import { describe, it, expect } from 'vitest';
import request from 'supertest';

// Isolate from the repo's conf.yml so test behaviour doesn't depend on which
// auth method (if any) the developer has configured locally.
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'dashy-general-test-'));
fs.writeFileSync(path.join(tmpDir, 'conf.yml'), 'pageInfo:\n  title: Test\nsections: []\n');
process.env.USER_DATA_DIR = tmpDir;

const app = require('../../services/app');

describe('Healthcheck', () => {
  it('GET /healthz returns 200 with status, uptime and version', async () => {
    const res = await request(app).get('/healthz');
    expect(res.status).toBe(200);
    expect(res.headers['cache-control']).toBe('no-store');
    const body = JSON.parse(res.text);
    expect(body.status).toBe('ok');
    expect(typeof body.uptime).toBe('number');
    expect(body.uptime).toBeGreaterThanOrEqual(0);
    expect(typeof body.version).toBe('string');
  });

  it('ignores POST', async () => {
    const res = await request(app).post('/healthz');
    expect(res.status).toBeLessThan(500);
    expect(res.status).not.toBe(200);
  });
});

describe('Config serving', () => {
  it('GET /conf.yml returns the config', async () => {
    const res = await request(app).get('/conf.yml');
    expect(res.status).toBe(200);
    expect(res.text).toContain('pageInfo');
  });

  it('GET /missing.yml returns 404 JSON', async () => {
    const res = await request(app).get('/nonexistent.yml');
    expect(res.status).toBe(404);
    expect(JSON.parse(res.text).success).toBe(false);
  });
});

describe('System info', () => {
  it('returns host metadata', async () => {
    const res = await request(app).get('/system-info');
    expect(res.status).toBe(200);
    const body = JSON.parse(res.text);
    expect(body.meta.hostname).toBeDefined();
    expect(body.meta.uptime).toBeGreaterThan(0);
    expect(body.memory).toBeDefined();
  });

  it('ignores POST', async () => {
    const res = await request(app).post('/system-info');
    expect(res.status).toBeLessThan(500);
  });
});

describe('Get user', () => {
  it('returns JSON', async () => {
    const res = await request(app).get('/get-user');
    expect(res.status).toBe(200);
    expect(typeof JSON.parse(res.text)).toBe('object');
  });
});

describe('SPA fallback', () => {
  // Workcenter renders one view, and the three panes are deep-linkable routes.
  // The shell is built into dist/, so assert on it when a build is present and
  // on the plain initialization page otherwise.
  const built = fs.existsSync(path.join(__dirname, '../../dist/index.html'));

  it.each(['/', '/files', '/chat', '/mail', '/login', '/some/nonexistent/route'])(
    'serves the app shell for %s',
    async (route) => {
      const res = await request(app).get(route);
      if (built) {
        // With dist/ present, every pane route renders the shell with 200.
        expect(res.status).toBe(200);
        expect(res.text).toContain('<div id="app">');
      } else {
        // Without a build there is no shell. The root falls back to the
        // initialization page from public/, and deep routes have no file to
        // send, so they report 404.
        expect(res.status).toBe(route === '/' ? 200 : 404);
      }
    },
  );

  it('serves the initialization page when no build is present', async () => {
    if (built) return; // Covered by the shell assertions above.
    const res = await request(app).get('/');
    expect(res.text).toContain('<title>Workcenter</title>');
  });

  it('reports 404 for a missing static asset so broken references surface', async () => {
    const res = await request(app).get('/assets/does-not-exist.js');
    expect(res.status).toBe(404);
  });
});
