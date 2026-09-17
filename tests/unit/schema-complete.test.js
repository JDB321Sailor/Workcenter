import { describe, it, expect } from 'vitest';
import { EditorState } from '@codemirror/state';
import { CompletionContext } from '@codemirror/autocomplete';
import { schemaComplete } from '../../src/utils/config/schemaComplete';

const at = (text, explicit = false) => {
  const pos = text.indexOf('|');
  const state = EditorState.create({ doc: text.replace('|', '') });
  return schemaComplete(new CompletionContext(state, pos, explicit));
};
const labels = (r) => (r ? r.options.map((o) => o.label) : null);

describe('schemaComplete', () => {
  it('completes nested keys', () => {
    const r = at('pageInfo:\n  ti|\n');
    expect(labels(r)).toContain('title');
    expect(r.options.find((o) => o.label === 'title').apply).toBe('title: ');
  });
  it('excludes keys already present', () => {
    const l = labels(at('pageInfo:\n  title: x\n  na|\n'));
    expect(l).toContain('navLinks');
    expect(l).not.toContain('title');
  });
  it('completes root keys, excluding present ones', () => {
    const l = labels(at('pa|\nsections: []\n'));
    expect(l).toEqual(expect.arrayContaining(['pages', 'pageInfo', '$schema']));
    expect(l).not.toContain('sections');
  });
  it('word that prefixes the PARENT key stays scoped to parent', () => {
    const l = labels(at('pageInfo:\n  pa|\n'));
    expect(l).toContain('title');       // pageInfo's props...
    expect(l).not.toContain('pages');   // ...not root's
  });
  it('completes enum values', () => {
    expect(labels(at('appConfig:\n  iconSize: |\n'))).toContain('medium');
  });
  it('completes enum values with a typed prefix', () => {
    expect(labels(at('appConfig:\n  iconSize: me|\n'))).toContain('medium');
  });
  it('completes booleans', () => {
    expect(labels(at('appConfig:\n  enableFontAwesome: |\n'))).toEqual(['true', 'false']);
  });
  it('completes keys inside a section item', () => {
    const l = labels(at('sections:\n  - name: A\n    items:\n      - ti|\n'));
    expect(l).toEqual(expect.arrayContaining(['title']));
  });
  it('silent for free-text values', () => {
    expect(at('pageInfo:\n  title: My|\n')).toBeNull();
    expect(at('pageInfo:\n  title: My Da|\n')).toBeNull();
  });
  it('resolves blank nested lines to the parent', () => {
    expect(labels(at('pageInfo:\n  |\n', true))).toContain('title');
    const l = labels(at('pageInfo:\n  title: x\n  |\n', true));
    expect(l).toContain('navLinks');
    expect(l).not.toContain('title');
  });
  it('offers item keys on a bare new list entry', () => {
    expect(labels(at('sections:\n  - name: A\n  - |\n', true))).toContain('name');
  });
  it('explicit trigger on empty root doc offers root keys', () => {
    expect(labels(at('|', true))).toContain('sections');
  });
  it('mid-key edit applies name without a colon', () => {
    const r = at('pageInfo:\n  tit|le: x\n');
    expect(r.options.find((o) => o.label === 'title').apply).toBe('title');
  });
  it('info and detail carry schema docs', () => {
    const o = at('pageInfo:\n  ti|\n').options.find((x) => x.label === 'title');
    expect(o.detail).toBe('string');
    expect(o.info).toBeTruthy();
  });
});
