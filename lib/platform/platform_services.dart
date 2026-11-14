import 'dart:io';

import 'package:flutter/services.dart';

import '../core/errors/failures.dart';
import 'android/android_platform_services.dart';
import 'ios/ios_platform_services.dart';

/// A file chosen in the system picker, copied into the app's temp directory.
class PickedMedia {
  const PickedMedia({required this.path, required this.name, this.sourceId});

  final String path;

  /// Original file name without extension (e.g. IMG_1234).
  final String name;

  /// Gallery identifier used to delete the original after import (iOS PHAsset local id /
  /// Android document URI). Null when the item can't be deleted (e.g. cloud documents).
  final String? sourceId;
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

  /// Deletes any biometric-protected key left by older versions of the app.
  Future<void> disableBiometric();

  /// Android: FLAG_SECURE (blank recents thumbnail, no screenshots).
  /// iOS: covers the app-switcher snapshot (screenshots cannot be blocked).
  Future<void> setSecureScreen(bool enabled);

  Future<MediaInfo?> mediaInfo(String path, {required bool isVideo, required int maxPixels});

  /// Returns a JPEG when the platform cannot otherwise display [bytes] (HEIC on iOS), else null.
  Future<Uint8List?> transcodeForDisplay(Uint8List bytes);

  Future<void> excludeFromBackup(String path);

  /// System photo/video picker that also reports each item's gallery id.
  Future<List<PickedMedia>> pickMedia({required bool video});

  /// Deletes originals from the device gallery. The OS always asks the user to confirm.
  /// Returns how many were deleted; throws [GalleryDeleteFailure].
  Future<int> deleteOriginals(List<String> sourceIds);
}

/// Shared MethodChannel plumbing; subclasses only adapt platform differences.
abstract class MethodChannelPlatformServices implements PlatformServices {
  static const channel = MethodChannel('color_match/platform');

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

  @override
  Future<List<PickedMedia>> pickMedia({required bool video}) async {
    final list = await channel.invokeListMethod<Map<Object?, Object?>>('pickMedia', {'video': video}) ?? const [];
    return [
      for (final m in list)
        PickedMedia(
          path: m['path']! as String,
          name: (m['name'] as String?)?.trim().isNotEmpty == true ? m['name']! as String : 'Item',
          sourceId: (m['sourceId'] as String?)?.isNotEmpty == true ? m['sourceId']! as String : null,
        ),
    ];
  }

  @override
  Future<int> deleteOriginals(List<String> sourceIds) async {
    if (sourceIds.isEmpty) return 0;
    try {
      return await channel.invokeMethod<int>('deleteOriginals', {'ids': sourceIds}) ?? 0;
    } on PlatformException catch (e) {
      throw GalleryDeleteFailure(
        GalleryDeleteError.values.firstWhere((v) => v.name == e.code, orElse: () => GalleryDeleteError.failed),
      );
    }
  }
}
