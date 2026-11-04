import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../errors/failures.dart';
import '../utilities/bytes.dart';

/// AES-256-GCM. On Android/iOS `cryptography_flutter` routes this to the platform's native
/// implementation; tests fall back to the pure-Dart one.
class Aead {
  Aead() : _algorithm = AesGcm.with256bits();

  static const keyLength = 32;
  static const nonceLength = 12;
  static const macLength = 16;

  final AesGcm _algorithm;

  /// Encrypts with a fresh random nonce. Output: nonce ‖ ciphertext ‖ tag.
  Future<Uint8List> seal(Uint8List key, List<int> plaintext, {required List<int> aad}) async {
    final nonce = randomBytes(nonceLength);
    final sealed = await sealWithNonce(key, nonce, plaintext, aad: aad);
    return concatBytes([nonce, sealed]);
  }

  Future<Uint8List> open(Uint8List key, List<int> sealed, {required List<int> aad}) {
    if (sealed.length < nonceLength + macLength) throw const IntegrityFailure();
    return openWithNonce(
      key,
      sealed.sublist(0, nonceLength),
      sealed.sublist(nonceLength),
      aad: aad,
    );
  }

  /// Caller guarantees the nonce is unique for this key. Output: ciphertext ‖ tag.
  Future<Uint8List> sealWithNonce(
    Uint8List key,
    List<int> nonce,
    List<int> plaintext, {
    required List<int> aad,
  }) async {
    final box = await _algorithm.encrypt(
      plaintext,
      secretKey: SecretKeyData(key),
      nonce: nonce,
      aad: aad,
    );
    return concatBytes([box.cipherText, box.mac.bytes]);
  }

  Future<Uint8List> openWithNonce(
    Uint8List key,
    List<int> nonce,
    List<int> cipherTextAndTag, {
    required List<int> aad,
  }) async {
    if (cipherTextAndTag.length < macLength) throw const IntegrityFailure();
    final split = cipherTextAndTag.length - macLength;
    try {
      final clear = await _algorithm.decrypt(
        SecretBox(
          cipherTextAndTag.sublist(0, split),
          nonce: nonce,
          mac: Mac(cipherTextAndTag.sublist(split)),
        ),
        secretKey: SecretKeyData(key),
        aad: aad,
      );
      return clear is Uint8List ? clear : Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const IntegrityFailure();
    }
  }
}
