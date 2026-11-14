import 'dart:convert';
import 'dart:typed_data';

import '../encryption/aead.dart';
import '../encryption/password_kdf.dart';
import '../errors/failures.dart';
import '../utilities/bytes.dart';

/// What is persisted for password unlock. None of it reveals the password or the master key:
/// the master key is AES-GCM-wrapped under an Argon2id key derived from the password.
class VaultKeyMaterial {
  const VaultKeyMaterial({required this.salt, required this.params, required this.wrappedMasterKey});

  final Uint8List salt;
  final KdfParams params;
  final Uint8List wrappedMasterKey;

  String encode() => jsonEncode({
    'v': 1,
    'salt': base64Encode(salt),
    'kdf': params.toJson(),
    'wmk': base64Encode(wrappedMasterKey),
  });

  factory VaultKeyMaterial.decode(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return VaultKeyMaterial(
      salt: base64Decode(map['salt'] as String),
      params: KdfParams.fromJson(map['kdf'] as Map<String, dynamic>),
      wrappedMasterKey: base64Decode(map['wmk'] as String),
    );
  }
}

/// Key hierarchy:
///   password --Argon2id(salt)--> KEK --wraps--> master key --wraps--> per-file keys
/// The master key also encrypts metadata fields. Changing the password only re-wraps the
/// master key; no media is re-encrypted.
class KeyHierarchy {
  KeyHierarchy(this._aead, {this.kdfParams = KdfParams.standard});

  final Aead _aead;
  final KdfParams kdfParams;

  static final _masterKeyAad = utf8Bytes('color-match/master-key/v1');

  /// Creates a new random master key protected by [password].
  Future<(VaultKeyMaterial, Uint8List)> create(String password) async {
    final masterKey = randomBytes(Aead.keyLength);
    return (await wrapMasterKey(masterKey, password), masterKey);
  }

  Future<VaultKeyMaterial> wrapMasterKey(Uint8List masterKey, String password) async {
    final salt = randomBytes(PasswordKdf.saltLength);
    final kek = await PasswordKdf.derive(password, salt, kdfParams);
    try {
      final wrapped = await _aead.seal(kek, masterKey, aad: _masterKeyAad);
      return VaultKeyMaterial(salt: salt, params: kdfParams, wrappedMasterKey: wrapped);
    } finally {
      wipe(kek);
    }
  }

  /// The GCM tag is the password check: a wrong password yields a wrong KEK and fails to open.
  Future<Uint8List> unwrapMasterKey(VaultKeyMaterial material, String password) async {
    final kek = await PasswordKdf.derive(password, material.salt, material.params);
    try {
      return await _aead.open(kek, material.wrappedMasterKey, aad: _masterKeyAad);
    } on IntegrityFailure {
      throw const WrongPassword();
    } finally {
      wipe(kek);
    }
  }

  Future<Uint8List> wrapFileKey(Uint8List masterKey, Uint8List fileKey, String fileId) =>
      _aead.seal(masterKey, fileKey, aad: utf8Bytes('file-key/$fileId'));

  Future<Uint8List> unwrapFileKey(Uint8List masterKey, Uint8List wrapped, String fileId) =>
      _aead.open(masterKey, wrapped, aad: utf8Bytes('file-key/$fileId'));

  /// Encrypts a metadata string (file or album name). [context] binds it to its record.
  Future<Uint8List> encryptText(Uint8List masterKey, String text, String context) =>
      _aead.seal(masterKey, utf8.encode(text), aad: utf8Bytes(context));

  Future<String> decryptText(Uint8List masterKey, Uint8List sealed, String context) async =>
      utf8.decode(await _aead.open(masterKey, sealed, aad: utf8Bytes(context)));
}
