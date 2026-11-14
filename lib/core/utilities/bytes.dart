import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

final Random _secureRandom = Random.secure();

/// Cryptographically secure random bytes.
Uint8List randomBytes(int length) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = _secureRandom.nextInt(256);
  }
  return out;
}

/// Random identifier used for media records and file names (128 bits).
String randomId() => hexEncode(randomBytes(16));

String hexEncode(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Compares without short-circuiting so timing does not reveal the mismatch position.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Best-effort wipe. Dart may already hold copies elsewhere; this only limits exposure.
void wipe(Uint8List? bytes) => bytes?.fillRange(0, bytes.length, 0);

Uint8List concatBytes(List<List<int>> parts) {
  final builder = BytesBuilder(copy: false);
  for (final part in parts) {
    builder.add(part);
  }
  return builder.takeBytes();
}

Uint8List utf8Bytes(String value) => Uint8List.fromList(utf8.encode(value));

Uint8List uint64Bytes(int value) =>
    (ByteData(8)..setUint64(0, value, Endian.big)).buffer.asUint8List();
