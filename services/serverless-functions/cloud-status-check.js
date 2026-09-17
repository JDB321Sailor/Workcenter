/* A cloud function that wraps the status checking method, for use on Netlify */
const statusCheck = require('../endpoints/status-check');

exports.handler = async (event) => {
  try {
    const body = await new Promise((resolve) => { statusCheck(event.rawQuery, resolve); });
    return { statusCode: 200, headers: { 'Content-Type': 'application/json' }, body };
  } catch {
    return {
      statusCode: 500,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ successStatus: false, message: '❌ Status check failed badly' }),
    };
  }
};
