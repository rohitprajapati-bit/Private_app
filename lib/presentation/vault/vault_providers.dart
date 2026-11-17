import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/failures.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/vault_library.dart';
import '../../injection.dart';

final vaultLibraryProvider =
    AsyncNotifierProvider<VaultLibraryNotifier, VaultLibrary>(
      VaultLibraryNotifier.new,
    );

/// Decrypted listing of the open vault. Empty while locked, reloaded on every unlock.
class VaultLibraryNotifier extends AsyncNotifier<VaultLibrary> {
  @override
  Future<VaultLibrary> build() async {
    final session = ref.watch(sessionProvider);
    final builtUnlocked = session.isUnlocked;
    // Rebuild on both transitions. Rebuilding only on lock left an empty listing cached
    // (built while locked) that the next unlock never replaced.
    void onSessionChanged() {
      if (session.isUnlocked != builtUnlocked) ref.invalidateSelf();
    }

    session.addListener(onSessionChanged);
    ref.onDispose(() => session.removeListener(onSessionChanged));
    if (!builtUnlocked) return const VaultLibrary();
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

  Future<void> delete(List<MediaItem> items) =>
      _whileUnlocked(() => ref.read(mediaRepositoryProvider).delete(items));

  Future<void> move(List<MediaItem> items, String? albumId) => _whileUnlocked(
    () => ref.read(mediaRepositoryProvider).move(items, albumId),
  );

  /// Null when the vault locked before the album could be created.
  Future<Album?> createAlbum(String name) =>
      _whileUnlocked(() => ref.read(mediaRepositoryProvider).createAlbum(name));

  Future<void> renameAlbum(String id, String name) => _whileUnlocked(
    () => ref.read(mediaRepositoryProvider).renameAlbum(id, name),
  );

  Future<void> deleteAlbum(String id) =>
      _whileUnlocked(() => ref.read(mediaRepositoryProvider).deleteAlbum(id));

  /// The vault can lock at any moment (background, idle timeout) — e.g. while a dialog is
  /// open. A change started after that is dropped instead of surfacing as an uncaught error;
  /// the router has already returned to the game.
  Future<T?> _whileUnlocked<T>(Future<T> Function() change) async {
    if (!ref.read(sessionProvider).isUnlocked) return null;
    try {
      final result = await change();
      await reload();
      return result;
    } on VaultLocked {
      return null;
    }
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
