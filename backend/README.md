# Backend — remote view-only sharing

Free backbone for the code→library sharing: **Firestore** (free) for codes/libraries/devices/audit,
your **2 TB Google Drive** for the files, a free **Cloudflare Worker** as the broker, and a Node
**admin CLI** so you never hand-edit anything.

```
backend/
  firestore.rules          security rules (admin-only; users never touch Firestore)
  firestore.indexes.json
  worker/                  Cloudflare Worker broker (streams Drive bytes, view-only)
  admin-cli/               Node CLI: register media, codes, devices, audit, admin-only delete
  scripts/                 deploy.sh, smoke-test.mjs
../firebase.json           points `firebase deploy` at the rules
```

## Storage ownership (important, and correct by design)

- **You (the owner) put files in the Drive folder.** They stay owned by you, so they count against
  **your 2 TB** — not the service account (a service account has no personal Drive quota, which is
  why it must not be the uploader).
- The **service account** only gets **Viewer** on that folder: it reads/streams, never owns.
- **Only you can delete** a Drive file (you own it). The Worker and users have no delete path at all.

So "upload" = drop files into the folder (Drive web/app or `rclone`); `admin-cli register` then records
them. This keeps the quota and deletion rights exactly where they should be.

---

## One-time setup

Steps marked 🧑 need your Google/Cloudflare login and **cannot be automated** — follow them exactly.
Everything else is a command you run.

### 🧑 1. Firestore + Auth (Firebase console)
1. <https://console.firebase.google.com> → your **Private-app** project.
2. **Firestore Database → Create database → Production mode** → pick a region.
3. Note the **Project ID** (Project settings → General).

### 🧑 2. Service account key
1. Firebase console → **Project settings → Service accounts → Generate new private key**.
2. Save the downloaded JSON as **`backend/admin-cli/service-account.json`** (git-ignored).
3. Enable the Drive API: <https://console.cloud.google.com/apis/library/drive.googleapis.com> →
   same project → **Enable**.

### 🧑 3. Drive folder (your 2 TB)
1. In Google Drive create a folder, e.g. **ColorMatch Vault**.
2. **Share** it with the service account's `client_email` (inside the JSON), role **Viewer**
   (use **Editor** only if you want `item:remove --trash` to trash files for you).
3. Copy the folder id from its URL `…/folders/<FOLDER_ID>`.

### 4. Configure + validate the CLI  (automated)
```sh
cd backend/admin-cli
cp .env.example .env            # then edit: GCP_PROJECT_ID, DRIVE_FOLDER_ID (service-account.json already placed)
npm install
npm run doctor                  # verifies Firestore + Drive folder are reachable — nothing secret is printed
```
`doctor` must print all ✓ before continuing.

### 5. Deploy the rules + Worker  (automated, asks first)
```sh
# from the repo root
backend/scripts/deploy.sh       # deploys Firestore rules, then the Worker (prompts before each)
```
For the Worker it runs `wrangler deploy`; the first time, `wrangler` opens a browser for a free
Cloudflare login (🧑), then you set the three secrets once when prompted, or ahead of time:
```sh
cd backend/worker
npx wrangler secret put GCP_PROJECT_ID
npx wrangler secret put GCP_SA_EMAIL
npx wrangler secret put GCP_SA_PRIVATE_KEY   # paste "private_key" from the JSON, including the \n parts
```
`wrangler deploy` prints the **broker URL** (e.g. `https://colormatch-broker.you.workers.dev`).

### 6. Point the app at the broker
Build the Flutter app with the URL:
```sh
flutter run --dart-define=BROKER_URL=https://colormatch-broker.you.workers.dev
```

### 7. Verify end-to-end  (automated)
```sh
node backend/scripts/smoke-test.mjs https://colormatch-broker.you.workers.dev
# add --code <CODE> to also prove a granted device streams and an ungranted one gets 401
```

---

## Daily admin use (CLI)

```sh
cd backend/admin-cli
node src/index.mjs library:create "Riya photos"      # → prints LIBRARY_ID
#   ...drop photos/videos into the Drive folder...
node src/index.mjs register LIBRARY_ID               # records the new files
node src/index.mjs code:create LIBRARY_ID --label "Riya" --max 1   # → prints the ACCESS CODE
node src/index.mjs devices:list                      # who installed / last seen / gone
node src/index.mjs device:revoke DEVICE_ID           # cut a device off
node src/index.mjs code:disable CODE                 # turn a code off
node src/index.mjs item:remove LIBRARY_ID ITEM_ID --trash   # admin-only delete
node src/index.mjs audit:list                        # access log
```
Run `node src/index.mjs help` for the full list.

## What normal users can and cannot do (enforced, not just hidden)

| | Enforced by |
|---|---|
| ❌ upload | the Worker has no write/upload endpoint; users never authenticate to Drive/Firestore |
| ❌ delete / modify | no DELETE/PUT/PATCH path exists; Firestore rules deny all non-admin access |
| ❌ get a Drive link | the Worker streams bytes with `Content-Disposition: inline`, `no-store`; the manifest exposes item ids, never `driveFileId`, `webViewLink` or `alt=media` URLs |
| ❌ access without a grant | every request needs a valid device token; revoking a code/device cuts access on the next request |
| ✅ view (stream) | `GET /v1/media/:id` with the device headers only |

Verify any time: `backend/scripts/smoke-test.mjs`, or `grep "request.method" backend/worker/src/index.js`.

See [`../docs/remote-sharing/ARCHITECTURE.md`](../docs/remote-sharing/ARCHITECTURE.md) for the design.
