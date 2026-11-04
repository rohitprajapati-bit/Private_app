import 'package:flutter/services.dart';

import '../platform_services.dart';

/// iOS: Keychain item gated by Face ID / Touch ID with device-passcode fallback.
class IosPlatformServices extends MethodChannelPlatformServices {
  @override
  String biometricLabel(String? kind) => switch (kind) {
    'face' => 'Face ID',
    'fingerprint' => 'Touch ID',
    _ => 'Device passcode',
  };

  @override
  Future<Uint8List?> transcodeForDisplay(Uint8List bytes) async {
    if (!_isHeif(bytes)) return null;
    return MethodChannelPlatformServices.channel.invokeMethod<Uint8List>('transcodeToJpeg', {'bytes': bytes});
  }

  /// ISO-BMFF `ftyp` box with a HEIF brand.
  static bool _isHeif(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final box = String.fromCharCodes(bytes.sublist(4, 8));
    final brand = String.fromCharCodes(bytes.sublist(8, 12));
    return box == 'ftyp' && const {'heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'}.contains(brand);
  }
}
