import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import HealthService, { HEALTH } from '@/utils/health/HealthService';
import { APP_LIST } from '@/utils/apps/registry';

vi.mock('@/utils/request', () => ({
  default: { get: vi.fn() },
}));

// eslint-disable-next-line import/first
import request from '@/utils/request';

/**
 * The indicators must never break the shell: a failed poll means the check did
 * not run, which is `unknown`, not `unhealthy`. See design.md D-2S.
 */
describe('HealthService', () => {
  beforeEach(() => {
    HealthService.stop();
    HealthService.apply({});
    vi.clearAllMocks();
  });

  afterEach(() => {
    HealthService.stop();
  });

  it('starts every application unknown', () => {
    for (const app of APP_LIST) {
      expect(HealthService.forApp(app.id).state).toBe(HEALTH.UNKNOWN);
    }
  });

  it('reports every application as unhealthy until proven otherwise', () => {
    expect(HealthService.allHealthy()).toBe(false);
  });

  it('applies a payload keyed by application id', () => {
    HealthService.apply({
      files: { state: HEALTH.HEALTHY, check: 'filebrowser /health' },
      chat: { state: HEALTH.DEGRADED, check: 'zulip long-poll' },
      mail: { state: HEALTH.UNHEALTHY, check: 'nginx-mailcow' },
    });
    expect(HealthService.forApp('files').state).toBe(HEALTH.HEALTHY);
    expect(HealthService.forApp('chat').check).toBe('zulip long-poll');
    expect(HealthService.forApp('mail').state).toBe(HEALTH.UNHEALTHY);
    expect(HealthService.allHealthy()).toBe(false);
  });

  it('reports all healthy only when every application is', () => {
    HealthService.apply({
      files: { state: HEALTH.HEALTHY },
      chat: { state: HEALTH.HEALTHY },
      mail: { state: HEALTH.HEALTHY },
    });
    expect(HealthService.allHealthy()).toBe(true);
  });

  it('ignores an application this build does not have', () => {
    HealthService.apply({ files: { state: HEALTH.HEALTHY }, widgets: { state: HEALTH.HEALTHY } });
    expect(HealthService.forApp('widgets').state).toBe(HEALTH.UNKNOWN);
  });

  it('falls back to unknown for a missing state', () => {
    HealthService.apply({ files: {} });
    expect(HealthService.forApp('files').state).toBe(HEALTH.UNKNOWN);
  });

  it('records when the check ran', () => {
    HealthService.apply({});
    // An ISO 8601 timestamp, so the tooltip can show when the state was read.
    expect(HealthService.state.lastChecked).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  it('polling a missing endpoint leaves every application unknown', async () => {
    request.get.mockRejectedValueOnce(new Error('404'));
    await HealthService.check();
    for (const app of APP_LIST) {
      expect(HealthService.forApp(app.id).state).toBe(HEALTH.UNKNOWN);
    }
  });

  it('takes the application map out of a wrapped payload', async () => {
    request.get.mockResolvedValueOnce({ apps: { chat: { state: HEALTH.HEALTHY } } });
    await HealthService.check();
    expect(HealthService.forApp('chat').state).toBe(HEALTH.HEALTHY);
  });

  it('reads the endpoint from the service map', async () => {
    request.get.mockResolvedValueOnce({});
    await HealthService.check();
    expect(request.get).toHaveBeenCalledWith('/api/broker/health');
  });

  it('can be started and stopped without leaking a timer', () => {
    vi.useFakeTimers();
    HealthService.start();
    expect(HealthService.state.polling).toBe(true);
    HealthService.stop();
    expect(HealthService.state.polling).toBe(false);
    vi.useRealTimers();
  });
});
