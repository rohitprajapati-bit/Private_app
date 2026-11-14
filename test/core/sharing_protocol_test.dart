import 'package:flutter_test/flutter_test.dart';
import 'package:private_app/core/utilities/bytes.dart';
import 'package:private_app/data/sharing/sharing_protocol.dart';

void main() {
  group('PairingHandshake', () {
    test('both sides derive the same key and code', () async {
      final admin = await PairingHandshake.start();
      final viewer = await PairingHandshake.start();
      final a = await admin.finish(
        remotePublic: viewer.publicKey,
        adminPublic: admin.publicKey,
        viewerPublic: viewer.publicKey,
      );
      final v = await viewer.finish(
        remotePublic: admin.publicKey,
        adminPublic: admin.publicKey,
        viewerPublic: viewer.publicKey,
      );
      expect(a.key, v.key);
      expect(a.key, hasLength(32));
      expect(a.code, v.code);
      expect(a.code, matches(RegExp(r'^\d{6}$')));
    });

    test('a man in the middle ends up with different codes on each side', () async {
      final admin = await PairingHandshake.start();
      final viewer = await PairingHandshake.start();
      final mallory = await PairingHandshake.start();
      // Mallory answers the viewer as "admin" and the admin as "viewer".
      final adminSide = await admin.finish(
        remotePublic: mallory.publicKey,
        adminPublic: admin.publicKey,
        viewerPublic: mallory.publicKey,
      );
      final viewerSide = await viewer.finish(
        remotePublic: mallory.publicKey,
        adminPublic: mallory.publicKey,
        viewerPublic: viewer.publicKey,
      );
      expect(adminSide.key, isNot(viewerSide.key));
      // Codes are 6 digits, so a collision is possible in principle (1 in a million); with
      // fresh random keys this run they differ.
      expect(adminSide.code, isNot(viewerSide.code));
    });
  });

  group('RequestSigner', () {
    final key = randomBytes(32);

    test('accepts a fresh signature for the same request', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sig = await RequestSigner.sign(key, 'GET', '/manifest', now);
      expect(await RequestSigner.verify(key, 'GET', '/manifest', now, sig), isTrue);
    });

    test('rejects another path, another key, or an old timestamp', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sig = await RequestSigner.sign(key, 'GET', '/manifest', now);
      expect(await RequestSigner.verify(key, 'GET', '/media/x', now, sig), isFalse);
      expect(await RequestSigner.verify(randomBytes(32), 'GET', '/manifest', now, sig), isFalse);

      final old = now - const Duration(minutes: 10).inMilliseconds;
      final oldSig = await RequestSigner.sign(key, 'GET', '/manifest', old);
      expect(await RequestSigner.verify(key, 'GET', '/manifest', old, oldSig), isFalse);
    });
  });
}
