import 'dart:typed_data';

import '../entities/album.dart';
import '../entities/media_item.dart';
import '../entities/vault_library.dart';

class ImportProgress {
  const ImportProgress({
    required this.completed,
    required this.total,
    required this.currentFraction,
    this.failed = 0,
  });

  final int completed;
  final int total;

  /// 0..1 progress of the file currently being encrypted.
  final double currentFraction;
  final int failed;

  double get overall => total == 0 ? 1 : (completed + currentFraction) / total;
}

abstract interface class MediaRepository {
  Future<VaultLibrary> load();

  /// Encrypts picked files into the vault. Each file is an independent transaction: an
  /// interruption leaves either a complete item or nothing (cleaned up by [recover]).
  Stream<ImportProgress> import(List<String> paths, MediaType type, {String? albumId});

  /// Rolls back interrupted imports and removes orphaned files.
  Future<void> recover();

  Future<Uint8List> thumbnail(MediaItem item);

  /// Full photo bytes, decrypted in memory only.
  Future<Uint8List> photoBytes(MediaItem item);

  /// A loopback URL that streams the decrypted video with HTTP range support.
  Future<Uri> videoUri(MediaItem item);

  /// Stops serving [item] and wipes its file key from memory.
  void releaseVideo(MediaItem item);

  /// Saves decrypted copies to the device gallery. Returns how many succeeded.
  Future<int> export(List<MediaItem> items);

  Future<void> delete(List<MediaItem> items);

  Future<void> move(List<MediaItem> items, String? albumId);

  Future<Album> createAlbum(String name);

  Future<void> renameAlbum(String albumId, String name);

  /// Items in the album are kept and moved back to "All".
  Future<void> deleteAlbum(String albumId);

  /// Drops decrypted caches and stops the video server. Called on lock.
  Future<void> releaseSecrets();
}
