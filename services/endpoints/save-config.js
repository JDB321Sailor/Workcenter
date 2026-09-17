/**
 * This file exports a function, used by the write config endpoint.
 * It will make a backup of the users conf.yml file
 * and then write their new config into the main conf.yml file.
 * Finally, it will call a function with the status message
 */
const fsPromises = require('fs').promises;
const path = require('path');

const MAX_CONFIG_BYTES = 256 * 1024;

/* Schema modeline to get added to conf.yml */
const SCHEMA_MODELINE = '# yaml-language-server: $schema='
  + 'https://raw.githubusercontent.com/Lissy93/dashy/master/src/utils/config/ConfigSchema.json';

/* Adds the $schema part in, if not already present */
const withModeline = (newConfig, oldConfig, isRootConfig) => {
  // ReGex for checking if a schema reference already present
  const MODELINE = /^#[ \t]+(?:yaml-language-server[ \t]*:|\$schema:).*/m;
  const SCHEMA_KEY = /^["']?\$schema["']?[ \t]*:/m;

  // Gets everything before the first line of content
  const headerOf = (text) => text.split(/^(?![ \t]*(?:#|%|---|$))/m)[0];

  // Skip if a schema is already referenced or if has byte-order-mark
  if (newConfig.startsWith('\uFEFF') || SCHEMA_KEY.test(newConfig)
    || MODELINE.test(headerOf(newConfig))) return newConfig;
  const [existing] = headerOf(oldConfig).match(MODELINE) || [];
  const modeline = existing || (isRootConfig ? SCHEMA_MODELINE : null);
  return modeline ? `${modeline}\n${newConfig}` : newConfig;
};

// Disallow paths having path separators, control chars (NUL/CR/LF), or ..
const SAFE_FILENAME = /^(?!\.+$)[^\\/\0\r\n]+\.ya?ml$/i;

module.exports = async (newConfig, render) => {
  const respond = (success, message) => render(JSON.stringify({ success, message }));

  // Validate request body
  if (!newConfig || typeof newConfig.config !== 'string' || newConfig.config.length === 0) {
    respond(false, "Request body is missing or has an invalid 'config' field");
    return;
  }
  if (newConfig.config.length > MAX_CONFIG_BYTES) {
    respond(false, `Config exceeds maximum size of ${MAX_CONFIG_BYTES / 1024} KB`);
    return;
  }

  // If `filename` (for sub-pages) is specified validate and set it
  let usersFileName;
  if (typeof newConfig.filename === 'string' && newConfig.filename) {
    const base = path.basename(newConfig.filename);
    if (!SAFE_FILENAME.test(base)) {
      respond(false, 'Invalid filename: must be a basename ending in .yml or .yaml');
      return;
    }
    usersFileName = base;
  }

  // Resolve paths
  const userDataDirectory = process.env.USER_DATA_DIR || './user-data/';
  const backupLocation = process.env.BACKUP_DIR || path.join(userDataDirectory, 'config-backups');
  const backupsEnabled = process.env.DISABLE_CONFIG_BACKUPS !== 'true';
  const targetFile = usersFileName || 'conf.yml';
  const targetFilePath = path.join(userDataDirectory, targetFile);

  const backupBase = targetFile.replace(/\.ya?ml$/i, '');
  const backupFilePath = path.join(backupLocation, `${backupBase}-${Date.now()}.backup.yml`);

  // Backup current config before proceeding (unless disabled via DISABLE_CONFIG_BACKUPS)
  let backedUp = false;
  if (backupsEnabled) {
    try {
      await fsPromises.mkdir(backupLocation, { recursive: true });
      await fsPromises.copyFile(targetFilePath, backupFilePath);
      backedUp = true;
    } catch (error) {
      if (error.code !== 'ENOENT') {
        respond(false, `Unable to backup ${targetFile}: ${error}`);
        return;
      }
    }
  }

  // Write the new config
  try {
    const previous = await fsPromises.readFile(targetFilePath, 'utf8').catch(() => '');
    const toWrite = withModeline(newConfig.config, previous, targetFile === 'conf.yml');
    await fsPromises.writeFile(targetFilePath, toWrite, { encoding: 'utf8' });
  } catch (error) {
    respond(false, `Unable to write to ${targetFile}: ${error}`);
    return;
  }

  // If successful, then render hasn't yet been called- call it
  let responseMsg = `Config saved successfully in ${targetFilePath}.`;
  if (backedUp) {
    responseMsg += ` Previous ${targetFile} was backed up to ${backupFilePath}.`;
  }
  respond(true, responseMsg);
};
