/**
 * The broker service.
 *
 * Mounted by `services/app.js` under `/api/broker`, in the same container and
 * the same origin as the shell (architecture.md AD-6). It composes its adapters
 * here so the routes themselves stay free of wiring.
 */

const { createBrokerRouter } = require('./utils/broker');
const transport = require('./utils/broker/transport');

/**
 * Per-user application credentials.
 *
 * The encrypted token vault is part of the file-movement phase. Until it
 * exists, no credential is available and the adapters say so, which is the
 * honest answer rather than a fabricated one.
 */
const credentialsFor = async () => null;

/**
 * Create the broker router for a configuration.
 *
 * `applications` is `appConfig.applications` from `user-data/conf.yml`; a
 * missing address is reported as unknown health, never as a failure.
 */
const createBrokerServer = ({ applications = {}, authConfig = {} } = {}) => {
  const { router } = createBrokerRouter({
    applications,
    authConfig,
    credentialsFor,
    transportImpl: transport,
  });
  return router;
};

module.exports = { createBrokerServer, credentialsFor };
