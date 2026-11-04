import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:cryptography/cryptography.dart';

import '../utilities/bytes.dart';

/// Argon2id parameters. Stored next to the salt so they can be raised later without
/// breaking existing vaults.
class KdfParams {
  const KdfParams({required this.memoryKiB, required this.iterations, required this.parallelism});

  /// OWASP minimum for Argon2id: m=19 MiB, t=2, p=1.
  static const standard = KdfParams(memoryKiB: 19456, iterations: 2, parallelism: 1);

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  Map<String, Object> toJson() => {'m': memoryKiB, 't': iterations, 'p': parallelism};

  factory KdfParams.fromJson(Map<String, dynamic> json) => KdfParams(
    memoryKiB: json['m'] as int,
    iterations: json['t'] as int,
    parallelism: json['p'] as int,
  );
}

abstract final class PasswordKdf {
  static const saltLength = 16;

  /// Derives a 256-bit key-encryption key. Runs on a background isolate so the UI stays responsive.
  static Future<Uint8List> derive(String password, Uint8List salt, KdfParams params) {
    final passwordBytes = utf8Bytes(password);
    return Isolate.run(() async {
      final algorithm = DartArgon2id(
        parallelism: params.parallelism,
        memory: params.memoryKiB,
        iterations: params.iterations,
        hashLength: 32,
        maxIsolates: 1,
      );
      final key = await algorithm.deriveKey(secretKey: SecretKeyData(passwordBytes), nonce: salt);
      return Uint8List.fromList(await key.extractBytes());
    });
  }
}
