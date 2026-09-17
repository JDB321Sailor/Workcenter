/**
 * YAML parsing helper
 * I've got this, since js-yaml v5 dropped some schema features from v4
 * which some users might still be using. Backward compatibility until next major release.
 */
const jsYaml = require('js-yaml');

const V4_SCHEMA = jsYaml.CORE_SCHEMA.withTags([jsYaml.mergeTag, jsYaml.timestampTag, jsYaml.binaryTag]);

const load = (src) => {
  try {
    return jsYaml.load(src, { schema: V4_SCHEMA });
  } catch (e) {
    if (e instanceof jsYaml.YAMLException && /input is empty/.test(e.message)) return undefined;
    throw e;
  }
};

module.exports = { load, dump: jsYaml.dump };
