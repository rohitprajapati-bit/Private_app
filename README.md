# Color Match

A colour-matching puzzle game for Android and iOS with a hidden, encrypted photo and video vault.
Fully offline: no backend, Firebase, analytics or ads. Built for private installation only, not for store release.

## Using it

1. **First launch:** you create a password (8+ characters), then pick a secret sequence of 4–6 colours. You can also turn on Face ID or fingerprint unlock.
2. **Playing:** match the target colour on a grid of near-identical shades. Grids grow and shades get closer as levels rise. There's a timer, a score, streak bonuses, haptics and sound.
3. **Opening the vault:** start a game, tap **Pause**, then tap your secret colours in order under **Tile style**. The password screen appears.
4. **Inside the vault:** there are Photos, Videos and Albums tabs. You can search, sort, multi-select (long-press), move items between albums, save items to the gallery, and delete. Videos stream with seeking and full-screen playback.
5. **Locking:** the vault locks when the app goes to the background, after an idle timeout (configurable), or when you tap the lock icon.

> ⚠️ **There is no password recovery.** Uninstalling the app erases the vault, and there are no backups by design.
> Importing *copies* media into the vault, so the originals stay in your Photos app until you delete them there.

## Security design

```
password ──Argon2id(m=19 MiB, t=2, p=1, 16-byte salt)──► KEK ──AES-256-GCM──► master key (random 256-bit)
biometrics ──Android Keystore key / iOS Keychain item────────────────────────► master key
master key ──AES-256-GCM──► per-file keys, file names, album names
per-file key ──chunked AES-256-GCM──► media/{id}.bin, thumbs/{id}.bin
```

| Concern | Implementation |
|---|---|
| Password storage | No password hash is stored. The password counts as correct only if it decrypts the master key (the GCM tag check). Salt and parameters live in Keychain/Keystore-backed secure storage. |
| Wrong guesses | 5 free attempts, then a delay starting at 30 s that doubles each time, up to 1 h. The delay persists across restarts. |
| Biometrics | Android: `BiometricPrompt` with a `CryptoObject`. The master key is wrapped by a hardware Keystore key that requires authentication on every use and is invalidated when a new fingerprint/face is enrolled. Device PIN works as fallback on Android 11+. iOS: a Keychain item with `.biometryCurrentSet` or device passcode, readable only on this device. The password always works too. |
| Media at rest | Each file is split into 1 MiB chunks. Each chunk has its own nonce (random 8-byte prefix + chunk counter). The authenticated data covers the header, file id, chunk index and a final-chunk flag, so tampering, truncation, reordering and swapping files between records are all detected (see `test/core/chunked_cipher_test.dart`). |
| Large videos | Videos are never decrypted to disk or fully into RAM. A loopback HTTP server (127.0.0.1, random port, 256-bit URL token) decrypts only the chunks the player requests via HTTP Range. It stops, and its keys are wiped, when the vault locks. |
| Photos | Decrypted in memory only. HEIC on iOS is converted to JPEG in memory for display. |
| Import transactions | Each file: pending row → encrypt to `tmp/*.part` and flush to disk → rename into place → commit. On the next unlock, unfinished `.part` files, pending rows and orphaned files are removed. The picker's plaintext copy is deleted whether the import succeeds or fails. |
| Metadata | SQLite. File and album names are AES-GCM encrypted, and per-file keys are wrapped. `PRAGMA secure_delete` overwrites deleted rows. Deleting a row destroys that file's key, so the file can't be decrypted even if flash storage keeps the old blocks. |
| On lock | The master key buffer is zeroed, caches and the image cache are cleared, the stream server is stopped, and temporary export files are deleted. |
| App switcher | Android: `FLAG_SECURE` while the vault is open (blank preview, no screenshots). iOS: a cover view hides the snapshot. iOS cannot block screenshots. |
| Backups | Android: `allowBackup=false` plus data-extraction rules that exclude everything. iOS: the vault folder is excluded from iCloud/iTunes backup, and Keychain items are `ThisDeviceOnly`. |
| Network | No outbound requests. Android declares `INTERNET` only because Android requires it for the loopback socket, and cleartext traffic is allowed only to `127.0.0.1`. |

**Known limits:**
- Dart can't guarantee that every copy of a secret in memory is wiped.
- A rooted or jailbroken phone, or malware running while the vault is open, can read decrypted content.
- The hidden entrance only hides the vault. The password is what protects it.
- File sizes, item counts and dates are stored unencrypted so the vault can list them.

## Project layout

```
lib/
  core/          constants, errors, encryption (AES-GCM, Argon2id, chunked format),
                 security (key hierarchy, session, lockout, secret sequence), storage, theme
  data/          SQLite datasource, loopback stream server, repository implementations
  domain/        entities (Freezed), repository interfaces, use cases (round generator, password policy)
  presentation/  game, onboarding, authentication, vault, gallery, albums, video_player, settings
  platform/      Dart side of the native bridge (android/, ios/)
  routes/        GoRouter with vault guards
android/app/src/main/kotlin/…/  BiometricKeyStore.kt, MediaThumbnailer.kt, PlatformChannel.kt
ios/Runner/PlatformChannel.swift  Keychain biometrics, thumbnails, privacy cover, backup exclusion
```

Stack: Flutter, Riverpod 3, GoRouter, Freezed, `cryptography` (with native AES-GCM through `cryptography_flutter`), sqflite, flutter_secure_storage, image_picker (system photo picker; no gallery permission needed), video_player, gal.

## Development

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after changing Freezed models
flutter analyze
flutter test
```

## Installing on Android (APK)

The release build is signed with `android/colormatch-release.jks`. Its passwords are in `android/key.properties`. Both files are git-ignored. **Back them up somewhere safe:** without that key you can't install updates over an existing install, and uninstalling erases the vault.

```sh
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
adb install -r build/app/outputs/flutter-apk/app-release.apk   # or copy the APK to the phone and open it
```

When installing from the phone, allow "Install unknown apps" for your file manager or browser.

## Installing on your iPhone (personal Apple Account)

1. **Toolchain:** run `flutter upgrade` first. Flutter 3.41.7 fails with Xcode 27 at the "Thin Binary" step (`does not contain architectures "arm64 x86_64"`).
2. **On the iPhone:** Settings → Privacy & Security → **Developer Mode** → On, then restart. Connect the phone by cable and tap "Trust this computer".
3. Open `ios/Runner.xcworkspace` in Xcode → select the **Runner** target → **Signing & Capabilities**:
   - Turn on "Automatically manage signing".
   - **Team:** add your Apple Account (Xcode → Settings → Accounts) and choose your *Personal Team*.
   - **Bundle Identifier:** if `com.furation.colormatch` is rejected, change it to something unique, e.g. `com.<yourname>.colormatch`.
4. Build and install from the terminal:
   ```sh
   flutter run --release -d <your-iphone-id>   # list devices: flutter devices
   ```
   or select your iPhone in Xcode and press ▶ with the scheme set to Release.
5. **On the iPhone:** Settings → General → VPN & Device Management → your developer certificate → **Trust**.

**How long it lasts:** with a free Apple Account the app stops launching after **7 days**. Reinstall it the same way, and your data is kept as long as you don't delete the app first. A paid Apple Developer Program membership makes installs last a year.

## Device test checklist

Real hardware is needed for biometrics, the photo picker, export and memory behaviour.

- [ ] Game: levels 1–12, timer runs out, wrong-tap penalty, pause/resume, background → auto-pause, sound/haptics toggles, progress after restart
- [ ] Setup: password mismatch, short password, sequence mismatch, biometrics enable/skip
- [ ] Entry: wrong colour sequence does nothing; correct sequence → password screen; back leaves no access
- [ ] Password: wrong ×5 → 30 s lockout (survives an app restart); correct → vault
- [ ] Biometrics: Face ID / fingerprint unlock; cancel → password; enroll a new finger → biometrics turn off and the password is required
- [ ] Import 20+ photos (including HEIC/Live Photos on iPhone) and a large video (≥1 GB); check memory stays flat
- [ ] Kill the app mid-import → reopen → no broken items; storage is cleaned up
- [ ] Video: play, pause, seek near the end, full screen, rotate
- [ ] Albums: create, rename, delete (items are kept), move items, view by album
- [ ] Export photo and video to the gallery; deny the permission → error message
- [ ] Lock: home button / app switcher → vault closes and the preview is hidden; idle timeout; device restart
- [ ] Storage full during import → that item fails cleanly and the others continue
