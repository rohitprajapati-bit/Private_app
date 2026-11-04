import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_app/core/encryption/aead.dart';
import 'package:private_app/core/encryption/password_kdf.dart';
import 'package:private_app/core/errors/failures.dart';
import 'package:private_app/core/security/key_hierarchy.dart';
import 'package:private_app/core/security/lockout_policy.dart';
import 'package:private_app/core/security/secret_sequence.dart';
import 'package:private_app/core/security/vault_session.dart';
import 'package:private_app/core/storage/secure_store.dart';
import 'package:private_app/core/utilities/bytes.dart';
import 'package:private_app/data/repositories/auth_repository_impl.dart';
import 'package:private_app/platform/platform_services.dart';

// Cheap parameters keep tests fast; production uses KdfParams.standard.
const _testKdf = KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KeyHierarchy', () {
    final keys = KeyHierarchy(Aead(), kdfParams: _testKdf);

    test('correct password unwraps the master key', () async {
      final (material, masterKey) = await keys.create('correct horse');
      final restored = await keys.unwrapMasterKey(VaultKeyMaterial.decode(material.encode()), 'correct horse');
      expect(restored, masterKey);
    });

    test('wrong password is rejected', () async {
      final (material, _) = await keys.create('correct horse');
      expect(keys.unwrapMasterKey(material, 'Correct horse'), throwsA(isA<WrongPassword>()));
    });

    test('salt is unique per vault and not the password', () async {
      final (a, _) = await keys.create('same password');
      final (b, _) = await keys.create('same password');
      expect(a.salt, isNot(b.salt));
      expect(a.encode().contains('same password'), isFalse);
    });

    test('rewrapping keeps the same master key under the new password', () async {
      final (material, masterKey) = await keys.create('old password');
      final rewrapped = await keys.wrapMasterKey(masterKey, 'new password');
      expect(await keys.unwrapMasterKey(rewrapped, 'new password'), masterKey);
      expect(keys.unwrapMasterKey(rewrapped, 'old password'), throwsA(isA<WrongPassword>()));
      expect(material.wrappedMasterKey, isNot(rewrapped.wrappedMasterKey));
    });

    test('file keys and names are bound to their record', () async {
      final masterKey = randomBytes(32);
      final fileKey = randomBytes(32);
      final wrapped = await keys.wrapFileKey(masterKey, fileKey, 'a');
      expect(await keys.unwrapFileKey(masterKey, wrapped, 'a'), fileKey);
      expect(keys.unwrapFileKey(masterKey, wrapped, 'b'), throwsA(isA<IntegrityFailure>()));

      final name = await keys.encryptText(masterKey, 'beach.jpg', 'media-name/a');
      expect(await keys.decryptText(masterKey, name, 'media-name/a'), 'beach.jpg');
      expect(keys.decryptText(masterKey, name, 'media-name/b'), throwsA(isA<IntegrityFailure>()));
    });
  });

  test('Argon2id with production parameters derives a stable 32-byte key', () async {
    final salt = randomBytes(16);
    final a = await PasswordKdf.derive('password123', salt, KdfParams.standard);
    final b = await PasswordKdf.derive('password123', salt, KdfParams.standard);
    final c = await PasswordKdf.derive('password124', salt, KdfParams.standard);
    expect(a.length, 32);
    expect(a, b);
    expect(a, isNot(c));
  }, timeout: const Timeout(Duration(minutes: 2)));

  group('LockoutPolicy', () {
    test('first five attempts are free, then the delay doubles up to an hour', () {
      expect(LockoutPolicy.delayAfter(4), Duration.zero);
      expect(LockoutPolicy.delayAfter(5), const Duration(seconds: 30));
      expect(LockoutPolicy.delayAfter(6), const Duration(seconds: 60));
      expect(LockoutPolicy.delayAfter(7), const Duration(seconds: 120));
      expect(LockoutPolicy.delayAfter(50), const Duration(hours: 1));
    });
  });

  group('SecretSequence', () {
    test('matches only the exact sequence, found inside longer tap streams', () {
      final sequence = SecretSequence.decode(SecretSequence.create([2, 0, 5, 1]).encode());
      final matcher = SecretSequenceMatcher(sequence);
      expect([3, 3, 2, 0, 5].map(matcher.add), everyElement(isFalse));
      expect(matcher.add(1), isTrue);
      expect(matcher.add(1), isFalse);
      expect(sequence.matches([2, 0, 5]), isFalse);
    });

    test('no sequence configured never matches', () {
      final matcher = SecretSequenceMatcher(null);
      expect([0, 1, 2, 3, 4, 5].map(matcher.add), everyElement(isFalse));
    });
  });

  group('AuthRepositoryImpl', () {
    late VaultSession session;
    late AuthRepositoryImpl auth;
    late DateTime now;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      session = VaultSession(isConfigured: false);
      now = DateTime(2026, 1, 1);
      auth = AuthRepositoryImpl(
        store: SecureStore(),
        keys: KeyHierarchy(Aead(), kdfParams: _testKdf),
        session: session,
        platform: _NoBiometrics(),
        clock: () => now,
      );
    });

    test('setup unlocks; password unlock after lock restores the same key', () async {
      await auth.setup(password: 'hunter22!', secretSequence: [0, 1, 2, 3]);
      final key = List.of(session.masterKey);
      session.lock();
      expect(session.isUnlocked, isFalse);
      await auth.unlockWithPassword('hunter22!');
      expect(session.masterKey, key);
    });

    test('wrong passwords lead to a lockout that expires', () async {
      await auth.setup(password: 'hunter22!', secretSequence: [0, 1, 2, 3]);
      session.lock();
      for (var i = 0; i < 4; i++) {
        await expectLater(auth.unlockWithPassword('nope'), throwsA(isA<WrongPassword>()));
      }
      await expectLater(auth.unlockWithPassword('nope'), throwsA(isA<LockedOut>()));
      // Even the right password is refused during the lockout.
      await expectLater(auth.unlockWithPassword('hunter22!'), throwsA(isA<LockedOut>()));
      now = now.add(const Duration(seconds: 31));
      await auth.unlockWithPassword('hunter22!');
      expect(session.isUnlocked, isTrue);
      expect(await auth.lockoutRemaining(), Duration.zero);
    });

    test('change password', () async {
      await auth.setup(password: 'first-pass', secretSequence: [0, 1, 2, 3]);
      session.lock();
      await expectLater(
        auth.changePassword(current: 'wrong-pass', next: 'second-pass'),
        throwsA(isA<WrongPassword>()),
      );
      await auth.changePassword(current: 'first-pass', next: 'second-pass');
      await expectLater(auth.unlockWithPassword('first-pass'), throwsA(isA<WrongPassword>()));
      await auth.unlockWithPassword('second-pass');
      expect(session.isUnlocked, isTrue);
    });
  });

  test('locking wipes the master key buffer', () {
    final session = VaultSession(isConfigured: true);
    final key = randomBytes(32);
    session.unlock(key);
    session.lock();
    expect(key.every((b) => b == 0), isTrue);
    expect(() => session.masterKey, throwsA(isA<VaultLocked>()));
  });
}

class _NoBiometrics extends MethodChannelPlatformServices {
  @override
  String biometricLabel(String? kind) => 'Biometrics';

  @override
  Future<BiometricStatus> biometricStatus() async => BiometricStatus.none;

  @override
  Future<Uint8List?> transcodeForDisplay(Uint8List bytes) async => null;
}
