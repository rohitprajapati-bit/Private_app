// Cloudflare Worker: view-only media broker for the code → library sharing model.
//
// User devices talk ONLY to this Worker. It validates the code + device against Firestore and
// streams media bytes straight from the admin's Google Drive — never returning a Drive URL or a
// downloadable link. It authenticates to Google with a service account (held as Worker secrets),
// so no Google/Drive credential is ever present on a user's phone.
//
// Required secrets / vars (see backend/README.md):
//   GCP_PROJECT_ID        Firebase/GCP project id
//   GCP_SA_EMAIL          service account email
//   GCP_SA_PRIVATE_KEY    service account private key (PEM, newlines as real newlines or \n)
//
// Endpoints (all under /v1):
//   POST /v1/redeem                 { code, deviceId, name, platform } -> { deviceToken, library }
//   GET  /v1/library                headers X-Device-Id, X-Device-Token -> { library }
//   GET  /v1/media/:itemId          device headers, optional Range -> streamed bytes
//   GET  /v1/thumb/:itemId          device headers -> streamed thumbnail bytes
//   POST /v1/heartbeat              device headers -> { ok: true }

const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPES = [
  'https://www.googleapis.com/auth/datastore',
  'https://www.googleapis.com/auth/drive.readonly',
].join(' ');

const DEVICE_SILENT_AFTER_MS = 1000 * 60 * 60 * 24 * 3; // not used server-side; doc for the dashboard

export default {
  async fetch(request, env, ctx) {
    const log = auditor(env, ctx);
    try {
      const url = new URL(request.url);
      const path = url.pathname.replace(/\/+$/, '');

      if (request.method === 'POST' && path === '/v1/redeem') return await redeem(request, env, log);
      if (request.method === 'GET' && path === '/v1/library') return await getLibrary(request, env, log);
      if (request.method === 'GET' && path.startsWith('/v1/media/')) {
        return await streamMedia(request, env, decodeURIComponent(path.slice('/v1/media/'.length)), false, log);
      }
      if (request.method === 'GET' && path.startsWith('/v1/thumb/')) {
        return await streamMedia(request, env, decodeURIComponent(path.slice('/v1/thumb/'.length)), true, log);
      }
      if (request.method === 'POST' && path === '/v1/heartbeat') return await heartbeat(request, env, log);

      // There is deliberately NO upload, write or delete endpoint: users physically cannot
      // mutate anything through this Worker.
      return json({ error: 'not_found' }, 404);
    } catch (e) {
      return json({ error: 'server_error', detail: String(e && e.message || e) }, 500);
    }
  },
};

/// Returns a non-blocking audit logger bound to this request's context.
function auditor(env, ctx) {
  return (entry) => {
    try {
      const write = createDoc(env, 'audit', { ...entry, ts: new Date().toISOString() });
      if (ctx && ctx.waitUntil) ctx.waitUntil(write.catch(() => {}));
    } catch (_) {
      // Auditing must never break a request.
    }
  };
}

// ---------------------------------------------------------------------------
// Endpoints
// ---------------------------------------------------------------------------

async function redeem(request, env, log) {
  const body = await request.json().catch(() => ({}));
  const code = String(body.code || '').trim().toUpperCase();
  const deviceId = String(body.deviceId || '').trim();
  const name = String(body.name || 'device').slice(0, 64);
  const platform = body.platform === 'ios' ? 'ios' : 'android';
  if (!code || !deviceId) return json({ error: 'bad_request' }, 400);

  const codeDoc = await getDoc(env, `codes/${code}`);
  if (!codeDoc) {
    log({ event: 'redeem_denied', reason: 'invalid_code', code, deviceId });
    return json({ error: 'invalid_code' }, 404);
  }
  const c = codeDoc.fields;
  if (c.active !== true) {
    log({ event: 'redeem_denied', reason: 'code_disabled', code, deviceId, ownerUid: c.ownerUid });
    return json({ error: 'code_disabled' }, 403);
  }
  if (c.expiresAt && Date.parse(c.expiresAt) < Date.now()) {
    log({ event: 'redeem_denied', reason: 'code_expired', code, deviceId, ownerUid: c.ownerUid });
    return json({ error: 'code_expired' }, 403);
  }

  const ownerUid = c.ownerUid;
  const libraryId = c.libraryId;
  const maxDevices = Number(c.maxDevices || 1);

  // Enforce the device cap, but always allow a device that already redeemed this code to come back.
  const existing = await getDoc(env, `devices/${deviceId}`);
  if (!existing || existing.fields.code !== code) {
    const peers = await queryDevicesForCode(env, code);
    const otherCount = peers.filter((d) => d.id !== deviceId && d.fields.revoked !== true).length;
    if (otherCount >= maxDevices) {
      log({ event: 'redeem_denied', reason: 'device_limit', code, deviceId, ownerUid });
      return json({ error: 'device_limit' }, 403);
    }
  }
  if (existing && existing.fields.revoked === true) {
    log({ event: 'redeem_denied', reason: 'revoked', code, deviceId, ownerUid });
    return json({ error: 'revoked' }, 403);
  }

  // Issue a fresh device token; store only its hash.
  const deviceToken = base64url(crypto.getRandomValues(new Uint8Array(32)));
  const tokenHash = await sha256Hex(deviceToken);
  const now = new Date().toISOString();

  await putDoc(env, `devices/${deviceId}`, {
    ownerUid, code, libraryId, name, platform,
    tokenHash,
    installedAt: existing ? existing.fields.installedAt || now : now,
    lastSeenAt: now,
    revoked: false,
  });

  const library = await buildManifest(env, libraryId);
  log({ event: 'redeem', code, deviceId, libraryId, ownerUid, platform, name });
  return json({ deviceToken, library });
}

async function getLibrary(request, env, log) {
  const device = await authDevice(request, env, log);
  if (!device.ok) return device.response;
  const library = await buildManifest(env, device.doc.fields.libraryId);
  return json({ library });
}

async function streamMedia(request, env, itemId, thumb, log) {
  const device = await authDevice(request, env, log);
  if (!device.ok) return device.response;

  const libraryId = device.doc.fields.libraryId;
  const item = await getDoc(env, `libraries/${libraryId}/items/${itemId}`);
  if (!item) return json({ error: 'not_found' }, 404);

  const driveFileId = thumb ? item.fields.thumbFileId : item.fields.driveFileId;
  if (!driveFileId) return json({ error: 'not_found' }, 404);

  const token = await accessToken(env);
  const driveUrl = `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(driveFileId)}?alt=media&supportsAllDrives=true`;
  const headers = { Authorization: `Bearer ${token}` };
  const range = request.headers.get('Range');
  if (range) headers['Range'] = range; // forward range so video seeks

  const upstream = await fetch(driveUrl, { headers });
  if (!upstream.ok && upstream.status !== 206) {
    return json({ error: 'upstream', status: upstream.status }, 502);
  }
  if (!thumb && !range) log({ event: 'media', deviceId: device.id, itemId, libraryId });

  // Pass bytes through; strip anything that could become a saveable URL/link.
  const out = new Headers();
  copyHeader(upstream, out, 'Content-Type');
  copyHeader(upstream, out, 'Content-Length');
  copyHeader(upstream, out, 'Content-Range');
  copyHeader(upstream, out, 'Accept-Ranges');
  out.set('Accept-Ranges', upstream.headers.get('Accept-Ranges') || 'bytes');
  out.set('Cache-Control', 'no-store');
  out.set('Content-Disposition', 'inline');
  return new Response(upstream.body, { status: upstream.status, headers: out });
}

async function heartbeat(request, env, log) {
  const device = await authDevice(request, env, log);
  if (!device.ok) return device.response;
  await patchDoc(env, `devices/${device.id}`, { lastSeenAt: new Date().toISOString() }, ['lastSeenAt']);
  return json({ ok: true });
}

// ---------------------------------------------------------------------------
// Device auth
// ---------------------------------------------------------------------------

async function authDevice(request, env, log) {
  const deviceId = request.headers.get('X-Device-Id') || '';
  const deviceToken = request.headers.get('X-Device-Token') || '';
  if (!deviceId || !deviceToken) return { ok: false, response: json({ error: 'unauthorized' }, 401) };

  const doc = await getDoc(env, `devices/${deviceId}`);
  if (!doc) return { ok: false, response: json({ error: 'unauthorized' }, 401) };
  if (doc.fields.revoked === true) {
    if (log) log({ event: 'denied', reason: 'revoked', deviceId });
    return { ok: false, response: json({ error: 'revoked' }, 403) };
  }

  const hash = await sha256Hex(deviceToken);
  if (!timingSafeEqual(hash, doc.fields.tokenHash || '')) {
    if (log) log({ event: 'denied', reason: 'bad_token', deviceId });
    return { ok: false, response: json({ error: 'unauthorized' }, 401) };
  }
  return { ok: true, id: deviceId, doc };
}

async function buildManifest(env, libraryId) {
  const lib = await getDoc(env, `libraries/${libraryId}`);
  const items = await listDocs(env, `libraries/${libraryId}/items`);
  return {
    id: libraryId,
    name: lib ? lib.fields.name : '',
    items: items.map((d) => ({
      id: d.id,
      type: d.fields.type,
      name: d.fields.name,
      ext: d.fields.ext,
      size: d.fields.size,
      width: d.fields.width ?? null,
      height: d.fields.height ?? null,
      durationMs: d.fields.durationMs ?? null,
      hasThumb: !!d.fields.thumbFileId,
    })),
  };
}

// ---------------------------------------------------------------------------
// Firestore REST (service account; bypasses security rules)
// ---------------------------------------------------------------------------

function fsBase(env) {
  return `https://firestore.googleapis.com/v1/projects/${env.GCP_PROJECT_ID}/databases/(default)/documents`;
}

async function getDoc(env, relPath) {
  const token = await accessToken(env);
  const res = await fetch(`${fsBase(env)}/${relPath}`, { headers: { Authorization: `Bearer ${token}` } });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`firestore get ${relPath}: ${res.status}`);
  const doc = await res.json();
  return { id: idFromName(doc.name), fields: decodeFields(doc.fields || {}) };
}

async function listDocs(env, relCollection) {
  const token = await accessToken(env);
  const out = [];
  let pageToken = '';
  do {
    const u = new URL(`${fsBase(env)}/${relCollection}`);
    u.searchParams.set('pageSize', '300');
    if (pageToken) u.searchParams.set('pageToken', pageToken);
    const res = await fetch(u, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) throw new Error(`firestore list ${relCollection}: ${res.status}`);
    const data = await res.json();
    for (const doc of data.documents || []) out.push({ id: idFromName(doc.name), fields: decodeFields(doc.fields || {}) });
    pageToken = data.nextPageToken || '';
  } while (pageToken);
  return out;
}

async function queryDevicesForCode(env, code) {
  const token = await accessToken(env);
  const body = {
    structuredQuery: {
      from: [{ collectionId: 'devices' }],
      where: { fieldFilter: { field: { fieldPath: 'code' }, op: 'EQUAL', value: { stringValue: code } } },
      limit: 1000,
    },
  };
  const res = await fetch(`${fsBase(env)}:runQuery`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`firestore query devices: ${res.status}`);
  const rows = await res.json();
  return rows
    .filter((r) => r.document)
    .map((r) => ({ id: idFromName(r.document.name), fields: decodeFields(r.document.fields || {}) }));
}

async function createDoc(env, collection, obj) {
  const token = await accessToken(env);
  // POST to a collection with no document id makes Firestore assign a random one.
  const res = await fetch(`${fsBase(env)}/${collection}`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields: encodeFields(obj) }),
  });
  if (!res.ok) throw new Error(`firestore create ${collection}: ${res.status}`);
}

async function putDoc(env, relPath, obj) {
  const token = await accessToken(env);
  // PATCH with no updateMask writes/overwrites the whole document (creates if absent).
  const res = await fetch(`${fsBase(env)}/${relPath}`, {
    method: 'PATCH',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields: encodeFields(obj) }),
  });
  if (!res.ok) throw new Error(`firestore put ${relPath}: ${res.status} ${await res.text()}`);
}

async function patchDoc(env, relPath, obj, fieldPaths) {
  const token = await accessToken(env);
  const u = new URL(`${fsBase(env)}/${relPath}`);
  for (const f of fieldPaths) u.searchParams.append('updateMask.fieldPaths', f);
  const res = await fetch(u, {
    method: 'PATCH',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields: encodeFields(obj) }),
  });
  if (!res.ok) throw new Error(`firestore patch ${relPath}: ${res.status}`);
}

function idFromName(name) {
  return name.slice(name.lastIndexOf('/') + 1);
}

// Firestore typed-value <-> plain JS.
function decodeFields(fields) {
  const out = {};
  for (const [k, v] of Object.entries(fields)) out[k] = decodeValue(v);
  return out;
}
function decodeValue(v) {
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return Number(v.doubleValue);
  if ('booleanValue' in v) return v.booleanValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('nullValue' in v) return null;
  if ('mapValue' in v) return decodeFields(v.mapValue.fields || {});
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(decodeValue);
  return null;
}
function encodeFields(obj) {
  const out = {};
  for (const [k, v] of Object.entries(obj)) out[k] = encodeValue(v);
  return out;
}
function encodeValue(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === 'string') {
    // ISO timestamps are stored as timestampValue so the dashboard can sort/age them.
    if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(v)) return { timestampValue: v };
    return { stringValue: v };
  }
  if (Array.isArray(v)) return { arrayValue: { values: v.map(encodeValue) } };
  if (typeof v === 'object') return { mapValue: { fields: encodeFields(v) } };
  return { nullValue: null };
}

// ---------------------------------------------------------------------------
// Google service-account auth (JWT -> access token), cached per isolate.
// ---------------------------------------------------------------------------

let _tokenCache = { value: '', exp: 0 };

async function accessToken(env) {
  const now = Math.floor(Date.now() / 1000);
  if (_tokenCache.value && _tokenCache.exp - 60 > now) return _tokenCache.value;

  const header = { alg: 'RS256', typ: 'JWT' };
  const claims = {
    iss: env.GCP_SA_EMAIL,
    scope: SCOPES,
    aud: GOOGLE_TOKEN_URL,
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${base64urlJson(header)}.${base64urlJson(claims)}`;
  const key = await importPrivateKey(env.GCP_SA_PRIVATE_KEY);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned));
  const jwt = `${unsigned}.${base64url(new Uint8Array(sig))}`;

  const res = await fetch(GOOGLE_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}&assertion=${jwt}`,
  });
  if (!res.ok) throw new Error(`token exchange: ${res.status} ${await res.text()}`);
  const data = await res.json();
  _tokenCache = { value: data.access_token, exp: now + (data.expires_in || 3600) };
  return _tokenCache.value;
}

async function importPrivateKey(pem) {
  const body = pem.replace(/\\n/g, '\n')
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '');
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), { status, headers: { 'Content-Type': 'application/json' } });
}
function copyHeader(from, to, name) {
  const v = from.headers.get(name);
  if (v) to.set(name, v);
}
function base64url(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function base64urlJson(obj) {
  return base64url(new TextEncoder().encode(JSON.stringify(obj)));
}
async function sha256Hex(str) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(str));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
