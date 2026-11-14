import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../core/encryption/aead.dart';
import '../../core/security/vault_session.dart';
import '../../core/storage/secure_store.dart';
import '../../core/utilities/bytes.dart';

/// Bonjour service type both roles use on the local network.
const sharingServiceType = '_colormatch._tcp';

/// A paired device: the admin keeps one per viewer, a viewer keeps one for its admin.
/// [key] is the 256-bit pair key both sides derived during pairing; it never travels.
class PairedDevice {
  const PairedDevice({required this.id, required this.name, required this.key});

  final String id;
  final String name;
  final Uint8List key;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'key': base64Encode(key)};

  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
    id: json['id'] as String,
    name: json['name'] as String,
    key: base64Decode(json['key'] as String),
  );
}

/// One side of an X25519 key agreement. Both devices derive the same pair key and the same
/// 6-digit code; the owners compare codes on screen, which defeats a man in the middle.
class PairingHandshake {
  PairingHandshake._(this._keyPair, this.publicKey);

  final SimpleKeyPair _keyPair;
  final Uint8List publicKey;

  static final _x25519 = X25519();

  static Future<PairingHandshake> start() async {
    final keyPair = await _x25519.newKeyPair();
    final pub = await keyPair.extractPublicKey();
    return PairingHandshake._(keyPair, Uint8List.fromList(pub.bytes));
  }

  /// [adminPublic]/[viewerPublic] fix the order so both sides hash the same transcript.
  Future<({Uint8List key, String code})> finish({
    required Uint8List remotePublic,
    required Uint8List adminPublic,
    required Uint8List viewerPublic,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: _keyPair,
      remotePublicKey: SimplePublicKey(remotePublic, type: KeyPairType.x25519),
    );
    final salt = concatBytes([adminPublic, viewerPublic]);
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final key = await hkdf.deriveKey(secretKey: shared, nonce: salt, info: utf8Bytes('color-match/pair-key/v1'));
    final codeBytes = await hkdf.deriveKey(secretKey: shared, nonce: salt, info: utf8Bytes('color-match/pair-code/v1'));
    final c = await codeBytes.extractBytes();
    final number = ((c[0] << 24) | (c[1] << 16) | (c[2] << 8) | c[3]) & 0x7fffffff;
    return (
      key: Uint8List.fromList(await key.extractBytes()),
      code: (number % 1000000).toString().padLeft(6, '0'),
    );
  }
}

/// Requests from viewer to admin carry `HMAC(pairKey, method ‖ path ‖ time)`. Requests older
/// than [maxSkew] are rejected, so a captured request cannot be replayed later.
abstract final class RequestSigner {
  static const maxSkew = Duration(minutes: 5);
  static final _hmac = Hmac.sha256();

  static Future<String> sign(Uint8List key, String method, String path, int timeMs) async {
    final mac = await _hmac.calculateMac(utf8Bytes('$method\n$path\n$timeMs'), secretKey: SecretKeyData(key));
    return base64Encode(mac.bytes);
  }

  static Future<bool> verify(Uint8List key, String method, String path, int timeMs, String signature) async {
    final age = DateTime.now().millisecondsSinceEpoch - timeMs;
    if (age.abs() > maxSkew.inMilliseconds) return false;
    final expected = await sign(key, method, path, timeMs);
    return constantTimeEquals(utf8.encode(expected), utf8.encode(signature));
  }
}

/// Pairings live in the Keychain sealed under the vault master key, so they are only usable
/// while the vault is unlocked — the password stays the only key.
class PairingStore {
  PairingStore(this._store, this._session, this._aead);

  final SecureStore _store;
  final VaultSession _session;
  final Aead _aead;

  static const _viewersAad = 'sharing/viewers/v1';
  static const _adminAad = 'sharing/admin/v1';

  Future<String> deviceId() async {
    final existing = await _store.readSharing(SecureStore.sharingDeviceId);
    if (existing != null) return existing;
    final id = randomId();
    await _store.writeSharing(SecureStore.sharingDeviceId, id);
    return id;
  }

  /// Viewers this device (as admin) shares with.
  Future<List<PairedDevice>> viewers() async {
    final json = await _open(SecureStore.sharingViewers, _viewersAad);
    if (json == null) return const [];
    return [for (final v in jsonDecode(json) as List) PairedDevice.fromJson(v as Map<String, dynamic>)];
  }

  Future<void> saveViewers(List<PairedDevice> viewers) => viewers.isEmpty
      ? _store.writeSharing(SecureStore.sharingViewers, null)
      : _seal(SecureStore.sharingViewers, _viewersAad, jsonEncode([for (final v in viewers) v.toJson()]));

  /// The admin this device (as viewer) receives from.
  Future<PairedDevice?> admin() async {
    final json = await _open(SecureStore.sharingAdmin, _adminAad);
    return json == null ? null : PairedDevice.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  Future<void> saveAdmin(PairedDevice? admin) => admin == null
      ? _store.writeSharing(SecureStore.sharingAdmin, null)
      : _seal(SecureStore.sharingAdmin, _adminAad, jsonEncode(admin.toJson()));

  Future<String?> _open(String key, String aad) async {
    final sealed = await _store.readSharing(key);
    if (sealed == null) return null;
    final clear = await _aead.open(_session.masterKey, base64Decode(sealed), aad: utf8Bytes(aad));
    return utf8.decode(clear);
  }

  Future<void> _seal(String key, String aad, String json) async {
    final sealed = await _aead.seal(_session.masterKey, utf8.encode(json), aad: utf8Bytes(aad));
    await _store.writeSharing(key, base64Encode(sealed));
  }
}
