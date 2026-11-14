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

enum GalleryDeleteError { cancelled, denied, unsupported, failed }

/// Removing originals from the device gallery after import did not happen.
class GalleryDeleteFailure extends VaultFailure {
  const GalleryDeleteFailure(this.reason);

  final GalleryDeleteError reason;

  @override
  String get message => switch (reason) {
    GalleryDeleteError.cancelled => 'Originals were kept in your gallery.',
    GalleryDeleteError.denied =>
      'Allow full photo access in Settings so the originals can be removed from your gallery.',
    GalleryDeleteError.unsupported => 'Delete the originals from your gallery manually on this Android version.',
    GalleryDeleteError.failed => 'The originals could not be removed from your gallery.',
  };
}

/// Pairing or syncing with another device failed (not found, refused, access removed…).
class SharingFailure extends VaultFailure {
  const SharingFailure(this.message);

  @override
  final String message;
}
