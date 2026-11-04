import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/failures.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/vault_library.dart';
import '../../injection.dart';

final vaultLibraryProvider = AsyncNotifierProvider<VaultLibraryNotifier, VaultLibrary>(VaultLibraryNotifier.new);

/// Decrypted listing of the open vault. Reset to empty the moment the vault locks.
class VaultLibraryNotifier extends AsyncNotifier<VaultLibrary> {
  @override
  Future<VaultLibrary> build() async {
    final session = ref.watch(sessionProvider);
    void onLock() => ref.invalidateSelf();
    session.addLockListener(onLock);
    ref.onDispose(() => session.removeLockListener(onLock));
    if (!session.isUnlocked) return const VaultLibrary();
    return ref.read(mediaRepositoryProvider).load();
  }

  Future<void> reload() async {
    // The vault may have locked while an action was running; the lock listener resets state.
    if (!ref.read(sessionProvider).isUnlocked) return;
    try {
      state = AsyncData(await ref.read(mediaRepositoryProvider).load());
    } on VaultLocked {
      // Locked mid-load.
    }
  }

  Future<void> delete(List<MediaItem> items) async {
    await ref.read(mediaRepositoryProvider).delete(items);
    await reload();
  }

  Future<void> move(List<MediaItem> items, String? albumId) async {
    await ref.read(mediaRepositoryProvider).move(items, albumId);
    await reload();
  }

  Future<Album> createAlbum(String name) async {
    final album = await ref.read(mediaRepositoryProvider).createAlbum(name);
    await reload();
    return album;
  }

  Future<void> renameAlbum(String id, String name) async {
    await ref.read(mediaRepositoryProvider).renameAlbum(id, name);
    await reload();
  }

  Future<void> deleteAlbum(String id) async {
    await ref.read(mediaRepositoryProvider).deleteAlbum(id);
    await reload();
  }
}

/// Convenience lookup used by the viewers.
final mediaItemProvider = Provider.family<MediaItem?, String>((ref, id) {
  final items = ref.watch(vaultLibraryProvider).value?.items ?? const [];
  for (final item in items) {
    if (item.id == id) return item;
  }
  return null;
});
