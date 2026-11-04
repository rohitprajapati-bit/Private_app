import 'dart:typed_data';

import '../platform_services.dart';

/// Android: BiometricPrompt + Android Keystore (fingerprint, face where the device classes it as
/// strong, device PIN/pattern fallback on Android 11+).
class AndroidPlatformServices extends MethodChannelPlatformServices {
  @override
  String biometricLabel(String? kind) => 'Fingerprint / face unlock';

  /// Flutter decodes HEIF on Android through the platform decoder.
  @override
  Future<Uint8List?> transcodeForDisplay(Uint8List bytes) async => null;
}
