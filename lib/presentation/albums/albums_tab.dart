import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/album.dart';
import '../../injection.dart';
import '../../routes/app_router.dart';
import '../gallery/encrypted_image.dart';
import '../vault/media_actions.dart';
import '../vault/vault_providers.dart';

class AlbumsTab extends ConsumerWidget {
  const AlbumsTab({super.key});

  static Future<void> create(BuildContext context, WidgetRef ref) async {
    final name = await MediaActions.promptName(context, title: 'New album');
    if (name != null)
      await ref.read(vaultLibraryProvider.notifier).createAlbum(name);
  }

  static Future<void> rename(
    BuildContext context,
    WidgetRef ref,
    Album album,
  ) async {
    final name = await MediaActions.promptName(
      context,
      title: 'Rename album',
      initial: album.name,
    );
    if (name != null)
      await ref.read(vaultLibraryProvider.notifier).renameAlbum(album.id, name);
  }

  /// Returns true when deleted.
  static Future<bool> delete(
    BuildContext context,
    WidgetRef ref,
    Album album,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${album.name}”?'),
        content: const Text(
          'Photos and videos in it are kept and stay under Photos / Videos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete album'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    await ref.read(vaultLibraryProvider.notifier).deleteAlbum(album.id);
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(vaultLibraryProvider).value;
    final repository = ref.watch(mediaRepositoryProvider);
    if (library == null)
      return const Center(child: CircularProgressIndicator());
    if (library.albums.isEmpty) {
      return const Center(
        child: Text(
          'No albums yet.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: library.albums.length,
      itemBuilder: (context, index) {
        final album = library.albums[index];
        final items = library.inAlbum(album.id);
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.go(Routes.album(album.id)),
          onLongPress: () => _menu(context, ref, album),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox.expand(
                    child: items.isEmpty
                        ? const ColoredBox(
                            color: AppColors.surface,
                            child: Icon(
                              Icons.folder_rounded,
                              size: 48,
                              color: AppColors.textMuted,
                            ),
                          )
                        : EncryptedThumbnail(
                            item: items.first,
                            repository: repository,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${items.length} item${items.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, Album album) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_rounded,
                color: AppColors.danger,
              ),
              title: const Text('Delete album'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'rename') {
      await rename(context, ref, album);
    } else if (action == 'delete') {
      await delete(context, ref, album);
    }
  }
}
