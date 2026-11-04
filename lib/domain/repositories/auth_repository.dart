import '../../core/security/secret_sequence.dart';
import '../../platform/platform_services.dart';

abstract interface class AuthRepository {
  /// First-launch setup: creates the master key, protects it with [password], saves the
  /// secret sequence and leaves the vault unlocked.
  Future<void> setup({required String password, required List<int> secretSequence});

  /// Throws [WrongPassword] or [LockedOut].
  Future<void> unlockWithPassword(String password);

  /// Throws [BiometricFailure].
  Future<void> unlockWithBiometric();

  Future<void> changePassword({required String current, required String next});

  Future<BiometricStatus> biometricStatus();

  /// Requires an unlocked vault. Prompts the user when enabling.
  Future<void> setBiometricEnabled(bool enabled);

  Future<SecretSequence?> secretSequence();

  Future<void> changeSecretSequence(List<int> taps);

  Future<Duration> autoLockDuration();

  Future<void> setAutoLockDuration(Duration value);

  /// Remaining lockout after too many wrong passwords (zero when allowed).
  Future<Duration> lockoutRemaining();
}
