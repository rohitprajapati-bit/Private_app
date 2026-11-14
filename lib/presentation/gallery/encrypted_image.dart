import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/repositories/media_repository.dart';

/// Decrypts in memory and hands the bytes straight to the image decoder — no plaintext file.
/// Flutter's image cache is cleared on lock (see app.dart).
@immutable
class EncryptedImageProvider extends ImageProvider<EncryptedImageProvider> {
  const EncryptedImageProvider(this.item, this.repository, {this.thumbnail = false});

  final MediaItem item;
  final MediaRepository repository;
  final bool thumbnail;

  @override
  Future<EncryptedImageProvider> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(EncryptedImageProvider key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = thumbnail ? await repository.thumbnail(item) : await repository.photoBytes(item);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is EncryptedImageProvider && other.item.id == item.id && other.thumbnail == thumbnail;

  @override
  int get hashCode => Object.hash(item.id, thumbnail);
}

class EncryptedThumbnail extends StatelessWidget {
  const EncryptedThumbnail({super.key, required this.item, required this.repository});

  final MediaItem item;
  final MediaRepository repository;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: EncryptedImageProvider(item, repository, thumbnail: true),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
        opacity: frame == null ? 0 : 1,
        duration: const Duration(milliseconds: 200),
        child: child,
      ),
      errorBuilder: (context, error, stack) => ColoredBox(
        color: AppColors.surfaceHigh,
        child: Icon(
          item.isVideo ? Icons.movie_rounded : Icons.image_rounded,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}
