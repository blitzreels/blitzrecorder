const readline = require('node:readline');

const endpoint = 'http://127.0.0.1:18473/mcp';

function createForwarder({ url, fetchRequest }) {
  let protocolVersion = '2025-11-25';
  let sessionId;

  return async function forward(message) {
    const headers = {
      'Content-Type': 'application/json',
      Accept: 'application/json, text/event-stream',
      'MCP-Protocol-Version': protocolVersion,
    };
    if (sessionId) headers['Mcp-Session-Id'] = sessionId;
    const response = await fetchRequest(url, {
      method: 'POST',
      headers,
      body: JSON.stringify(message),
      signal: AbortSignal.timeout(60000),
      redirect: 'error',
    });
    if (!response.ok) throw new Error(`BlitzRecorder returned HTTP ${response.status}. Check Settings > Integrations.`);
    sessionId = response.headers.get('mcp-session-id') || sessionId;
    if (response.status === 202 || response.status === 204) return null;
    const result = await response.json();
    if (message.method === 'initialize' && result.result?.protocolVersion) {
      protocolVersion = result.result.protocolVersion;
    }
    return result;
  };
}

function startBridge({ input, output, diagnostics, forward }) {
  const lines = readline.createInterface({ input, crlfDelay: Infinity });
  let pending = Promise.resolve();
  lines.on('line', line => {
    pending = pending.then(async () => {
      let message;
      try {
        message = JSON.parse(line);
        if (!message || message.jsonrpc !== '2.0' || typeof message.method !== 'string') {
          throw new Error('Expected a JSON-RPC 2.0 request.');
        }
        const result = await forward(message);
        if (result && Object.hasOwn(message, 'id')) output.write(JSON.stringify(result) + '\n');
      } catch (error) {
        const detail = error.cause?.code === 'ECONNREFUSED'
          ? 'Open BlitzRecorder and turn on Settings > Integrations > Allow local agents, then reconnect.'
          : error.message;
        if (message && Object.hasOwn(message, 'id')) {
          output.write(JSON.stringify({ jsonrpc: '2.0', id: message.id, error: { code: -32000, message: detail } }) + '\n');
        } else {
          diagnostics.write(`BlitzRecorder: ${detail}\n`);
        }
      }
    });
  });
  return new Promise(resolve => lines.on('close', () => pending.then(resolve)));
}

module.exports = { createForwarder, startBridge };

if (require.main === module) {
  startBridge({
    input: process.stdin,
    output: process.stdout,
    diagnostics: process.stderr,
    forward: createForwarder({ url: endpoint, fetchRequest: fetch }),
  }).catch(error => {
    process.stderr.write(`BlitzRecorder: ${error.message}\n`);
    process.exitCode = 1;
  });
}
