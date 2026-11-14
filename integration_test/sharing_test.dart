import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:private_app/core/encryption/aead.dart';
import 'package:private_app/core/encryption/chunked_cipher.dart';
import 'package:private_app/core/errors/failures.dart';
import 'package:private_app/core/security/key_hierarchy.dart';
import 'package:private_app/core/security/vault_session.dart';
import 'package:private_app/core/storage/secure_store.dart';
import 'package:private_app/core/storage/vault_paths.dart';
import 'package:private_app/core/utilities/bytes.dart';
import 'package:private_app/data/datasources/media_stream_server.dart';
import 'package:private_app/data/datasources/vault_database.dart';
import 'package:private_app/data/repositories/media_repository_impl.dart';
import 'package:private_app/data/sharing/sharing_client.dart';
import 'package:private_app/data/sharing/sharing_host.dart';
import 'package:private_app/data/sharing/sharing_protocol.dart';
import 'package:private_app/domain/entities/media_item.dart';
import 'package:private_app/domain/repositories/media_repository.dart';
import 'package:private_app/platform/platform_services.dart';

/// One vault (admin or viewer) with its own folder, database and master key.
class _Vault {
  _Vault._(this.paths, this.session, this.database, this.repository, this.pairings);

  final VaultPaths paths;
  final VaultSession session;
  final VaultDatabase database;
  final MediaRepositoryImpl repository;
  final PairingStore pairings;

  static Future<_Vault> create(Directory root) async {
    final paths = VaultPaths(root);
    await paths.ensure();
    final session = VaultSession(isConfigured: true)..unlock(randomBytes(32));
    final aead = Aead();
    final cipher = ChunkedCipher(aead);
    final database = VaultDatabase(paths.databasePath);
    final repository = MediaRepositoryImpl(
      database: database,
      paths: paths,
      keys: KeyHierarchy(aead),
      cipher: cipher,
      session: session,
      platform: PlatformServices(),
      server: MediaStreamServer(cipher),
    );
    return _Vault._(paths, session, database, repository, PairingStore(SecureStore(), session, aead));
  }
}

/// Admin → viewer sharing over the real network stack on a device/simulator: Bonjour
/// discovery, HTTP, pairing, signed requests, SQLite and platform AES-GCM.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late _Vault admin;
  late _Vault viewer;
  late SharingHost host;
  late SharingClient client;
  final store = SecureStore();

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sharing_test');
    admin = await _Vault.create(Directory(p.join(temp.path, 'admin')));
    viewer = await _Vault.create(Directory(p.join(temp.path, 'viewer')));
    final aead = Aead();
    host = SharingHost(
      database: admin.database,
      keys: KeyHierarchy(aead),
      paths: admin.paths,
      session: admin.session,
      pairings: admin.pairings,
      aead: aead,
    );
    client = SharingClient(
      database: viewer.database,
      keys: KeyHierarchy(aead),
      paths: viewer.paths,
      session: viewer.session,
      pairings: viewer.pairings,
      aead: aead,
    );
  });

  tearDown(() async {
    host.dispose();
    client.dispose();
    await admin.database.close();
    await viewer.database.close();
    // Both roles share this app's Keychain; don't leave test pairings for the real app.
    await store.writeSharing(SecureStore.sharingViewers, null);
    await store.writeSharing(SecureStore.sharingAdmin, null);
    await temp.delete(recursive: true);
  });

  Future<File> makePng(String name, Color color) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 320, 240), Paint()..color = color);
    final image = await recorder.endRecording().toImage(320, 240);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return File(p.join(temp.path, name))..writeAsBytesSync(png!.buffer.asUint8List());
  }

  Future<void> importPhotos(List<File> files) => admin.repository.import(
    [for (final f in files) ImportSource(path: f.path, name: p.basenameWithoutExtension(f.path))],
    MediaType.photo,
  ).last;

  testWidgets('pair, sync view-only, follow deletes, revoke', (tester) async {
    await tester.runAsync(() async {
      await importPhotos([await makePng('sunset.png', Colors.orange), await makePng('sea.png', Colors.blue)]);

      // --- Pairing: viewer finds the admin over Bonjour, both sides show the same code ---
      await host.openPairing();
      final found = await client
          .discover(timeout: const Duration(seconds: 15))
          .firstWhere((a) => a.endpoint.port == host.port);
      final attempt = await client.requestPairing(found);
      expect(host.pending, isNotNull);
      expect(host.pending!.code, attempt.code);
      await host.approve();
      expect(await client.waitForApproval(attempt), isTrue);
      expect((await client.linkedAdmin())!.id, attempt.admin.id);

      // Unsigned or wrongly signed requests are refused.
      final http = HttpClient();
      final unsigned = await (await http.getUrl(found.endpoint.replace(path: '/manifest'))).close();
      expect(unsigned.statusCode, HttpStatus.forbidden);
      await unsigned.drain<void>();
      final forged = await http.getUrl(found.endpoint.replace(path: '/manifest'));
      forged.headers
        ..set('x-viewer', attempt.viewerId)
        ..set('x-time', '${DateTime.now().millisecondsSinceEpoch}')
        ..set('x-sig', 'AAAA');
      final forgedResponse = await forged.close();
      expect(forgedResponse.statusCode, HttpStatus.unauthorized);
      await forgedResponse.drain<void>();
      http.close(force: true);

      // --- Sync: the viewer gets both photos, byte-identical, marked shared ---
      var result = await client.sync();
      expect(result.added, 2);
      expect(result.failed, 0);
      var received = (await viewer.repository.load()).items;
      expect(received, hasLength(2));
      expect(received.every((i) => i.isShared), isTrue);
      expect(received.map((i) => i.name).toSet(), {'sunset', 'sea'});
      final adminItems = (await admin.repository.load()).items;
      for (final item in received) {
        final original = adminItems.singleWhere((i) => i.id == item.id);
        expect(await viewer.repository.photoBytes(item), await admin.repository.photoBytes(original));
        expect(await viewer.repository.thumbnail(item), isNotEmpty);
      }

      // --- View-only: the viewer cannot export, move or delete shared items ---
      await expectLater(viewer.repository.delete(received), throwsA(isA<StorageFailure>()));
      await expectLater(viewer.repository.move(received, null), throwsA(isA<StorageFailure>()));
      await expectLater(viewer.repository.export(received), throwsA(isA<StorageFailure>()));

      // A second sync with no changes downloads nothing.
      result = await client.sync();
      expect((result.added, result.removed), (0, 0));

      // --- The admin deletes one photo; the viewer follows ---
      await admin.repository.delete([adminItems.first]);
      result = await client.sync();
      expect(result.removed, 1);
      received = (await viewer.repository.load()).items;
      expect(received.map((i) => i.id), [adminItems.last.id]);
      expect(await viewer.paths.mediaFile(adminItems.first.id).exists(), isFalse);

      // --- Revoking access wipes the viewer's copies and the link ---
      await host.removeViewer(attempt.viewerId);
      await host.openPairing(); // keep the server up so the viewer can learn it was removed
      await expectLater(client.sync(), throwsA(isA<SharingFailure>()));
      expect((await viewer.repository.load()).items, isEmpty);
      expect(await client.linkedAdmin(), isNull);

      // --- Locking the admin vault stops sharing ---
      admin.session.lock();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(host.isRunning, isFalse);
    });
  });
}
