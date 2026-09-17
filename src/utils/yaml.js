/**
 * js-yaml with the same parsing behaviour as js-yaml v4's default schema:
 * YAML 1.2 core scalars plus merge keys (<<:), timestamps and !!binary.
 * v5's bare CORE default drops those tags, and throws on empty documents
 * where v4 returned undefined
 */
import {
  load as jsYamlLoad, CORE_SCHEMA, mergeTag, timestampTag, binaryTag, YAMLException,
} from 'js-yaml';

const V4_SCHEMA = CORE_SCHEMA.withTags([mergeTag, timestampTag, binaryTag]);

export const load = (src) => {
  try {
    return jsYamlLoad(src, { schema: V4_SCHEMA });
  } catch (e) {
    if (e instanceof YAMLException && /input is empty/.test(e.message)) return undefined;
    throw e;
  }
};

export { dump } from 'js-yaml';
