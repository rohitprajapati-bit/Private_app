# Remote view-only sharing (code → library)

This extends the existing **local-network** admin→viewer sharing (`lib/data/sharing/`) to work
**over the internet**, with the media stored in the admin's **own Google Drive** and streamed
**view-only** to users who redeem an access **code**.

It does **not** change the offline vault. The admin's local encrypted vault still works exactly as
before; remote sharing is an additional, opt-in surface.

## Roles

| Role | Signs in as | Talks to | Can |
|---|---|---|---|
| **Admin** | Google (Drive) + Firebase Auth | Firestore + Drive directly | upload media, make libraries, issue codes, see devices, revoke |
| **User** | nothing (just a local app password) | the Worker **only** | redeem a code, browse one library **view-only** |

A user never authenticates to Google or Firebase. They only ever hold: their local app password, a
device id, and a device token the Worker gave them when they redeemed a code.

## Why a broker (Cloudflare Worker) is required

The files live in the admin's **private** Drive. A user's app has no permission to read that Drive,
and we must never ship the admin's Drive credential to user devices (any user could then download or
delete the whole Drive). So a small server-side **broker** holds a **service account** key and:

1. validates the code + device on each request (against Firestore),
2. streams **only** the allowed file's bytes to the user (supports HTTP Range so video seeks),
3. **never** returns a Drive URL or a downloadable link.

That byte-streaming, link-free path is what makes "view-only, no download" real rather than just a
hidden button. It is not absolute — a user who can see a photo has its pixels, and a rooted phone or a
second camera can still capture — but there is no file, no URL, and no Save action.

## Data model (Firestore)

All documents are owned by one admin (`ownerUid`). Users never read or write Firestore directly; only
the admin (via security rules) and the Worker (via the service account) touch it.

```
config/{adminUid}
  driveFolderId      string   # the private Drive folder uploads go into
  serviceAccountEmail string  # the SA the folder is shared with (reader)
  brokerUrl          string

libraries/{libraryId}
  ownerUid    string
  name        string
  createdAt   timestamp

libraries/{libraryId}/items/{itemId}
  type        'image' | 'video'
  name        string            # display name
  ext         string
  driveFileId string            # the file in the admin's Drive
  thumbFileId string | null     # optional small thumbnail file in Drive
  size        number
  width       number | null
  height      number | null
  durationMs  number | null
  createdAt   timestamp

codes/{code}                    # code is the doc id (e.g. 8 chars, A–Z2–9)
  ownerUid    string
  libraryId   string
  label       string            # e.g. "Riya's phone"
  active      bool
  maxDevices  number            # how many devices may redeem this code (e.g. 1)
  createdAt   timestamp
  expiresAt   timestamp | null

devices/{deviceId}
  ownerUid    string
  code        string
  libraryId   string
  name        string            # device-reported name
  platform    'android' | 'ios'
  tokenHash   string            # sha256 of the device token the Worker issued
  installedAt timestamp
  lastSeenAt  timestamp         # heartbeat; "uninstalled" is inferred from silence
  revoked     bool
```

### "Who installed / uninstalled"

- **Installed / redeemed:** a `devices/*` doc is created the moment a code is redeemed.
- **Active / went away:** every user app sends a `heartbeat` (updates `lastSeenAt`). The admin
  dashboard shows "active" vs "silent N days" — a silence past a threshold is treated as gone.
- The OS never runs our code on uninstall, so uninstall is **inferred** from a stale `lastSeenAt`
  (and, if FCM is added later, from a push-token becoming unregistered). It's reliable within ~a day,
  not instant. This is a platform limit, not a gap we can close in code.

## Worker API (used only by user devices)

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/v1/redeem` | code in body | redeem a code, register this device, get a device token + manifest |
| GET | `/v1/library` | `X-Device-Id` + `X-Device-Token` | re-fetch the library manifest |
| GET | `/v1/media/:itemId` | device headers, optional `Range` | stream one item's bytes (view-only) |
| GET | `/v1/thumb/:itemId` | device headers | stream a thumbnail |
| POST | `/v1/heartbeat` | device headers | update `lastSeenAt` |

Every non-redeem request is rejected unless the device is known, not revoked, its token hash matches,
and the requested item belongs to the device's library. Revoking a code or device in the dashboard
takes effect on the **next** request — there is no cached access on the user's side beyond what is
on screen at that moment.

## Encryption note (Stage 1 vs later)

- **Stage 1 (this):** files sit in the admin's **private** Drive folder (shared only with the service
  account) and are streamed by the broker. Google/Drive could technically read them, like any Drive
  file. Access to users is fully controlled by code + device + revocation.
- **Later (optional):** encrypt each file with a per-library content key before upload, and have the
  Worker decrypt chunks on the fly. Then Drive stores only ciphertext. This matches the vault's
  end-to-end posture at the cost of more code; it can be added without changing the data model.

## Build stages

1. **Backbone (this):** Firestore rules, the Worker, and the one-time setup guide (`backend/README.md`).
2. **Admin app:** Google sign-in, upload to Drive, create libraries/items, issue codes, device dashboard.
3. **User app:** enter a code on the hide screen, browse one library view-only (no Save, no delete),
   reusing the existing `FLAG_SECURE`/privacy-cover protections.
