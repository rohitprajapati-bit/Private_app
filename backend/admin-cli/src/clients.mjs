import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import 'dotenv/config';
import admin from 'firebase-admin';
import { google } from 'googleapis';

/// Loads config from the environment and fails loudly (never printing secret values).
export function loadConfig() {
  const saPath = resolve(process.env.GOOGLE_APPLICATION_CREDENTIALS || './service-account.json');
  let sa;
  try {
    sa = JSON.parse(readFileSync(saPath, 'utf8'));
  } catch (e) {
    throw new Error(
      `Could not read the service account key at ${saPath}. ` +
        `Download it from Firebase → Project settings → Service accounts and place it there.`,
    );
  }
  const projectId = process.env.GCP_PROJECT_ID || sa.project_id;
  if (!projectId) throw new Error('GCP_PROJECT_ID is not set and the key has no project_id.');
  return {
    sa,
    projectId,
    folderId: process.env.DRIVE_FOLDER_ID || '',
    ownerUid: process.env.ADMIN_OWNER_UID || 'admin',
    brokerUrl: process.env.BROKER_URL || '',
    serviceAccountEmail: sa.client_email,
  };
}

let _db;
export function firestore(cfg) {
  if (_db) return _db;
  if (!admin.apps.length) {
    admin.initializeApp({ credential: admin.credential.cert(cfg.sa), projectId: cfg.projectId });
  }
  _db = admin.firestore();
  return _db;
}

let _drive;
export function drive(cfg) {
  if (_drive) return _drive;
  const auth = new google.auth.JWT({
    email: cfg.sa.client_email,
    key: cfg.sa.private_key,
    // Full drive scope so `item:remove --trash` can trash files when the folder is shared as Editor;
    // registering/reading only needs read, which this scope also covers.
    scopes: ['https://www.googleapis.com/auth/drive'],
  });
  _drive = google.drive({ version: 'v3', auth });
  return _drive;
}

export const FieldValue = admin.firestore.FieldValue;
export const Timestamp = admin.firestore.Timestamp;
