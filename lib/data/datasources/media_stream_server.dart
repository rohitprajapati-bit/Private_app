import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../core/encryption/chunked_cipher.dart';
import '../../core/utilities/bytes.dart';

class _StreamSource {
  _StreamSource({required this.file, required this.key, required this.fileId, required this.mimeType});

  final File file;
  final Uint8List key;
  final String fileId;
  final String mimeType;
}

/// Serves decrypted video to the platform player over 127.0.0.1 with HTTP Range support, so
/// large videos play and seek without ever existing decrypted on disk or fully in RAM.
///
/// Only bound to loopback, on a random port, and every URL carries a 256-bit random token —
/// other apps on the device cannot guess it. Stopped (and keys wiped) when the vault locks.
class MediaStreamServer {
  MediaStreamServer(this._cipher);

  final ChunkedCipher _cipher;
  HttpServer? _server;
  String _token = '';
  final _sources = <String, _StreamSource>{};

  Future<Uri> register({
    required String id,
    required File file,
    required Uint8List fileKey,
    required String mimeType,
    required String extension,
  }) async {
    final server = await _ensureStarted();
    _sources[id] = _StreamSource(file: file, key: fileKey, fileId: id, mimeType: mimeType);
    return Uri(scheme: 'http', host: '127.0.0.1', port: server.port, pathSegments: [_token, '$id.$extension']);
  }

  void unregister(String id) => wipe(_sources.remove(id)?.key);

  Future<void> stop() async {
    for (final source in _sources.values) {
      wipe(source.key);
    }
    _sources.clear();
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<HttpServer> _ensureStarted() async {
    final existing = _server;
    if (existing != null) return existing;
    _token = hexEncode(randomBytes(32));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false);
    server.listen(_handle, onError: (_) {});
    return _server = server;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      final source = segments.length == 2 && constantTimeEquals(utf8Bytes(segments[0]), utf8Bytes(_token))
          ? _sources[segments[1].split('.').first]
          : null;
      if (source == null || (request.method != 'GET' && request.method != 'HEAD')) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      final length = await _cipher.plainLength(source.file);
      var start = 0;
      var end = length - 1;
      final range = request.headers.value(HttpHeaders.rangeHeader);
      final match = range == null ? null : RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range.trim());
      if (match != null) {
        final from = match.group(1)!;
        final to = match.group(2)!;
        if (from.isEmpty && to.isNotEmpty) {
          start = length - int.parse(to); // suffix range: last N bytes
        } else {
          start = int.parse(from);
          if (to.isNotEmpty) end = int.parse(to);
        }
        if (start < 0) start = 0;
        if (end >= length) end = length - 1;
        if (start > end || start >= length) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
          await response.close();
          return;
        }
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$length');
      }

      response.headers
        ..contentType = ContentType.parse(source.mimeType)
        ..contentLength = length == 0 ? 0 : end - start + 1
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set(HttpHeaders.cacheControlHeader, 'no-store');

      if (request.method == 'GET' && length > 0) {
        await response.addStream(
          _cipher.decryptRange(source: source.file, key: source.key, fileId: source.fileId, start: start, endInclusive: end),
        );
      }
      await response.close();
    } catch (_) {
      // Player disconnected mid-stream (normal when seeking) or the file failed integrity
      // checks. Never log details.
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
      try {
        await response.close();
      } catch (_) {}
    }
  }
}
