import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import '../../core/encryption/aead.dart';
import '../../core/security/key_hierarchy.dart';
import '../../core/security/vault_session.dart';
import '../../core/storage/vault_paths.dart';
import '../../core/utilities/bytes.dart';
import '../datasources/vault_database.dart';
import '../repositories/media_repository_impl.dart';
import 'sharing_protocol.dart';

/// A viewer that asked to pair and is waiting for the owner to compare codes and approve.
class PendingViewer {
  const PendingViewer({required this.device, required this.code});

  final PairedDevice device;
  final String code;
}

/// Admin role: serves the owner's own items, view-only, to paired viewers on the local
/// network. Runs only while the vault is unlocked (it needs the master key) and only when a
/// viewer is paired or pairing is open — otherwise nothing is advertised on the network.
///
/// Media files go over the wire exactly as stored: still encrypted with their per-file key.
/// The file keys and names travel only inside the manifest, sealed with the viewer's pair key.
class SharingHost extends ChangeNotifier {
  SharingHost({
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
       _aead = aead {
    _session.addLockListener(_onLock);
  }

  final VaultDatabase _db;
  final KeyHierarchy _keys;
  final VaultPaths _paths;
  final VaultSession _session;
  final PairingStore _pairings;
  final Aead _aead;

  HttpServer? _server;
  BonsoirBroadcast? _broadcast;
  List<PairedDevice> _viewers = const [];
  bool _pairingOpen = false;
  PendingViewer? _pending;
  final _pairResults = <String, bool>{};
  bool _disposed = false;

  bool get isRunning => _server != null;
  int? get port => _server?.port;
  bool get pairingOpen => _pairingOpen;
  PendingViewer? get pending => _pending;
  List<PairedDevice> get viewers => _viewers;

  /// Called when the vault opens: resumes sharing if any viewer is paired.
  Future<void> startIfPaired() async {
    _viewers = await _pairings.viewers();
    notifyListeners();
    if (_viewers.isNotEmpty) await _start();
  }

  Future<void> openPairing() async {
    _pairingOpen = true;
    _pending = null;
    notifyListeners();
    await _start();
  }

  Future<void> closePairing() async {
    _pairingOpen = false;
    _pending = null;
    notifyListeners();
    if (_viewers.isEmpty) await _stop();
  }

  /// The owner confirmed both screens show the same code.
  Future<void> approve() async {
    final pending = _pending;
    if (pending == null) return;
    _viewers = [..._viewers.where((v) => v.id != pending.device.id), pending.device];
    await _pairings.saveViewers(_viewers);
    _pairResults[pending.device.id] = true;
    _pending = null;
    _pairingOpen = false;
    notifyListeners();
  }

  void deny() {
    final pending = _pending;
    if (pending == null) return;
    _pairResults[pending.device.id] = false;
    _pending = null;
    notifyListeners();
  }

  /// Revokes access. The viewer's next sync gets 403 and deletes what it received.
  Future<void> removeViewer(String id) async {
    _viewers = _viewers.where((v) => v.id != id).toList();
    await _pairings.saveViewers(_viewers);
    notifyListeners();
    if (_viewers.isEmpty && !_pairingOpen) await _stop();
  }

  void _onLock() {
    _viewers = const [];
    _pairingOpen = false;
    _pending = null;
    _pairResults.clear();
    unawaited(_stop());
    notifyListeners();
  }

  Future<void> _start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    server.listen((request) => unawaited(_handle(request)), onError: (_) {});
    final id = await _pairings.deviceId();
    final broadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: 'Color Match ${id.substring(0, 6)}',
        type: sharingServiceType,
        port: server.port,
        attributes: {'id': id, 'name': _deviceName},
      ),
    );
    try {
      await broadcast.initialize();
      await broadcast.start();
      _broadcast = broadcast;
    } on Object {
      // Not discoverable (e.g. local network access denied); the server itself still works.
    }
    notifyListeners();
  }

  Future<void> _stop() async {
    final server = _server;
    final broadcast = _broadcast;
    _server = null;
    _broadcast = null;
    await broadcast?.stop();
    await server?.close(force: true);
    if (!_disposed) notifyListeners();
  }

  static String get _deviceName {
    final host = Platform.localHostname.replaceAll('.local', '');
    return host.isEmpty || host == 'localhost' ? 'Admin device' : host;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      switch ((request.method, segments)) {
        case ('POST', ['pair']):
          await _pair(request);
        case ('GET', ['pair', 'status']):
          await _pairStatus(request);
        case ('GET', ['manifest']):
          final viewer = await _authorize(request);
          if (viewer != null) await _manifest(request, viewer);
        case ('GET', [final kind, final id]) when kind == 'media' || kind == 'thumb':
          final viewer = await _authorize(request);
          if (viewer != null) await _file(request, kind, id);
        default:
          response.statusCode = HttpStatus.notFound;
      }
    } on Object {
      try {
        response.statusCode = HttpStatus.internalServerError;
      } on StateError {
        // Headers already sent.
      }
    } finally {
      await response.close().catchError((_) {});
    }
  }

  /// Body: `{id, name, pub}` from the viewer. Replies with the admin's half of the handshake.
  Future<void> _pair(HttpRequest request) async {
    if (!_pairingOpen || _pending != null) {
      request.response.statusCode = HttpStatus.forbidden;
      return;
    }
    final body = jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic>;
    final viewerPublic = base64Decode(body['pub'] as String);
    final handshake = await PairingHandshake.start();
    final result = await handshake.finish(
      remotePublic: viewerPublic,
      adminPublic: handshake.publicKey,
      viewerPublic: viewerPublic,
    );
    final viewerId = body['id'] as String;
    _pairResults.remove(viewerId);
    _pending = PendingViewer(
      device: PairedDevice(id: viewerId, name: body['name'] as String, key: result.key),
      code: result.code,
    );
    notifyListeners();
    _json(request.response, {
      'id': await _pairings.deviceId(),
      'name': _deviceName,
      'pub': base64Encode(handshake.publicKey),
    });
  }

  Future<void> _pairStatus(HttpRequest request) async {
    final id = request.uri.queryParameters['id'];
    final result = _pairResults[id];
    _json(request.response, {
      'status': switch (result) {
        true => 'approved',
        false => 'denied',
        null => _pending?.device.id == id ? 'pending' : 'unknown',
      },
    });
  }

  /// Checks the viewer's signed headers. Writes the error response itself.
  Future<PairedDevice?> _authorize(HttpRequest request) async {
    final id = request.headers.value('x-viewer');
    final time = int.tryParse(request.headers.value('x-time') ?? '');
    final signature = request.headers.value('x-sig');
    final viewer = _viewers.where((v) => v.id == id).firstOrNull;
    if (viewer == null) {
      request.response.statusCode = HttpStatus.forbidden; // not (or no longer) paired
      return null;
    }
    if (time == null ||
        signature == null ||
        !await RequestSigner.verify(viewer.key, request.method, request.uri.path, time, signature)) {
      request.response.statusCode = HttpStatus.unauthorized;
      return null;
    }
    return viewer;
  }

  /// Every own item with its file key and name, sealed with the viewer's pair key.
  Future<void> _manifest(HttpRequest request, PairedDevice viewer) async {
    final masterKey = Uint8List.fromList(_session.masterKey);
    try {
      final items = <Map<String, Object?>>[];
      for (final record in await _db.ownCommittedMedia()) {
        final fileKey = await _keys.unwrapFileKey(masterKey, record.wrappedKey, record.id);
        items.add({
          'id': record.id,
          'type': record.type,
          'name': await _keys.decryptText(masterKey, record.encryptedName, MediaRepositoryImpl.nameContext(record.id)),
          'ext': record.extension,
          'size': record.sizeBytes,
          'importedAt': record.importedAt,
          'durationMs': record.durationMs,
          'width': record.width,
          'height': record.height,
          'key': base64Encode(fileKey),
          'thumb': await _paths.thumbFile(record.id).exists(),
        });
        wipe(fileKey);
      }
      final sealed = await _aead.seal(
        viewer.key,
        utf8.encode(jsonEncode({'items': items})),
        aad: utf8Bytes('sharing/manifest/${viewer.id}'),
      );
      request.response
        ..headers.contentType = ContentType.binary
        ..add(sealed);
    } finally {
      wipe(masterKey);
    }
  }

  Future<void> _file(HttpRequest request, String kind, String id) async {
    final record = await _db.media(id);
    if (record == null || !record.committed || record.sharedFrom != null) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    final file = kind == 'media' ? _paths.mediaFile(id) : _paths.thumbFile(id);
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    request.response
      ..headers.contentType = ContentType.binary
      ..contentLength = await file.length();
    await request.response.addStream(file.openRead());
  }

  static void _json(HttpResponse response, Object body) {
    response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
  }

  @override
  void dispose() {
    _disposed = true;
    _session.removeLockListener(_onLock);
    unawaited(_stop());
    super.dispose();
  }
}
