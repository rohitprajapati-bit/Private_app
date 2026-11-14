import '../../core/constants/app_constants.dart';
import '../../core/errors/failures.dart';
import '../../core/security/key_hierarchy.dart';
import '../../core/security/lockout_policy.dart';
import '../../core/security/secret_sequence.dart';
import '../../core/security/vault_session.dart';
import '../../core/storage/secure_store.dart';
import '../../core/utilities/bytes.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required SecureStore store,
    required KeyHierarchy keys,
    required VaultSession session,
    DateTime Function()? clock,
  }) : _store = store,
       _keys = keys,
       _session = session,
       _clock = clock ?? DateTime.now;

  final SecureStore _store;
  final KeyHierarchy _keys;
  final VaultSession _session;
  final DateTime Function() _clock;

  @override
  Future<void> setup({required String password, required List<int> secretSequence}) async {
    final (material, masterKey) = await _keys.create(password);
    await _store.writeKeyMaterial(material.encode());
    await _store.writeSequence(SecretSequence.create(secretSequence).encode());
    await _store.clearFailures();
    // The caller finishes onboarding and then marks the session configured.
    _session.unlock(masterKey);
  }

  @override
  Future<void> unlockWithPassword(String password) async {
    final remaining = await lockoutRemaining();
    if (remaining > Duration.zero) throw LockedOut(remaining);

    final encoded = await _store.readKeyMaterial();
    if (encoded == null) throw const StorageFailure('The vault has not been set up.');
    try {
      final masterKey = await _keys.unwrapMasterKey(VaultKeyMaterial.decode(encoded), password);
      await _store.clearFailures();
      _session.unlock(masterKey);
    } on WrongPassword {
      final failures = await _store.readFailures() + 1;
      await _store.recordFailure(failures, _clock());
      final delay = LockoutPolicy.delayAfter(failures);
      if (delay > Duration.zero) throw LockedOut(delay);
      rethrow;
    }
  }

  @override
  Future<void> changePassword({required String current, required String next}) async {
    final encoded = await _store.readKeyMaterial();
    if (encoded == null) throw const StorageFailure('The vault has not been set up.');
    final masterKey = await _keys.unwrapMasterKey(VaultKeyMaterial.decode(encoded), current);
    try {
      // Only the master-key wrapper changes; media stays valid.
      final material = await _keys.wrapMasterKey(masterKey, next);
      await _store.writeKeyMaterial(material.encode());
    } finally {
      wipe(masterKey);
    }
  }

  @override
  Future<SecretSequence?> secretSequence() async {
    final encoded = await _store.readSequence();
    return encoded == null ? null : SecretSequence.decode(encoded);
  }

  @override
  Future<void> changeSecretSequence(List<int> taps) =>
      _store.writeSequence(SecretSequence.create(taps).encode());

  @override
  Future<Duration> autoLockDuration() async => await _store.readAutoLock() ?? AppConstants.defaultAutoLock;

  @override
  Future<void> setAutoLockDuration(Duration value) async {
    await _store.writeAutoLock(value);
    _session.autoLockAfter = value;
  }

  @override
  Future<Duration> lockoutRemaining() async {
    final failures = await _store.readFailures();
    final last = await _store.readLastFailure();
    final delay = LockoutPolicy.delayAfter(failures);
    if (last == null || delay == Duration.zero) return Duration.zero;
    final remaining = last.add(delay).difference(_clock());
    // A clock moved backwards must not lock the owner out forever.
    if (remaining > delay) return delay;
    return remaining.isNegative ? Duration.zero : remaining;
  }
}
