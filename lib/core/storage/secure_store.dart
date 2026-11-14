import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small secrets and vault configuration in the iOS Keychain / Android Keystore-backed storage.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Never silently wipe on a Keystore error: that would destroy the wrapped master
            // key and make the vault unrecoverable.
            aOptions: AndroidOptions(resetOnError: false),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
              synchronizable: false,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _keyMaterial = 'vault.keyMaterial';
  static const _sequence = 'vault.sequence';
  static const _failures = 'vault.failures';
  static const _lastFailure = 'vault.lastFailure';
  static const _biometric = 'vault.biometric';
  static const _autoLockSeconds = 'vault.autoLockSeconds';
  static const _keepOriginals = 'vault.keepOriginals';

  Future<String?> readKeyMaterial() => _storage.read(key: _keyMaterial);
  Future<void> writeKeyMaterial(String value) => _storage.write(key: _keyMaterial, value: value);

  Future<String?> readSequence() => _storage.read(key: _sequence);
  Future<void> writeSequence(String value) => _storage.write(key: _sequence, value: value);

  Future<int> readFailures() async => int.tryParse(await _storage.read(key: _failures) ?? '') ?? 0;

  Future<DateTime?> readLastFailure() async {
    final ms = int.tryParse(await _storage.read(key: _lastFailure) ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> recordFailure(int failures, DateTime at) async {
    await _storage.write(key: _failures, value: '$failures');
    await _storage.write(key: _lastFailure, value: '${at.millisecondsSinceEpoch}');
  }

  Future<void> clearFailures() async {
    await _storage.delete(key: _failures);
    await _storage.delete(key: _lastFailure);
  }

  /// Older versions could store the master key behind biometrics; that unlock path is gone.
  Future<bool> takeLegacyBiometricFlag() async {
    final enabled = await _storage.read(key: _biometric) == '1';
    if (enabled) await _storage.delete(key: _biometric);
    return enabled;
  }

  Future<Duration?> readAutoLock() async {
    final seconds = int.tryParse(await _storage.read(key: _autoLockSeconds) ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }

  Future<void> writeAutoLock(Duration value) =>
      _storage.write(key: _autoLockSeconds, value: '${value.inSeconds}');

  /// Remove gallery originals after import unless the owner turned it off.
  Future<bool> readRemoveOriginals() async => await _storage.read(key: _keepOriginals) != '1';
  Future<void> writeRemoveOriginals(bool remove) =>
      remove ? _storage.delete(key: _keepOriginals) : _storage.write(key: _keepOriginals, value: '1');

  static const sharingDeviceId = 'sharing.deviceId';
  static const sharingViewers = 'sharing.viewers';
  static const sharingAdmin = 'sharing.admin';

  Future<String?> readSharing(String key) => _storage.read(key: key);
  Future<void> writeSharing(String key, String? value) =>
      value == null ? _storage.delete(key: key) : _storage.write(key: key, value: value);

  /// iOS keeps Keychain items after uninstall; called when the app's files are gone.
  Future<void> deleteAll() => _storage.deleteAll();
}
