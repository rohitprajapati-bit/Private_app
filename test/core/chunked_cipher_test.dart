import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_app/core/encryption/aead.dart';
import 'package:private_app/core/encryption/chunked_cipher.dart';
import 'package:private_app/core/errors/failures.dart';
import 'package:private_app/core/utilities/bytes.dart';

void main() {
  late Directory dir;
  final cipher = ChunkedCipher(Aead());
  final key = randomBytes(32);
  const chunk = 1024; // small chunks so tests exercise many of them

  setUp(() async => dir = await Directory.systemTemp.createTemp('cipher_test'));
  tearDown(() async => dir.delete(recursive: true));

  Future<File> encrypt(Uint8List data, {String id = 'file-a'}) async {
    final source = File('${dir.path}/plain')..writeAsBytesSync(data);
    final target = File('${dir.path}/enc-$id');
    await cipher.encryptFile(source: source, target: target, key: key, fileId: id, chunkSize: chunk);
    return target;
  }

  Future<Uint8List> decrypt(File f, {String id = 'file-a', Uint8List? withKey}) =>
      cipher.decryptToMemory(source: f, key: withKey ?? key, fileId: id);

  for (final size in [0, 1, chunk - 1, chunk, chunk + 1, chunk * 5 + 17]) {
    test('round-trips $size bytes', () async {
      final data = randomBytes(size);
      final enc = await encrypt(data);
      expect(await decrypt(enc), data);
      expect(enc.lengthSync(), EncryptedFileHeader(chunkSize: chunk, noncePrefix: Uint8List(8), plainLength: size).encryptedLength);
    });
  }

  test('ciphertext does not contain the plaintext', () async {
    final data = Uint8List.fromList(List.filled(4096, 0x41));
    final enc = (await encrypt(data)).readAsBytesSync();
    expect(String.fromCharCodes(enc).contains('AAAAAAAAAAAAAAAA'), isFalse);
  });

  test('same plaintext encrypts differently each time (unique nonces)', () async {
    final data = randomBytes(3000);
    final a = (await encrypt(data, id: 'x')).readAsBytesSync();
    final b = (await encrypt(data, id: 'y')).readAsBytesSync();
    expect(a.sublist(9, 17), isNot(b.sublist(9, 17)));
  });

  test('flipped ciphertext byte is detected', () async {
    final enc = await encrypt(randomBytes(chunk * 3));
    final bytes = enc.readAsBytesSync();
    bytes[EncryptedFileHeader.length + chunk + 40] ^= 0x01;
    enc.writeAsBytesSync(bytes);
    expect(decrypt(enc), throwsA(isA<IntegrityFailure>()));
  });

  test('tampered header length is detected', () async {
    final enc = await encrypt(randomBytes(chunk * 2));
    final bytes = enc.readAsBytesSync();
    bytes[24] ^= 0x01; // plainLength low byte
    enc.writeAsBytesSync(bytes);
    expect(decrypt(enc), throwsA(isA<IntegrityFailure>()));
  });

  test('truncation (dropping the final chunk) is detected', () async {
    final enc = await encrypt(randomBytes(chunk * 3));
    final bytes = enc.readAsBytesSync();
    enc.writeAsBytesSync(bytes.sublist(0, bytes.length - (chunk + Aead.macLength)));
    expect(decrypt(enc), throwsA(isA<IntegrityFailure>()));
  });

  test('reordered chunks are detected', () async {
    final enc = await encrypt(randomBytes(chunk * 3));
    final bytes = enc.readAsBytesSync();
    const h = EncryptedFileHeader.length;
    const c = chunk + Aead.macLength;
    final swapped = Uint8List.fromList([
      ...bytes.sublist(0, h),
      ...bytes.sublist(h + c, h + 2 * c),
      ...bytes.sublist(h, h + c),
      ...bytes.sublist(h + 2 * c),
    ]);
    enc.writeAsBytesSync(swapped);
    expect(decrypt(enc), throwsA(isA<IntegrityFailure>()));
  });

  test('file cannot be opened under another record id', () async {
    final enc = await encrypt(randomBytes(500), id: 'file-a');
    expect(decrypt(enc, id: 'file-b'), throwsA(isA<IntegrityFailure>()));
  });

  test('wrong key fails', () async {
    final enc = await encrypt(randomBytes(500));
    expect(decrypt(enc, withKey: randomBytes(32)), throwsA(isA<IntegrityFailure>()));
  });

  test('range decryption returns exactly the requested bytes', () async {
    final data = randomBytes(chunk * 4 + 300);
    final enc = await encrypt(data);
    for (final (start, end) in [(0, 0), (0, 99), (chunk - 10, chunk + 10), (chunk * 2, chunk * 3 - 1), (100, data.length - 1)]) {
      final parts = await cipher.decryptRange(source: enc, key: key, fileId: 'file-a', start: start, endInclusive: end).toList();
      expect(concatBytes(parts), data.sublist(start, end + 1), reason: '$start-$end');
    }
  });

  test('encryptBytes matches encryptFile format', () async {
    final data = randomBytes(2500);
    final target = File('${dir.path}/bytes');
    await cipher.encryptBytes(data: data, target: target, key: key, fileId: 'thumb', chunkSize: chunk);
    expect(await cipher.decryptToMemory(source: target, key: key, fileId: 'thumb'), data);
    expect(await cipher.plainLength(target), 2500);
  });
}
