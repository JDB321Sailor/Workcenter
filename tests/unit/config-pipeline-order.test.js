import {
  describe, it, expect,
} from 'vitest';
import fs from 'node:fs';
import path from 'node:path';

/**
 * The config pipeline's module order.
 *
 * `store.js` imports `ConfigHelpers.js`, which constructs `ConfigAccumulator`,
 * which used to import `store.js` back. That cycle made start-up depend on which
 * module the bundler happened to evaluate first: in the failing order the
 * accumulator's class did not exist yet and the shell died with
 * `TypeError: … is not a constructor`, leaving the loading watermark on screen.
 *
 * These tests fail if the cycle is reintroduced, whichever way it is written.
 */

const storeSource = fs.readFileSync(path.resolve(__dirname, '../../src/store.js'), 'utf8');
const accumulatorSource = fs.readFileSync(
  path.resolve(__dirname, '../../src/utils/config/ConfigAccumalator.js'),
  'utf8',
);
const helpersSource = fs.readFileSync(
  path.resolve(__dirname, '../../src/utils/config/ConfigHelpers.js'),
  'utf8',
);

describe('the config pipeline does not depend on module evaluation order', () => {
  it('never imports the store from the accumulator', () => {
    expect(accumulatorSource).not.toMatch(/from '@\/store'/);
    expect(accumulatorSource).toMatch(/from '@\/utils\/config\/storeRef'/);
  });

  it('never constructs the accumulator at module scope', () => {
    // A module-scope `new ConfigAccumulator()` runs while modules are still
    // evaluating, which is exactly what made the old cycle fatal.
    expect(helpersSource).not.toMatch(/^export const config = \(\(\) => \{/m);
    expect(helpersSource).not.toMatch(/^\s*const \w+ = new ConfigAccumulator\(\);\s*$/m);
  });

  it('publishes the store for the accumulator', () => {
    expect(storeSource).toMatch(/storeRef\.current = store;/);
  });

  it('constructs the accumulator before the store exists, without throwing', async () => {
    // Imported first on purpose: this is the order that used to fail.
    const { default: ConfigAccumulator } = await import('@/utils/config/ConfigAccumalator');
    const accumulator = new ConfigAccumulator();
    expect(accumulator.appConfig()).toBeTruthy();
    expect(accumulator.appConfig().theme).toBeTruthy();
  });

  it('reads the live store once it has published itself', async () => {
    const { default: store } = await import('@/store');
    const { default: storeRef } = await import('@/utils/config/storeRef');
    expect(storeRef.current).toBe(store);
  });
});
