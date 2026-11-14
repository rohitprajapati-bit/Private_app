import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../domain/entities/media_item.dart';
import '../../domain/entities/vault_library.dart';
import '../../injection.dart';
import '../vault/media_actions.dart';
import '../vault/vault_providers.dart';
import 'encrypted_image.dart';
import 'media_grid.dart';

/// Full-screen, zoomable, swipeable photo viewer.
class PhotoViewerScreen extends ConsumerStatefulWidget {
  const PhotoViewerScreen({super.key, required this.initialId, this.albumId, this.orderedIds});

  final String initialId;
  final String? albumId;

  /// Order from the grid (search/sort applied); falls back to newest-first.
  final List<String>? orderedIds;

  @override
  ConsumerState<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends ConsumerState<PhotoViewerScreen> {
  PageController? _pageController;
  String? _currentId;
  bool _chrome = true;

  List<MediaItem> _photos(VaultLibrary library) {
    final photos = library.items.where((i) => !i.isVideo && (widget.albumId == null || i.albumId == widget.albumId));
    final ordered = widget.orderedIds;
    if (ordered == null) return photos.toList().sortedBy(MediaSort.newest);
    final byId = {for (final p in photos) p.id: p};
    return [for (final id in ordered) ?byId[id]];
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(vaultLibraryProvider).value;
    final repository = ref.watch(mediaRepositoryProvider);
    final photos = library == null ? <MediaItem>[] : _photos(library);
    if (photos.isEmpty) {
      return Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black));
    }

    _currentId ??= widget.initialId;
    var index = photos.indexWhere((p) => p.id == _currentId);
    if (index < 0) index = 0; // current photo was deleted; show its neighbour
    _pageController ??= PageController(initialPage: index);
    final current = photos[index];

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _chrome
          ? AppBar(
              backgroundColor: Colors.black54,
              title: Text('${index + 1} / ${photos.length}'),
              actions: [
                if (!current.isShared) ...[
                  IconButton(
                    tooltip: 'Move to album',
                    icon: const Icon(Icons.drive_file_move_rounded),
                    onPressed: () => MediaActions.moveToAlbum(context, ref, [current]),
                  ),
                  IconButton(
                    tooltip: 'Save to gallery',
                    icon: const Icon(Icons.download_rounded),
                    onPressed: () => MediaActions.export(context, ref, [current]),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_rounded),
                    onPressed: () async {
                      final deleted = await MediaActions.delete(context, ref, [current]);
                      if (deleted && photos.length == 1 && context.mounted) context.pop();
                    },
                  ),
                ],
              ],
            )
          : null,
      body: GestureDetector(
        onTap: () => setState(() => _chrome = !_chrome),
        child: Stack(
          children: [
            PhotoViewGallery.builder(
              pageController: _pageController,
              itemCount: photos.length,
              onPageChanged: (i) => setState(() => _currentId = photos[i].id),
              loadingBuilder: (context, event) => const Center(child: CircularProgressIndicator()),
              builder: (context, i) => PhotoViewGalleryPageOptions(
                imageProvider: EncryptedImageProvider(photos[i], repository),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4,
                heroAttributes: PhotoViewHeroAttributes(tag: photos[i].id),
                errorBuilder: (context, error, stack) => const Center(
                  child: Text('This photo could not be opened.', style: TextStyle(color: Colors.white70)),
                ),
              ),
            ),
            if (_chrome)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black54,
                  padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.paddingOf(context).bottom),
                  child: Text(
                    '${current.name} · ${formatBytes(current.sizeBytes)}'
                    '${current.width != null ? ' · ${current.width}×${current.height}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
