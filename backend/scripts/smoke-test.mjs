#!/usr/bin/env node
// Verifies the deployed Worker enforces the view-only guarantees.
//
// Usage:
//   node backend/scripts/smoke-test.mjs <brokerUrl> [--code ABCD1234]
//   BROKER_URL=https://... node backend/scripts/smoke-test.mjs
//
// Without --code it runs the checks that need no real data. With a real --code it also proves a
// granted device can stream, an ungranted request cannot, and no Google Drive URL ever leaks.

const base = (process.argv[2] && !process.argv[2].startsWith('--') ? process.argv[2] : process.env.BROKER_URL || '').replace(/\/+$/, '');
const code = flag('--code');
if (!base) fail('Pass the broker URL: node backend/scripts/smoke-test.mjs https://colormatch-broker.you.workers.dev');

let passed = 0, failed = 0;
const DRIVE_LEAK = /drive\.google\.com|googleapis\.com\/drive|alt=media/i;

await test('media without a device token is rejected (401)', async () => {
  const r = await fetch(`${base}/v1/media/whatever`);
  assert(r.status === 401, `expected 401, got ${r.status}`);
  assert(!DRIVE_LEAK.test(await r.text()), 'response leaked a Drive URL');
});

await test('library without a device token is rejected (401)', async () => {
  const r = await fetch(`${base}/v1/library`);
  assert(r.status === 401, `expected 401, got ${r.status}`);
});

await test('invalid code is rejected', async () => {
  const r = await fetch(`${base}/v1/redeem`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code: 'ZZZZZZZZ', deviceId: 'smoke', platform: 'android' }),
  });
  const body = await r.json();
  assert(body.error === 'invalid_code', `expected invalid_code, got ${JSON.stringify(body)}`);
});

for (const [method, path] of [['POST', '/v1/media/x'], ['DELETE', '/v1/media/x'], ['PUT', '/v1/library'], ['POST', '/v1/upload'], ['DELETE', '/v1/library/x']]) {
  await test(`no write surface: ${method} ${path} → not found`, async () => {
    const r = await fetch(`${base}${path}`, { method });
    assert(r.status === 404 || r.status === 401, `expected 404/401, got ${r.status}`);
  });
}

if (code) {
  const deviceId = 'smoke-' + Math.random().toString(36).slice(2, 8);
  let token, manifest;
  await test('a real code redeems and returns a manifest (no Drive URLs)', async () => {
    const r = await fetch(`${base}/v1/redeem`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code, deviceId, platform: 'android', name: 'smoke-test' }),
    });
    const text = await r.text();
    assert(r.ok, `redeem failed: ${r.status} ${text}`);
    assert(!DRIVE_LEAK.test(text), 'manifest leaked a Drive URL');
    const body = JSON.parse(text);
    token = body.deviceToken;
    manifest = body.library;
    assert(token && manifest, 'missing token or library');
    console.log(`     library "${manifest.name}" with ${manifest.items.length} item(s)`);
  });

  if (manifest?.items?.length) {
    const item = manifest.items[0];
    await test('granted device can stream an item', async () => {
      const r = await fetch(`${base}/v1/media/${item.id}`, { headers: { 'X-Device-Id': deviceId, 'X-Device-Token': token } });
      assert(r.ok || r.status === 206, `expected 200/206, got ${r.status}`);
      assert(r.headers.get('content-disposition') !== 'attachment', 'served as a download, not inline');
    });
    await test('same item without the token is rejected', async () => {
      const r = await fetch(`${base}/v1/media/${item.id}`);
      assert(r.status === 401, `expected 401, got ${r.status}`);
    });
  }
}

console.log(`\n${failed ? '✗' : '✓'} ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);

// --- helpers ---
async function test(name, fn) {
  try { await fn(); passed++; console.log(`  ✓ ${name}`); }
  catch (e) { failed++; console.log(`  ✗ ${name}\n      ${e.message}`); }
}
function assert(cond, msg) { if (!cond) throw new Error(msg); }
function flag(n) { const i = process.argv.indexOf(n); return i >= 0 ? process.argv[i + 1] : null; }
function fail(m) { console.error(m); process.exit(1); }
