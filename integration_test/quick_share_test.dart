import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:private_app/core/encryption/aead.dart';
import 'package:private_app/core/encryption/chunked_cipher.dart';
import 'package:private_app/core/security/key_hierarchy.dart';
import 'package:private_app/core/security/vault_session.dart';
import 'package:private_app/core/storage/secure_store.dart';
import 'package:private_app/core/storage/vault_paths.dart';
import 'package:private_app/core/utilities/bytes.dart';
import 'package:private_app/data/datasources/media_stream_server.dart';
import 'package:private_app/data/datasources/vault_database.dart';
import 'package:private_app/data/repositories/media_repository_impl.dart';
import 'package:private_app/data/sharing/quick_share.dart';
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

/// Send / Receive over the real network stack: Bonjour discovery, offer + code, accept,
/// sealed manifest, signed uploads. The receiver ends up with its own, fully owned copies.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late _Vault from;
  late _Vault to;
  late QuickShareSender sender;
  late QuickShareReceiver receiver;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('quick_share_test');
    from = await _Vault.create(Directory(p.join(temp.path, 'from')));
    to = await _Vault.create(Directory(p.join(temp.path, 'to')));
    final aead = Aead();
    sender = QuickShareSender(
      database: from.database,
      keys: KeyHierarchy(aead),
      paths: from.paths,
      session: from.session,
      pairings: from.pairings,
      aead: aead,
    );
    receiver = QuickShareReceiver(
      database: to.database,
      keys: KeyHierarchy(aead),
      paths: to.paths,
      session: to.session,
      pairings: to.pairings,
      aead: aead,
    );
  });

  tearDown(() async {
    sender.dispose();
    receiver.dispose();
    await from.database.close();
    await to.database.close();
    await temp.delete(recursive: true);
  });

  Future<File> makePng(String name, Color color) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 320, 240), Paint()..color = color);
    final image = await recorder.endRecording().toImage(320, 240);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return File(p.join(temp.path, name))..writeAsBytesSync(png!.buffer.asUint8List());
  }

  /// Accepts the next offer once the sender shows its code, checking the codes match.
  void autoAccept() {
    late void Function() listener;
    listener = () {
      if (receiver.stage != ReceiveStage.offered) return;
      receiver.removeListener(listener);
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        expect(receiver.offer!.code, sender.code);
        receiver.accept();
      });
    };
    receiver.addListener(listener);
  }

  testWidgets('send, receive as own copies, skip duplicates, decline, QR', (tester) async {
    await tester.runAsync(() async {
      await from.repository.import([
        for (final f in [await makePng('sunset.png', Colors.orange), await makePng('sea.png', Colors.blue)])
          ImportSource(path: f.path, name: p.basenameWithoutExtension(f.path)),
      ], MediaType.photo).last;
      final originals = (await from.repository.load()).items;

      await receiver.start();
      expect(receiver.stage, ReceiveStage.ready);
      final found = await sender
          .discover(timeout: const Duration(seconds: 15))
          .firstWhere((d) => d.name == receiver.deviceName);

      // --- Send both: the receiver gets byte-identical, fully owned copies ---
      autoAccept();
      await sender.send(found, [for (final i in originals) i.id]);
      expect(sender.stage, SendStage.done, reason: sender.error);
      expect((sender.progress.doneItems, sender.progress.failed), (2, 0));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(receiver.stage, ReceiveStage.done);
      expect(receiver.progress.doneItems, 2);

      final received = (await to.repository.load()).items;
      expect(received.map((i) => i.name).toSet(), {'sunset', 'sea'});
      expect(received.any((i) => i.isShared), isFalse);
      for (final item in received) {
        final original = originals.singleWhere((i) => i.id == item.id);
        expect(await to.repository.photoBytes(item), await from.repository.photoBytes(original));
        expect(await to.repository.thumbnail(item), isNotEmpty);
      }
      expect(await to.paths.temp.list().where((f) => f.path.endsWith('.part')).isEmpty, isTrue);

      // --- Sending again skips what is already there ---
      receiver.receiveMore();
      sender.reset();
      autoAccept();
      await sender.send(found, [for (final i in originals) i.id]);
      expect(sender.stage, SendStage.done, reason: sender.error);
      expect((sender.progress.doneItems, sender.progress.skipped), (0, 2));

      // --- Unsigned uploads are refused ---
      final http = HttpClient();
      final unsigned = await (await http.putUrl(found.endpoint.replace(path: '/media/x'))).close();
      expect(unsigned.statusCode, HttpStatus.forbidden);
      await unsigned.drain<void>();
      http.close(force: true);

      // --- Decline ---
      final fresh = await makePng('forest.png', Colors.green);
      await from.repository.import([ImportSource(path: fresh.path, name: 'forest')], MediaType.photo).last;
      final forest = (await from.repository.load()).items.singleWhere((i) => i.name == 'forest');
      receiver.receiveMore();
      sender.reset();
      void decliner() {
        if (receiver.stage == ReceiveStage.offered) receiver.decline();
      }

      receiver.addListener(decliner);
      await sender.send(found, [forest.id]);
      expect(sender.stage, SendStage.declined);
      expect((await to.repository.load()).items, hasLength(2));

      // --- QR code: the scanned ticket is accepted without any tap on the receiver ---
      receiver.removeListener(decliner);
      receiver.receiveMore();
      sender.reset();
      await Future<void>.delayed(const Duration(milliseconds: 300)); // fresh ticket
      final ticket = ReceiverTicket.decode(receiver.ticket!.encode())!;
      await sender.sendToTicket(ticket, [forest.id]);
      expect(sender.stage, SendStage.done, reason: sender.error);
      expect(sender.progress.doneItems, 1);
      expect((await to.repository.load()).items, hasLength(3));

      // A used (rotated) or forged code is refused.
      receiver.receiveMore();
      sender.reset();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await sender.sendToTicket(ticket, [forest.id]);
      expect(sender.stage, SendStage.failed);
      expect(sender.error, contains('expired'));
      expect(ReceiverTicket.decode('https://example.com'), isNull);

      // --- Locking the receiving vault stops receiving ---
      to.session.lock();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(receiver.stage, ReceiveStage.off);
    });
  });
}
