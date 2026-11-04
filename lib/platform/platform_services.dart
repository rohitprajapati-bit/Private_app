import 'dart:io';

import 'package:flutter/services.dart';

import '../core/errors/failures.dart';
import 'android/android_platform_services.dart';
import 'ios/ios_platform_services.dart';

class BiometricStatus {
  const BiometricStatus({required this.available, required this.enabled, required this.label});

  static const none = BiometricStatus(available: false, enabled: false, label: 'Biometrics');

  final bool available;
  final bool enabled;

  /// "Face ID", "Touch ID", "Fingerprint / face"…
  final String label;
}

class MediaInfo {
  const MediaInfo({this.thumbnail, this.duration, this.width, this.height});

  final Uint8List? thumbnail;
  final Duration? duration;
  final int? width;
  final int? height;
}

/// Native security and media hooks. Implemented in Kotlin (android/app/src/main/kotlin/…/
/// PlatformChannel.kt) and Swift (ios/Runner/PlatformChannel.swift).
abstract class PlatformServices {
  factory PlatformServices() =>
      Platform.isIOS ? IosPlatformServices() : AndroidPlatformServices();

  Future<BiometricStatus> biometricStatus();

  /// Stores [masterKey] behind a hardware key that requires biometric (or device credential)
  /// authentication. Prompts the user.
  Future<void> enableBiometric(Uint8List masterKey);

  /// Prompts and returns the master key on success.
  Future<Uint8List> unlockWithBiometric();

  Future<void> disableBiometric();

  /// Android: FLAG_SECURE (blank recents thumbnail, no screenshots).
  /// iOS: covers the app-switcher snapshot (screenshots cannot be blocked).
  Future<void> setSecureScreen(bool enabled);

  Future<MediaInfo?> mediaInfo(String path, {required bool isVideo, required int maxPixels});

  /// Returns a JPEG when the platform cannot otherwise display [bytes] (HEIC on iOS), else null.
  Future<Uint8List?> transcodeForDisplay(Uint8List bytes);

  Future<void> excludeFromBackup(String path);
}

/// Shared MethodChannel plumbing; subclasses only adapt platform differences.
abstract class MethodChannelPlatformServices implements PlatformServices {
  static const channel = MethodChannel('color_match/platform');

  String get promptTitle => 'Unlock';
  String get promptCancel => 'Use password';

  @override
  Future<BiometricStatus> biometricStatus() async {
    try {
      final map = await channel.invokeMapMethod<String, Object?>('biometricStatus') ?? {};
      return BiometricStatus(
        available: map['available'] == true,
        enabled: map['enabled'] == true,
        label: biometricLabel(map['kind'] as String?),
      );
    } on PlatformException {
      return BiometricStatus.none;
    } on MissingPluginException {
      return BiometricStatus.none;
    }
  }

  String biometricLabel(String? kind);

  @override
  Future<void> enableBiometric(Uint8List masterKey) => _guard(
    () => channel.invokeMethod<void>('biometricEnable', {
      // Copy: the native side zeroes its buffer after wrapping.
      'key': Uint8List.fromList(masterKey),
      'title': promptTitle,
      'cancel': promptCancel,
    }),
  );

  @override
  Future<Uint8List> unlockWithBiometric() async {
    final key = await _guard(
      () => channel.invokeMethod<Uint8List>('biometricUnlock', {'title': promptTitle, 'cancel': promptCancel}),
    );
    if (key == null || key.length != 32) throw const BiometricFailure(BiometricError.failed);
    return key;
  }

  @override
  Future<void> disableBiometric() => channel.invokeMethod<void>('biometricDisable');

  @override
  Future<void> setSecureScreen(bool enabled) async {
    try {
      await channel.invokeMethod<void>('setSecureScreen', {'enabled': enabled});
    } on MissingPluginException {
      // Tests / unsupported platforms.
    }
  }

  @override
  Future<MediaInfo?> mediaInfo(String path, {required bool isVideo, required int maxPixels}) async {
    try {
      final map = await channel.invokeMapMethod<String, Object?>('mediaInfo', {
        'path': path,
        'isVideo': isVideo,
        'maxSize': maxPixels,
      });
      if (map == null) return null;
      final ms = (map['durationMs'] as num?)?.toInt();
      return MediaInfo(
        thumbnail: map['thumbnail'] as Uint8List?,
        duration: ms == null ? null : Duration(milliseconds: ms),
        width: (map['width'] as num?)?.toInt(),
        height: (map['height'] as num?)?.toInt(),
      );
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> excludeFromBackup(String path) async {
    try {
      await channel.invokeMethod<void>('excludeFromBackup', {'path': path});
    } on MissingPluginException {
      // Tests / unsupported platforms.
    }
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      throw BiometricFailure(
        BiometricError.values.firstWhere((v) => v.name == e.code, orElse: () => BiometricError.failed),
      );
    } on MissingPluginException {
      throw const BiometricFailure(BiometricError.unavailable);
    }
  }
}
