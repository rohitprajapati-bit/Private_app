import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import '../../core/encryption/aead.dart';
import '../../core/encryption/chunked_cipher.dart';
import '../../core/errors/failures.dart';
import '../../core/security/key_hierarchy.dart';
import '../../core/security/vault_session.dart';
import '../../core/storage/vault_paths.dart';
import '../../core/utilities/bytes.dart';
import '../datasources/vault_database.dart';
import '../models/media_record.dart';
import '../repositories/media_repository_impl.dart';
import 'sharing_protocol.dart';

/// An admin device found on the local network.
class DiscoveredAdmin {
  const DiscoveredAdmin({required this.id, required this.name, required this.endpoint});

  final String id;
  final String name;
  final Uri endpoint;
}

/// A pairing request the admin has received; both screens now show [code].
class PairingAttempt {
  const PairingAttempt({required this.admin, required this.endpoint, required this.code, required this.viewerId});

  final PairedDevice admin;
  final Uri endpoint;
  final String code;
  final String viewerId;
}

class SyncResult {
  const SyncResult({required this.added, required this.removed, required this.failed});

  final int added;
  final int removed;
  final int failed;
}

/// Viewer role: pairs with one admin device and mirrors its items, view-only.
///
/// Received files are stored byte-for-byte as the admin sent them (still encrypted with their
/// per-file key); only the file key is re-wrapped under this device's master key. They live in
/// the normal vault tables tagged with `shared_from`, so they get the same at-rest protection
/// as the owner's own items.
class SharingClient extends ChangeNotifier {
  SharingClient({
    required VaultDatabase database,
    required KeyHierarchy keys,
    required VaultPaths paths,
    required VaultSession session,
    required PairingStore pairings,
    required Aead aead,
  }) : _db = database,
       _keys = keys,
       _paths = paths,
       _session = session,
       _pairings = pairings,
       _aead = aead;

  final VaultDatabase _db;
  final KeyHierarchy _keys;
  final VaultPaths _paths;
  final VaultSession _session;
  final PairingStore _pairings;
  final Aead _aead;

  static const _requestTimeout = Duration(seconds: 15);

  bool _syncing = false;
  bool get syncing => _syncing;

  Future<PairedDevice?> linkedAdmin() => _pairings.admin();

  /// Admin devices currently sharing on this network. Ends after [timeout].
  Stream<DiscoveredAdmin> discover({Duration timeout = const Duration(seconds: 10)}) {
    final controller = StreamController<DiscoveredAdmin>();
    final discovery = BonsoirDiscovery(type: sharingServiceType);
    final seen = <String>{};
    Timer? timer;
    Future<void> close() async {
      timer?.cancel();
      await discovery.stop().catchError((_) {});
      if (!controller.isClosed) await controller.close();
    }

    controller.onListen = () async {
      try {
        await discovery.initialize();
        discovery.eventStream!.listen((event) {
          switch (event) {
            case BonsoirDiscoveryServiceFoundEvent():
              unawaited(event.service.resolve(discovery.serviceResolver));
            case BonsoirDiscoveryServiceResolvedEvent():
              final admin = _toAdmin(event.service);
              if (admin != null && seen.add(admin.id) && !controller.isClosed) controller.add(admin);
            default:
              break;
          }
        });
        await discovery.start();
        timer = Timer(timeout, close);
      } on Object catch (e) {
        if (!controller.isClosed) controller.addError(e);
        await close();
      }
    };
    controller.onCancel = close;
    return controller.stream;
  }

  static DiscoveredAdmin? _toAdmin(BonsoirService service) {
    final id = service.attributes['id'];
    if (id == null) return null;
    // Prefer IPv4: link-local IPv6 addresses need a zone id that Uri cannot carry.
    final address = service.hostAddresses.where((a) => !a.contains(':')).firstOrNull ?? service.hostAddress;
    if (address == null) return null;
    return DiscoveredAdmin(
      id: id,
      name: service.attributes['name'] ?? service.name,
      endpoint: Uri(scheme: 'http', host: address, port: service.port),
    );
  }

  /// Sends this device's half of the key agreement. Both screens then show the same code.
  Future<PairingAttempt> requestPairing(DiscoveredAdmin admin) async {
    final viewerId = await _pairings.deviceId();
    final handshake = await PairingHandshake.start();
    final reply = await _postJson(admin.endpoint.replace(path: '/pair'), {
      'id': viewerId,
      'name': _deviceName,
      'pub': base64Encode(handshake.publicKey),
    });
    final adminPublic = base64Decode(reply['pub'] as String);
    final result = await handshake.finish(
      remotePublic: adminPublic,
      adminPublic: adminPublic,
      viewerPublic: handshake.publicKey,
    );
    return PairingAttempt(
      admin: PairedDevice(id: reply['id'] as String, name: reply['name'] as String, key: result.key),
      endpoint: admin.endpoint,
      code: result.code,
      viewerId: viewerId,
    );
  }

  /// Polls until the admin approves (returns true and saves the link) or denies.
  Future<bool> waitForApproval(PairingAttempt attempt, {Duration timeout = const Duration(minutes: 2)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final reply = await _getJson(
        attempt.endpoint.replace(path: '/pair/status', queryParameters: {'id': attempt.viewerId}),
      );
      switch (reply['status']) {
        case 'approved':
          await _pairings.saveAdmin(attempt.admin);
          notifyListeners();
          return true;
        case 'denied' || 'unknown':
          return false;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  /// Removes the link and everything received from the admin.
  Future<void> unlink() async {
    final admin = await _pairings.admin();
    if (admin != null) await _removeItems(await _db.sharedIds(admin.id));
    await _pairings.saveAdmin(null);
    notifyListeners();
  }

  /// Mirrors the admin's current items: downloads new ones, removes ones the admin deleted.
  /// Throws [SharingFailure] when the admin is not reachable.
  Future<SyncResult> sync() async {
    if (_syncing) return const SyncResult(added: 0, removed: 0, failed: 0);
    final admin = await _pairings.admin();
    if (admin == null) throw const SharingFailure('Not linked to an admin device.');
    _syncing = true;
    notifyListeners();
    try {
      final found = await discover(
        timeout: const Duration(seconds: 8),
      ).cast<DiscoveredAdmin?>().firstWhere((a) => a!.id == admin.id, orElse: () => null);
      if (found == null) {
        throw const SharingFailure(
          'Admin device not found. Open its vault and keep both phones on the same Wi-Fi.',
        );
      }
      final viewerId = await _pairings.deviceId();
      final manifest = await _fetchManifest(found.endpoint, admin, viewerId);

      final local = await _db.sharedIds(admin.id);
      final remoteIds = {for (final item in manifest) item['id'] as String};
      final removed = local.difference(remoteIds);
      await _removeItems(removed);

      var added = 0;
      var failed = 0;
      for (final item in manifest) {
        if (local.contains(item['id'])) continue;
        if (!_session.isUnlocked) throw const VaultLocked();
        try {
          await _receive(found.endpoint, admin, viewerId, item);
          added++;
        } on VaultLocked {
          rethrow;
        } on Object {
          failed++;
        }
      }
      return SyncResult(added: added, removed: removed.length, failed: failed);
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchManifest(Uri endpoint, PairedDevice admin, String viewerId) async {
    final bytes = await _signedGet(endpoint, '/manifest', admin, viewerId, (response) async {
      final builder = BytesBuilder(copy: false);
      await response.forEach(builder.add);
      return builder.takeBytes();
    });
    final clear = await _aead.open(admin.key, bytes, aad: utf8Bytes('sharing/manifest/$viewerId'));
    final json = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    return [for (final item in json['items'] as List) item as Map<String, dynamic>];
  }

  /// Same transaction shape as an import: pending row → files → rename → commit.
  Future<void> _receive(Uri endpoint, PairedDevice admin, String viewerId, Map<String, dynamic> item) async {
    final id = item['id'] as String;
    if (await _db.media(id) != null) return; // already present (e.g. own copy with same id)
    final masterKey = Uint8List.fromList(_session.masterKey);
    final fileKey = base64Decode(item['key'] as String);
    final mediaPart = _paths.partFile(id, 'media');
    final thumbPart = _paths.partFile(id, 'thumb');
    try {
      await _db.insertPending(
        MediaRecord(
          id: id,
          type: item['type'] as int,
          encryptedName: await _keys.encryptText(masterKey, item['name'] as String, MediaRepositoryImpl.nameContext(id)),
          extension: item['ext'] as String,
          wrappedKey: await _keys.wrapFileKey(masterKey, fileKey, id),
          sizeBytes: item['size'] as int,
          importedAt: item['importedAt'] as int,
          committed: false,
          durationMs: item['durationMs'] as int?,
          width: item['width'] as int?,
          height: item['height'] as int?,
          sharedFrom: admin.id,
        ),
      );
      await _download(endpoint, '/media/$id', admin, viewerId, mediaPart);
      if (item['thumb'] == true) {
        await _download(endpoint, '/thumb/$id', admin, viewerId, thumbPart);
        await thumbPart.rename(_paths.thumbFile(id).path);
      }
      if (!_session.isUnlocked) throw const VaultLocked();
      await mediaPart.rename(_paths.mediaFile(id).path);
      await _db.commit(id);
    } on Object {
      await _deleteQuietly([mediaPart, thumbPart, _paths.mediaFile(id), _paths.thumbFile(id)]);
      await _db.deleteMedia([id]).catchError((_) {});
      rethrow;
    } finally {
      wipe(fileKey);
      wipe(masterKey);
    }
  }

  /// Streams an encrypted file to [target] and checks it is a complete vault file.
  Future<void> _download(Uri endpoint, String path, PairedDevice admin, String viewerId, File target) async {
    await _signedGet(endpoint, path, admin, viewerId, (response) async {
      final sink = target.openWrite();
      try {
        await response.pipe(sink);
      } finally {
        await sink.close().catchError((_) {});
      }
    });
    final raf = await target.open();
    try {
      final header = EncryptedFileHeader.parse(await raf.read(EncryptedFileHeader.length));
      if (await target.length() != header.encryptedLength) throw const SharingFailure('Incomplete download.');
    } finally {
      await raf.close();
    }
  }

  Future<T> _signedGet<T>(
    Uri endpoint,
    String path,
    PairedDevice admin,
    String viewerId,
    Future<T> Function(HttpClientResponse response) read,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final time = DateTime.now().millisecondsSinceEpoch;
      final request = await client.getUrl(endpoint.replace(path: path)).timeout(_requestTimeout);
      request.headers
        ..set('x-viewer', viewerId)
        ..set('x-time', '$time')
        ..set('x-sig', await RequestSigner.sign(admin.key, 'GET', path, time));
      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode == HttpStatus.forbidden) {
        await response.drain<void>();
        // The admin removed this viewer: drop the link and everything received.
        await unlink();
        throw const SharingFailure('The admin device removed your access.');
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw SharingFailure('Admin device refused the request (${response.statusCode}).');
      }
      return await read(response);
    } on SocketException {
      throw const SharingFailure('Could not reach the admin device.');
    } on TimeoutException {
      throw const SharingFailure('The admin device did not respond.');
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _postJson(Uri uri, Map<String, Object?> body) => _jsonRequest(uri, 'POST', body);

  Future<Map<String, dynamic>> _getJson(Uri uri) => _jsonRequest(uri, 'GET', null);

  Future<Map<String, dynamic>> _jsonRequest(Uri uri, String method, Map<String, Object?>? body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.openUrl(method, uri).timeout(_requestTimeout);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(_requestTimeout);
      final text = await utf8.decodeStream(response);
      if (response.statusCode == HttpStatus.forbidden) {
        throw const SharingFailure('The admin device is not accepting new viewers right now.');
      }
      if (response.statusCode != HttpStatus.ok) throw SharingFailure('Request failed (${response.statusCode}).');
      return jsonDecode(text) as Map<String, dynamic>;
    } on SocketException {
      throw const SharingFailure('Could not reach the admin device.');
    } on TimeoutException {
      throw const SharingFailure('The admin device did not respond.');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _removeItems(Set<String> ids) async {
    if (ids.isEmpty) return;
    // Row first: destroys the wrapped key, then the ciphertext.
    await _db.deleteMedia(ids);
    for (final id in ids) {
      await _deleteQuietly([_paths.mediaFile(id), _paths.thumbFile(id)]);
    }
  }

  static String get _deviceName {
    final host = Platform.localHostname.replaceAll('.local', '');
    return host.isEmpty || host == 'localhost' ? 'Viewer device' : host;
  }

  static Future<void> _deleteQuietly(List<File> files) async {
    for (final file in files) {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Recovery removes orphans on the next unlock.
      }
    }
  }
}
