import '../../core/security/secret_sequence.dart';

abstract interface class AuthRepository {
  /// First-launch setup: creates the master key, protects it with [password], saves the
  /// secret sequence and leaves the vault unlocked.
  Future<void> setup({required String password, required List<int> secretSequence});

  /// Throws [WrongPassword] or [LockedOut].
  Future<void> unlockWithPassword(String password);

  Future<void> changePassword({required String current, required String next});

  Future<SecretSequence?> secretSequence();

  Future<void> changeSecretSequence(List<int> taps);

  Future<Duration> autoLockDuration();

  Future<void> setAutoLockDuration(Duration value);

  /// Remaining lockout after too many wrong passwords (zero when allowed).
  Future<Duration> lockoutRemaining();
}
