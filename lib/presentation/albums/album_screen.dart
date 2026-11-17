import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/media_item.dart';
import '../../routes/app_router.dart';
import '../gallery/media_grid.dart';
import '../vault/media_actions.dart';
import '../vault/vault_providers.dart';
import 'albums_tab.dart';

class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({super.key, required this.albumId});

  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(vaultLibraryProvider).value?.albums ?? const [];
    final album = albums.where((a) => a.id == albumId).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(album?.name ?? 'Album'),
        actions: [
          if (album != null)
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'rename') {
                  await AlbumsTab.rename(context, ref, album);
                } else if (value == 'delete') {
                  final deleted = await AlbumsTab.delete(context, ref, album);
                  if (deleted && context.mounted) context.go(Routes.vault);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete album')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: MediaGrid(albumId: albumId, basePath: Routes.album(albumId)),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add to album',
        onPressed: () async {
          final type = await showModalBottomSheet<MediaType>(
            context: context,
            showDragHandle: true,
            builder: (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.photo_rounded),
                    title: const Text('Photos'),
                    onTap: () => Navigator.pop(context, MediaType.photo),
                  ),
                  ListTile(
                    leading: const Icon(Icons.videocam_rounded),
                    title: const Text('Videos'),
                    onTap: () => Navigator.pop(context, MediaType.video),
                  ),
                ],
              ),
            ),
          );
          if (type != null && context.mounted)
            await MediaActions.import(context, ref, type, albumId: albumId);
        },
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}
