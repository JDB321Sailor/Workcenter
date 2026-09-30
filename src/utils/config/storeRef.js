/**
 * The Vuex store, published for the config pipeline.
 *
 * `ConfigAccumulator` needs the store's live configuration — the authentication
 * block in particular — but importing the store directly creates an import
 * cycle: `store.js` → `ConfigHelpers.js` → `ConfigAccumalator.js` → `store.js`.
 * A cycle is not itself a bug, but anything that *constructs* the accumulator
 * while a module is still evaluating depends on the bundler's evaluation order,
 * and that order changes whenever an unrelated import is added. The symptom is a
 * boot failure — `TypeError: … is not a constructor` — and a shell that never
 * mounts.
 *
 * So the store publishes itself here instead. Nothing imports the store for this
 * purpose, no module-scope code depends on evaluation order, and the accumulator
 * reads whatever is available when it is constructed.
 */

export const storeRef = { current: null };

export default storeRef;
