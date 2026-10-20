const readline = require('node:readline');
const { execFile } = require('node:child_process');

const endpoint = 'http://127.0.0.1:18473/mcp';
const bundleIds = ['dev.blitzreels.blitzrecorder', 'dev.blitzreels.blitzrecorder.debug'];
const launchTimeoutMs = 20000;

const isConnectionRefused = error => error.cause?.code === 'ECONNREFUSED';
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

function openInBackground(bundleId) {
  return new Promise(resolve => {
    execFile('/usr/bin/open', ['-g', '-b', bundleId, '--args', '--agent-background'], error => resolve(!error));
  });
}

async function launchApp() {
  for (const bundleId of bundleIds) {
    if (await openInBackground(bundleId)) return true;
  }
  return false;
}

function createForwarder({ url, fetchRequest, launchApp }) {
  let protocolVersion = '2025-11-25';
  let sessionId;

  async function fetchLaunchingApp(options) {
    try {
      return await fetchRequest(url, options());
    } catch (error) {
      if (!isConnectionRefused(error) || !(await launchApp())) throw error;
      const deadline = Date.now() + launchTimeoutMs;
      for (;;) {
        await delay(500);
        try {
          return await fetchRequest(url, options());
        } catch (retryError) {
          if (!isConnectionRefused(retryError) || Date.now() > deadline) throw retryError;
        }
      }
    }
  }

  return async function forward(message) {
    const headers = {
      'Content-Type': 'application/json',
      Accept: 'application/json, text/event-stream',
      'MCP-Protocol-Version': protocolVersion,
    };
    if (sessionId) headers['Mcp-Session-Id'] = sessionId;
    const response = await fetchLaunchingApp(() => ({
      method: 'POST',
      headers,
      body: JSON.stringify(message),
      signal: AbortSignal.timeout(60000),
      redirect: 'error',
    }));
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
        const detail = isConnectionRefused(error)
          ? 'Could not reach BlitzRecorder. Open BlitzRecorder and turn on Settings > Integrations > Allow local agents, then retry.'
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
    forward: createForwarder({ url: endpoint, fetchRequest: fetch, launchApp }),
  }).catch(error => {
    process.stderr.write(`BlitzRecorder: ${error.message}\n`);
    process.exitCode = 1;
  });
}
