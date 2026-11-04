import 'package:freezed_annotation/freezed_annotation.dart';

part 'media_item.freezed.dart';

enum MediaType { photo, video }

@freezed
abstract class MediaItem with _$MediaItem {
  const MediaItem._();

  const factory MediaItem({
    required String id,
    required MediaType type,
    required String name,
    required String extension,
    required int sizeBytes,
    required DateTime importedAt,
    String? albumId,
    Duration? duration,
    int? width,
    int? height,
  }) = _MediaItem;

  bool get isVideo => type == MediaType.video;

  String get mimeType => switch (extension.toLowerCase()) {
    'mov' => 'video/quicktime',
    'm4v' => 'video/x-m4v',
    'webm' => 'video/webm',
    '3gp' => 'video/3gpp',
    'mkv' => 'video/x-matroska',
    _ when isVideo => 'video/mp4',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' || 'heif' => 'image/heic',
    _ => 'image/jpeg',
  };
}
