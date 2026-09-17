/**
 * A completion source for CodeMirror 6,
 * suggests property names and enum/boolean values from
 * ConfigSchema.json, based on the cursor's path in the YAML doc
 */
import { parseDocument } from 'yaml';
import schema from './ConfigSchema.json';
import { yamlPathAtOffset, yamlNodeAt, schemaAt } from './schemaPath';

// Spliced in at the cursor before parsing, so blank lines still resolve to a path
const PROBE = 'xProbex';

const describeType = (s) => (Array.isArray(s.type) ? s.type.join(' | ') : s.type);

// Whether the offset falls within a node's source range
const insideNode = (node, offset) => {
  const r = node?.range;
  return !!r && offset >= r[0] && offset <= (r[2] ?? r[1] ?? r[0]);
};

// Property names for an object schema, minus keys already used in the map
const keyOptions = (target, mapNode, currentKey, colonAfter) => {
  const existing = new Set((mapNode?.items || [])
    .map((p) => String(p.key && 'value' in p.key ? p.key.value : p.key))
    // A half-typed key can parse merged with the next line, as "pa sections"
    .flatMap((k) => k.split(/\s+/)));
  return Object.entries(target?.properties || {})
    .filter(([name]) => !existing.has(name) || name === currentKey)
    .map(([name, s]) => ({
      label: name,
      type: 'property',
      detail: describeType(s),
      info: s.description,
      apply: colonAfter ? name : `${name}: `,
    }));
};

// Value completions: the schema's allowed enum entries, or true/false for booleans
const valueOptions = (target) => {
  if (Array.isArray(target?.enum)) {
    return target.enum.map((v) => ({ label: String(v), type: 'constant' }));
  }
  if ([].concat(target?.type || []).includes('boolean')) {
    return [{ label: 'true', type: 'constant' }, { label: 'false', type: 'constant' }];
  }
  return [];
};

export const schemaComplete = (context) => {
  const { state, pos } = context;
  const word = context.matchBefore(/[\w$-]*/);
  if (!word) return null;

  const line = state.doc.lineAt(pos);
  const beforeCursor = line.text.slice(0, pos - line.from);
  const afterCursor = line.text.slice(pos - line.from);
  const typingKey = /^[\s-]*[\w$-]*$/.test(beforeCursor); // `  ti` or `  - `
  const typingValue = /:\s+[\w$-]*$/.test(beforeCursor); // `  layout: au` or `  layout: `
  if (!typingKey && !typingValue) return null;

  const doc = parseDocument(state.sliceDoc(0, pos) + PROBE + state.sliceDoc(pos));
  const path = yamlPathAtOffset(doc, pos);
  const [wordAfter] = /^[\w$-]*/.exec(afterCursor);
  const result = (options) => (options.length
    ? { from: word.from, to: pos + wordAfter.length, options, validFor: /^[\w$-]*$/ }
    : null);

  if (typingValue) return result(valueOptions(schemaAt(schema, path)));

  // When the cursor is on a key (not inside a value), complete against its parent
  const onKey = path.length && !insideNode(yamlNodeAt(doc.contents, path), pos);
  const currentKey = onKey ? String(path.pop()).replace(PROBE, '') : null;
  const colonAfter = /^\s*:/.test(afterCursor.slice(wordAfter.length));
  return result(keyOptions(schemaAt(schema, path), yamlNodeAt(doc.contents, path), currentKey, colonAfter));
};
