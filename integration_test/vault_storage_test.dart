import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:private_app/core/encryption/aead.dart';
import 'package:private_app/core/encryption/chunked_cipher.dart';
import 'package:private_app/core/security/key_hierarchy.dart';
import 'package:private_app/core/security/vault_session.dart';
import 'package:private_app/core/storage/vault_paths.dart';
import 'package:private_app/core/utilities/bytes.dart';
import 'package:private_app/data/datasources/media_stream_server.dart';
import 'package:private_app/data/datasources/vault_database.dart';
import 'package:private_app/data/models/media_record.dart';
import 'package:private_app/data/repositories/media_repository_impl.dart';
import 'package:private_app/domain/entities/media_item.dart';
import 'package:private_app/domain/repositories/media_repository.dart';
import 'package:private_app/platform/platform_services.dart';
import 'package:video_player/video_player.dart';

import 'fixtures.dart';

/// Runs the real storage stack on a device/simulator: native thumbnailer, SQLite, platform
/// AES-GCM, loopback streaming into the real video player, export.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late VaultPaths paths;
  late VaultSession session;
  late VaultDatabase database;
  late MediaRepositoryImpl repository;
  late Directory sources;

  setUp(() async {
    paths = await VaultPaths.resolve();
    if (await paths.root.exists()) await paths.root.delete(recursive: true);
    await paths.ensure();
    sources = await Directory.systemTemp.createTemp('vault_test_sources');
    session = VaultSession(isConfigured: true)..unlock(randomBytes(32));
    final aead = Aead();
    final cipher = ChunkedCipher(aead);
    database = VaultDatabase(paths.databasePath);
    repository = MediaRepositoryImpl(
      database: database,
      paths: paths,
      keys: KeyHierarchy(aead),
      cipher: cipher,
      session: session,
      platform: PlatformServices(),
      server: MediaStreamServer(cipher),
    );
  });

  tearDown(() async {
    await repository.releaseSecrets();
    await database.close();
    if (await sources.exists()) await sources.delete(recursive: true);
  });

  Future<File> makePng(String name, {int width = 640, int height = 480}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = Colors.teal);
    canvas.drawCircle(Offset(width / 2, height / 2), height / 3, Paint()..color = Colors.orange);
    final image = await recorder.endRecording().toImage(width, height);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return File(p.join(sources.path, name))..writeAsBytesSync(png!.buffer.asUint8List());
  }

  Future<ImportProgress> importAll(List<File> files, MediaType type, {String? albumId}) =>
      repository.import(
        [for (final f in files) ImportSource(path: f.path, name: p.basenameWithoutExtension(f.path))],
        type,
        albumId: albumId,
      ).last;

  testWidgets('photo import: encrypted at rest, metadata, thumbnail, exact decrypt', (tester) async {
    final png = await makePng('beach.png');
    final original = png.readAsBytesSync();

    final result = await importAll([png], MediaType.photo);
    expect(result.failed, 0);
    expect(result.importedPaths, [png.path], reason: 'only these originals may be removed');

    final library = await repository.load();
    expect(library.items, hasLength(1));
    final item = library.items.single;
    expect(item.name, 'beach');
    expect(item.extension, 'png');
    expect((item.width, item.height), (640, 480));

    // Nothing in the vault directory contains the plaintext.
    final stored = paths.mediaFile(item.id).readAsBytesSync();
    expect(stored.length, greaterThan(original.length));
    expect(_contains(stored, original.sublist(0, 64)), isFalse);
    expect(await repository.photoBytes(item), original);

    final thumb = await repository.thumbnail(item);
    expect(thumb.sublist(0, 2), [0xFF, 0xD8], reason: 'thumbnail is a JPEG');
    // The plaintext DB never holds the name.
    expect(_contains(File(paths.databasePath).readAsBytesSync(), utf8.encode('beach')), isFalse);
  });

  testWidgets('video import, duration, thumbnail and real playback through the loopback server', (tester) async {
    final mp4 = File(p.join(sources.path, 'clip.mp4'))..writeAsBytesSync(base64Decode(sampleMp4Base64));
    final result = await importAll([mp4], MediaType.video);
    expect(result.failed, 0);

    final item = (await repository.load()).items.single;
    expect(item.isVideo, isTrue);
    expect(item.duration!.inMilliseconds, inInclusiveRange(2500, 3500));
    expect((item.width, item.height), (160, 120));
    expect((await repository.thumbnail(item)).sublist(0, 2), [0xFF, 0xD8]);

    final uri = await repository.videoUri(item);
    final controller = VideoPlayerController.networkUrl(uri);
    await controller.initialize().timeout(const Duration(seconds: 20));
    expect(controller.value.isInitialized, isTrue);
    expect(controller.value.duration.inMilliseconds, inInclusiveRange(2500, 3500));
    expect(controller.value.size, const Size(160, 120));
    await controller.play();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(controller.value.position, greaterThan(Duration.zero), reason: 'player advanced');
    await controller.seekTo(const Duration(seconds: 2));
    await controller.dispose();
    repository.releaseVideo(item);
  });

  testWidgets('large file: 40 MB round-trips in chunks; range reads are exact', (tester) async {
    final big = File(p.join(sources.path, 'big.mp4'));
    final sink = big.openWrite();
    final block = randomBytes(1024 * 1024);
    for (var i = 0; i < 40; i++) {
      block[0] = i; // make every MiB distinct
      sink.add(block);
    }
    await sink.close();
    final raf = await big.open();
    await raf.setPosition(big.lengthSync() - 5000);
    final expectedTail = await raf.read(5000);
    await raf.close();

    final watch = Stopwatch()..start();
    final result = await importAll([big], MediaType.video);
    debugPrint('40 MB import took ${watch.elapsedMilliseconds} ms');
    expect(result.failed, 0);
    final item = (await repository.load()).items.single;
    expect(item.sizeBytes, 40 * 1024 * 1024);

    final uri = await repository.videoUri(item);
    final client = HttpClient();
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=${item.sizeBytes - 5000}-');
    final response = await request.close();
    expect(response.statusCode, 206);
    expect(concatBytes(await response.toList()), expectedTail);
    client.close(force: true);
  });

  testWidgets('a failed import is never reported as safe to delete from the gallery', (tester) async {
    final good = await makePng('good.png');
    final missing = File(p.join(sources.path, 'vanished.png')); // e.g. picker copy lost
    final result = await importAll([missing, good], MediaType.photo);
    expect(result.failed, 1);
    expect(result.importedPaths, [good.path]);
    expect((await repository.load()).items.map((i) => i.name), ['good']);
  });

  testWidgets('albums, move, delete; deleted files are gone', (tester) async {
    await importAll([await makePng('a.png'), await makePng('b.png')], MediaType.photo);
    final album = await repository.createAlbum('Trips');
    var library = await repository.load();
    await repository.move([library.items.first], album.id);
    await repository.renameAlbum(album.id, 'Holidays');

    library = await repository.load();
    expect(library.albums.single.name, 'Holidays');
    expect(library.inAlbum(album.id), hasLength(1));

    await repository.deleteAlbum(album.id);
    library = await repository.load();
    expect(library.albums, isEmpty);
    expect(library.items, hasLength(2), reason: 'deleting an album keeps its items');

    final victim = library.items.first;
    await repository.delete([victim]);
    expect(paths.mediaFile(victim.id).existsSync(), isFalse);
    expect(paths.thumbFile(victim.id).existsSync(), isFalse);
    expect((await repository.load()).items, hasLength(1));
  });

  testWidgets('interrupted import is rolled back on the next unlock', (tester) async {
    await importAll([await makePng('keep.png')], MediaType.photo);
    // Simulate a crash mid-import: pending row + partial file + orphan.
    await database.insertPending(
      MediaRecord(
        id: 'deadbeef',
        type: 0,
        encryptedName: randomBytes(40),
        extension: 'jpg',
        wrappedKey: randomBytes(60),
        sizeBytes: 10,
        importedAt: 0,
        committed: false,
      ),
    );
    paths.partFile('deadbeef', 'media').writeAsBytesSync(randomBytes(100));
    paths.mediaFile('orphan').writeAsBytesSync(randomBytes(100));

    await repository.releaseSecrets(); // next unlock runs recovery again
    final library = await repository.load();
    expect(library.items.map((i) => i.name), ['keep']);
    expect(await database.pendingIds(), isEmpty);
    expect(paths.mediaFile('orphan').existsSync(), isFalse);
    expect(paths.temp.listSync(), isEmpty);
  });

  testWidgets('picker copies inside temp are deleted after import', (tester) async {
    final pickerDir = Directory.systemTemp; // where the iOS picker puts its copies
    final copy = await makePng('picked.png');
    final inTemp = await copy.copy(p.join(pickerDir.path, 'picked_test.png'));
    await importAll([inTemp], MediaType.photo);
    expect(inTemp.existsSync(), isFalse);
  });

  testWidgets('export saves photo and video to the gallery', (tester) async {
    await importAll([await makePng('export.png')], MediaType.photo);
    await importAll([File(p.join(sources.path, 'e.mp4'))..writeAsBytesSync(base64Decode(sampleMp4Base64))], MediaType.video);
    final items = (await repository.load()).items;
    expect(await repository.export(items), 2);
    expect(paths.temp.listSync(), isEmpty, reason: 'decrypted export copy removed');
  });
}

bool _contains(Uint8List haystack, List<int> needle) {
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
