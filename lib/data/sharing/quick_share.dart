import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';
import 'package:cryptography/cryptography.dart';
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

/// Bonjour type for one-shot sending. Separate from [sharingServiceType] so senders never see
/// admin devices and viewers never see receivers.
const quickShareServiceType = '_cmsend._tcp';

/// What the Receive screen's QR code carries: where to connect, plus a one-time secret. A
/// sender that scanned it proves so in its offer and the receiver proves it back, so the two
/// phones authenticate each other without comparing codes — and it works where Bonjour
/// doesn't (e.g. one phone's hotspot).
class ReceiverTicket {
  const ReceiverTicket({required this.hosts, required this.port, required this.id, required this.name, required this.secret});

  final List<String> hosts;
  final int port;
  final String id;
  final String name;
  final Uint8List secret;

  static const _scheme = 'cmsend';

  List<DiscoveredDevice> get endpoints => [
    for (final host in hosts) DiscoveredDevice(id: id, name: name, endpoint: Uri(scheme: 'http', host: host, port: port)),
  ];

  String encode() => Uri(
    scheme: _scheme,
    host: 'v1',
    queryParameters: {'h': hosts.join(','), 'p': '$port', 'i': id, 'n': name, 't': base64Url.encode(secret)},
  ).toString();

  /// Null for anything that isn't one of our codes.
  static ReceiverTicket? decode(String text) {
    try {
      final uri = Uri.parse(text.trim());
      if (uri.scheme != _scheme || uri.host != 'v1') return null;
      final q = uri.queryParameters;
      final hosts = q['h']!.split(',').where((h) => InternetAddress.tryParse(h) != null).toList();
      final secret = base64Url.decode(q['t']!);
      if (hosts.isEmpty || secret.length != 32) return null;
      return ReceiverTicket(hosts: hosts, port: int.parse(q['p']!), id: q['i']!, name: q['n'] ?? 'Phone', secret: secret);
    } on Object {
      return null;
    }
  }
}

/// `HMAC(secret, role ‖ publicKey)`: proves knowledge of the QR secret and binds it to this
/// handshake, so a device on the network that saw one message cannot reuse it.
abstract final class TicketProof {
  static final _hmac = Hmac.sha256();

  static Future<String> make(Uint8List secret, String role, Uint8List publicKey) async {
    final mac = await _hmac.calculateMac(
      concatBytes([utf8Bytes('quickshare/$role/'), publicKey]),
      secretKey: SecretKeyData(secret),
    );
    return base64Encode(mac.bytes);
  }

  static Future<bool> verify(Uint8List secret, String role, Uint8List publicKey, String? proof) async =>
      proof != null && constantTimeEquals(utf8.encode(await make(secret, role, publicKey)), utf8.encode(proof));
}

/// This phone's IPv4 addresses another phone on the same Wi-Fi or hotspot could reach.
Future<List<String>> localAddresses() async {
  final cellular = RegExp(r'^(pdp_ip|rmnet|ccmni|v4-rmnet)');
  final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  return [
    for (final i in interfaces)
      if (!cellular.hasMatch(i.name))
        for (final a in i.addresses)
          if (!a.isLoopback && !a.isLinkLocal) a.address,
  ];
}

/// Progress of one transfer, as either side sees it.
class TransferProgress {
  const TransferProgress({
    this.totalItems = 0,
    this.doneItems = 0,
    this.skipped = 0,
    this.failed = 0,
    this.totalBytes = 0,
    this.doneBytes = 0,
  });

  final int totalItems;
  final int doneItems;

  /// Already on the receiving phone (same item sent before).
  final int skipped;
  final int failed;
  final int totalBytes;
  final int doneBytes;

  double? get fraction => totalBytes == 0 ? null : (doneBytes / totalBytes).clamp(0, 1);

  TransferProgress copyWith({int? doneItems, int? skipped, int? failed, int? doneBytes}) => TransferProgress(
    totalItems: totalItems,
    doneItems: doneItems ?? this.doneItems,
    skipped: skipped ?? this.skipped,
    failed: failed ?? this.failed,
    totalBytes: totalBytes,
    doneBytes: doneBytes ?? this.doneBytes,
  );
}

/// What a sender asked to send; the receiver shows it with [code] before accepting.
class IncomingOffer {
  const IncomingOffer({required this.sender, required this.code, required this.count, required this.bytes});

  final PairedDevice sender;
  final String code;
  final int count;
  final int bytes;
}

enum ReceiveStage { off, ready, offered, receiving, done }

/// Receiving side of "Send / Receive": while the Receive screen is open this phone is
/// discoverable, a nearby sender offers items, the owner compares the code and accepts, and
/// the items arrive as this vault's own (savable, deletable) copies.
///
/// Files arrive exactly as stored on the sender — still encrypted with their per-file key —
/// and the keys travel only inside a manifest sealed with the one-time pair key.
class QuickShareReceiver extends ChangeNotifier {
  QuickShareReceiver({
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
  ReceiveStage _stage = ReceiveStage.off;
  IncomingOffer? _offer;
  PairedDevice? _sender;
  final _declined = <String>{};
  Map<String, Map<String, dynamic>> _manifest = const {};
  TransferProgress _progress = const TransferProgress();
  DateTime _lastNotify = DateTime(0);
  bool _disposed = false;
  ReceiverTicket? _ticket;

  ReceiveStage get stage => _stage;

  /// For the QR code; a fresh secret for every transfer. Null when not on any network.
  ReceiverTicket? get ticket => _ticket;

  /// False when Bonjour could not start: senders must scan the QR code.
  bool get discoverable => _broadcast != null;
  IncomingOffer? get offer => _offer;
  PairedDevice? get sender => _sender;
  TransferProgress get progress => _progress;
  String get deviceName => localDeviceName('This phone');

  /// Makes this phone discoverable to senders on the network.
  Future<void> start() async {
    if (_server == null) {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _server = server;
      server.listen((request) => unawaited(_handle(request)), onError: (_) {});
      final id = await _pairings.deviceId();
      final broadcast = BonsoirBroadcast(
        service: BonsoirService(
          name: 'Color Match ${id.substring(0, 6)}',
          type: quickShareServiceType,
          port: server.port,
          attributes: {'id': id, 'name': deviceName},
        ),
      );
      try {
        await broadcast.initialize();
        await broadcast.start();
        _broadcast = broadcast;
      } on Object {
        // Not discoverable (e.g. local network access denied); the QR code still works.
      }
    }
    _reset(ReceiveStage.ready);
    await _newTicket();
  }

  Future<void> _newTicket() async {
    final server = _server;
    if (server == null) return;
    final hosts = await localAddresses().catchError((_) => <String>[]);
    _ticket = hosts.isEmpty
        ? null
        : ReceiverTicket(
            hosts: hosts,
            port: server.port,
            id: await _pairings.deviceId(),
            name: deviceName,
            secret: randomBytes(32),
          );
    _notify();
  }

  Future<void> stop() async {
    final server = _server;
    final broadcast = _broadcast;
    _server = null;
    _broadcast = null;
    final stray = _deleteStrayParts();
    _ticket = null;
    _reset(ReceiveStage.off);
    await broadcast?.stop().catchError((_) {});
    await server?.close(force: true);
    await stray;
  }

  /// Ready for the next sender after a finished (or abandoned) transfer.
  void receiveMore() {
    if (_server == null) return;
    unawaited(_deleteStrayParts());
    _reset(ReceiveStage.ready);
    unawaited(_newTicket());
  }

  void accept() {
    final offer = _offer;
    if (offer == null) return;
    _sender = offer.sender;
    _offer = null;
    _stage = ReceiveStage.receiving;
    _progress = TransferProgress(totalItems: offer.count, totalBytes: offer.bytes);
    _notify();
  }

  void decline() {
    final offer = _offer;
    if (offer == null) return;
    _declined.add(offer.sender.id);
    _offer = null;
    _stage = ReceiveStage.ready;
    _notify();
  }

  void _reset(ReceiveStage stage) {
    _stage = stage;
    _offer = null;
    _sender = null;
    _declined.clear();
    _manifest = const {};
    _progress = const TransferProgress();
    _notify();
  }

  void _onLock() => unawaited(stop());

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      switch ((request.method, request.uri.pathSegments)) {
        case ('POST', ['offer']):
          await _onOffer(request);
        case ('GET', ['offer', 'status']):
          _onStatus(request);
        case ('POST', ['manifest']):
          final sender = await _authorize(request);
          if (sender != null) await _onManifest(request, sender);
        case ('PUT', [final kind, final id]) when kind == 'media' || kind == 'thumb':
          final sender = await _authorize(request);
          if (sender != null) await _onFile(request, kind, id);
        case ('POST', ['done']):
          final sender = await _authorize(request);
          if (sender != null) {
            _stage = ReceiveStage.done;
            _notify();
            await _deleteStrayParts();
          }
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

  /// Body: `{id, name, pub, count, bytes, proof?}`. One sender at a time. With a valid QR
  /// [TicketProof] the offer is accepted at once — showing the code was the consent.
  Future<void> _onOffer(HttpRequest request) async {
    if (_stage != ReceiveStage.ready) {
      request.response.statusCode = HttpStatus.conflict;
      return;
    }
    final body = jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic>;
    final senderPublic = base64Decode(body['pub'] as String);
    final proof = body['proof'] as String?;
    final secret = _ticket?.secret;
    final scanned = proof != null;
    if (scanned && (secret == null || !await TicketProof.verify(secret, 'sender', senderPublic, proof))) {
      request.response.statusCode = HttpStatus.forbidden; // stale or forged QR code
      return;
    }
    final handshake = await PairingHandshake.start();
    // The receiver plays the "admin" half so both sides hash the transcript in the same order.
    final result = await handshake.finish(
      remotePublic: senderPublic,
      adminPublic: handshake.publicKey,
      viewerPublic: senderPublic,
    );
    final senderId = body['id'] as String;
    _declined.remove(senderId);
    _offer = IncomingOffer(
      sender: PairedDevice(id: senderId, name: body['name'] as String, key: result.key),
      code: result.code,
      count: body['count'] as int,
      bytes: body['bytes'] as int,
    );
    _stage = ReceiveStage.offered;
    if (scanned) {
      accept();
    } else {
      _notify();
    }
    _json(request.response, {
      'id': await _pairings.deviceId(),
      'name': deviceName,
      'pub': base64Encode(handshake.publicKey),
      if (scanned) 'proof': await TicketProof.make(secret!, 'receiver', handshake.publicKey),
    });
  }

  void _onStatus(HttpRequest request) {
    final id = request.uri.queryParameters['id'];
    _json(request.response, {
      'status': _sender?.id == id
          ? 'accepted'
          : _offer?.sender.id == id
          ? 'pending'
          : _declined.contains(id)
          ? 'declined'
          : 'unknown',
    });
  }

  Future<PairedDevice?> _authorize(HttpRequest request) async {
    final sender = _sender;
    final time = int.tryParse(request.headers.value('x-time') ?? '');
    final signature = request.headers.value('x-sig');
    if (sender == null || request.headers.value('x-sender') != sender.id || _stage == ReceiveStage.off) {
      request.response.statusCode = HttpStatus.forbidden;
      return null;
    }
    if (time == null ||
        signature == null ||
        !await RequestSigner.verify(sender.key, request.method, request.uri.path, time, signature)) {
      request.response.statusCode = HttpStatus.unauthorized;
      return null;
    }
    return sender;
  }

  /// Replies with the ids this vault already has, so the sender skips them.
  Future<void> _onManifest(HttpRequest request, PairedDevice sender) async {
    final builder = BytesBuilder(copy: false);
    await request.forEach(builder.add);
    final clear = await _aead.open(sender.key, builder.takeBytes(), aad: utf8Bytes('quickshare/manifest/${sender.id}'));
    final items = (jsonDecode(utf8.decode(clear)) as Map<String, dynamic>)['items'] as List;
    final manifest = <String, Map<String, dynamic>>{};
    final skip = <String>[];
    var bytes = 0;
    for (final raw in items) {
      final item = raw as Map<String, dynamic>;
      final id = item['id'] as String;
      if (await _db.media(id) != null) {
        skip.add(id);
      } else {
        manifest[id] = item;
        bytes += item['wire'] as int;
      }
    }
    _manifest = manifest;
    _progress = TransferProgress(totalItems: manifest.length, totalBytes: bytes, skipped: skip.length);
    _notify();
    _json(request.response, {'skip': skip});
  }

  /// Thumbnails arrive first; the media upload then writes the row and commits the item, with
  /// the same pending → rename → commit shape as an import so an interrupted transfer leaves
  /// nothing half-visible.
  Future<void> _onFile(HttpRequest request, String kind, String id) async {
    final item = _manifest[id];
    if (item == null) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    if (kind == 'thumb') {
      await _write(request, _paths.partFile(id, 'thumb'));
      return;
    }
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
          importedAt: DateTime.now().millisecondsSinceEpoch,
          committed: false,
          durationMs: item['durationMs'] as int?,
          width: item['width'] as int?,
          height: item['height'] as int?,
        ),
      );
      await _write(request, mediaPart);
      final raf = await mediaPart.open();
      try {
        final header = EncryptedFileHeader.parse(await raf.read(EncryptedFileHeader.length));
        if (await mediaPart.length() != header.encryptedLength) throw const SharingFailure('Incomplete file.');
      } finally {
        await raf.close();
      }
      if (!_session.isUnlocked) throw const VaultLocked();
      if (await thumbPart.exists()) await thumbPart.rename(_paths.thumbFile(id).path);
      await mediaPart.rename(_paths.mediaFile(id).path);
      await _db.commit(id);
      _manifest.remove(id);
      _progress = _progress.copyWith(doneItems: _progress.doneItems + 1);
      _notify();
    } on Object {
      await _deleteQuietly([mediaPart, thumbPart, _paths.mediaFile(id), _paths.thumbFile(id)]);
      await _db.deleteMedia([id]).catchError((_) {});
      _progress = _progress.copyWith(failed: _progress.failed + 1);
      _notify();
      rethrow;
    } finally {
      wipe(fileKey);
      wipe(masterKey);
    }
  }

  Future<void> _write(HttpRequest request, File target) async {
    final sink = target.openWrite();
    try {
      await for (final chunk in request) {
        sink.add(chunk);
        _session.recordActivity();
        _progress = _progress.copyWith(doneBytes: _progress.doneBytes + chunk.length);
        _notify(throttled: true);
      }
    } finally {
      await sink.close().catchError((_) {});
    }
  }

  void _notify({bool throttled = false}) {
    if (_disposed) return;
    final now = DateTime.now();
    if (throttled && now.difference(_lastNotify) < const Duration(milliseconds: 120)) return;
    _lastNotify = now;
    notifyListeners();
  }

  /// Thumbnails whose media never arrived; startup recovery handles rows and media parts.
  Future<void> _deleteStrayParts() async {
    final ids = _manifest.keys.toList();
    await _deleteQuietly([for (final id in ids) _paths.partFile(id, 'thumb')]);
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
    unawaited(stop());
    super.dispose();
  }
}

enum SendStage { idle, connecting, awaitingAccept, sending, done, declined, failed }

/// Sending side: offers the owner's own items to a nearby receiver and uploads them once the
/// receiver accepts. Items received view-only from an admin device are never sent.
class QuickShareSender extends ChangeNotifier {
  QuickShareSender({
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

  SendStage _stage = SendStage.idle;
  String? _code;
  String? _error;
  TransferProgress _progress = const TransferProgress();
  HttpClient? _client;
  bool _cancelled = false;
  DateTime _lastNotify = DateTime(0);

  SendStage get stage => _stage;
  String? get code => _code;
  String? get error => _error;
  TransferProgress get progress => _progress;
  bool get busy => switch (_stage) {
    SendStage.connecting || SendStage.awaitingAccept || SendStage.sending => true,
    _ => false,
  };

  /// Receivers currently open on this network.
  Stream<DiscoveredDevice> discover({Duration timeout = const Duration(seconds: 30)}) =>
      discoverDevices(quickShareServiceType, timeout: timeout);

  /// Own, committed items among [ids] with their on-disk sizes.
  Future<List<({MediaRecord record, int wire, bool thumb})>> sendable(List<String> ids) async {
    final result = <({MediaRecord record, int wire, bool thumb})>[];
    for (final id in ids) {
      final record = await _db.media(id);
      if (record == null || !record.committed || record.sharedFrom != null) continue;
      final media = _paths.mediaFile(id);
      final thumb = _paths.thumbFile(id);
      if (!await media.exists()) continue;
      final hasThumb = await thumb.exists();
      result.add((
        record: record,
        wire: await media.length() + (hasThumb ? await thumb.length() : 0),
        thumb: hasThumb,
      ));
    }
    return result;
  }

  void reset() {
    if (busy) return;
    _stage = SendStage.idle;
    _code = null;
    _error = null;
    _progress = const TransferProgress();
    notifyListeners();
  }

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  /// Sends to the phone whose QR code was scanned, trying each address it listed.
  Future<void> sendToTicket(ReceiverTicket ticket, List<String> ids) async {
    if (busy) return;
    _cancelled = false;
    _error = null;
    _set(SendStage.connecting);
    for (final device in ticket.endpoints) {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      try {
        final probe = await client.getUrl(device.endpoint.replace(path: '/offer/status')).timeout(const Duration(seconds: 4));
        final response = await probe.close().timeout(const Duration(seconds: 4));
        await response.drain<void>();
        _stage = SendStage.idle;
        return send(device, ids, secret: ticket.secret);
      } on Object {
        // Try the next address.
      } finally {
        client.close(force: true);
      }
    }
    _fail('Could not reach ${ticket.name}. Connect both phones to the same Wi-Fi or hotspot.');
  }

  /// [secret] is set when the receiver's QR code was scanned.
  Future<void> send(DiscoveredDevice receiver, List<String> ids, {Uint8List? secret}) async {
    if (busy) return;
    _cancelled = false;
    _code = null;
    _error = null;
    _set(SendStage.connecting);
    try {
      final items = await sendable(ids);
      if (items.isEmpty) throw const SharingFailure('Nothing to send.');
      final senderId = await _pairings.deviceId();
      final handshake = await PairingHandshake.start();
      final reply = await _json(receiver.endpoint.replace(path: '/offer'), 'POST', {
        'id': senderId,
        'name': localDeviceName('Nearby phone'),
        'pub': base64Encode(handshake.publicKey),
        'count': items.length,
        'bytes': items.fold<int>(0, (sum, i) => sum + i.wire),
        if (secret != null) 'proof': await TicketProof.make(secret, 'sender', handshake.publicKey),
      });
      final receiverPublic = base64Decode(reply['pub'] as String);
      if (secret != null && !await TicketProof.verify(secret, 'receiver', receiverPublic, reply['proof'] as String?)) {
        throw const SharingFailure('That is not the phone whose code you scanned.');
      }
      final pair = await handshake.finish(
        remotePublic: receiverPublic,
        adminPublic: receiverPublic,
        viewerPublic: handshake.publicKey,
      );
      _code = pair.code;
      _set(SendStage.awaitingAccept);

      switch (await _waitForAccept(receiver.endpoint, senderId)) {
        case 'accepted':
          break;
        case 'declined':
          _set(SendStage.declined);
          return;
        default:
          throw SharingFailure(_cancelled ? 'Cancelled.' : 'The other phone did not answer.');
      }

      final key = pair.key;
      final skip = await _sendManifest(receiver.endpoint, key, senderId, items);
      final toSend = items.where((i) => !skip.contains(i.record.id)).toList();
      _progress = TransferProgress(
        totalItems: toSend.length,
        skipped: items.length - toSend.length,
        totalBytes: toSend.fold<int>(0, (sum, i) => sum + i.wire),
      );
      _set(SendStage.sending);

      for (final item in toSend) {
        if (_cancelled) throw const SharingFailure('Cancelled.');
        if (!_session.isUnlocked) throw const VaultLocked();
        final id = item.record.id;
        try {
          if (item.thumb) await _upload(receiver.endpoint, key, senderId, '/thumb/$id', _paths.thumbFile(id));
          await _upload(receiver.endpoint, key, senderId, '/media/$id', _paths.mediaFile(id));
          _progress = _progress.copyWith(doneItems: _progress.doneItems + 1);
        } on SharingFailure catch (e) {
          // The receiver is gone or stopped; end instead of failing every remaining item.
          if (e.message == _lost || e.message == _stopped) rethrow;
          _progress = _progress.copyWith(failed: _progress.failed + 1);
        }
        notifyListeners();
      }
      await _signed(receiver.endpoint, key, senderId, 'POST', '/done');
      _set(SendStage.done);
    } on VaultFailure catch (e) {
      _fail(_cancelled ? 'Cancelled.' : e.message);
    } on Object {
      _fail(_cancelled ? 'Cancelled.' : 'Sending failed.');
    } finally {
      _client?.close(force: true);
      _client = null;
    }
  }

  static const _lost = 'Lost connection to the other phone.';
  static const _stopped = 'The other phone stopped receiving.';

  void _fail(String message) {
    _error = message;
    _set(SendStage.failed);
  }

  void _set(SendStage stage) {
    _stage = stage;
    notifyListeners();
  }

  /// `accepted`, `declined` (also when the receiver moved on), or `timeout`.
  Future<String> _waitForAccept(Uri endpoint, String senderId) async {
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (!_cancelled && DateTime.now().isBefore(deadline)) {
      final reply = await _json(endpoint.replace(path: '/offer/status', queryParameters: {'id': senderId}), 'GET', null);
      switch (reply['status']) {
        case 'accepted':
          return 'accepted';
        case 'declined' || 'unknown':
          return 'declined';
      }
      _session.recordActivity();
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return 'timeout';
  }

  Future<Set<String>> _sendManifest(
    Uri endpoint,
    Uint8List key,
    String senderId,
    List<({MediaRecord record, int wire, bool thumb})> items,
  ) async {
    final masterKey = Uint8List.fromList(_session.masterKey);
    final Uint8List sealed;
    try {
      final manifest = <Map<String, Object?>>[];
      for (final item in items) {
        final r = item.record;
        final fileKey = await _keys.unwrapFileKey(masterKey, r.wrappedKey, r.id);
        manifest.add({
          'id': r.id,
          'type': r.type,
          'name': await _keys.decryptText(masterKey, r.encryptedName, MediaRepositoryImpl.nameContext(r.id)),
          'ext': r.extension,
          'size': r.sizeBytes,
          'durationMs': r.durationMs,
          'width': r.width,
          'height': r.height,
          'key': base64Encode(fileKey),
          'wire': item.wire,
        });
        wipe(fileKey);
      }
      sealed = await _aead.seal(
        key,
        utf8.encode(jsonEncode({'items': manifest})),
        aad: utf8Bytes('quickshare/manifest/$senderId'),
      );
    } finally {
      wipe(masterKey);
    }
    final reply = await _signed(endpoint, key, senderId, 'POST', '/manifest', body: sealed);
    return {for (final id in (jsonDecode(reply) as Map<String, dynamic>)['skip'] as List) id as String};
  }

  Future<void> _upload(Uri endpoint, Uint8List key, String senderId, String path, File file) async {
    await _signed(endpoint, key, senderId, 'PUT', path, file: file);
  }

  /// Signed request (same HMAC scheme as viewer → admin). Returns the response text.
  Future<String> _signed(
    Uri endpoint,
    Uint8List key,
    String senderId,
    String method,
    String path, {
    Uint8List? body,
    File? file,
  }) async {
    final client = _client ??= HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final time = DateTime.now().millisecondsSinceEpoch;
      final request = await client.openUrl(method, endpoint.replace(path: path)).timeout(_requestTimeout);
      request.headers
        ..contentType = ContentType.binary
        ..set('x-sender', senderId)
        ..set('x-time', '$time')
        ..set('x-sig', await RequestSigner.sign(key, method, path, time));
      if (file != null) {
        request.contentLength = await file.length();
        await request.addStream(
          file.openRead().map((chunk) {
            _session.recordActivity();
            _progress = _progress.copyWith(doneBytes: _progress.doneBytes + chunk.length);
            _notifyThrottled();
            return chunk;
          }),
        );
      } else if (body != null) {
        request.contentLength = body.length;
        request.add(body);
      } else {
        request.contentLength = 0;
      }
      final response = await request.close().timeout(_requestTimeout);
      final text = await utf8.decodeStream(response);
      if (response.statusCode == HttpStatus.forbidden) throw const SharingFailure(_stopped);
      if (response.statusCode != HttpStatus.ok) {
        throw SharingFailure('The other phone refused the item (${response.statusCode}).');
      }
      return text;
    } on SocketException {
      throw const SharingFailure(_lost);
    } on HttpException {
      throw const SharingFailure(_lost);
    } on TimeoutException {
      throw const SharingFailure(_lost);
    }
  }

  Future<Map<String, dynamic>> _json(Uri uri, String method, Map<String, Object?>? body) async {
    final client = _client ??= HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.openUrl(method, uri).timeout(_requestTimeout);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(_requestTimeout);
      final text = await utf8.decodeStream(response);
      if (response.statusCode == HttpStatus.conflict) {
        throw const SharingFailure('That phone is busy with another transfer.');
      }
      if (response.statusCode == HttpStatus.forbidden) {
        throw const SharingFailure('That code has expired. Scan the code on the other phone again.');
      }
      if (response.statusCode != HttpStatus.ok) throw SharingFailure('Request failed (${response.statusCode}).');
      return jsonDecode(text) as Map<String, dynamic>;
    } on SocketException {
      throw const SharingFailure('Could not reach the other phone.');
    } on HttpException {
      throw const SharingFailure('Could not reach the other phone.');
    } on TimeoutException {
      throw const SharingFailure('The other phone did not respond.');
    }
  }

  void _notifyThrottled() {
    final now = DateTime.now();
    if (now.difference(_lastNotify) < const Duration(milliseconds: 120)) return;
    _lastNotify = now;
    notifyListeners();
  }
}

Future<void> _deleteQuietly(List<File> files) async {
  for (final file in files) {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Recovery removes orphans on the next unlock.
    }
  }
}
