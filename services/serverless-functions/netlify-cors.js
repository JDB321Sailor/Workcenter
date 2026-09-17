/* A Netlify cloud function to handle requests to CORS-disabled services */
const request = require('../utils/request');

const { validateTargetUrl } = request;

exports.handler = async (event) => {
  // Get input data
  const { body, headers, queryStringParameters } = event;

  // Get URL from header or GET param
  const requestUrl = queryStringParameters?.url || headers['Target-URL'] || headers['target-url'];

  const returnError = (msg, error) => ({
    statusCode: 400,
    body: JSON.stringify({ success: false, msg, error }),
  });
  // If URL missing, return error
  if (!requestUrl) return returnError('Missing Target-URL header', null);

  let custom;
  try {
    custom = JSON.parse(headers.CustomHeaders || headers.customheaders || '{}');
  } catch { return returnError('Unable to parse custom headers'); }

  // Response headers
  const requestHeaders = {
    'Access-Control-Allow-Origin': '*',
    ...custom,
  };

  // Prepare request
  const requestConfig = {
    method: 'GET',
    url: requestUrl,
    data: body,
    headers: requestHeaders,
    validateUrl: validateTargetUrl,
    timeout: 30000,
    maxResponseSize: 10 * 1024 * 1024, // 10 MB
  };

  // Make request
  try {
    const response = await request(requestConfig);
    return { statusCode: 200, body: JSON.stringify(response.data) };
  } catch (error) {
    return returnError('Request failed', error);
  }
};
