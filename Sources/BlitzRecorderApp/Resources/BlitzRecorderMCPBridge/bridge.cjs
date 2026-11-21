const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const readline = require('node:readline');

const endpoint = 'http://127.0.0.1:18473/mcp';
const defaultProtocolVersion = '2025-11-25';
const appClosedMessage = "BlitzRecorder isn't open. Open BlitzRecorder (Settings > Integrations > Allow local agents), then retry.";

const isConnectionRefused = error => error.cause?.code === 'ECONNREFUSED';

function createFileCache(file) {
  function read() {
    try {
      return JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch {
      return {};
    }
  }
  function write(entry) {
    try {
      fs.mkdirSync(path.dirname(file), { recursive: true });
      const temporary = `${file}.${process.pid}.tmp`;
      fs.writeFileSync(temporary, JSON.stringify({ ...read(), ...entry }));
      fs.renameSync(temporary, file);
    } catch {}
  }
  return { read, write };
}

function answerWhileAppClosed({ message, cache, error }) {
  if (!Object.hasOwn(message, 'id')) return null;
  const saved = cache.read();
  const reply = result => ({ jsonrpc: '2.0', id: message.id, result });
  switch (message.method) {
    case 'initialize':
      return reply(saved.initialize ?? {
        protocolVersion: message.params?.protocolVersion ?? defaultProtocolVersion,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: 'blitzrecorder', version: '0.0.0' },
      });
    case 'tools/list':
      return reply({ tools: saved.tools ?? [] });
    case 'ping':
      return reply({});
    default:
      throw error;
  }
}

function createForwarder({ url, fetchRequest, cache }) {
  let protocolVersion = defaultProtocolVersion;
  let sessionId;

  return async function forward(message) {
    const headers = {
      'Content-Type': 'application/json',
      Accept: 'application/json, text/event-stream',
      'MCP-Protocol-Version': protocolVersion,
    };
    if (sessionId) headers['Mcp-Session-Id'] = sessionId;
    let response;
    try {
      response = await fetchRequest(url, {
        method: 'POST',
        headers,
        body: JSON.stringify(message),
        signal: AbortSignal.timeout(60000),
        redirect: 'error',
      });
    } catch (error) {
      if (!isConnectionRefused(error)) throw error;
      const reply = answerWhileAppClosed({ message, cache, error });
      if (message.method === 'initialize' && reply?.result.protocolVersion) {
        protocolVersion = reply.result.protocolVersion;
      }
      return reply;
    }
    if (!response.ok) throw new Error(`BlitzRecorder returned HTTP ${response.status}. Check Settings > Integrations.`);
    sessionId = response.headers.get('mcp-session-id') || sessionId;
    if (response.status === 202 || response.status === 204) return null;
    const result = await response.json();
    if (message.method === 'initialize' && result.result) {
      if (result.result.protocolVersion) protocolVersion = result.result.protocolVersion;
      cache.write({ initialize: result.result });
    }
    if (message.method === 'tools/list' && !message.params?.cursor && Array.isArray(result.result?.tools)) {
      cache.write({ tools: result.result.tools });
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
        const detail = isConnectionRefused(error) ? appClosedMessage : error.message;
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
  const cacheName = /^[\w.-]+$/.test(process.argv[2] ?? '') ? process.argv[2] : 'default';
  const cacheFile = path.join(os.homedir(), 'Library', 'Caches', 'BlitzRecorderMCPBridge', `${cacheName}.json`);
  startBridge({
    input: process.stdin,
    output: process.stdout,
    diagnostics: process.stderr,
    forward: createForwarder({ url: endpoint, fetchRequest: fetch, cache: createFileCache(cacheFile) }),
  }).catch(error => {
    process.stderr.write(`BlitzRecorder: ${error.message}\n`);
    process.exitCode = 1;
  });
}
