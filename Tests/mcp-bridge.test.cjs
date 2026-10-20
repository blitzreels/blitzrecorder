const { test } = require('node:test');
const assert = require('node:assert/strict');
const { PassThrough } = require('node:stream');
const { createForwarder, startBridge } = require('../Sources/BlitzRecorderApp/Resources/BlitzRecorderMCPBridge/bridge.cjs');

test('bridge forwards lifecycle headers and keeps notifications off stdout', async () => {
  const requests = [];
  const forward = createForwarder({
    url: 'http://127.0.0.1:18473/mcp',
    launchApp: async () => false,
    fetchRequest: async (url, options) => {
      const message = JSON.parse(options.body);
      requests.push({ url, options, message });
      if (!Object.hasOwn(message, 'id')) return new Response(null, { status: 202 });
      const result = message.method === 'initialize' ? { protocolVersion: '2025-06-18' } : { tools: [] };
      return new Response(JSON.stringify({ jsonrpc: '2.0', id: message.id, result }), {
        status: 200, headers: { 'mcp-session-id': 'test-session' },
      });
    },
  });
  const input = new PassThrough();
  const output = new PassThrough();
  const diagnostics = new PassThrough();
  let text = '';
  output.on('data', data => { text += data; });
  const finished = startBridge({ input, output, diagnostics, forward });
  input.end([
    { jsonrpc: '2.0', id: 1, method: 'initialize' },
    { jsonrpc: '2.0', method: 'notifications/initialized' },
    { jsonrpc: '2.0', id: 2, method: 'tools/list' },
  ].map(message => JSON.stringify(message)).join('\n') + '\n');
  await finished;
  const responses = text.trim().split('\n').map(JSON.parse);
  assert.deepEqual(responses.map(response => response.id), [1, 2]);
  assert.equal(requests[2].options.headers['MCP-Protocol-Version'], '2025-06-18');
  assert.equal(requests[2].options.headers['Mcp-Session-Id'], 'test-session');
  assert.equal(requests[2].options.headers.Accept, 'application/json, text/event-stream');
});

test('connection failures explain recovery and never retry a tool call', async () => {
  const input = new PassThrough();
  const output = new PassThrough();
  const diagnostics = new PassThrough();
  let text = '';
  let attempts = 0;
  output.on('data', data => { text += data; });
  const finished = startBridge({ input, output, diagnostics, forward: async () => {
    attempts += 1;
    throw new Error('fetch failed', { cause: { code: 'ECONNREFUSED' } });
  } });
  input.end(JSON.stringify({ jsonrpc: '2.0', id: 9, method: 'tools/call' }) + '\n');
  await finished;
  assert.equal(attempts, 1);
  const response = JSON.parse(text);
  assert.equal(response.id, 9);
  assert.match(response.error.message, /Open BlitzRecorder/);
});
