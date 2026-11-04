/// Failures surfaced by the vault layers. Messages are user-facing and never contain secrets.
sealed class VaultFailure implements Exception {
  const VaultFailure();

  String get message;

  @override
  String toString() => '$runtimeType';
}

class WrongPassword extends VaultFailure {
  const WrongPassword();

  @override
  String get message => 'Incorrect password.';
}

class LockedOut extends VaultFailure {
  const LockedOut(this.remaining);

  final Duration remaining;

  @override
  String get message => 'Too many attempts. Try again in ${_format(remaining)}.';

  static String _format(Duration d) =>
      d.inMinutes >= 1 ? '${d.inMinutes + 1} min' : '${d.inSeconds + 1} s';
}

class VaultLocked extends VaultFailure {
  const VaultLocked();

  @override
  String get message => 'Locked.';
}

/// Authentication tag mismatch, truncated file or malformed header.
class IntegrityFailure extends VaultFailure {
  const IntegrityFailure();

  @override
  String get message => 'This item is damaged and cannot be opened.';
}

class StorageFailure extends VaultFailure {
  const StorageFailure(this.message);

  @override
  final String message;
}

enum BiometricError { cancelled, lockout, invalidated, notEnabled, unavailable, failed }

class BiometricFailure extends VaultFailure {
  const BiometricFailure(this.reason);

  final BiometricError reason;

  @override
  String get message => switch (reason) {
    BiometricError.cancelled => 'Cancelled.',
    BiometricError.lockout => 'Biometrics are temporarily locked. Use your password.',
    BiometricError.invalidated =>
      'Biometric enrollment changed. Unlock with your password and re-enable biometrics.',
    BiometricError.notEnabled => 'Biometric unlock is not enabled.',
    BiometricError.unavailable => 'Biometrics are not available on this device.',
    BiometricError.failed => 'Biometric authentication failed.',
  };
}
