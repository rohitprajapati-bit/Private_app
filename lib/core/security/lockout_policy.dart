import 'dart:math';

import '../constants/app_constants.dart';

/// Escalating delay after repeated wrong passwords: 5 free attempts, then 30 s, 60 s, 2 min…
/// capped at one hour. Argon2id already makes each guess expensive; this slows manual guessing.
abstract final class LockoutPolicy {
  static Duration delayAfter(int failures) {
    if (failures < AppConstants.freeAttempts) return Duration.zero;
    final exponent = min(failures - AppConstants.freeAttempts, 16);
    final seconds = AppConstants.firstLockout.inSeconds * pow(2, exponent);
    return Duration(seconds: min(seconds.toInt(), AppConstants.maxLockout.inSeconds));
  }
}
