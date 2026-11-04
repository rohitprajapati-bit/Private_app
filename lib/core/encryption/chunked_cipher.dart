import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../errors/failures.dart';
import '../utilities/bytes.dart';
import 'aead.dart';

/// Header of an encrypted media file.
///
/// Layout (25 bytes, big-endian):
///   magic "CMV1" (4) ‖ version (1) ‖ chunkSize u32 (4) ‖ noncePrefix (8) ‖ plainLength u64 (8)
///
/// Followed by ceil(plainLength / chunkSize) chunks (at least one), each
/// `ciphertext ‖ 16-byte GCM tag`. Chunk i uses nonce `noncePrefix ‖ u32(i)` and AAD
/// `header ‖ fileId ‖ u64(i) ‖ isFinal`, which binds every chunk to its file, its position and
/// the declared length — reordering, truncation, extension and cross-file swaps all fail.
class EncryptedFileHeader {
  EncryptedFileHeader({required this.chunkSize, required this.noncePrefix, required this.plainLength});

  static const magic = [0x43, 0x4D, 0x56, 0x31];
  static const version = 1;
  static const length = 25;
  static const noncePrefixLength = 8;

  final int chunkSize;
  final Uint8List noncePrefix;
  final int plainLength;

  int get chunkCount => max(1, (plainLength + chunkSize - 1) ~/ chunkSize);

  int get encryptedLength => length + plainLength + chunkCount * Aead.macLength;

  int chunkOffset(int index) => length + index * (chunkSize + Aead.macLength);

  int chunkPlainLength(int index) =>
      index == chunkCount - 1 ? plainLength - index * chunkSize : chunkSize;

  Uint8List toBytes() {
    final data = ByteData(length);
    for (var i = 0; i < 4; i++) {
      data.setUint8(i, magic[i]);
    }
    data.setUint8(4, version);
    data.setUint32(5, chunkSize, Endian.big);
    for (var i = 0; i < noncePrefixLength; i++) {
      data.setUint8(9 + i, noncePrefix[i]);
    }
    data.setUint64(17, plainLength, Endian.big);
    return data.buffer.asUint8List();
  }

  static EncryptedFileHeader parse(Uint8List bytes) {
    if (bytes.length < length) throw const IntegrityFailure();
    final data = ByteData.sublistView(bytes, 0, length);
    for (var i = 0; i < 4; i++) {
      if (data.getUint8(i) != magic[i]) throw const IntegrityFailure();
    }
    if (data.getUint8(4) != version) throw const IntegrityFailure();
    final chunkSize = data.getUint32(5, Endian.big);
    if (chunkSize == 0 || chunkSize > 16 * 1024 * 1024) throw const IntegrityFailure();
    return EncryptedFileHeader(
      chunkSize: chunkSize,
      noncePrefix: Uint8List.fromList(bytes.sublist(9, 17)),
      plainLength: data.getUint64(17, Endian.big),
    );
  }
}

/// Streaming authenticated encryption for media files of any size. Memory use is bounded by
/// one chunk regardless of file size.
class ChunkedCipher {
  ChunkedCipher(this._aead);

  static const defaultChunkSize = 1024 * 1024;

  final Aead _aead;

  /// Encrypts [source] into [target]. [target] is created/overwritten and flushed to disk.
  Future<void> encryptFile({
    required File source,
    required File target,
    required Uint8List key,
    required String fileId,
    int chunkSize = defaultChunkSize,
    void Function(int done, int total)? onProgress,
  }) async {
    final input = await source.open();
    try {
      final total = await input.length();
      await _encrypt(
        plainLength: total,
        read: (offset, count) async {
          final bytes = await input.read(count);
          // The source changed size underneath us: abort rather than write a short file.
          if (bytes.length != count) throw const StorageFailure('Source file changed during import.');
          return bytes;
        },
        target: target,
        key: key,
        fileId: fileId,
        chunkSize: chunkSize,
        onProgress: onProgress,
      );
    } finally {
      await input.close();
    }
  }

  Future<void> encryptBytes({
    required Uint8List data,
    required File target,
    required Uint8List key,
    required String fileId,
    int chunkSize = defaultChunkSize,
  }) => _encrypt(
    plainLength: data.length,
    read: (offset, count) async => Uint8List.sublistView(data, offset, offset + count),
    target: target,
    key: key,
    fileId: fileId,
    chunkSize: chunkSize,
  );

  /// Decrypts a whole (small) file into memory — photos and thumbnails.
  Future<Uint8List> decryptToMemory({required File source, required Uint8List key, required String fileId}) async {
    final builder = BytesBuilder(copy: false);
    await for (final part in decryptRange(source: source, key: key, fileId: fileId)) {
      builder.add(part);
    }
    return builder.takeBytes();
  }

  /// Decrypts to a plaintext file. Only used for export into a temp file that is deleted after.
  Future<void> decryptToFile({
    required File source,
    required File target,
    required Uint8List key,
    required String fileId,
  }) async {
    final out = await target.open(mode: FileMode.write);
    try {
      await for (final part in decryptRange(source: source, key: key, fileId: fileId)) {
        await out.writeFrom(part);
      }
      await out.flush();
    } finally {
      await out.close();
    }
  }

  Future<int> plainLength(File source) async {
    final input = await source.open();
    try {
      return EncryptedFileHeader.parse(await input.read(EncryptedFileHeader.length)).plainLength;
    } finally {
      await input.close();
    }
  }

  /// Streams decrypted bytes `[start, endInclusive]` (whole file by default), decrypting only
  /// the chunks that overlap the range. Every chunk is authenticated before any byte is emitted.
  Stream<Uint8List> decryptRange({
    required File source,
    required Uint8List key,
    required String fileId,
    int start = 0,
    int? endInclusive,
  }) async* {
    final input = await source.open();
    try {
      final headerBytes = await input.read(EncryptedFileHeader.length);
      final header = EncryptedFileHeader.parse(headerBytes);
      if (await input.length() != header.encryptedLength) throw const IntegrityFailure();

      final end = endInclusive ?? header.plainLength - 1;
      if (header.plainLength == 0) {
        // Still authenticate the single empty chunk.
        await _decryptChunk(input, header, headerBytes, key, fileId, 0);
        return;
      }
      if (start < 0 || end >= header.plainLength || start > end) {
        throw RangeError('Invalid range $start-$end of ${header.plainLength}');
      }

      final firstChunk = start ~/ header.chunkSize;
      final lastChunk = end ~/ header.chunkSize;
      for (var i = firstChunk; i <= lastChunk; i++) {
        final clear = await _decryptChunk(input, header, headerBytes, key, fileId, i);
        final chunkStart = i * header.chunkSize;
        final from = max(start - chunkStart, 0);
        final to = min(end - chunkStart + 1, clear.length);
        yield Uint8List.sublistView(clear, from, to);
      }
    } finally {
      await input.close();
    }
  }

  Future<void> _encrypt({
    required int plainLength,
    required Future<Uint8List> Function(int offset, int count) read,
    required File target,
    required Uint8List key,
    required String fileId,
    required int chunkSize,
    void Function(int done, int total)? onProgress,
  }) async {
    final header = EncryptedFileHeader(
      chunkSize: chunkSize,
      noncePrefix: randomBytes(EncryptedFileHeader.noncePrefixLength),
      plainLength: plainLength,
    );
    final headerBytes = header.toBytes();
    final out = await target.open(mode: FileMode.write);
    try {
      await out.writeFrom(headerBytes);
      for (var i = 0; i < header.chunkCount; i++) {
        final offset = i * chunkSize;
        final clear = await read(offset, header.chunkPlainLength(i));
        final sealed = await _aead.sealWithNonce(
          key,
          _nonce(header, i),
          clear,
          aad: _aad(headerBytes, fileId, i, i == header.chunkCount - 1),
        );
        await out.writeFrom(sealed);
        onProgress?.call(offset + clear.length, plainLength);
      }
      await out.flush();
    } finally {
      await out.close();
    }
  }

  Future<Uint8List> _decryptChunk(
    RandomAccessFile input,
    EncryptedFileHeader header,
    Uint8List headerBytes,
    Uint8List key,
    String fileId,
    int index,
  ) async {
    await input.setPosition(header.chunkOffset(index));
    final sealed = await input.read(header.chunkPlainLength(index) + Aead.macLength);
    return _aead.openWithNonce(
      key,
      _nonce(header, index),
      sealed,
      aad: _aad(headerBytes, fileId, index, index == header.chunkCount - 1),
    );
  }

  static Uint8List _nonce(EncryptedFileHeader header, int index) {
    final nonce = Uint8List(Aead.nonceLength)..setAll(0, header.noncePrefix);
    ByteData.sublistView(nonce).setUint32(8, index, Endian.big);
    return nonce;
  }

  static Uint8List _aad(Uint8List headerBytes, String fileId, int index, bool isFinal) =>
      concatBytes([headerBytes, utf8Bytes(fileId), uint64Bytes(index), [isFinal ? 1 : 0]]);
}
