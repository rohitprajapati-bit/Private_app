import 'package:flutter/material.dart';

abstract final class AppConstants {
  static const appName = 'Color Match';

  static const minPasswordLength = 8;
  static const secretSequenceMinLength = 4;
  static const secretSequenceMaxLength = 6;

  static const thumbnailMaxPixels = 400;

  /// Auto-lock after this much inactivity while the vault is open.
  static const defaultAutoLock = Duration(minutes: 2);
  static const autoLockChoices = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
  ];

  /// Wrong-password attempts allowed before an escalating delay starts.
  static const freeAttempts = 5;
  static const firstLockout = Duration(seconds: 30);
  static const maxLockout = Duration(hours: 1);

  /// Game "tile styles". The pause-menu palette doubles as the secret-sequence keypad.
  static const palette = <Color>[
    Color(0xFFFF5C8A),
    Color(0xFFFFB547),
    Color(0xFF3DD6A3),
    Color(0xFF45B4FF),
    Color(0xFF9B7BFF),
    Color(0xFFFF7A45),
  ];
}
