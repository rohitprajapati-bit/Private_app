import 'dart:typed_data';

import '../platform_services.dart';

class AndroidPlatformServices extends MethodChannelPlatformServices {
  /// Flutter decodes HEIF on Android through the platform decoder.
  @override
  Future<Uint8List?> transcodeForDisplay(Uint8List bytes) async => null;
}
