import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_app/core/encryption/aead.dart';
import 'package:private_app/core/encryption/chunked_cipher.dart';
import 'package:private_app/core/utilities/bytes.dart';
import 'package:private_app/data/datasources/media_stream_server.dart';

void main() {
  late Directory dir;
  late MediaStreamServer server;
  late Uri uri;
  final cipher = ChunkedCipher(Aead());
  final data = randomBytes(3 * 1024 * 1024 + 123);
  final client = HttpClient();

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('server_test');
    final key = randomBytes(32);
    final enc = File('${dir.path}/v.bin');
    await cipher.encryptBytes(data: data, target: enc, key: key, fileId: 'vid');
    server = MediaStreamServer(cipher);
    uri = await server.register(id: 'vid', file: enc, fileKey: Uint8List.fromList(key), mimeType: 'video/mp4', extension: 'mp4');
  });

  tearDownAll(() async {
    await server.stop();
    client.close(force: true);
    await dir.delete(recursive: true);
  });

  Future<(HttpClientResponse, Uint8List)> get(Uri u, {String? range}) async {
    final request = await client.getUrl(u);
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close();
    final body = concatBytes(await response.toList());
    return (response, body);
  }

  test('serves only on loopback', () {
    expect(uri.host, '127.0.0.1');
    expect(uri.pathSegments.first.length, 64);
  });

  test('full GET returns the whole decrypted file', () async {
    final (response, body) = await get(uri);
    expect(response.statusCode, 200);
    expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    expect(body, data);
  });

  test('range requests return 206 with exact bytes', () async {
    for (final (range, start, end) in [
      ('bytes=0-1', 0, 1),
      ('bytes=1048570-1048590', 1048570, 1048590),
      ('bytes=3000000-', 3000000, data.length - 1),
      ('bytes=-100', data.length - 100, data.length - 1),
    ]) {
      final (response, body) = await get(uri, range: range);
      expect(response.statusCode, 206, reason: range);
      expect(response.headers.value(HttpHeaders.contentRangeHeader), 'bytes $start-$end/${data.length}');
      expect(body, data.sublist(start, end + 1), reason: range);
    }
  });

  test('unsatisfiable range is rejected', () async {
    final (response, _) = await get(uri, range: 'bytes=${data.length + 5}-');
    expect(response.statusCode, 416);
  });

  test('wrong token or unknown id is refused', () async {
    final badToken = uri.replace(pathSegments: ['0' * 64, uri.pathSegments.last]);
    expect((await get(badToken)).$1.statusCode, 404);
    final badId = uri.replace(pathSegments: [uri.pathSegments.first, 'other.mp4']);
    expect((await get(badId)).$1.statusCode, 404);
  });
}
