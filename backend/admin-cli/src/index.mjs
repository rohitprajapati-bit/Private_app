#!/usr/bin/env node
// Admin CLI for Color Match remote view-only sharing.
// Uses the service account (Firestore + Drive) — no Google password, no admin app.
//
// Usage: node src/index.mjs <command> [args]   (see `help`)

import { loadConfig, firestore, drive, FieldValue } from './clients.mjs';

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I
const SILENT_AFTER_MS = 1000 * 60 * 60 * 24 * 3;

async function main() {
  const [cmd, ...args] = process.argv.slice(2);
  const commands = {
    doctor, 'config:show': configShow, 'config:set': configSet,
    'library:create': libraryCreate, 'library:list': libraryList,
    register, 'item:list': itemList, 'item:remove': itemRemove,
    'code:create': codeCreate, 'code:list': codeList, 'code:disable': codeDisable,
    'devices:list': devicesList, 'device:revoke': deviceRevoke,
    'audit:list': auditList, help,
  };
  const fn = commands[cmd] || help;
  try {
    const cfg = loadConfig();
    await fn(cfg, args);
  } catch (e) {
    console.error('✗', e.message || e);
    process.exit(1);
  }
}

// --- Validation -------------------------------------------------------------

async function doctor(cfg) {
  console.log('Checking configuration (no secrets are printed)…\n');
  let ok = true;
  console.log(`  project         ${cfg.projectId}`);
  console.log(`  service account ${mask(cfg.serviceAccountEmail)}`);
  console.log(`  owner tag       ${cfg.ownerUid}`);
  console.log(`  drive folder    ${cfg.folderId || '(not set)'}\n`);

  try {
    await firestore(cfg).collection('libraries').limit(1).get();
    console.log('  ✓ Firestore reachable');
  } catch (e) {
    ok = false;
    console.log(`  ✗ Firestore: ${e.message}`);
  }

  if (cfg.folderId) {
    try {
      const meta = await drive(cfg).files.get({
        fileId: cfg.folderId,
        fields: 'id,name,mimeType',
        supportsAllDrives: true,
      });
      if (meta.data.mimeType !== 'application/vnd.google-apps.folder') {
        ok = false;
        console.log(`  ✗ DRIVE_FOLDER_ID is not a folder (${meta.data.mimeType})`);
      } else {
        console.log(`  ✓ Drive folder reachable: "${meta.data.name}"`);
      }
    } catch (e) {
      ok = false;
      console.log(`  ✗ Drive folder not reachable by the service account.`);
      console.log(`    → Share the folder with ${mask(cfg.serviceAccountEmail)} (Viewer). (${e.message})`);
    }
  } else {
    console.log('  ! DRIVE_FOLDER_ID not set — set it in .env to register media.');
  }
  console.log('');
  console.log(ok ? '✓ All checks passed.' : '✗ Some checks failed (see above).');
  if (!ok) process.exit(1);
}

// --- Config -----------------------------------------------------------------

async function configShow(cfg) {
  const doc = await firestore(cfg).collection('config').doc(cfg.ownerUid).get();
  console.log(doc.exists ? doc.data() : '(no config doc yet — run config:set)');
}

async function configSet(cfg, args) {
  const folder = flag(args, '--folder') || cfg.folderId;
  await firestore(cfg).collection('config').doc(cfg.ownerUid).set(
    {
      driveFolderId: folder,
      serviceAccountEmail: cfg.serviceAccountEmail,
      brokerUrl: cfg.brokerUrl,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  console.log('✓ Config saved.');
}

// --- Libraries --------------------------------------------------------------

async function libraryCreate(cfg, args) {
  const name = args.filter((a) => !a.startsWith('--')).join(' ').trim();
  if (!name) throw new Error('Usage: library:create "<name>"');
  const ref = await firestore(cfg).collection('libraries').add({
    ownerUid: cfg.ownerUid,
    name,
    createdAt: FieldValue.serverTimestamp(),
  });
  console.log(`✓ Library created: ${ref.id}  ("${name}")`);
  console.log(`  Next: add files to the Drive folder, then  register ${ref.id}`);
}

async function libraryList(cfg) {
  const snap = await firestore(cfg).collection('libraries').where('ownerUid', '==', cfg.ownerUid).get();
  if (snap.empty) return console.log('(no libraries yet)');
  for (const d of snap.docs) {
    const items = await firestore(cfg).collection('libraries').doc(d.id).collection('items').count().get();
    console.log(`  ${d.id}  "${d.data().name}"  — ${items.data().count} item(s)`);
  }
}

// --- Register (upload = drop into Drive folder; this records them) -----------

async function register(cfg, args) {
  const libraryId = args.find((a) => !a.startsWith('--'));
  const folderId = flag(args, '--folder') || cfg.folderId;
  if (!libraryId) throw new Error('Usage: register <libraryId> [--folder <id>]');
  if (!folderId) throw new Error('No Drive folder id. Set DRIVE_FOLDER_ID or pass --folder.');

  const lib = await firestore(cfg).collection('libraries').doc(libraryId).get();
  if (!lib.exists) throw new Error(`Library ${libraryId} not found. Create it with library:create.`);

  const itemsRef = firestore(cfg).collection('libraries').doc(libraryId).collection('items');
  const known = new Set((await itemsRef.get()).docs.map((d) => d.data().driveFileId));

  const d = drive(cfg);
  let added = 0, skipped = 0, pageToken;
  do {
    const res = await d.files.list({
      q: `'${folderId}' in parents and trashed = false`,
      fields:
        'nextPageToken, files(id,name,mimeType,size,imageMediaMetadata(width,height),videoMediaMetadata(width,height,durationMillis))',
      pageSize: 200,
      pageToken,
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
    });
    for (const f of res.data.files || []) {
      const type = f.mimeType?.startsWith('video/') ? 'video' : f.mimeType?.startsWith('image/') ? 'image' : null;
      if (!type) { skipped++; continue; }
      if (known.has(f.id)) { skipped++; continue; }
      const vm = f.videoMediaMetadata || {};
      const im = f.imageMediaMetadata || {};
      await itemsRef.add({
        type,
        name: f.name || 'untitled',
        ext: (f.name?.split('.').pop() || '').toLowerCase(),
        driveFileId: f.id,
        thumbFileId: null,
        size: Number(f.size || 0),
        width: vm.width || im.width || null,
        height: vm.height || im.height || null,
        durationMs: vm.durationMillis ? Number(vm.durationMillis) : null,
        createdAt: FieldValue.serverTimestamp(),
      });
      console.log(`  + ${type}  ${f.name}`);
      added++;
    }
    pageToken = res.data.nextPageToken;
  } while (pageToken);

  console.log(`\n✓ Registered ${added} new item(s); ${skipped} skipped (already known or non-media).`);
}

async function itemList(cfg, args) {
  const libraryId = args.find((a) => !a.startsWith('--'));
  if (!libraryId) throw new Error('Usage: item:list <libraryId>');
  const snap = await firestore(cfg).collection('libraries').doc(libraryId).collection('items').get();
  if (snap.empty) return console.log('(no items)');
  for (const d of snap.docs) {
    const i = d.data();
    console.log(`  ${d.id}  [${i.type}]  ${i.name}  ${(i.size / 1048576).toFixed(1)}MB`);
  }
}

async function itemRemove(cfg, args) {
  const [libraryId, itemId] = args.filter((a) => !a.startsWith('--'));
  const alsoTrash = args.includes('--trash');
  if (!libraryId || !itemId) throw new Error('Usage: item:remove <libraryId> <itemId> [--trash]');
  const ref = firestore(cfg).collection('libraries').doc(libraryId).collection('items').doc(itemId);
  const doc = await ref.get();
  if (!doc.exists) throw new Error('Item not found.');
  const driveFileId = doc.data().driveFileId;
  await ref.delete();
  console.log('✓ Unregistered from the library (users can no longer see it).');
  if (alsoTrash && driveFileId) {
    try {
      await drive(cfg).files.update({ fileId: driveFileId, requestBody: { trashed: true }, supportsAllDrives: true });
      console.log('✓ Drive file moved to trash.');
    } catch (e) {
      console.log(`! Could not trash the Drive file (needs Editor on the folder): ${e.message}`);
      console.log('  You can delete it yourself in Google Drive (you own it).');
    }
  }
}

// --- Codes ------------------------------------------------------------------

async function codeCreate(cfg, args) {
  const libraryId = args.find((a) => !a.startsWith('--'));
  if (!libraryId) throw new Error('Usage: code:create <libraryId> [--label "name"] [--max N]');
  const lib = await firestore(cfg).collection('libraries').doc(libraryId).get();
  if (!lib.exists) throw new Error(`Library ${libraryId} not found.`);
  const label = flag(args, '--label') || '';
  const maxDevices = Number(flag(args, '--max') || '1');

  const db = firestore(cfg);
  let code;
  for (let tries = 0; tries < 10; tries++) {
    code = randomCode(8);
    if (!(await db.collection('codes').doc(code).get()).exists) break;
    code = null;
  }
  if (!code) throw new Error('Could not allocate a unique code, try again.');

  await db.collection('codes').doc(code).set({
    ownerUid: cfg.ownerUid,
    libraryId,
    label,
    active: true,
    maxDevices,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: null,
  });
  console.log(`\n  ACCESS CODE:  ${code}\n`);
  console.log(`  library "${lib.data().name}"  ·  up to ${maxDevices} device(s)${label ? `  ·  ${label}` : ''}`);
  console.log('  Give this code to the viewer; they enter it in the app.');
}

async function codeList(cfg) {
  const db = firestore(cfg);
  const snap = await db.collection('codes').where('ownerUid', '==', cfg.ownerUid).get();
  if (snap.empty) return console.log('(no codes)');
  for (const d of snap.docs) {
    const c = d.data();
    const devices = await db.collection('devices').where('code', '==', d.id).get();
    const active = devices.docs.filter((x) => x.data().revoked !== true).length;
    console.log(`  ${d.id}  ${c.active ? 'ON ' : 'OFF'}  lib=${c.libraryId}  max=${c.maxDevices}  devices=${active}${c.label ? `  "${c.label}"` : ''}`);
  }
}

async function codeDisable(cfg, args) {
  const code = (args.find((a) => !a.startsWith('--')) || '').toUpperCase();
  if (!code) throw new Error('Usage: code:disable <CODE>');
  await firestore(cfg).collection('codes').doc(code).set({ active: false }, { merge: true });
  console.log(`✓ Code ${code} turned off. Devices lose access on their next request.`);
}

// --- Devices (install / uninstall / revoke) ---------------------------------

async function devicesList(cfg) {
  const snap = await firestore(cfg).collection('devices').where('ownerUid', '==', cfg.ownerUid).get();
  if (snap.empty) return console.log('(no devices have redeemed a code yet)');
  const now = Date.now();
  for (const d of snap.docs) {
    const v = d.data();
    const seen = tsToMs(v.lastSeenAt);
    const status = v.revoked ? 'REVOKED' : seen && now - seen < SILENT_AFTER_MS ? 'active' : 'silent/gone';
    console.log(`  ${d.id}  ${v.platform || '?'}  "${v.name || ''}"  code=${v.code}  ${status}  lastSeen=${fmt(seen)}`);
  }
}

async function deviceRevoke(cfg, args) {
  const id = args.find((a) => !a.startsWith('--'));
  if (!id) throw new Error('Usage: device:revoke <deviceId>');
  await firestore(cfg).collection('devices').doc(id).set({ revoked: true }, { merge: true });
  console.log(`✓ Device ${id} revoked. It loses access on its next request.`);
}

// --- Audit ------------------------------------------------------------------

async function auditList(cfg, args) {
  const limit = Number(flag(args, '--limit') || '30');
  const snap = await firestore(cfg).collection('audit').orderBy('ts', 'desc').limit(limit).get();
  if (snap.empty) return console.log('(no audit entries yet)');
  for (const d of snap.docs.reverse()) {
    const a = d.data();
    console.log(`  ${a.ts}  ${a.event}${a.reason ? `(${a.reason})` : ''}  dev=${a.deviceId || '-'}  item=${a.itemId || '-'}  code=${a.code || '-'}`);
  }
}

// --- helpers ----------------------------------------------------------------

function help() {
  console.log(`Color Match admin CLI

  doctor                              validate config, Firestore and Drive access
  config:set [--folder <id>]          write the config doc
  config:show

  library:create "<name>"             make a library, prints its id
  library:list
  register <libraryId> [--folder id]  record new media you dropped in the Drive folder
  item:list <libraryId>
  item:remove <libraryId> <itemId> [--trash]   admin-only delete

  code:create <libraryId> [--label "x"] [--max N]   issue an access code
  code:list
  code:disable <CODE>

  devices:list                        who installed / last seen / revoked
  device:revoke <deviceId>

  audit:list [--limit N]              recent access log

First run:  cp .env.example .env  &&  edit .env  &&  npm install  &&  npm run doctor`);
}

const flag = (args, name) => {
  const i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
};
const mask = (s) => (s ? s.replace(/^(.{3}).*(@.*)$/, '$1•••$2') : s);
const randomCode = (n) => {
  const b = new Uint8Array(n);
  globalThis.crypto.getRandomValues(b);
  return [...b].map((x) => CODE_ALPHABET[x % CODE_ALPHABET.length]).join('');
};
const tsToMs = (t) => (t?.toMillis ? t.toMillis() : t?._seconds ? t._seconds * 1000 : typeof t === 'string' ? Date.parse(t) : null);
const fmt = (ms) => (ms ? new Date(ms).toISOString().replace('T', ' ').slice(0, 16) : 'never');

main();
