import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../errors/failures.dart';
import '../utilities/bytes.dart';

/// In-memory vault state. The master key exists only here, only while unlocked.
/// Also drives router redirects (it is the router's refreshListenable).
class VaultSession extends ChangeNotifier {
  VaultSession({required bool isConfigured}) : _isConfigured = isConfigured;

  Uint8List? _masterKey;
  bool _isConfigured;
  bool _entryGranted = false;
  int _autoLockSuppressions = 0;
  DateTime _lastActivity = DateTime.now();
  Duration autoLockAfter = AppConstants.defaultAutoLock;
  final _lockListeners = <VoidCallback>[];

  bool get isConfigured => _isConfigured;
  bool get isUnlocked => _masterKey != null;

  /// Set by the secret in-game sequence; allows exactly one visit to the password screen.
  bool get entryGranted => _entryGranted;

  bool get autoLockSuppressed => _autoLockSuppressions > 0;

  Uint8List get masterKey => _masterKey ?? (throw const VaultLocked());

  void markConfigured() {
    _isConfigured = true;
    notifyListeners();
  }

  void grantEntry() {
    _entryGranted = true;
    notifyListeners();
  }

  /// Silent on purpose: called from widget disposal, where notifying the router is unsafe.
  /// No route depends on the flag turning false.
  void revokeEntry() => _entryGranted = false;

  void unlock(Uint8List masterKey) {
    _masterKey = masterKey;
    _entryGranted = false;
    _lastActivity = DateTime.now();
    notifyListeners();
  }

  void lock() {
    if (_masterKey == null && !_entryGranted) return;
    wipe(_masterKey);
    _masterKey = null;
    _entryGranted = false;
    for (final listener in List.of(_lockListeners)) {
      listener();
    }
    notifyListeners();
  }

  void addLockListener(VoidCallback listener) => _lockListeners.add(listener);
  void removeLockListener(VoidCallback listener) => _lockListeners.remove(listener);

  void recordActivity() => _lastActivity = DateTime.now();

  bool get isIdleExpired => isUnlocked && DateTime.now().difference(_lastActivity) > autoLockAfter;

  /// Keeps the vault open while a system sheet (photo picker, permission dialog, biometric
  /// prompt) briefly sends the app to the background.
  Future<T> withoutAutoLock<T>(Future<T> Function() action) async {
    _autoLockSuppressions++;
    try {
      return await action();
    } finally {
      _autoLockSuppressions--;
      recordActivity();
    }
  }
}
